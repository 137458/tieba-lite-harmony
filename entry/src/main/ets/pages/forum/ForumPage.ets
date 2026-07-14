import { HdsNavDestination, ScrollEffectType, hdsMaterial } from '@kit.UIDesignKit';
import { TiebaAPI } from '../../api/TiebaAPI';
import { ImageLoadTypeState, IsWifiState, SafeBottomState, connectImageLoadType, connectIsWifi, connectForumsNeedRefresh } from '../../model/AppStorageV2Models';
import { ThreadInfo, ForumInfo, SelfFollowForum, PageData } from '../../model/ForumModels';
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
import { RouterUtil, ThreadNavParams, ForumNavParams, UserProfileNavParams } from '../../utils/RouterUtil';
import { getStatusBarHeight } from '../../utils/StatusBarUtil';

/** 排序方式常量（对齐 aiotieba ThreadSortType） */
const SORT_REPLY: number = 6;   // 按回复时间（默认）
const SORT_CREATE: number = 1;  // 按发布时间
// HdsNavDestination titleBar mini 模式高度，用于内容区顶部占位避让
const TITLE_BAR_HEIGHT: number = 48;

class ForumViewModel extends BaseViewModel<ThreadInfo> {
  private forumName: string = '';
  private sortType: number = SORT_REPLY;
  private isGood: boolean = false;
  // 吧信息（含 fid），从 getThreads 响应的 forum 字段提取，用于关注/取消关注吧
  private forumInfo: ForumInfo = new ForumInfo();

  setForumName(name: string): void {
    this.forumName = name;
  }

  setSortType(type: number): void {
    this.sortType = type;
  }

  setIsGood(good: boolean): void {
    this.isGood = good;
  }

  /** 获取最近一次拉取到的吧信息（含 fid） */
  getForumInfo(): ForumInfo {
    return this.forumInfo;
  }

  protected async fetchData(page: number, isRefresh: boolean): Promise<FetchDataResult<ThreadInfo>> {
    // getThreads 返回 FrsPageResult（含 forum + threads），forum.id 是 fid
    const result = await TiebaAPI.getThreads(
      this.forumName,
      page,
      this.sortType,
      this.isGood
    );
    // 提取吧信息（关注/取消关注 API 需要 fid + kw）
    this.forumInfo = result.forum;
    // 返回 threads 分页数据（PageData<ThreadInfo> 结构兼容 FetchDataResult<ThreadInfo>）
    return result.threads;
  }
}

// #164 [A4-S4] Navigation 路由表 @Builder：供 router_map.json 的 buildFunction 引用
@Builder
export function ForumPageBuilder() {
  ForumPage()
}

@ComponentV2
export struct ForumPage {
  private viewModel: ForumViewModel = new ForumViewModel();

  @Local forumName: string = '';
  private dataSource: CommonDataSource<ThreadInfo> = new CommonDataSource<ThreadInfo>();
  @Local threadCount: number = 0;
  @Local isLoading: boolean = false;
  @Local isRefreshing: boolean = false;
  @Local hasMore: boolean = true;
  @Local errorMessage: string = '';
  @Local sortType: number = SORT_REPLY;
  @Local isGood: boolean = false;
  // #164 滚动器，绑定到 HdsNavDestination.bindToScrollable 实现标题栏滚动动态模糊
  private scroller: Scroller = new Scroller();
  // Bug #2 修复：aboutToAppear 完成标志，false 时不渲染 List，避免 onReachEnd 在 forumName 设置前触发空请求
  @Local isReady: boolean = false;
  // 吧 id（fid），从 getThreads 响应的 forum.id 提取，关注/取消关注 API 必传参数
  @Local forumId: number = 0;
  // 当前用户是否已关注该吧（本地状态，FrsPage 不返回 isFollowed，默认 false，点击后切换）
  @Local isFollowing: boolean = false;
  // 关注操作进行中锁，避免连点导致重复请求
  @Local isFollowLoading: boolean = false;
  // 是否已检查过关注状态（避免每次 syncState 都发请求），首次拿到 forumId 后检查一次
  private hasCheckedFollowing: boolean = false;
  // 吧头像 URL（从 getThreads 响应的 forum.avatar 提取，顶部导航栏显示）
  @Local forumAvatar: string = '';
  // #81 图片加载策略：通过 AppStorage 共享，SettingsPage 修改后自动响应
  @Local imageLoadTypeState: ImageLoadTypeState = connectImageLoadType();
  @Local isWifiState: IsWifiState = connectIsWifi();
  @Local themeState: ThemeState = connectTheme();
  // 状态栏高度（hideTitleBar 模式下自定义顶部栏需避让状态栏）
  @Local statusBarHeight: number = 36;

