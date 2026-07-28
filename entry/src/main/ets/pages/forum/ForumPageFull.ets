import { HdsNavDestination, ScrollEffectType } from '@kit.UIDesignKit';
import { TiebaAPI } from '../../api/TiebaAPI';
import {
  ImageLoadTypeState,
  IsWifiState,
  SafeBottomState,
  connectImageLoadType,
  connectIsWifi,
  connectSafeBottom,
  connectForumsNeedRefresh,
  connectMaterialLevel,
  MaterialLevelState,
  resolveMaterialLevel,
  MATERIAL_TYPE_IMMERSIVE,
  connectForumFabFunction,
  ForumFabFunctionState
} from '../../model/AppStorageV2Models';
import {
  ThreadInfo,
  ForumInfo,
  SelfFollowForum,
  PageData,
  NavTabInfo,
  FrsTabInfo
} from '../../model/ForumModels';
import { FrsPageResult } from '../../proto/FrsPageProto';
import { GeneralTabListResult } from '../../proto/GeneralTabListProto';
import { ThreadCard } from '../../components/ThreadCard';
import { LoadingView } from '../../components/LoadingView';
import { getResourceString } from '../../utils/ResourceUtil';
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
  SearchNavParams
} from '../../utils/RouterUtil';
import { getStatusBarHeight } from '../../utils/StatusBarUtil';

