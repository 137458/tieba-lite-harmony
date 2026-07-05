import { router } from '@kit.ArkUI';
import { TiebaAPI } from '../../api/TiebaAPI';
import { ThreadInfo } from '../../model/ForumModels';
import { ThreadCard } from '../../components/ThreadCard';
import { LoadingView } from '../../components/LoadingView';
import { getResourceString } from '../../utils/ResourceUtil';
import { ErrorView } from '../../components/ErrorView';
import { BaseViewModel, FetchDataResult } from '../../viewmodel/BaseViewModel';
import { handleThreadAgree, handleThreadDisagree } from '../../utils/ThreadInteractionHelper';
import { CommonDataSource } from '../../utils/CommonDataSource';
import { getStatusBarHeight } from '../../utils/StatusBarUtil';

/** ForumPage 路由参数 */
interface ForumPageParams {
  forumName?: string;
}

class ForumViewModel extends BaseViewModel<ThreadInfo> {
  private forumName: string = '';
  private sortType: number = 1;
  private isGood: boolean = false;

  setForumName(name: string): void {
    this.forumName = name;
  }

  setSortType(type: number): void {
    this.sortType = type;
  }

  setIsGood(good: boolean): void {
    this.isGood = good;
  }

  protected async fetchData(page: number, isRefresh: boolean): Promise<FetchDataResult<ThreadInfo>> {
    return await TiebaAPI.getThreads(
      this.forumName,
      page,
      this.sortType,
      this.isGood
    );
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
    } else {
      this.dataSource.appendData(this.viewModel.lastAddedList);
    }
    this.threadCount = this.dataSource.totalCount();
    this.hasMore = paginationData.hasMore;
    this.isLoading = loadingState.isLoading;
    this.isRefreshing = loadingState.isRefreshing;
    this.errorMessage = loadingState.error;
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
          Text(this.sortType === 1 ? $r('app.string.forum_sort_reply') : $r('app.string.forum_sort_post'))
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.primary'))
            .backgroundColor($r('app.color.primary_light'))
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .borderRadius(12)
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
        .padding({ left: 16, right: 16 })
        .onReachEnd(() => this.onReachEnd())
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }
}
