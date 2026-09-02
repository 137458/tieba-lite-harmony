import { HdsNavDestination, ScrollEffectType, HdsTabs, HdsTabsController } from '@kit.UIDesignKit';
import { TiebaAPI, UserForumLevelInfo } from '../../api/TiebaAPI';
import {
  ImageLoadTypeState,
  IsWifiState,
  connectImageLoadType,
  connectIsWifi,
  connectForumsNeedRefresh,
  connectMaterialLevel,
  MaterialLevelState,
  resolveMaterialLevel,
  MATERIAL_TYPE_IMMERSIVE,
  connectForumFabFunction,
  ForumFabFunctionState,
  ForumCommentPreviewState,
  connectForumCommentPreview
} from '../../model/AppStorageV2Models';
import {
  ThreadInfo,
  ForumInfo,
  SelfFollowForum,
  PageData,
  NavTabInfo,
  FrsTabInfo,
  SubPostInfo
} from '../../model/ForumModels';
import { FrsPageResult } from '../../proto/FrsPageProto';
import { GeneralTabListResult } from '../../proto/GeneralTabListProto';
import { ThreadCard } from '../../components/ThreadCard';
import { LoadingView } from '../../components/LoadingView';
import { getResourceString } from '../../utils/ResourceUtil';
import { formatCount } from '../../utils/FormatUtil';
import { ErrorView } from '../../components/ErrorView';
import { BaseViewModel, FetchDataResult } from '../../viewmodel/BaseViewModel';
import { handleThreadAgree, handleThreadDisagree } from '../../utils/ThreadInteractionHelper';
import { CommonDataSource } from '../../utils/CommonDataSource';
import { shouldLoad, getAvatarImageUrl } from '../../utils/ImageLoadUtil';
import { connectTheme, ThemeState } from '../../theme/ThemeManager';
import { VibratorUtil } from '../../utils/VibratorUtil';
import {
  RouterUtil,
  ThreadNavParams,
  ForumNavParams,
  UserProfileNavParams,
  ForumDetailNavParams,
  SearchNavParams,
  SubPostsNavParams
} from '../../utils/RouterUtil';
import { getStatusBarHeight } from '../../utils/StatusBarUtil';
import { AppStorageManager } from '../../data/AppStorage';
import { RecentForumHistory, RecentForumItem } from '../../utils/RecentForumHistory';

/** 排序方式常量（对齐 aiotieba ThreadSortType） */
const SORT_REPLY: number = 6;   // 按回复时间（默认）
const SORT_CREATE: number = 1;  // 按发布时间
const SORT_PREFERENCE_PREFIX: string = 'forum_sort_type_';
// HdsNavDestination titleBar mini 模式高度，用于内容区顶部占位避让
const TITLE_BAR_HEIGHT: number = 48;
// Tab 栏高度（vp）
const TAB_BAR_HEIGHT: number = 44;
// 关注列表最大查询数量（用于检查吧关注状态）
const FOLLOW_FORUMS_PAGE_SIZE: number = 100;

/**
 * 完整版吧内页面 ViewModel
 * 复用 ForumPage 的 ForumViewModel 结构，额外暴露 navTabInfo 给 UI 层渲染 Tab 栏
 */
class ForumFullViewModel extends BaseViewModel<ThreadInfo> {
  private forumName: string = '';
  private sortType: number = SORT_REPLY;
  private isGood: boolean = false;
  // 吧信息（含 fid），从 getThreads 响应的 forum 字段提取
  private forumInfo: ForumInfo = new ForumInfo();
  // 吧内 Tab 信息（FrsPage field 37），用于渲染 Tab 栏
  private navTabInfo: NavTabInfo = new NavTabInfo();
  // 当前选中的通用 Tab（null=最新/精品，走 getThreads；非 null=通用 Tab，走 getGeneralTabList）
  // 对齐安卓版 ForumPage.kt：切换到通用 Tab 时使用独立接口 /c/f/frs/generalTabList?cmd=309622
  private currentTabInfo: FrsTabInfo | null = null;

  setForumName(name: string): void {
    this.forumName = name;
  }

  setSortType(type: number): void {
    this.sortType = type;
  }

  setIsGood(good: boolean): void {
    this.isGood = good;
  }

  /**
   * 设置当前 Tab
   * @param tab null=最新/精品（走 getThreads），非 null=通用 Tab（走 getGeneralTabList）
   */
  setCurrentTab(tab: FrsTabInfo | null): void {
    this.currentTabInfo = tab;
  }

  /** 当前是否在通用 Tab（用于 syncState 跳过 forumInfo/navTabInfo 同步，避免覆盖首次 FrsPage 数据） */
  isOnGeneralTab(): boolean {
    return this.currentTabInfo !== null;
  }

  getForumInfo(): ForumInfo {
    return this.forumInfo;
  }

  getNavTabInfo(): NavTabInfo {
    return this.navTabInfo;
  }

  protected async fetchData(page: number, isRefresh: boolean): Promise<FetchDataResult<ThreadInfo>> {
    if (this.currentTabInfo !== null) {
      // 通用 Tab：调用 /c/f/frs/generalTabList?cmd=309622（与 FrsPage 是独立接口）
      // lastThreadId：翻页时取上一页最后一帖 tid，首页传 0
      const lastThreadId: number = isRefresh ? 0 : this.getLastThreadId();
      const result: GeneralTabListResult = await TiebaAPI.getGeneralTabList(
        this.currentTabInfo,
        this.forumInfo.id,
        page,
        this.sortType,
        lastThreadId
      );
      // 通用 Tab 不更新 forumInfo / navTabInfo（已在首次 FrsPage 加载时填充）
      return result.threads;
    }
    // 普通 Tab（最新/精品）：调用 /c/f/frs/page?cmd=301001
    const result: FrsPageResult = await TiebaAPI.getThreads(
      this.forumName,
      page,
      this.sortType,
      this.isGood
    );
    this.forumInfo = result.forum;
    this.navTabInfo = result.navTabInfo;
    return result.threads;
  }

  /** 获取当前列表最后一帖 tid，用于通用 Tab 翻页 */
  private getLastThreadId(): number {
    const list: ThreadInfo[] = this.paginationState.dataList;
    if (list.length === 0) {
      return 0;
    }
    return list[list.length - 1].tid;
  }
}

