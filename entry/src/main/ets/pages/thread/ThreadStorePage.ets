// 收藏帖子列表页（issue #49 切片2）
// 数据来源：TiebaAPI.getThreadStore（/c/f/post/threadstore）
// 入口：ProfilePage "我的收藏" 菜单项
// 展示已收藏的帖子，点击跳转 ThreadPage

import { router } from '@kit.ArkUI';
import { TiebaAPI } from '../../api/TiebaAPI';
import { ThreadInfo } from '../../model/ForumModels';
import { ThreadCard } from '../../components/ThreadCard';
import { LoadingView } from '../../components/LoadingView';
import { ErrorView } from '../../components/ErrorView';
import { getResourceString } from '../../utils/ResourceUtil';
import { getStatusBarHeight } from '../../utils/StatusBarUtil';
import { handleThreadAgree, handleThreadDisagree } from '../../utils/ThreadInteractionHelper';
import { BaseViewModel, FetchDataResult } from '../../viewmodel/BaseViewModel';
import { CommonDataSource } from '../../utils/CommonDataSource';

/**
 * 收藏列表 ViewModel
 * 调用 TiebaAPI.getThreadStore（/c/f/post/threadstore，offset 分页）
 */
class ThreadStoreViewModel extends BaseViewModel<ThreadInfo> {
  // 每页收藏数（对齐原 app 默认 res_num）
  private static readonly PAGE_SIZE: number = 20;

  protected async fetchData(page: number, isRefresh: boolean): Promise<FetchDataResult<ThreadInfo>> {
    // BaseViewModel currentPage 从 1 开始，getThreadStore page 从 0 开始（对齐 Android），需 -1
    return await TiebaAPI.getThreadStore(page - 1, ThreadStoreViewModel.PAGE_SIZE);
  }
}

@Entry
@Component
struct ThreadStorePage {
  private viewModel: ThreadStoreViewModel = new ThreadStoreViewModel();
  private dataSource: CommonDataSource<ThreadInfo> = new CommonDataSource<ThreadInfo>();

  @State threadCount: number = 0;
  @State isLoading: boolean = false;
  @State isRefreshing: boolean = false;
  @State hasMore: boolean = true;
  @State errorMessage: string = '';
  // 状态栏高度（vp），沉浸式避让，默认 36，aboutToAppear 动态获取
  @State statusBarHeight: number = 36;
  @StorageProp('safeBottom') safeBottom: number = 0;

  // Toast 提示 helper（API 12+ 推荐用 UIContext.getPromptAction() 替代全局 promptAction）
  private showToast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message });
  }

  async aboutToAppear() {
    // 获取状态栏高度（沉浸式，失败时保留默认 36，不阻塞页面初始化）
    try {
      this.statusBarHeight = await getStatusBarHeight(getContext(this));
    } catch (err) {
      console.error(`[ThreadStorePage] getStatusBarHeight failed: ${(err as Error).message}`);
    }
    this.loadThreads(true).catch((err: Error) => {
      console.error(`[ThreadStorePage] loadThreads failed: ${err.message}`);
    });
  }

  async loadThreads(isRefresh: boolean = false): Promise<void> {
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
    if (this.viewModel.canLoadMore()) {
      this.loadThreads(false).catch((err: Error) => {
        console.error(`[ThreadStorePage] loadThreads more failed: ${err.message}`);
      });
    }
  }

  navigateToThread(tid: number): void {
    if (tid <= 0) {
      console.warn(`[ThreadStorePage] invalid tid: ${tid}, skip navigation`);
      return;
    }
    router.pushUrl({
      url: 'pages/thread/ThreadPage',
      params: { tid: tid.toString() }
    }).catch((err: Error) => {
      console.error(`[ThreadStorePage] navigate to thread failed: ${err.message}`);
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
      console.error(`[ThreadStorePage] navigate to userProfile failed: ${err.message}`);
    });
  }

  /** 点赞（issue #17） */
  async handleAgree(thread: ThreadInfo): Promise<void> {
    await handleThreadAgree(this.dataSource, thread, this.getUIContext());
  }

  async handleDisagree(thread: ThreadInfo): Promise<void> {
    await handleThreadDisagree(this.dataSource, thread, this.getUIContext());
  }

  /** 评论按钮点击：提示功能开发中 */
  showCommentToast(): void {
    this.showToast(getResourceString($r('app.string.page_developing')));
  }

  build() {
    Column() {
      // 顶部导航栏（对齐原型 detail-nav，44px + 状态栏，返回按钮 primary 蓝）
      Row() {
        Image($r('app.media.ic_back'))
          .width(20)
          .height(20)
          .fillColor($r('app.color.primary'))
          .onClick(() => {
            router.back();
          })

        Text($r('app.string.thread_store_title'))
          .fontSize(17)
          .fontWeight(600)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .margin({ left: 8, right: 8 })

        // 右侧占位，保持标题居中
        Row()
          .width(20)
          .height(20)
      }
      .width('100%')
      .height(44 + this.statusBarHeight)
      .padding({ left: 16, right: 16, top: this.statusBarHeight })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
      .alignItems(VerticalAlign.Center)
      .backgroundColor($r('app.color.page_background'))

      // 内容区
      if (this.errorMessage.length > 0 && this.threadCount === 0) {
        ErrorView({
          message: this.errorMessage,
          onRetryClick: () => this.loadThreads(true).catch((err: Error) => {
            console.error(`[ThreadStorePage] loadThreads retry failed: ${err.message}`);
          })
        })
          .layoutWeight(1)
      } else if (this.threadCount === 0 && !this.isLoading) {
        // 空状态
        Column() {
          Text($r('app.string.thread_store_empty'))
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
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
                    console.error(`[ThreadStorePage] handleAgree failed: ${err.message}`);
                  });
                },
                onDisagreeClick: (t: ThreadInfo) => {
                  this.handleDisagree(t).catch((err: Error) => {
                    console.error(`[ThreadStorePage] handleDisagree failed: ${err.message}`);
                  });
                },
                onCommentClick: () => this.showCommentToast()
              })
                .margin({ top: 4, bottom: 4 })
            }
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
        .padding({ left: 16, right: 16, bottom: this.safeBottom + 16 })
        .backgroundColor($r('app.color.page_background'))
        .onReachEnd(() => this.onReachEnd())
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }
}