/** 排序方式常量（对齐 aiotieba ThreadSortType） */
const SORT_REPLY: number = 6;   // 按回复时间（默认）
const SORT_CREATE: number = 1;  // 按发布时间
// HdsNavDestination titleBar mini 模式高度，用于内容区顶部占位避让
const TITLE_BAR_HEIGHT: number = 48;
// 头部展开时高度（vp），折叠时变为 0
const HEADER_EXPANDED_HEIGHT: number = 96;
// Tab 栏高度（vp）
const TAB_BAR_HEIGHT: number = 44;
// titleBar 内容右侧 padding：2 个 menu 图标宽度 + 间距（完整版仅搜索+更多 2 个图标）
const MENU_PADDING_RIGHT_2ICON: number = 110;
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
  // 吧头像 URL
  @Local forumAvatar: string = '';
  // 是否已签到（本地状态，签到成功后置 true）
  @Local isSigned: boolean = false;
  // 签到操作进行中锁
  @Local isSigning: boolean = false;
  // 头部当前高度（vp，范围 [0, HEADER_EXPANDED_HEIGHT]，直接跟手赋值不使用 animateTo）
  // 对齐安卓版 NestedScrollConnection：滚动时直接消费偏移量改变 headerHeight，无动画延迟
  @Local headerHeight: number = HEADER_EXPANDED_HEIGHT;
  // 滚动停止时是否需要吸附（Idle 时用 animateTo 吸附到 0 或 HEADER_EXPANDED_HEIGHT）
  @Local isHeaderSnapping: boolean = false;
  // 防抖锁：是否正在跳转搜索页（避免连点触发多次 push）
  private isNavigatingToSearch: boolean = false;
  // 图片加载策略
  @Local imageLoadTypeState: ImageLoadTypeState = connectImageLoadType();
  @Local isWifiState: IsWifiState = connectIsWifi();
  @Local safeBottomState: SafeBottomState = connectSafeBottom();
  @Local themeState: ThemeState = connectTheme();
  // 沉浸光感材质强度档位
  @Local materialLevelState: MaterialLevelState = connectMaterialLevel();
  // FAB 功能模式（0=发帖 1=刷新 2=回顶 3=隐藏）
  @Local fabFunctionState: ForumFabFunctionState = connectForumFabFunction();
  // 状态栏高度
  @Local statusBarHeight: number = 36;

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
        this.viewModel.setForumName(this.forumName);
        if (params.forumAvatar && params.forumAvatar.length > 0) {
          this.forumAvatar = params.forumAvatar;
        }
      }
    }
    // 获取状态栏高度
    try {
      this.statusBarHeight = await getStatusBarHeight(getContext(this));
    } catch (err) {
      console.error(`[ForumPageFull] getStatusBarHeight failed: ${(err as Error).message}`);
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
    this.viewModel.setSortType(this.sortType);
    this.viewModel.setIsGood(this.isGood);
    await this.viewModel.loadData(isRefresh);
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
      // 同步吧信息
      const forumInfo: ForumInfo = this.viewModel.getForumInfo();
      if (forumInfo.id > 0) {
        this.forumId = forumInfo.id;
        // #234 forumInfo 整体同步到 @Local 字段，触发 HeaderBuilder 响应式重组
        // 关注/签到成功后等级进度字段（userLevel/curScore/levelupScore/levelName）变化时头部立即更新
        this.forumInfo = forumInfo;
        if (forumInfo.avatar.length > 0) {
          this.forumAvatar = forumInfo.avatar;
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
   */
  private async checkFollowingStatus(): Promise<void> {
    try {
      const result: PageData<SelfFollowForum> = await TiebaAPI.getFollowForums(1, FOLLOW_FORUMS_PAGE_SIZE);
      for (let i = 0; i < result.list.length; i++) {
        if (result.list[i].fid === this.forumId) {
          this.isFollowing = true;
          // 同步签到状态（关注列表返回 isSigned 字段）
          this.isSigned = result.list[i].isSigned;
          if (result.list[i].avatar.length > 0) {
            this.forumAvatar = result.list[i].avatar;
          }
          return;
        }
      }
      this.isFollowing = false;
    } catch (err) {
      console.error(`[ForumPageFull] checkFollowingStatus failed: ${(err as Error).message}`);
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

  navigateToUserProfile(portrait: string, userName: string, uid: number): void {
    RouterUtil.push(RouterUtil.ROUTE_USER_PROFILE_PAGE,
      new UserProfileNavParams(portrait, userName, uid));
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
    // 切换 Tab 时重新加载数据
    this.loadThreads(true).catch((err: Error) => {
      console.error(`[ForumPageFull] handleTabChange loadThreads failed: ${err.message}`);
    });
  }

  /** 切换排序方式（最新 Tab 下点击排序按钮） */
  handleSortChange(): void {
    this.sortType = this.sortType === SORT_REPLY ? SORT_CREATE : SORT_REPLY;
    const tip: string = getResourceString(
      this.sortType === SORT_REPLY ? $r('app.string.forum_sort_reply') : $r('app.string.forum_sort_post')
    );
    this.showToast(tip);
    this.loadThreads(true).catch((err: Error) => {
      console.error(`[ForumPageFull] handleSortChange loadThreads failed: ${err.message}`);
    });
  }

  /**
   * List 滚动回调：驱动头部折叠/展开
   * 鸿蒙 List.onDidScroll 的 scrollOffset 含义：
   *   - 正值：内容向上移动（手指上滑，看下方内容）
   *   - 负值：内容向下移动（手指下滑，看上方内容）
   * 折叠逻辑（对齐安卓版 NestedScrollConnection）：
   *   - 手指上滑（offset > 0，看下方内容）→ 折叠头部，让出空间给帖子列表
   *   - 手指下滑（offset < 0，看上方内容）→ 展开头部（仅在列表已到顶时）
   * 直接赋值 headerHeight 跟手，不用 animateTo 避免动画延迟
   * 滚动停止时用 onScrollStop 事件触发 snapHeader 吸附
   */
  onListScroll(offset: number): void {
    // 吸附动画期间用户重新触摸滚动 → 立即中断吸附，响应跟手
    if (this.isHeaderSnapping) {
      this.isHeaderSnapping = false;
    }
    if (offset > 0) {
      // 手指上滑 → 折叠头部（headerHeight 递减）
      const newHeight: number = this.headerHeight - offset;
      this.headerHeight = Math.max(0, newHeight);
    } else if (offset < 0) {
      // 手指下滑 → 展开头部（headerHeight 递增）
      // 仅在列表已到顶时展开（避免列表中间下滑误触发）
      // scroller.currentOffset().yOffset <= 0 表示列表已在顶部
      const currentOffset = this.scroller.currentOffset();
      if (currentOffset.yOffset <= 0) {
        const newHeight: number = this.headerHeight - offset;
        this.headerHeight = Math.min(HEADER_EXPANDED_HEIGHT, newHeight);
      }
    }
  }

  /** 滚动停止时吸附头部到 0 或 HEADER_EXPANDED_HEIGHT（由 onScrollStop 触发） */
  private snapHeader(): void {
    // 已经在完整状态，不需要吸附
    if (this.headerHeight === HEADER_EXPANDED_HEIGHT || this.headerHeight === 0) {
      return;
    }
    const threshold: number = HEADER_EXPANDED_HEIGHT / 2;
    const targetHeight: number = this.headerHeight >= threshold ? HEADER_EXPANDED_HEIGHT : 0;
    this.isHeaderSnapping = true;
    this.getUIContext().animateTo({
      duration: 200,
      curve: Curve.EaseOut,
      onFinish: () => {
        // 动画结束释放锁，比 setTimeout 更精确（动画被中断时也会触发）
        this.isHeaderSnapping = false;
      }
    }, () => {
      this.headerHeight = targetHeight;
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
   * 头部 Builder：可折叠的头部区域
   * 包含：吧头像 + 吧名 + 等级进度 + 关注/签到按钮
   * 折叠时高度为 0，展开时高度为 HEADER_EXPANDED_HEIGHT
   */
  @Builder
  HeaderBuilder() {
    Column() {
      Row() {
        // 吧头像（48x48 圆形）
        if (this.forumAvatar.length > 0 && shouldLoad(this.imageLoadTypeState.value, this.isWifiState.value)) {
          Image(getAvatarImageUrl(this.forumAvatar, this.imageLoadTypeState.value, this.isWifiState.value))
            .width(48)
            .height(48)
            .borderRadius(24)
            .objectFit(ImageFit.Cover)
            .backgroundColor($r('app.color.input_background'))
            .alt($r('app.media.startIcon'))
            .syncLoad(true)
            .interpolation(ImageInterpolation.Low)
            .onClick(() => this.navigateToForumDetail())
            .hitTestBehavior(HitTestMode.Transparent)
        } else {
          Text(this.getForumInitial(this.forumName))
            .width(48)
            .height(48)
            .borderRadius(24)
            .textAlign(TextAlign.Center)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.card_background'))
            .backgroundColor(this.themeState.primary)
            .onClick(() => this.navigateToForumDetail())
        }

        // 中间：吧名 + 等级进度（已关注时显示）
        Column() {
          Text(this.forumName)
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .onClick(() => this.navigateToForumDetail())

          // 等级进度条（仅已关注且 userLevel > 0 时显示）
          // 使用 @Local forumInfo 触发响应式重组（对齐 P1-10 修复）
          if (this.isFollowing && this.forumInfo.userLevel > 0) {
            Progress({
              value: this.forumInfo.curScore,
              total: Math.max(1, this.forumInfo.levelupScore),
              type: ProgressType.Linear
            })
              .width('100%')
              .height(6)
              .color(this.themeState.primary)
              .backgroundColor(this.themeState.primary_light)
              .margin({ top: 6 })

            // 等级文本：Lv.X 等级名称
            Text(getResourceString($r('app.string.forum_level_label',
              this.forumInfo.userLevel.toString(),
              this.forumInfo.levelName)))
              .fontSize(11)
              .fontColor($r('app.color.text_secondary'))
              .margin({ top: 4 })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .margin({ left: 12 })

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
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    }
    .width('100%')
    .height(this.headerHeight)
    .clip(true)
  }

  /**
   * Tab 栏 Builder：水平可滚动的 Tab 切换栏
   * 包含：最新（带排序下拉）、精品、通用 Tab（来自 navTabInfo）
   * 用 Scroll 包裹 Row 支持横向滚动，对齐安卓版 ScrollableTabRow
   * 当 generalTabs 较多时不被截断
   */
  @Builder
  TabBarBuilder() {
    Scroll() {
      Row() {
        // 最新 Tab（带排序按钮）
        Row() {
          Text($r('app.string.forum_tab_latest'))
            .fontSize(14)
            .fontWeight(this.currentTab === 0 ? FontWeight.Bold : FontWeight.Normal)
            .fontColor(this.currentTab === 0 ? this.themeState.primary : $r('app.color.text_secondary'))
            .onClick(() => this.handleTabChange(0))

          // 排序按钮（仅最新 Tab 显示，点击切换排序方式）
          Image($r('app.media.ic_sort'))
            .width(16)
            .height(16)
            .margin({ left: 4 })
            .fillColor(this.currentTab === 0 ? this.themeState.primary : $r('app.color.text_secondary'))
            .onClick(() => this.handleSortChange())
        }
        .alignItems(VerticalAlign.Center)
        .padding({ left: 16, right: 16 })
        .height(TAB_BAR_HEIGHT)

        // 精品 Tab
        Text($r('app.string.forum_tab_good'))
          .fontSize(14)
          .fontWeight(this.currentTab === 1 ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(this.currentTab === 1 ? this.themeState.primary : $r('app.color.text_secondary'))
          .padding({ left: 16, right: 16 })
          .height(TAB_BAR_HEIGHT)
          .textAlign(TextAlign.Center)
          .onClick(() => this.handleTabChange(1))

        // 通用 Tab（来自 navTabInfo）
        ForEach(this.generalTabs, (tab: FrsTabInfo, index: number) => {
          Text(tab.tabName)
            .fontSize(14)
            .fontWeight(this.currentTab === index + 2 ? FontWeight.Bold : FontWeight.Normal)
            .fontColor(this.currentTab === index + 2 ? this.themeState.primary : $r('app.color.text_secondary'))
            .padding({ left: 16, right: 16 })
            .height(TAB_BAR_HEIGHT)
            .textAlign(TextAlign.Center)
            .onClick(() => this.handleTabChange(index + 2))
        }, (tab: FrsTabInfo, index: number) => `${tab.tabId}_${index}`)
      }
      .height(TAB_BAR_HEIGHT)
    }
    .width('100%')
    .height(TAB_BAR_HEIGHT)
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .backgroundColor($r('app.color.card_background'))
    .border({ width: { bottom: 0.5 }, color: { bottom: $r('app.color.divider') } })
  }

  /**
   * titleBar stackBuilder：吧头像 + 吧名（固定在 titleBar 不随列表滚动）
   * 布局与 ForumPage.forumAvatarBuilder 一致，保持视觉统一
   */
  @Builder
  forumAvatarBuilder() {
    Row() {
      if (this.forumAvatar.length > 0 && shouldLoad(this.imageLoadTypeState.value, this.isWifiState.value)) {
        Image(getAvatarImageUrl(this.forumAvatar, this.imageLoadTypeState.value, this.isWifiState.value))
          .width(39)
          .height(39)
          .borderRadius(19)
          .objectFit(ImageFit.Cover)
          .backgroundColor($r('app.color.input_background'))
          .alt($r('app.media.startIcon'))
          .syncLoad(true)
          .interpolation(ImageInterpolation.Low)
          .onError(() => { })
          .hitTestBehavior(HitTestMode.Transparent)
      } else {
        Column() {
          Text(this.forumName.length > 0 ? this.forumName.charAt(0).toUpperCase() : '?')
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
        }
        .width(38)
        .height(38)
        .borderRadius(19)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .linearGradient({
          angle: 135,
          colors: [[this.themeState.primary, 0.0], [$r('app.color.accent_blue'), 1.0]]
        })
      }

      Text(this.forumName)
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ left: 8 })
        .layoutWeight(1)
        .hitTestBehavior(HitTestMode.Transparent)
    }
    .width('100%')
    .height('100%')
    // 完整版 menu 仅 2 个图标（搜索 + 更多），right 110 避让即可
    // 简化版 ForumPage menu 有 3 个图标（关注 + 排序 + 精品）才需要 right 160
    .padding({ left: 60, right: MENU_PADDING_RIGHT_2ICON })
    .alignItems(VerticalAlign.Center)
  }

  /**
   * FAB Builder：浮动按钮（4 模式）
   * fabFunctionState.value: 0=发帖 1=刷新 2=回顶 3=隐藏
   * 3=隐藏时不渲染 FAB
   */
  @Builder
  FabBuilder() {
    if (this.fabFunctionState.value !== 3) {
      Button() {
        Image(this.getFabIcon())
          .width(24)
          .height(24)
          .fillColor($r('app.color.text_primary'))
      }
      .width(56)
      .height(56)
      .borderRadius(28)
      .backgroundColor($r('app.color.card_background'))
      .shadow({ radius: 8, color: '#66000000', offsetX: 0, offsetY: 4 })
      .margin({ right: 16, bottom: this.safeBottomState.value + 16 })
      .onClick(() => this.handleFabClick())
    }
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

  /**
   * 弹出三点菜单（分享 / 发送到桌面 / 取消关注）
   * 使用 showActionMenu 弹出底部操作菜单，对齐 ThreadPage.showSortMenu 模式
   * 取消关注仅在已关注（isFollowing=true）时显示
   */
  showMoreMenu(): void {
    // showActionMenu buttons 是元组类型（最多 6 项），不支持动态数组
    // isFollowing=true 时 3 项菜单，false 时 2 项菜单，需分支构造
    if (this.isFollowing) {
      this.getUIContext().getPromptAction().showActionMenu({
        title: this.forumName,
        buttons: [
          { text: getResourceString($r('app.string.forum_menu_share')), color: $r('app.color.text_primary') },
          { text: getResourceString($r('app.string.forum_menu_add_to_desktop')), color: $r('app.color.text_primary') },
          { text: getResourceString($r('app.string.forum_menu_unfollow')), color: $r('app.color.error') }
        ]
      }).then((result) => {
        this.handleMenuSelect(result.index);
      }).catch((err: Error) => {
        console.error(`[ForumPageFull] showMoreMenu failed: ${err.message}`);
      });
    } else {
      this.getUIContext().getPromptAction().showActionMenu({
        title: this.forumName,
        buttons: [
          { text: getResourceString($r('app.string.forum_menu_share')), color: $r('app.color.text_primary') },
          { text: getResourceString($r('app.string.forum_menu_add_to_desktop')), color: $r('app.color.text_primary') }
        ]
      }).then((result) => {
        this.handleMenuSelect(result.index);
      }).catch((err: Error) => {
        console.error(`[ForumPageFull] showMoreMenu failed: ${err.message}`);
      });
    }
  }

  /**
   * 处理菜单选择
   * @param index 0=分享 1=发送到桌面 2=取消关注（仅 isFollowing=true 时存在）
   */
  private handleMenuSelect(index: number): void {
    if (index === 0) {
      this.showToast(getResourceString($r('app.string.share_developing')));
    } else if (index === 1) {
      this.showToast(getResourceString($r('app.string.feature_developing')));
    } else if (index === 2) {
      this.showUnfollowConfirmDialog();
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
    // 完整版吧内页面结构：
    // HdsNavDestination(titleBar + menu) > Stack > [Column(HeaderBuilder + TabBarBuilder + List) + FabBuilder]
    // List clip(false) + cachedCount(_, true) 让内容穿透到 titleBar 下方做模糊
    // Stack BottomEnd 让 FAB 浮在右下角
    HdsNavDestination() {
      Stack({ alignContent: Alignment.BottomEnd }) {
        Column() {
        if (!this.isReady || (this.isLoading && this.threadCount === 0)) {
          // 合并 isReady 未完成和首次加载中两个分支（两者互斥：isReady=false 期间不会触发 loadThreads）
          LoadingView({ message: getResourceString($r('app.string.loading')) })
            .layoutWeight(1)
        } else if (this.errorMessage.length > 0 && this.threadCount === 0) {
          ErrorView({
            message: this.errorMessage,
            onRetryClick: () => this.loadThreads(true).catch((err: Error) => {
              console.error(`[ForumPageFull] loadThreads retry failed: ${err.message}`);
            })
          })
            .layoutWeight(1)
        } else {
          // 可折叠头部
          this.HeaderBuilder()

          // Tab 栏
          this.TabBarBuilder()

          // 帖子列表
          Refresh({ refreshing: $$this.isRefreshing }) {
            List({ scroller: this.scroller }) {
              LazyForEach(this.dataSource, (thread: ThreadInfo) => {
                ListItem() {
                  ThreadCard({
                    thread: thread,
                    imageLoadType: this.imageLoadTypeState.value,
                    isWifi: this.isWifiState.value,
                    onCardClick: () => this.navigateToThread(thread.tid),
                    onAuthorClick: () => this.navigateToUserProfile(
                      thread.author.portrait,
                      thread.author.name,
                      thread.author.uid
                    ),
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
                .margin({ top: 4, bottom: 4 })
              }, (thread: ThreadInfo) => thread.tid.toString())

              if (this.isLoading && this.threadCount > 0) {
                ListItem() {
                  LoadingView({ message: getResourceString($r('app.string.loading_more')) })
                    .height(60)
                }
              }
            }
            .width('100%')
            .divider({ strokeWidth: 0 })
            .scrollBar(BarState.Off)
            .edgeEffect(EdgeEffect.Spring)
            .cachedCount(5, true)
            .padding({ left: 16, right: 16 })
            .clip(false)
            .backgroundColor($r('app.color.page_background'))
            .onReachEnd(() => this.onReachEnd())
            .onDidScroll((scrollOffset: number, scrollState: ScrollState) => {
              // P1-8 修复：Fling 状态也响应头部折叠/展开
              // onDidScroll 仅在滚动中触发（Scroll/Fling），滚动停止由 onScrollStop 处理
              // 代码触发的滚动（如 scrollEdge）也会触发 onDidScroll，但 offset 通常为 0 或很小
              this.onListScroll(scrollOffset);
            })
            .onScrollStop(() => {
              // 滚动停止时吸附头部到 0 或 HEADER_EXPANDED_HEIGHT
              // onDidScroll 的 Idle 状态触发不可靠，改用 onScrollStop 确保吸附
              this.snapHeader();
            })
          }
          .layoutWeight(1)
          .clip(false)
          .backgroundColor($r('app.color.page_background'))
          .onRefreshing(() => this.onRefresh())
        }
      }
      .width('100%')
      .height('100%')
      .padding({ top: this.statusBarHeight + TITLE_BAR_HEIGHT })
      .backgroundColor($r('app.color.page_background'))

      // FAB 浮在右下角（Stack BottomEnd 对齐 + margin 避让安全区域）
      this.FabBuilder()
      }
    }
    .titleBar({
      content: {
        title: { mainTitle: '' },
        stackBuilder: (): void => this.forumAvatarBuilder(),
        menu: {
          value: [{
            content: {
              icon: $r('app.media.ic_search'),
              isEnabled: true,
              action: () => this.navigateToSearch()
            }
          }, {
            content: {
              icon: $r('app.media.ic_more'),
              isEnabled: true,
              action: () => {
                this.showMoreMenu();
              }
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