// #164 [A4-S4] Navigation 路由表 @Builder：供 router_map.json 的 buildFunction 引用
@Builder
export function ForumPageFullBuilder() {
  ForumPageFull()
}

@ComponentV2
export struct ForumPageFull {
  private viewModel: ForumFullViewModel = new ForumFullViewModel();

  @Local forumName: string = '';
  private dataSource: CommonDataSource<ThreadInfo> = new CommonDataSource<ThreadInfo>();
  @Local threadCount: number = 0;
  @Local isLoading: boolean = false;
  @Local isRefreshing: boolean = false;
  @Local hasMore: boolean = true;
  @Local errorMessage: string = '';
  @Local sortType: number = SORT_REPLY;
  @Local isGood: boolean = false;
  // 当前选中的 Tab 索引（0=最新 1=精品 2+=通用 Tab）
  @Local currentTab: number = 0;
  // 吧内导航 Tab 信息（从 FrsPage 响应 field 37 提取）
  @Local navTabInfo: NavTabInfo = new NavTabInfo();
  // 通用 Tab 列表（navTabInfo.tabs 中 isGeneralTab==1 且 tabType==15 的项）
  @Local generalTabs: FrsTabInfo[] = [];
  // 滚动器，绑定到 HdsNavDestination.bindToScrollable
  private scroller: Scroller = new Scroller();
  // aboutToAppear 完成标志
  @Local isReady: boolean = false;
  // 吧 id（fid）
  @Local forumId: number = 0;
  // 吧信息（@Local 让 HeaderBuilder 响应等级进度字段变化，关注/签到成功后立即更新）
  @Local forumInfo: ForumInfo = new ForumInfo();
  // 当前用户是否已关注该吧
  @Local isFollowing: boolean = false;
  // 关注操作进行中锁
  @Local isFollowLoading: boolean = false;
  // 是否已检查过关注状态
  private hasCheckedFollowing: boolean = false;
  private hasLoadedForumLevel: boolean = false;
  // 吧头像 URL
  @Local forumAvatar: string = '';
  // 是否已签到（本地状态，签到成功后置 true）
  @Local isSigned: boolean = false;
  // 签到操作进行中锁
  @Local isSigning: boolean = false;
  // 防抖锁：是否正在跳转搜索页（避免连点触发多次 push）
  private isNavigatingToSearch: boolean = false;
  // 图片加载策略
  @Local imageLoadTypeState: ImageLoadTypeState = connectImageLoadType();
  @Local isWifiState: IsWifiState = connectIsWifi();
  @Local themeState: ThemeState = connectTheme();
  // 沉浸光感材质强度档位
  @Local materialLevelState: MaterialLevelState = connectMaterialLevel();
  // FAB 功能模式（0=发帖 1=刷新 2=回顶 3=隐藏）
  @Local fabFunctionState: ForumFabFunctionState = connectForumFabFunction();
  @Local commentPreviewState: ForumCommentPreviewState = connectForumCommentPreview();
  private fabController: HdsTabsController = new HdsTabsController();
  // 状态栏高度
  @Local statusBarHeight: number = 36;
  private sortRequestGeneration: number = 0;
  private sortPreferenceKey: string = '';