  // Toast 提示 helper（API 12+ 推荐用 UIContext.getPromptAction() 替代全局 promptAction）
  private showToast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message });
  }

  async aboutToAppear() {
    // #203 注入 DataSource 引用，供 BaseViewModel 内存压力时自动 clearCache
    this.viewModel.setDataSource(this.dataSource);
    // #164 路由迁移：router.getParams() → NavPathStack.getParamByName()
    // SDK 返回 Array<unknown>，ArkTS 不支持 unknown，用 as Object[] 断言
    const paramsStack: Object[] = RouterUtil.getStack().getParamByName(RouterUtil.ROUTE_FORUM_PAGE) as Object[];
    if (paramsStack && paramsStack.length > 0) {
      const params = paramsStack[paramsStack.length - 1] as ForumNavParams;
      if (params && params.forumName && params.forumName.length > 0) {
        this.forumName = params.forumName;
        this.viewModel.setForumName(this.forumName);
        // 从路由参数接收吧头像（HomePage 已关注吧列表传入）
        // FrsPage protobuf 响应不返回 avatar 字段，未关注吧需通过其他接口或参数传入
        if (params.forumAvatar && params.forumAvatar.length > 0) {
          this.forumAvatar = params.forumAvatar;
        }
      }
    }
    // 获取状态栏高度，用于自定义顶部栏避让状态栏
    try {
      this.statusBarHeight = await getStatusBarHeight(getContext(this));
    } catch (err) {
      console.error(`[ForumPage] getStatusBarHeight failed: ${(err as Error).message}`);
    }
    // Bug #2 修复：标记 ready，允许渲染 List
    this.isReady = true;
    // 最后加载数据
    if (this.forumName.length > 0) {
      this.loadThreads(true).catch((err: Error) => {
        console.error(`[ForumPage] loadThreads failed: ${err.message}`);
      });
    }
  }

  aboutToDisappear(): void {
    // #203 清理 ViewModel 持有的 DataSource 引用，防止 ViewModel 被全局缓存时引用泄漏
    this.viewModel.setDataSource(null);
  }

  async loadThreads(isRefresh: boolean = false): Promise<void> {
    // Bug #2 修复：forumName 未设置时不加载，避免空 forumName 请求
    if (this.forumName.length === 0) {
      return;
    }
    this.viewModel.setSortType(this.sortType);
    this.viewModel.setIsGood(this.isGood);
    await this.viewModel.loadData(isRefresh);
    this.syncState();
  }

  private syncState(): void {
    const paginationData = this.viewModel.paginationData;
    const loadingState = this.viewModel.loadingState;

    // issue #39：刷新用 setData 全量替换，loadMore 用 appendData 增量追加
    if (this.viewModel.lastOpWasRefresh) {
      this.dataSource.setData(paginationData.dataList);
      // 刷新时同步吧信息（fid 从 getThreads 响应 forum 字段提取）
      // 仅在 forum.id > 0 时更新，避免空响应覆盖已有 forumId
      const forumInfo: ForumInfo = this.viewModel.getForumInfo();
      if (forumInfo.id > 0) {
        this.forumId = forumInfo.id;
        // 同步吧头像 URL（顶部导航栏显示）
        this.forumAvatar = forumInfo.avatar;
        // 首次拿到 forumId 后检查关注状态（FrsPage 不返回 isFollowed，需调用 getFollowForums 查询）
        // hasCheckedFollowing 标志位避免每次刷新都发请求
        if (!this.hasCheckedFollowing) {
          this.hasCheckedFollowing = true;
          this.checkFollowingStatus().catch((err: Error) => {
            console.error(`[ForumPage] checkFollowingStatus failed: ${err.message}`);
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
   * FrsPage 响应不返回 isFollowed 字段，需调用 getFollowForums 查询本地关注的吧列表
   * 在列表中查找 forumId，匹配则 isFollowing=true
   * 同时从关注列表提取吧头像（FrsPage protobuf 不返回 avatar 字段）
   * 检查失败不阻塞，保持默认 isFollowing=false
   */
  private async checkFollowingStatus(): Promise<void> {
    try {
      // 加载关注的吧列表（第一页，rn=100 覆盖大部分用户）
      const result: PageData<SelfFollowForum> = await TiebaAPI.getFollowForums(1, 100);
      // 遍历列表，检查 forumId 是否匹配
      for (let i = 0; i < result.list.length; i++) {
        if (result.list[i].fid === this.forumId) {
          this.isFollowing = true;
          // 从关注列表提取吧头像（FrsPage 不返回 avatar，getFollowForums 返回）
          if (result.list[i].avatar.length > 0) {
            this.forumAvatar = result.list[i].avatar;
          }
          return;
        }
      }
      this.isFollowing = false;
    } catch (err) {
      // 检查失败不阻塞，保持默认 isFollowing=false
      console.error(`[ForumPage] checkFollowingStatus failed: ${(err as Error).message}`);
    }
  }

  /** 关注/取消关注吧（issue 功能1）：根据 isFollowing 状态调用对应 API */
  async handleFollowForum(): Promise<void> {
    // 防抖：操作进行中或 forumId 未就绪时直接返回
    if (this.isFollowLoading || this.forumId === 0) {
      if (this.forumId === 0) {
        this.showToast(getResourceString($r('app.string.error_invalid_params')));
      }
      return;
    }
    this.isFollowLoading = true;
    // #121 触感反馈：关注/取消关注贴吧属于强调交互，触发重震动
    VibratorUtil.heavy();
    try {
      if (this.isFollowing) {
        // 已关注 → 取消关注
        await TiebaAPI.unfollowForum(this.forumId, this.forumName);
        this.isFollowing = false;
        this.showToast(getResourceString($r('app.string.unfollow_forum_success')));
        // 通知首页刷新关注吧列表
        const forumsNeedRefreshState = connectForumsNeedRefresh();
        forumsNeedRefreshState.value = Date.now();
        // 取消关注成功后留在当前页，不 router.back
      } else {
        // 未关注 → 关注
        await TiebaAPI.followForum(this.forumId, this.forumName);
        this.isFollowing = true;
        this.showToast(getResourceString($r('app.string.follow_forum_success')));
        // 通知首页刷新关注吧列表
        const forumsNeedRefreshState = connectForumsNeedRefresh();
        forumsNeedRefreshState.value = Date.now();
        // 关注成功后返回上一页（通常是 HomePage），让用户看到新关注的吧
        // #164 路由迁移：router.back() → RouterUtil.back()
        RouterUtil.back();
      }
    } catch (err) {
      const msg: string = (err as Error).message || getResourceString($r('app.string.follow_operation_failed'));
      this.showToast(msg);
    } finally {
      this.isFollowLoading = false;
    }
  }

  onReachEnd(): void {
    // Bug #2 修复：forumName 未设置时不触发 loadMore
    if (this.forumName.length === 0) {
      return;
    }
    if (this.viewModel.canLoadMore()) {
      // onReachEnd 回调不处理 async 返回值，需 catch 避免 unhandled rejection
      this.loadThreads(false).catch((err: Error) => {
        console.error(`[ForumPage] onReachEnd loadThreads failed: ${err.message}`);
      });
    }
  }

  navigateToThread(tid: number): void {
    // 校验 tid 合法性（issue #35），避免导航到无效帖子
    if (tid <= 0) {
      console.warn(`[ForumPage] invalid tid: ${tid}, skip navigation`);
      return;
    }
    // #163 路由迁移：router.pushUrl → RouterUtil.push
    RouterUtil.push(RouterUtil.ROUTE_THREAD_PAGE, new ThreadNavParams(tid));
  }

  navigateToUserProfile(portrait: string, userName: string, uid: number): void {
    // #165 路由迁移：router.pushUrl → RouterUtil.push
    RouterUtil.push(RouterUtil.ROUTE_USER_PROFILE_PAGE,
      new UserProfileNavParams(portrait, userName, uid));
  }

  /** 点赞/取消赞（issue #17，#31 改 LazyForEach），主题帖 pid=0。@ObservedV2+@Trace+@Require @Param 自动局部刷新 */
  async handleAgree(thread: ThreadInfo): Promise<void> {
    await handleThreadAgree(this.dataSource, thread, this.getUIContext());
  }

  async handleDisagree(thread: ThreadInfo): Promise<void> {
    await handleThreadDisagree(this.dataSource, thread, this.getUIContext());
  }

  /** 评论按钮提示开发中（issue #17） */
  showCommentToast(): void {
    this.showToast(getResourceString($r('app.string.page_developing')));
  }

  /**
   * 吧头像 + 吧名 Builder：用于 titleBar stackBuilder，固定显示在 titleBar 不随列表滚动
   * 官方文档：stackBuilder 从 6.0.0(20) 起支持，可在自定义构建器中用 Image 加载网络图片
   * 布局：Row(头像32 + 吧名) padding left 48 避让 back 按钮，right 120 避让 menu
   * titleBar 的 title.mainTitle 设为空字符串，吧名完全靠此 builder 显示，避免遮挡
   * 头像 32x32 与 HDS titleBar 返回按钮（含外层沉浸光感遮罩）视觉大小一致
   */
  @Builder
  forumAvatarBuilder() {
    Row() {
      // 吧头像（34x34 圆形，与 HDS 返回按钮含遮罩视觉大小一致，网络图或首字母 fallback）
      if (this.forumAvatar.length > 0 && shouldLoad(this.imageLoadTypeState.value, this.isWifiState.value)) {
        Image(getAvatarImageUrl(this.forumAvatar, this.imageLoadTypeState.value, this.isWifiState.value))
          .width(34)
          .height(34)
          .borderRadius(17)
          .objectFit(ImageFit.Cover)
          .backgroundColor($r('app.color.input_background'))
          .alt($r('app.media.startIcon'))
          .syncLoad(true)
          .interpolation(ImageInterpolation.Low)
          .onError(() => { /* 头像加载失败静默处理 */ })
          .hitTestBehavior(HitTestMode.Transparent)
      } else {
        Column() {
          Text(this.forumName.length > 0 ? this.forumName.charAt(0).toUpperCase() : '?')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
        }
        .width(34)
        .height(34)
        .borderRadius(17)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .linearGradient({
          angle: 135,
          colors: [[this.themeState.primary, 0.0], [$r('app.color.accent_blue'), 1.0]]
        })
      }

      // 吧名（跟头像同一行，layoutWeight 自适应宽度 + ellipsis 截断避免被 menu 遮挡）
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
    .padding({ left: 52, right: 140 })  // left 52 避让 back 按钮+向右偏移，right 140 避让 menu 三个图标避免吧名...被遮挡
    .alignItems(VerticalAlign.Center)
  }

  build() {
    // 模式三（混合式）：HDS titleBar（title=吧名 + menu 关注/排序/精品图标）+ 外层 Column padding top 避让
    // List clip(false) + cachedCount(_, true) 让内容穿透到 titleBar 下方做模糊
    // 吧头像放在 List 第一个 ListItem 作为 header
    HdsNavDestination() {
      Column() {
        if (!this.isReady) {
          // Bug #2 修复：aboutToAppear 完成前显示加载中，不渲染 List 避免 onReachEnd 触发
          LoadingView({ message: getResourceString($r('app.string.loading')) })
            .layoutWeight(1)
        } else if (this.errorMessage.length > 0 && this.threadCount === 0) {
          ErrorView({
            message: this.errorMessage,
            onRetryClick: () => this.loadThreads(true).catch((err: Error) => {
              console.error(`[ForumPage] loadThreads retry failed: ${err.message}`);
            })
          })
            .layoutWeight(1)
        } else {
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
                      console.error(`[ForumPage] handleAgree failed: ${err.message}`);
                    });
                  },
                  onDisagreeClick: (t: ThreadInfo) => {
                    this.handleDisagree(t).catch((err: Error) => {
                      console.error(`[ForumPage] handleDisagree failed: ${err.message}`);
                    });
                  },
                  onCommentClick: () => this.showCommentToast()
                })
              }
              .margin({ top: 4, bottom: 4 })
            }, (thread: ThreadInfo, index: number) => `${thread.tid}`)

            if (this.isLoading && this.threadCount > 0) {
              ListItem() {
                LoadingView({ message: getResourceString($r('app.string.loading_more')) })
                  .height(60)
              }
            }
          }
          .width('100%')
          .layoutWeight(1)
          .divider({ strokeWidth: 0 })
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
          .cachedCount(5, true)
          .padding({ left: 16, right: 16 })
          // 模式三：clip(false) 让内容穿透到 titleBar 下方，titleBar 对穿透内容做模糊
          .clip(false)
          .backgroundColor($r('app.color.page_background'))
          .onReachEnd(() => this.onReachEnd())
        }
      }
      .width('100%')
      .height('100%')
      // 模式三：外层 Column padding top 避让状态栏 + titleBar
      .padding({ top: this.statusBarHeight + TITLE_BAR_HEIGHT })
      .backgroundColor($r('app.color.page_background'))
    }
    .titleBar({
      content: {
        // title.mainTitle 设为空字符串，吧名完全靠 stackBuilder 显示（头像+吧名同行）
        // 避免系统 title 文字与 stackBuilder 中的吧名重叠
        title: { mainTitle: '' },
        // stackBuilder：吧头像+吧名叠加在 titleBar 上，固定不随列表滚动
        // 官方写法：stackBuilder: (): void => this.xxxBuilder()（箭头函数包装）
        stackBuilder: (): void => this.forumAvatarBuilder(),
        menu: {
          value: [{
            content: {
              // 关注/取消关注：用 + 图标，避免心形被误解为收藏
              icon: $r('app.media.ic_add'),
              isEnabled: true,
              action: () => {
                this.handleFollowForum().catch((err: Error) => {
                  console.error(`[ForumPage] handleFollowForum failed: ${err.message}`);
                });
              }
            }
          }, {
            content: {
              icon: $r('app.media.ic_sort'),
              isEnabled: true,
              action: () => {
                this.sortType = this.sortType === SORT_REPLY ? SORT_CREATE : SORT_REPLY;
                // 切换排序方式时 Toast 提示当前排序
                const tip: string = getResourceString(
                  this.sortType === SORT_REPLY ? $r('app.string.forum_sort_reply') : $r('app.string.forum_sort_post')
                );
                this.showToast(tip);
                this.loadThreads(true).catch((err: Error) => {
                  console.error(`[ForumPage] loadThreads sort change failed: ${err.message}`);
                });
              }
            }
          }, {
            content: {
              icon: $r('app.media.ic_star'),
              isEnabled: true,
              action: () => {
                this.isGood = !this.isGood;
                // 切换精品/全部时 Toast 提示当前筛选
                const tip: string = getResourceString(
                  this.isGood ? $r('app.string.forum_filter_good') : $r('app.string.forum_filter_all')
                );
                this.showToast(tip);
                this.loadThreads(true).catch((err: Error) => {
                  console.error(`[ForumPage] loadThreads filter change failed: ${err.message}`);
                });
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
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
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
