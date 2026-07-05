import { router } from '@kit.ArkUI';
import { TiebaAPI } from '../../api/TiebaAPI';
import { ThreadInfo, ForumInfo, SelfFollowForum, PageData } from '../../model/ForumModels';
import { ThreadCard } from '../../components/ThreadCard';
import { LoadingView } from '../../components/LoadingView';
import { getResourceString } from '../../utils/ResourceUtil';
import { ErrorView } from '../../components/ErrorView';
import { BaseViewModel, FetchDataResult } from '../../viewmodel/BaseViewModel';
import { handleThreadAgree, handleThreadDisagree } from '../../utils/ThreadInteractionHelper';
import { CommonDataSource } from '../../utils/CommonDataSource';
import { getStatusBarHeight } from '../../utils/StatusBarUtil';
import { shouldLoad, getAvatarImageUrl } from '../../utils/ImageLoadUtil';

/** ForumPage 路由参数 */
interface ForumPageParams {
  forumName?: string;
}

class ForumViewModel extends BaseViewModel<ThreadInfo> {
  private forumName: string = '';
  private sortType: number = 1;
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

@Entry
@Component
struct ForumPage {
  private viewModel: ForumViewModel = new ForumViewModel();

  @State forumName: string = '';
  private dataSource: CommonDataSource<ThreadInfo> = new CommonDataSource<ThreadInfo>();
  @State threadCount: number = 0;
  @State isLoading: boolean = false;
  @State isRefreshing: boolean = false;
  @State hasMore: boolean = true;
  @State errorMessage: string = '';
  @State sortType: number = 1;
  @State isGood: boolean = false;
  // 状态栏高度（vp），沉浸式避让状态栏，默认 36，aboutToAppear 动态获取
  @State statusBarHeight: number = 36;
  // Bug #2 修复：aboutToAppear 完成标志，false 时不渲染 List，避免 onReachEnd 在 forumName 设置前触发空请求
  @State isReady: boolean = false;
  // 吧 id（fid），从 getThreads 响应的 forum.id 提取，关注/取消关注 API 必传参数
  @State forumId: number = 0;
  // 当前用户是否已关注该吧（本地状态，FrsPage 不返回 isFollowed，默认 false，点击后切换）
  @State isFollowing: boolean = false;
  // 关注操作进行中锁，避免连点导致重复请求
  @State isFollowLoading: boolean = false;
  // 是否已检查过关注状态（避免每次 syncState 都发请求），首次拿到 forumId 后检查一次
  private hasCheckedFollowing: boolean = false;
  // 吧头像 URL（从 getThreads 响应的 forum.avatar 提取，顶部导航栏显示）
  @State forumAvatar: string = '';
  // #81 图片加载策略：通过 AppStorage 共享，SettingsPage 修改后自动响应
  @StorageProp('imageLoadType') imageLoadType: number = 0;
  @StorageProp('isWifi') isWifi: boolean = false;
  // #93 底部安全高度，避让系统手势条
  @StorageProp('safeBottom') safeBottom: number = 0;