  // Toast 提示 helper
  private showToast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message });
  }

  async aboutToAppear() {
    // 注入 DataSource 引用，供 BaseViewModel 内存压力时自动 clearCache
    this.viewModel.setDataSource(this.dataSource);
    // 读取路由参数
    const paramsStack: Object[] = RouterUtil.getStack().getParamByName(RouterUtil.ROUTE_FORUM_PAGE_FULL) as Object[];
    if (paramsStack && paramsStack.length > 0) {
      const params = paramsStack[paramsStack.length - 1] as ForumNavParams;
      if (params && params.forumName && params.forumName.length > 0) {
        this.forumName = params.forumName;
        RecentForumHistory.save(new RecentForumItem(0, this.forumName, params.forumAvatar)).catch((err: Error) => {
          console.error(`[ForumPageFull] save recent forum failed: ${err.message}`);
        });
        this.viewModel.setForumName(this.forumName);
        if (params.forumAvatar && params.forumAvatar.length > 0) {
          this.forumAvatar = params.forumAvatar;
        }
      }
    }
    // 获取状态栏高度
    try {
      this.statusBarHeight = await getStatusBarHeight(this.getUIContext());
    } catch (err) {
      console.error(`[ForumPageFull] getStatusBarHeight failed: ${(err as Error).message}`);
    }
    // 按吧名恢复排序偏好；偏好读取失败时沿用默认排序。
    this.sortPreferenceKey = `${SORT_PREFERENCE_PREFIX}${this.forumName}`;
    if (this.sortPreferenceKey.length > SORT_PREFERENCE_PREFIX.length) {
      try {
        const storage: AppStorageManager = AppStorageManager.getInstance();
        await storage.ensureReady();
        const savedSort: number = await storage.getNumber(this.sortPreferenceKey, SORT_REPLY);
        if (savedSort === SORT_REPLY || savedSort === SORT_CREATE) {
          this.sortType = savedSort;
        }
      } catch (err) {
        console.warn(`[ForumPageFull] restore sort preference failed: ${(err as Error).message}`);
      }
    }
    this.isReady = true;
    // 加载数据
    if (this.forumName.length > 0) {
      this.loadThreads(true).catch((err: Error) => {
        console.error(`[ForumPageFull] loadThreads failed: ${err.message}`);
      });
    }
  }

  aboutToDisappear(): void {
    this.viewModel.setDataSource(null);
  }

  async loadThreads(isRefresh: boolean = false): Promise<void> {
    if (this.forumName.length === 0) {
      return;
    }
    const requestGeneration: number = ++this.sortRequestGeneration;
    this.viewModel.setSortType(this.sortType);
    this.viewModel.setIsGood(this.isGood);
    await this.viewModel.loadData(isRefresh);
    // 排序或页面状态在请求期间发生变化时，禁止旧请求同步列表状态。
    if (requestGeneration !== this.sortRequestGeneration) {
      return;
    }
    this.syncState();
  }

  /**
   * 下拉刷新回调（Refresh 组件 onRefreshing 触发）
   * 加载完成后由 ViewModel 同步 isRefreshing=false
   */
  onRefresh(): void {
    VibratorUtil.light();
    this.loadThreads(true).catch((err: Error) => {
      console.error(`[ForumPageFull] onRefresh loadThreads failed: ${err.message}`);
    });
  }

  private syncState(): void {
    const paginationData = this.viewModel.paginationData;
    const loadingState = this.viewModel.loadingState;

    if (this.viewModel.lastOpWasRefresh) {
      this.dataSource.setData(paginationData.dataList);
      // 仅在非通用 Tab 时同步 forumInfo/navTabInfo
      // 通用 Tab 走 getGeneralTabList，不返回 forum 字段，沿用首次 FrsPage 拉取的数据（避免覆盖等级进度）
      if (!this.viewModel.isOnGeneralTab()) {
        const forumInfo: ForumInfo = this.viewModel.getForumInfo();
        if (forumInfo.id > 0) {
          this.forumId = forumInfo.id;
          // #234 forumInfo 合并同步到 @Local 字段（而非整体覆盖），触发 HeaderBuilder 响应式重组
          // 关注/签到成功后等级进度字段（userLevel/curScore/levelupScore/levelName）变化时头部立即更新
          // 合并策略：以新 forumInfo 为基底，但保留已通过 checkFollowingStatus/getUserForumInfo 同步的字段
          // （avatar/userLevel/levelName/curScore/levelupScore 等 FrsPage 不返回的字段）
          // 避免 Tab 切换时 FrsPage 返回的 forumInfo 覆盖关注列表/等级接口同步的数据
          const newForumInfo: ForumInfo = new ForumInfo(forumInfo);
          if (this.forumInfo.avatar.length > 0 && (newForumInfo.avatar.length === 0 || newForumInfo.avatar === '0')) {
            newForumInfo.avatar = this.forumInfo.avatar;
          }
          if (this.forumInfo.userLevel > 0 && newForumInfo.userLevel === 0) {
            newForumInfo.userLevel = this.forumInfo.userLevel;
          }
          if (this.forumInfo.levelName.length > 0 && newForumInfo.levelName.length === 0) {
            newForumInfo.levelName = this.forumInfo.levelName;
          }
          if (this.hasLoadedForumLevel) {
            newForumInfo.curScore = this.forumInfo.curScore;
            newForumInfo.levelupScore = this.forumInfo.levelupScore;
          }
          // memberCount/postCount：优先用 FrsPage 返回的值（更实时），否则保留已同步的值
          if (newForumInfo.memberCount === 0 && this.forumInfo.memberCount > 0) {
            newForumInfo.memberCount = this.forumInfo.memberCount;
          }
          if (newForumInfo.postCount === 0 && this.forumInfo.postCount > 0) {
            newForumInfo.postCount = this.forumInfo.postCount;
          }
          this.forumInfo = newForumInfo;
          if (newForumInfo.avatar.length > 0) {
            this.forumAvatar = newForumInfo.avatar;
          }
          // 同步 navTabInfo（完整版吧内页面切片）
          const navInfo: NavTabInfo = this.viewModel.getNavTabInfo();
          this.navTabInfo = navInfo;
          // 提取通用 Tab（isGeneralTab==1 且 tabType==15，对齐 Android ForumPage.kt:454）
          const generalList: FrsTabInfo[] = [];
          for (let i = 0; i < navInfo.tabs.length; i++) {
            if (navInfo.tabs[i].isGeneralTab === 1 && navInfo.tabs[i].tabType === 15) {
              generalList.push(navInfo.tabs[i]);
            }
          }
          this.generalTabs = generalList;
          // 首次拿到 forumId 后检查关注状态
          if (!this.hasCheckedFollowing) {
            this.hasCheckedFollowing = true;
            this.checkFollowingStatus().catch((err: Error) => {
              console.error(`[ForumPageFull] checkFollowingStatus failed: ${err.message}`);
            });
          }
          if (!this.hasLoadedForumLevel) {
            this.fetchUserForumLevel().catch((err: Error) => {
              console.warn(`[ForumPageFull] fetchUserForumLevel failed: ${err.message}`);
            });
          }
        }
      }
    } else {
      this.dataSource.appendData(this.viewModel.lastAddedList);
    }
    this.threadCount = this.dataSource.totalCount();
    this.hasMore = paginationData.hasMore;
    this.isLoading = loadingState.isLoading;
    this.isRefreshing = loadingState.isRefreshing;
    this.errorMessage = loadingState.error;
  }

  /**
   * 检查当前吧的关注状态（进入页面后调用一次）
   * FrsPage 响应不返回 isFollowed 字段，需调用 getFollowForums 查询
   * 同时从 SelfFollowForum 同步 memberCount/postCount/userLevel/avatar 到 forumInfo
   * （FrsPage.ForumInfo 仅含 id/name/first_class/second_class/member_num/thread_num/post_num/managers，
   *   不含 avatar/userLevel/levelName/curScore/levelupScore，这些字段需要从关注列表或独立接口获取）
   */
  private async checkFollowingStatus(): Promise<void> {
    try {
      const result: PageData<SelfFollowForum> = await TiebaAPI.getFollowForums(1, FOLLOW_FORUMS_PAGE_SIZE);
      let followedForum: SelfFollowForum | null = null;
      for (let i = 0; i < result.list.length; i++) {
        const followed: SelfFollowForum = result.list[i];
        if ((this.forumId > 0 && followed.fid === this.forumId) ||
            (this.forumName.length > 0 && followed.fname === this.forumName)) {
          followedForum = followed;
          break;
        }
      }
      if (followedForum !== null) {
        this.isFollowing = true;
        // 同步签到状态（关注列表返回 isSigned 字段）
        this.isSigned = followedForum.isSigned;
        if (followedForum.avatar.length > 0) {
          this.forumAvatar = followedForum.avatar;
        }
        // 从关注列表同步吧统计信息（FrsPage.ForumInfo 不返回 avatar/userLevel 等）
        // 构造新 ForumInfo 实例触发 @Local 响应式更新（直接改字段不触发）
        const newForumInfo: ForumInfo = new ForumInfo(this.forumInfo);
        if (followedForum.avatar.length > 0) {
          newForumInfo.avatar = followedForum.avatar;
        }
        if (followedForum.memberCount > 0) {
          newForumInfo.memberCount = followedForum.memberCount;
        }
        if (followedForum.threadNum > 0) {
          newForumInfo.postCount = followedForum.threadNum;
        }
        if (followedForum.level > 0) {
          newForumInfo.userLevel = followedForum.level;
        }
        this.forumInfo = newForumInfo;

      } else {
        this.isFollowing = false;
      }
    } catch (err) {
      console.error(`[ForumPageFull] checkFollowingStatus failed: ${(err as Error).message}`);
    }
  }

  /**
   * 获取用户在吧内的等级经验值进度（curScore/levelupScore/levelName）
   * 调用 getUserForumLevelInfo 接口，需要当前用户 portrait
   * 关注/签到成功后调用此方法刷新等级进度
   */
  private async fetchUserForumLevel(): Promise<void> {
    if (this.forumId <= 0) {
      return;
    }
    try {
      const storage: AppStorageManager = AppStorageManager.getInstance();
      await storage.ensureReady();
      const portrait: string = await storage.getString('avatar', '');
      if (portrait.length === 0) {
        return;
      }
      const levelInfo: UserForumLevelInfo = await TiebaAPI.getUserForumInfo(this.forumId, portrait);
      // 合并到 forumInfo 触发 HeaderBuilder 响应式更新
      const newForumInfo: ForumInfo = new ForumInfo(this.forumInfo);
      if (levelInfo.level > 0) {
        newForumInfo.userLevel = levelInfo.level;
      }
      if (levelInfo.levelName.length > 0) {
        newForumInfo.levelName = levelInfo.levelName;
      }
      newForumInfo.curScore = Math.max(0, levelInfo.curScore);
      newForumInfo.levelupScore = Math.max(0, levelInfo.levelupScore);
      if (newForumInfo.levelupScore > 0) {
        newForumInfo.curScore = Math.min(newForumInfo.curScore, newForumInfo.levelupScore);
      }
      this.hasLoadedForumLevel = true;
      this.forumInfo = newForumInfo;
    } catch (err) {
      console.warn(`[ForumPageFull] fetchUserForumLevel failed: ${(err as Error).message}`);
    }
  }

  /** 关注/取消关注吧 */
  async handleFollowForum(): Promise<void> {
    if (this.isFollowLoading || this.forumId === 0) {
      if (this.forumId === 0) {
        this.showToast(getResourceString($r('app.string.error_invalid_params')));
      }
      return;
    }
    this.isFollowLoading = true;
    VibratorUtil.heavy();
    try {
      if (this.isFollowing) {
        // 已关注 → 取消关注
        await TiebaAPI.unfollowForum(this.forumId, this.forumName);
        this.isFollowing = false;
        this.showToast(getResourceString($r('app.string.unfollow_forum_success')));
        const forumsNeedRefreshState = connectForumsNeedRefresh();
        forumsNeedRefreshState.value = Date.now();
      } else {
        // 未关注 → 关注
        await TiebaAPI.followForum(this.forumId, this.forumName);
        this.isFollowing = true;
        this.showToast(getResourceString($r('app.string.follow_forum_success')));
        const forumsNeedRefreshState = connectForumsNeedRefresh();
        forumsNeedRefreshState.value = Date.now();
        // #234 关注成功后重新拉取 forumInfo 刷新等级进度（对齐安卓版 SignIn/Like Reduce 更新 userLevel/curScore）
        this.loadThreads(true).catch((err: Error) => {
          console.error(`[ForumPageFull] refresh after follow failed: ${err.message}`);
        });
        this.fetchUserForumLevel().catch((err: Error) => {
          console.error(`[ForumPageFull] fetch level after follow failed: ${err.message}`);
        });
      }
    } catch (err) {
      const msg: string = (err as Error).message || getResourceString($r('app.string.follow_operation_failed'));
      this.showToast(msg);
    } finally {
      this.isFollowLoading = false;
    }
  }

  /** 签到（完整版吧内页面：已关注但未签到时调用） */
  async handleSignForum(): Promise<void> {
    if (this.isSigning || this.forumId === 0) {
      return;
    }
    this.isSigning = true;
    VibratorUtil.heavy();
    try {
      await TiebaAPI.signForum(this.forumName, this.forumId);
      this.isSigned = true;
      this.showToast(getResourceString($r('app.string.sign_success')));
      // #234 签到成功后重新拉取 forumInfo 刷新等级进度（对齐安卓版 SignIn Reduce 更新 curScore/userLevel）
      this.loadThreads(true).catch((err: Error) => {
        console.error(`[ForumPageFull] refresh after sign failed: ${err.message}`);
      });
      this.fetchUserForumLevel().catch((err: Error) => {
        console.error(`[ForumPageFull] fetch level after sign failed: ${err.message}`);
      });
    } catch (err) {
      const msg: string = (err as Error).message || getResourceString($r('app.string.sign_failed'));
      this.showToast(msg);
    } finally {
      this.isSigning = false;
    }
  }

  onReachEnd(): void {
    if (this.forumName.length === 0) {
      return;
    }
    if (this.viewModel.canLoadMore()) {
      this.loadThreads(false).catch((err: Error) => {
        console.error(`[ForumPageFull] onReachEnd loadThreads failed: ${err.message}`);
      });
    }
  }

  navigateToThread(tid: number): void {
    if (tid <= 0) {
      console.warn(`[ForumPageFull] invalid tid: ${tid}, skip navigation`);
      return;
    }
    RouterUtil.push(RouterUtil.ROUTE_THREAD_PAGE, new ThreadNavParams(tid));
  }

  navigateToSubPosts(subPost: SubPostInfo): void {
    if (subPost.tid <= 0 || subPost.pid <= 0 || subPost.spid <= 0) {
      return;
    }
    RouterUtil.push(RouterUtil.ROUTE_SUB_POSTS_PAGE,
      new SubPostsNavParams(subPost.tid, subPost.pid, subPost.floor));
  }

  navigateToUserProfile(portrait: string, userName: string, uid: number): void {
    RouterUtil.push(RouterUtil.ROUTE_USER_PROFILE_PAGE,
      new UserProfileNavParams(portrait, userName, uid));
  }

  navigateToForum(thread: ThreadInfo): void {
    if (thread.forumName.length === 0) {
      return;
    }
    RouterUtil.push(RouterUtil.ROUTE_FORUM_PAGE_FULL,
      new ForumNavParams(thread.forumName, thread.forumInfo.avatar));
  }

  /** 跳转吧详情页（点击头部吧名/头像时触发） */
  navigateToForumDetail(): void {
    if (this.forumId <= 0) {
      return;
    }
    RouterUtil.push(RouterUtil.ROUTE_FORUM_DETAIL_PAGE,
      new ForumDetailNavParams(this.forumId, this.forumName));
  }

  /** 跳转吧内搜索页（500ms 防抖，对齐安卓版 ForumPage.kt:1159-1176 debounceClickable） */
  navigateToSearch(): void {
    if (this.isNavigatingToSearch) {
      return;
    }
    this.isNavigatingToSearch = true;
    RouterUtil.push(RouterUtil.ROUTE_SEARCH_PAGE, new SearchNavParams(this.forumName));
    // 500ms 后释放防抖锁，避免连点触发多次 push
    setTimeout(() => {
      this.isNavigatingToSearch = false;
    }, 500);
  }

  /** 点赞/取消赞 */
  async handleAgree(thread: ThreadInfo): Promise<void> {
    await handleThreadAgree(this.dataSource, thread, this.getUIContext());
  }

  async handleDisagree(thread: ThreadInfo): Promise<void> {
    await handleThreadDisagree(this.dataSource, thread, this.getUIContext());
  }

  /** 评论按钮提示开发中 */
  showCommentToast(): void {
    this.showToast(getResourceString($r('app.string.page_developing')));
  }

  /**
   * 切换 Tab
   * @param tabIndex 0=最新 1=精品 2+=通用 Tab（按 generalTabs 顺序）
   *
   * 路由分支：
   * - 0/1：走 FrsPage（getThreads），通过 isGood 区分最新/精品
   * - 2+：走 GeneralTabList（getGeneralTabList），传入对应 FrsTabInfo
   *   对齐安卓版 ForumPage.kt：通用 Tab 使用独立接口 /c/f/frs/generalTabList?cmd=309622
   */
  handleTabChange(tabIndex: number): void {
    if (tabIndex === this.currentTab) {
      return;
    }
    VibratorUtil.light();
    this.currentTab = tabIndex;
    // 0=最新（isGood=false） 1=精品（isGood=true） 2+=通用 Tab（isGood=false，走通用接口）
    this.isGood = tabIndex === 1;
    // 设置 ViewModel 当前 Tab：通用 Tab 传入 FrsTabInfo，普通 Tab 传 null
    if (tabIndex >= 2) {
      const generalIndex: number = tabIndex - 2;
      if (generalIndex < this.generalTabs.length) {
        this.viewModel.setCurrentTab(this.generalTabs[generalIndex]);
      } else {
        // 越界保护：理论上不会触发（Tab 栏 ForEach 已基于 generalTabs 渲染）
        console.warn(`[ForumPageFull] handleTabChange invalid generalTabIndex: ${generalIndex}`);
        this.viewModel.setCurrentTab(null);
      }
    } else {
      this.viewModel.setCurrentTab(null);
    }
    // 清空数据触发内联 loading 占位（Header + TabBar 保持可见，threads 区显示 LoadingView）
    this.dataSource.setData([]);
    this.threadCount = 0;
    this.errorMessage = '';
    this.isLoading = true;
    // 回顶（重置上一 Tab 的滚动位置）
    this.scroller.scrollEdge(Edge.Top);
    // 切换 Tab 时重新加载数据
    this.loadThreads(true).catch((err: Error) => {
      console.error(`[ForumPageFull] handleTabChange loadThreads failed: ${err.message}`);
    });
  }

  /**
   * 处理排序分段控件选择
   * @param index 0=按回复时间（SORT_REPLY=6） 1=按发布时间（SORT_CREATE=1）
   */
  private handleSortSelect(index: number): void {
    const newSort: number = index === 0 ? SORT_REPLY : SORT_CREATE;
    if (newSort === this.sortType) {
      return;
    }
    VibratorUtil.light();
    this.sortType = newSort;
    this.viewModel.clearCache();
    this.dataSource.setData([]);
    this.threadCount = 0;
    const tip: string = getResourceString(
      this.sortType === SORT_REPLY ? $r('app.string.forum_sort_reply') : $r('app.string.forum_sort_post')
    );
    this.showToast(tip);
    this.persistSortPreference(newSort);
    this.loadThreads(true).catch((err: Error) => {
      console.error(`[ForumPageFull] handleSortSelect loadThreads failed: ${err.message}`);
    });
  }

  private persistSortPreference(sortType: number): void {
    if (this.sortPreferenceKey.length <= SORT_PREFERENCE_PREFIX.length) {
      return;
    }
    AppStorageManager.getInstance().setNumber(this.sortPreferenceKey, sortType).catch((err: Error) => {
      console.warn(`[ForumPageFull] persist sort preference failed: ${err.message}`);
    });
  }

  /** 获取吧名首字母大写，用于头像 fallback */
  private getForumInitial(name: string): string {
    if (name.length === 0) {
      return '?';
    }
    return name.charAt(0).toUpperCase();
  }

  /**
   * 头部 Builder：作为 List 第一个 ListItem，随列表滚动自然消失/重现
   * 对齐安卓版 ForumPage Header：吧头像(80vp) + 吧名 + slogan + 统计(关注/帖子) + 等级进度 + 关注/签到按钮
   * 折叠由 List 滚动天然实现（Header 滚出视口后被 titleBar GRADIENT_BLUR 模糊），
   * 不再使用手动 headerHeight 动画（避免与 bindToScrollable / Refresh 三方争抢导致抖动）
   */
  @Builder
  HeaderBuilder() {
    Column() {
      Row() {
        // 吧头像（80x80 圆形，对齐 PRD #158 展开时 80vp）
        if (this.forumAvatar.length > 0 && shouldLoad(this.imageLoadTypeState.value, this.isWifiState.value)) {
          Image(getAvatarImageUrl(this.forumAvatar, this.imageLoadTypeState.value, this.isWifiState.value))
            .width(80)
            .height(80)
            .borderRadius(40)
            .objectFit(ImageFit.Cover)
            .backgroundColor($r('app.color.input_background'))
            .alt($r('app.media.startIcon'))
            .syncLoad(true)
            .interpolation(ImageInterpolation.Low)
            .onClick(() => this.navigateToForumDetail())
            .hitTestBehavior(HitTestMode.Transparent)
        } else {
          Text(this.getForumInitial(this.forumName))
            .width(80)
            .height(80)
            .borderRadius(40)
            .textAlign(TextAlign.Center)
            .fontSize(32)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.card_background'))
            .backgroundColor(this.themeState.primary)
            .onClick(() => this.navigateToForumDetail())
        }

        // 中间：吧名 + slogan
        Column() {
          Text(this.forumName)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .onClick(() => this.navigateToForumDetail())

          // slogan（对齐 ForumInfo.slogan，原 app 显示吧简介短语）
          if (this.forumInfo.slogan.length > 0) {
            Text(this.forumInfo.slogan)
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ top: 4 })
              .onClick(() => this.navigateToForumDetail())
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .margin({ left: 16 })

        // 右侧：关注/签到按钮
        if (this.isFollowing) {
          // 已关注 → 显示签到/已签到按钮
          if (this.isSigned) {
            Text($r('app.string.forum_signed'))
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.success'))
              .backgroundColor($r('app.color.success_light'))
              .borderRadius(16)
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          } else {
            Text(this.isSigning ? $r('app.string.loading') : $r('app.string.forum_sign'))
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.card_background'))
              .backgroundColor(this.themeState.primary)
              .borderRadius(16)
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .onClick(() => {
                this.handleSignForum().catch((err: Error) => {
                  console.error(`[ForumPageFull] handleSignForum failed: ${err.message}`);
                });
              })
          }
        } else {
          // 未关注 → 显示关注按钮
          Text(this.isFollowLoading ? $r('app.string.loading') : $r('app.string.forum_follow'))
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.card_background'))
            .backgroundColor(this.themeState.primary)
            .borderRadius(16)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .onClick(() => {
              this.handleFollowForum().catch((err: Error) => {
                console.error(`[ForumPageFull] handleFollowForum failed: ${err.message}`);
              });
            })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // 统计行：关注人数 + 帖子数（对齐原 app Header 统计）
      Row() {
        Column() {
          Text(formatCount(this.forumInfo.memberCount))
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
          Text(getResourceString($r('app.string.forum_member_count')))
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Center)

        Column() {
          Text(formatCount(this.forumInfo.postCount))
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
          Text(getResourceString($r('app.string.forum_thread_count')))
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Center)
        .margin({ left: 32 })

        // 等级进度（已关注且 userLevel > 0 时显示）
        // userLevel 来自 SelfFollowForum.level（关注列表接口）
        // curScore/levelupScore 来自 get_user_forum_info 接口（暂未集成），仅在 levelupScore>0 时显示进度条
        if (this.isFollowing && this.forumInfo.userLevel > 0) {
          Column() {
            Text(getResourceString($r('app.string.forum_level_label',
              this.forumInfo.userLevel.toString(),
              this.forumInfo.levelName)))
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.themeState.primary)
            // 仅在 levelupScore > 0 时显示进度条（curScore/levelupScore 需 get_user_forum_info 接口）
            if (this.forumInfo.levelupScore > 0) {
              Progress({
                value: this.forumInfo.curScore,
                total: Math.max(1, this.forumInfo.levelupScore),
                type: ProgressType.Linear
              })
                .width(120)
                .height(4)
                .color(this.themeState.primary)
                .backgroundColor(this.themeState.primary_light)
                .margin({ top: 4 })
            }
          }
          .alignItems(HorizontalAlign.Start)
          .margin({ left: 32 })
          .layoutWeight(1)
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .margin({ top: 16 })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 16, bottom: 16 })
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  TabBarBuilder() {
    Column() {
      Scroll() {
        Row() {
          // 最新 Tab
          Column() {
            Text($r('app.string.forum_tab_latest'))
              .fontSize(15)
              .fontWeight(this.currentTab === 0 ? FontWeight.Bold : FontWeight.Normal)
              .fontColor(this.currentTab === 0 ? this.themeState.primary : $r('app.color.text_secondary'))
          }
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .padding({ left: 16, right: 16 })
          .height(TAB_BAR_HEIGHT)
          .backgroundColor(this.currentTab === 0 ? this.themeState.primary_light : Color.Transparent)
          .borderRadius(18)
          .onClick(() => this.handleTabChange(0))

          // 精品 Tab
          Column() {
            Text($r('app.string.forum_tab_good'))
              .fontSize(15)
              .fontWeight(this.currentTab === 1 ? FontWeight.Bold : FontWeight.Normal)
              .fontColor(this.currentTab === 1 ? this.themeState.primary : $r('app.color.text_secondary'))
          }
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .padding({ left: 16, right: 16 })
          .height(TAB_BAR_HEIGHT)
          .backgroundColor(this.currentTab === 1 ? this.themeState.primary_light : Color.Transparent)
          .borderRadius(18)
          .onClick(() => this.handleTabChange(1))

          // 通用 Tab（来自 navTabInfo）
          ForEach(this.generalTabs, (tab: FrsTabInfo, index: number) => {
            Column() {
              Text(tab.tabName)
                .fontSize(15)
                .fontWeight(this.currentTab === index + 2 ? FontWeight.Bold : FontWeight.Normal)
                .fontColor(this.currentTab === index + 2 ? this.themeState.primary : $r('app.color.text_secondary'))
            }
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .padding({ left: 16, right: 16 })
            .height(TAB_BAR_HEIGHT)
            .backgroundColor(this.currentTab === index + 2 ? this.themeState.primary_light : Color.Transparent)
            .borderRadius(18)
            .onClick(() => this.handleTabChange(index + 2))
          }, (tab: FrsTabInfo, index: number) => `${tab.tabId}_${index}`)
        }
        .height(TAB_BAR_HEIGHT)
        .padding({ left: 4, right: 4 })
      }
      .width('100%')
      .height(TAB_BAR_HEIGHT)
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)

      // 排序分段控件：直接点击即可切换，无需打开弹窗
      Row() {
        Row() {
          Text($r('app.string.forum_sort_reply'))
            .fontSize(13)
            .fontWeight(this.sortType === SORT_REPLY ? FontWeight.Bold : FontWeight.Normal)
            .fontColor(this.sortType === SORT_REPLY ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
            .padding({ left: 14, right: 14, top: 8, bottom: 8 })
            .backgroundColor(this.sortType === SORT_REPLY ? $r('app.color.card_background') : Color.Transparent)
            .borderRadius(16)
            .onClick(() => this.handleSortSelect(0))

          Text($r('app.string.forum_sort_post'))
            .fontSize(13)
            .fontWeight(this.sortType === SORT_CREATE ? FontWeight.Bold : FontWeight.Normal)
            .fontColor(this.sortType === SORT_CREATE ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
            .padding({ left: 14, right: 14, top: 8, bottom: 8 })
            .backgroundColor(this.sortType === SORT_CREATE ? $r('app.color.card_background') : Color.Transparent)
            .borderRadius(16)
            .onClick(() => this.handleSortSelect(1))
        }
        .padding({ left: 4, right: 4, top: 4, bottom: 4 })
        .backgroundColor($r('app.color.input_background'))
        .borderRadius(20)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 4, bottom: 8 })
      .backgroundColor($r('app.color.page_background'))
    }
    .width('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  FabTabBarBuilder() {
    Stack({ alignContent: Alignment.Center }) {
      Image(this.getFabIcon())
        .width(24)
        .height(24)
        .fillColor($r('app.color.text_primary'))
    }
    .width('100%')
    .height('100%')
    .onClick(() => this.handleFabClick())
  }

  @Builder
  FabBuilder() {
    if (this.fabFunctionState.value !== 3) {
      HdsTabs({ controller: this.fabController }) {
        TabContent() {
          Column()
        }
        .tabBar(this.FabTabBarBuilder())
      }
      .barPosition(BarPosition.End)
      .barMode(BarMode.Fixed)
      .scrollable(false)
      .barHeight(56)
      .barOverlap(true)
      .barFloatingStyle({
        barWidth: { smallWidth: 56, mediumWidth: 56, largeWidth: 56 },
        barSideMargin: 16,
        barBottomMargin: 16,
        gradientMask: {
          maskColor: '#00000000', // 完全透明，去掉渐变
          maskHeight: 1 // 最小高度
        },
        systemMaterialEffect: {
          materialType: MATERIAL_TYPE_IMMERSIVE,
          materialLevel: resolveMaterialLevel(this.materialLevelState.value)
        }
      })
      .width(88)
      .height(88)
    }
  }

  /**
   * titleBar 透明点击层 Builder：用于 stackBuilder，覆盖 title 区域（避让 back/menu）
   * 单击 titleBar 触发列表回顶（对齐原 app "点击状态栏回顶" 交互，鸿蒙状态栏由系统占用无法监听，
   * 改为点击 titleBar 的 title 文字区域触发回顶）
   * 不绘制可见内容，让 titleBar 的 mainTitle（吧名）透过来显示
   */
  @Builder
  titleBarClickBuilder() {
    Row() {
      // 左侧空白避让 back 按钮（约 48vp）
      Column()
        .width(48)
        .height('100%')
        .hitTestBehavior(HitTestMode.Transparent)
      // 中间点击区域：响应 onClick 触发回顶
      Column()
        .layoutWeight(1)
        .height('100%')
        .onClick(() => {
          this.scroller.scrollEdge(Edge.Top);
        })
      // 右侧空白避让 menu（搜索+更多，约 120vp）
      Column()
        .width(120)
        .height('100%')
        .hitTestBehavior(HitTestMode.Transparent)
    }
    .width('100%')
    .height('100%')
  }

  /**
   * 获取 FAB 图标
   * 0=发帖 ic_add / 1=刷新 ic_sort / 2=回顶 ic_back
   * 注意：刷新模式暂复用 ic_sort（项目暂无 ic_refresh 资源），后续新增 ic_refresh.svg 后替换
   */
  getFabIcon(): Resource {
    if (this.fabFunctionState.value === 1) {
      // 刷新：暂用 ic_sort，后续替换为 ic_refresh
      return $r('app.media.ic_sort');
    } else if (this.fabFunctionState.value === 2) {
      return $r('app.media.ic_back');
    }
    return $r('app.media.ic_add');
  }

  /** FAB 点击处理（0=发帖 1=刷新 2=回顶 3=隐藏） */
  handleFabClick(): void {
    if (this.fabFunctionState.value === 0) {
      // 发帖：ThreadPage 当前不支持 tid=0 发帖模式（aboutToAppear 校验 tid>0，tid<=0 显示 error_invalid_params）
      // 鸿蒙版暂无独立发帖页面，先显示"开发中"提示，待新增 NewThreadPage 后替换为 RouterUtil.push(ROUTE_NEW_THREAD_PAGE, ...)
      this.showToast(getResourceString($r('app.string.page_developing')));
    } else if (this.fabFunctionState.value === 1) {
      // 刷新：重新加载当前 Tab + 回顶
      this.loadThreads(true).catch((err: Error) => {
        console.error(`[ForumPageFull] FAB refresh failed: ${err.message}`);
      });
      this.scroller.scrollEdge(Edge.Top);
    } else if (this.fabFunctionState.value === 2) {
      // 回顶
      this.scroller.scrollEdge(Edge.Top);
    }
  }

  /** 取消关注确认弹窗 */
  private showUnfollowConfirmDialog(): void {
    this.getUIContext().getPromptAction().showDialog({
      title: getResourceString($r('app.string.confirm_unfollow_title')),
      message: getResourceString($r('app.string.confirm_unfollow_message', this.forumName)),
      buttons: [
        { text: getResourceString($r('app.string.cancel')), color: $r('app.color.text_secondary') },
        { text: getResourceString($r('app.string.confirm')), color: $r('app.color.error') }
      ]
    }).then((result) => {
      if (result.index === 1) {
        this.handleFollowForum().catch((err: Error) => {
          console.error(`[ForumPageFull] unfollow failed: ${err.message}`);
        });
      }
    }).catch((err: Error) => {
      console.error(`[ForumPageFull] unfollow dialog failed: ${err.message}`);
    });
  }

  build() {
    // 完整版吧内页面结构（对齐简洁版 ForumPage 模式三：HDS titleBar + Column padding top 避让 + List clip(false) 穿透模糊）：
    // HdsNavDestination(titleBar + menu) > Stack > [Column(padding top) > Refresh > List(header ListItem + ListItemGroup sticky TabBar + threads) + FabBuilder]
    // List clip(false) + cachedCount(_, true) 让 Header 滚出后穿透到 titleBar 下方做 GRADIENT_BLUR 模糊
    // Header 作为第一个 ListItem 随列表自然滚动消失/重现，TabBar 作为 ListItemGroup header 吸附在 titleBar 下方
    // 移除手动 headerHeight 折叠动画（避免与 bindToScrollable / Refresh 三方争抢导致抖动 + 下拉刷新后 header 消失）
    HdsNavDestination() {
      Stack({ alignContent: Alignment.BottomEnd }) {
        Column() {
          // 初始加载/错误（forumId === 0 表示尚未首次加载成功）：全屏 LoadingView/ErrorView
          if (!this.isReady || (this.isLoading && this.threadCount === 0 && this.forumId === 0)) {
            LoadingView({ message: getResourceString($r('app.string.loading')) })
              .layoutWeight(1)
          } else if (this.errorMessage.length > 0 && this.threadCount === 0 && this.forumId === 0) {
            ErrorView({
              message: this.errorMessage,
              onRetryClick: () => this.loadThreads(true).catch((err: Error) => {
                console.error(`[ForumPageFull] loadThreads retry failed: ${err.message}`);
              })
            })
              .layoutWeight(1)
          } else {
            Refresh({ refreshing: $$this.isRefreshing }) {
              List({ scroller: this.scroller }) {
                // 头部 ListItem：随列表自然滚动消失/重现（无手动 headerHeight 折叠）
                ListItem() {
                  this.HeaderBuilder()
                }

                ListItem() {
                  this.TabBarBuilder()
                }
                if (this.isLoading && this.threadCount === 0) {
                    ListItem() {
                      LoadingView({ message: getResourceString($r('app.string.loading')) })
                        .height(120)
                    }
                } else if (this.errorMessage.length > 0 && this.threadCount === 0) {
                    ListItem() {
                      ErrorView({
                        message: this.errorMessage,
                        onRetryClick: () => this.loadThreads(true).catch((err: Error) => {
                          console.error(`[ForumPageFull] loadThreads retry failed: ${err.message}`);
                        })
                      })
                        .height(120)
                    }
                } else {
                    LazyForEach(this.dataSource, (thread: ThreadInfo) => {
                      ListItem() {
                        ThreadCard({
                          thread: thread,
                          imageLoadType: this.imageLoadTypeState.value,
                          isWifi: this.isWifiState.value,
                          commentPreviewEnabled: this.commentPreviewState.value,
                          onCardClick: () => this.navigateToThread(thread.tid),
                          onSubPostClick: (subPost: SubPostInfo) => this.navigateToSubPosts(subPost),
                          onAuthorClick: () => this.navigateToUserProfile(
                            thread.author.portrait,
                            thread.author.name,
                            thread.author.uid
                          ),
                          onForumClick: (t: ThreadInfo): void => this.navigateToForum(t),
                          onAgreeClick: (t: ThreadInfo) => {
                            this.handleAgree(t).catch((err: Error) => {
                              console.error(`[ForumPageFull] handleAgree failed: ${err.message}`);
                            });
                          },
                          onDisagreeClick: (t: ThreadInfo) => {
                            this.handleDisagree(t).catch((err: Error) => {
                              console.error(`[ForumPageFull] handleDisagree failed: ${err.message}`);
                            });
                          },
                          onCommentClick: () => this.showCommentToast()
                        })
                      }
                      .margin({ left: 16, right: 16, top: 4, bottom: 4 })
                    }, (thread: ThreadInfo) => thread.tid.toString())

                    // 加载更多 loading
                    if (this.isLoading && this.threadCount > 0) {
                      ListItem() {
                        LoadingView({ message: getResourceString($r('app.string.loading_more')) })
                          .height(60)
                      }
                      .margin({ left: 16, right: 16 })
                  }
                }
              }
              .width('100%')
              .layoutWeight(1)
              .divider({ strokeWidth: 0 })
              .scrollBar(BarState.Off)
              .edgeEffect(EdgeEffect.Spring)
              .cachedCount(5, true)
              // 模式三：clip(false) 让 Header 滚出后穿透到 titleBar 下方做 GRADIENT_BLUR 模糊
              .clip(false)
              // 不启用 sticky header：Tab 栏随 Header 一起滚动消失（对齐原 app 设计）
              .backgroundColor($r('app.color.page_background'))
              .onReachEnd(() => this.onReachEnd())
            }
            .layoutWeight(1)
            .clip(false)
            .backgroundColor($r('app.color.page_background'))
            .onRefreshing(() => this.onRefresh())
          }
        }
        .width('100%')
        .height('100%')
        // 模式三：外层 Column padding top 避让状态栏 + titleBar（与简洁版 ForumPage 一致）
        .padding({ top: this.statusBarHeight + TITLE_BAR_HEIGHT })
        .backgroundColor($r('app.color.page_background'))

        // FAB 浮在右下角（Stack BottomEnd 对齐 + margin 避让安全区域）
        this.FabBuilder()
      }
    }
    .titleBar({
      content: {
        // titleBar 显示吧名（Header 滚出后用户仍能在 titleBar 看到当前吧名）
        // stackBuilder：透明点击层覆盖 title 区域（避让 back/menu），单击 titleBar 触发回顶
        title: { mainTitle: this.forumName },
        stackBuilder: (): void => this.titleBarClickBuilder(),
        menu: {
          maxCount: 2,
          value: [{
            content: {
              icon: $r('app.media.ic_search'),
              isEnabled: true,
              action: () => this.navigateToSearch()
            }
          }, {
            content: {
              icon: $r('app.media.ic_share'),
              label: $r('app.string.forum_menu_share'),
              isEnabled: true,
              action: () => this.showToast(getResourceString($r('app.string.share_developing')))
            }
          }, {
            content: {
              icon: $r('app.media.ic_add'),
              label: $r('app.string.forum_menu_add_to_desktop'),
              isEnabled: true,
              action: () => this.showToast(getResourceString($r('app.string.feature_developing')))
            }
          }, {
            content: {
              icon: $r('app.media.ic_add'),
              label: $r('app.string.forum_menu_unfollow'),
              isEnabled: this.isFollowing,
              action: () => this.showUnfollowConfirmDialog()
            }
          }]
        }
      },
      style: {
        scrollEffectOpts: {
          enableScrollEffect: true,
          scrollEffectType: ScrollEffectType.GRADIENT_BLUR
        },
        systemMaterialEffect: {
          materialType: MATERIAL_TYPE_IMMERSIVE,
          materialLevel: resolveMaterialLevel(this.materialLevelState.value)
        },
        originalStyle: {
          contentStyle: { menuStyle: { iconColor: this.themeState.primary } }
        },
        scrollEffectStyle: {
          contentStyle: { menuStyle: { iconColor: this.themeState.primary } }
        }
      },
      avoidLayoutSafeArea: true
    })
    .bindToScrollable([this.scroller])
    .backgroundColor($r('app.color.page_background'))
  }
}
