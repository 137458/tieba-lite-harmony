// 动态页（"收藏"tab，issue #50 切片3）
// 原占位 PagePlaceholder 替换为关注吧帖子聚合流
// 数据来源：TiebaAPI.getUserLikeFlow（/c/f/concern/userlike?cmd=309474，protobuf）
// 分页：pageTag 游标（非 page number），刷新 pageTag="" + loadType=1，加载更多用上次响应 pageTag + loadType=2

import { router, promptAction } from '@kit.ArkUI';
import { TiebaAPI } from '../../api/TiebaAPI';
import { ThreadInfo, UserLikeResult } from '../../model/ForumModels';
import { ThreadCard } from '../../components/ThreadCard';
import { LoadingView } from '../../components/LoadingView';
import { ErrorView } from '../../components/ErrorView';
import { getResourceString } from '../../utils/ResourceUtil';
import { getStatusBarHeight } from '../../utils/StatusBarUtil';
import { handleThreadAgree, handleThreadDisagree } from '../../utils/ThreadInteractionHelper';
import { BaseViewModel, FetchDataResult } from '../../viewmodel/BaseViewModel';
import { CommonDataSource } from '../../utils/CommonDataSource';
import { AppStorageManager } from '../../data/AppStorage';

/**
 * 动态页 ViewModel
 * 适配 pageTag 游标分页：内部维护 nextPageTag，fetchData 不依赖 page 参数
 * - isRefresh=true: pageTag="" + loadType=1
 * - isRefresh=false: pageTag=nextPageTag + loadType=2
 */
class UserLikeViewModel extends BaseViewModel<ThreadInfo> {
  // 下次加载更多的 pageTag 游标（刷新时清空，加载更多后用响应的 pageTag 更新）
  private nextPageTag: string = '';

  protected async fetchData(page: number, isRefresh: boolean): Promise<FetchDataResult<ThreadInfo>> {
    const pageTag: string = isRefresh ? '' : this.nextPageTag;
    const loadType: number = isRefresh ? 1 : 2;
    const result: UserLikeResult = await TiebaAPI.getUserLikeFlow(pageTag, loadType);

    // 更新 nextPageTag 供下次 loadMore 使用
    this.nextPageTag = result.pageTag;

    const fetchResult: FetchDataResult<ThreadInfo> = {
      list: result.threadList,
      hasMore: result.hasMore,
      // currentPage 占位，BaseViewModel 用 currentPage+1 调 loadMore，但本子类不依赖 page 参数
      currentPage: page
    };
    return fetchResult;
  }
}

@Component
export struct FavoritePage {
  private viewModel: UserLikeViewModel = new UserLikeViewModel();
  private dataSource: CommonDataSource<ThreadInfo> = new CommonDataSource<ThreadInfo>();

  @State threadCount: number = 0;
  @State isLoading: boolean = false;
  @State isRefreshing: boolean = false;
  @State hasMore: boolean = true;
  @State errorMessage: string = '';
  // 状态栏高度（vp），沉浸式避让，默认 36，aboutToAppear 动态获取
  @State statusBarHeight: number = 36;
  // 是否已登录（未登录显示登录引导）
  @State bduss: string = '';

  async aboutToAppear() {
    this.statusBarHeight = await getStatusBarHeight(getContext(this));
    // 检查登录状态
    const storage: AppStorageManager = AppStorageManager.getInstance();
    await storage.ensureReady();
    this.bduss = await storage.getString('bduss', '');
    // 已登录才加载动态流
    if (this.bduss.length > 0) {
      this.loadThreads(true).catch((err: Error) => {
        console.error(`[FavoritePage] loadThreads failed: ${err.message}`);
      });
    }
  }

  async loadThreads(isRefresh: boolean = false): Promise<void> {
    await this.viewModel.loadData(isRefresh);
    this.syncState();
  }

  private syncState(): void {
    const paginationData = this.viewModel.paginationData;
    const loadingState = this.viewModel.loadingState;

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
      this.loadThreads(false);
    }
  }

  navigateToThread(tid: number): void {
    if (tid <= 0) {
      console.warn(`[FavoritePage] invalid tid: ${tid}, skip navigation`);
      return;
    }
    router.pushUrl({
      url: 'pages/thread/ThreadPage',
      params: { tid: tid.toString() }
    }).catch((err: Error) => {
      console.error(`[FavoritePage] navigate to thread failed: ${err.message}`);
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
      console.error(`[FavoritePage] navigate to userProfile failed: ${err.message}`);
    });
  }

  /** 点赞（issue #17） */
  async handleAgree(thread: ThreadInfo): Promise<void> {
    await handleThreadAgree(this.dataSource, thread);
  }

  async handleDisagree(thread: ThreadInfo): Promise<void> {
    await handleThreadDisagree(this.dataSource, thread);
  }

  /** 评论按钮点击：提示功能开发中 */
  showCommentToast(): void {
    promptAction.showToast({ message: getResourceString($r('app.string.page_developing')) });
  }

  /** 跳转到登录页（未登录时点击触发） */
  navigateToLogin(): void {
    router.pushUrl({ url: 'pages/main/LoginPage' }).catch((err: Error) => {
      console.error(`[FavoritePage] navigate to login failed: ${err.message}`);
    });
  }

  build() {
    Column() {
      // 顶部标题栏（标题左对齐，tab 内页面无返回按钮）
      Row() {
        Text($r('app.string.favorite_page_title'))
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .textAlign(TextAlign.Start)
      }
      .width('100%')
      .height(56 + this.statusBarHeight)
      .padding({ left: 16, right: 16, top: this.statusBarHeight })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
      .alignItems(VerticalAlign.Center)
      .backgroundColor($r('app.color.background'))

      // 内容区
      if (this.bduss.length === 0) {
        // 未登录：登录引导
        Column() {
          Text($r('app.string.favorite_login_required'))
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .margin({ bottom: 12 })
          Text($r('app.string.login_button'))
            .fontSize(14)
            .fontColor($r('app.color.primary'))
            .padding({ left: 24, right: 24, top: 8, bottom: 8 })
            .border({ width: 1, color: $r('app.color.primary'), radius: 20 })
            .onClick(() => this.navigateToLogin())
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.errorMessage.length > 0 && this.threadCount === 0) {
        ErrorView({
          message: this.errorMessage,
          onRetryClick: () => this.loadThreads(true)
        })
          .layoutWeight(1)
      } else if (this.threadCount === 0 && !this.isLoading) {
        // 空状态
        Column() {
          Text($r('app.string.favorite_empty'))
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
                    console.error(`[FavoritePage] handleAgree failed: ${err.message}`);
                  });
                },
                onDisagreeClick: (t: ThreadInfo) => {
                  this.handleDisagree(t).catch((err: Error) => {
                    console.error(`[FavoritePage] handleDisagree failed: ${err.message}`);
                  });
                },
                onCommentClick: () => this.showCommentToast()
              })
                .margin({ left: 12, right: 12, top: 8 })
            }
          }, (thread: ThreadInfo) => thread.tid.toString())

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
        .edgeEffect(EdgeEffect.Spring)
        .cachedCount(5)
        .onReachEnd(() => this.onReachEnd())
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }
}