  // Toast 提示 helper（API 12+ 推荐用 UIContext.getPromptAction() 替代全局 promptAction）
  private showToast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message });
  }

  async aboutToAppear() {
    // Bug #2 修复：先读取 router params 并设置 forumName，避免 await 期间 build() 执行时 forumName 为空
    const params = router.getParams() as ForumPageParams;
    if (params && params.forumName) {
      this.forumName = params.forumName;
      this.viewModel.setForumName(this.forumName);
    }
    // 获取状态栏高度（沉浸式，P1 重构提取为 StatusBarUtil），失败不阻塞
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
    try {
      if (this.isFollowing) {
        // 已关注 → 取消关注
        await TiebaAPI.unfollowForum(this.forumId, this.forumName);
        this.isFollowing = false;
        this.showToast(getResourceString($r('app.string.unfollow_forum_success')));
        // 通知首页刷新关注吧列表
        AppStorage.setOrCreate('forumsNeedRefresh', Date.now());
        // 取消关注成功后留在当前页，不 router.back
      } else {
        // 未关注 → 关注
        await TiebaAPI.followForum(this.forumId, this.forumName);
        this.isFollowing = true;
        this.showToast(getResourceString($r('app.string.follow_forum_success')));
        // 通知首页刷新关注吧列表
        AppStorage.setOrCreate('forumsNeedRefresh', Date.now());
        // 关注成功后返回上一页（通常是 HomePage），让用户看到新关注的吧
        router.back();
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
    router.pushUrl({
      url: 'pages/thread/ThreadPage',
      params: { tid: tid.toString() }
    }).catch((err: Error) => {
      console.error(`[ForumPage] navigate to thread failed: ${err.message}`);
    });
  }

  navigateToUserProfile(portrait: string, userName: string, uid: number): void {
    router.pushUrl({
      url: 'pages/user/UserProfilePage',
      params: {
        portrait: portrait,
        userName: userName,
        uid: uid
      }
    }).catch((err: Error) => {
      console.error(`[ForumPage] navigate to userProfile failed: ${err.message}`);
    });
  }

  /** 点赞/取消赞（issue #17，#31 改 LazyForEach），主题帖 pid=0。@Observed+@ObjectLink 自动局部刷新 */
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

  build() {
    Column() {
      // 顶部导航栏：返回 + 贴吧名（layoutWeight 自适应剩余空间） + 排序/精品按钮
      // 改用 Row 替代原 Stack+padding44 方案，长吧名用 Ellipsis 截断，不会被左右按钮遮挡
      Row() {
        Image($r('app.media.ic_back'))
          .width(20)
          .height(20)
          .fillColor($r('app.color.primary'))
          .onClick(() => {
            router.back();
          })

        // 吧头像（36x36 圆形，borderRadius(18)）
        // 有 avatar URL 且图片加载策略允许时显示网络图，否则用渐变背景 + 首字母 fallback
        // #81 shouldLoad=false（如智能无图+移动网络）时走首字母 fallback，省流且 UX 一致
        if (this.forumAvatar.length > 0 && shouldLoad(this.imageLoadType, this.isWifi)) {
          Image(getAvatarImageUrl(this.forumAvatar, this.imageLoadType, this.isWifi))
            .width(36)
            .height(36)
            .borderRadius(18)
            .objectFit(ImageFit.Cover)
            .backgroundColor($r('app.color.input_background'))
            .alt($r('app.media.startIcon'))
            .margin({ left: 8 })
            // #92 HitTestMode.Transparent：让触控穿透到父 Row，避免点击头像触发返回
            .hitTestBehavior(HitTestMode.Transparent)
        } else {
          Column() {
            Text(this.forumName.length > 0 ? this.forumName.charAt(0).toUpperCase() : '?')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
          }
          .width(36)
          .height(36)
          .borderRadius(18)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .margin({ left: 8 })
          .linearGradient({
            angle: 135,
            colors: [[$r('app.color.primary'), 0.0], [$r('app.color.accent_blue'), 1.0]]
          })
        }

        Text(this.forumName)
          .fontSize(18)
          .fontWeight(600)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .margin({ left: 8, right: 8 })

        Row() {
          // 关注/已关注按钮（issue 功能1）：forumId 加载完成后才显示
          // 未关注：primary 色 + primary_light 背景；已关注：text_secondary 色 + input_background
          if (this.forumId > 0) {
            Text(this.isFollowing ? $r('app.string.forum_following') : $r('app.string.forum_follow'))
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.isFollowing ? $r('app.color.text_secondary') : $r('app.color.primary'))
              .backgroundColor(this.isFollowing ? $r('app.color.input_background') : $r('app.color.primary_light'))
              .padding({ left: 10, right: 10, top: 4, bottom: 4 })
              .borderRadius(12)
              .onClick(() => {
                this.handleFollowForum().catch((err: Error) => {
                  console.error(`[ForumPage] handleFollowForum failed: ${err.message}`);
                });
              })
          }

          Text(this.sortType === 1 ? $r('app.string.forum_sort_reply') : $r('app.string.forum_sort_post'))
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.primary'))
            .backgroundColor($r('app.color.primary_light'))
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .borderRadius(12)
            .margin({ left: this.forumId > 0 ? 8 : 0 })
            .onClick(() => {
              this.sortType = this.sortType === 1 ? 2 : 1;
              this.loadThreads(true).catch((err: Error) => {
                console.error(`[ForumPage] loadThreads sort change failed: ${err.message}`);
              });
            })

          Text(this.isGood ? $r('app.string.forum_filter_all') : $r('app.string.forum_filter_good'))
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.primary'))
            .backgroundColor($r('app.color.primary_light'))
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .borderRadius(12)
            .margin({ left: 8 })
            .onClick(() => {
              this.isGood = !this.isGood;
              this.loadThreads(true).catch((err: Error) => {
                console.error(`[ForumPage] loadThreads filter change failed: ${err.message}`);
              });
            })
        }
      }
      .width('100%')
      .height(56 + this.statusBarHeight)
      .padding({ left: 16, right: 16, top: this.statusBarHeight })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
      .alignItems(VerticalAlign.Center)
      .backgroundColor($r('app.color.card_background'))

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
        List() {
          LazyForEach(this.dataSource, (thread: ThreadInfo) => {
            ListItem() {
              ThreadCard({
                thread: thread,
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
        .cachedCount(5)
        // #93 padding bottom = safeBottom + 16：避让系统手势条，backgroundColor 与外层一致消除遮罩
        .padding({ left: 16, right: 16, bottom: this.safeBottom + 16 })
        .backgroundColor($r('app.color.page_background'))
        .onReachEnd(() => this.onReachEnd())
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
    // #93 背景延伸到系统手势条区域，消除底部遮罩
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }
}
