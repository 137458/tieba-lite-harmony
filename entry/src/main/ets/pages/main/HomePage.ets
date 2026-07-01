import { router, window, promptAction } from '@kit.ArkUI';
import { TiebaAPI } from '../../api/TiebaAPI';
import { ThreadInfo } from '../../model/ForumModels';
import { ThreadCard } from '../../components/ThreadCard';
import { LoadingView } from '../../components/LoadingView';
import { ErrorView } from '../../components/ErrorView';
import { AppStorageManager } from '../../data/AppStorage';
import { BaseViewModel, FetchDataResult, dedupByKey } from '../../viewmodel/BaseViewModel';
import { getResourceString } from '../../utils/ResourceUtil';
import { handleThreadAgree, handleThreadDisagree } from '../../utils/ThreadInteractionHelper';
import { CommonDataSource } from '../../utils/CommonDataSource';

class HomeViewModel extends BaseViewModel<ThreadInfo> {
  protected async fetchData(page: number, isRefresh: boolean): Promise<FetchDataResult<ThreadInfo>> {
    // 主页改用个性化推荐 API（issue #45），聚合多吧帖子，避免单一吧内容循环
    const result = await TiebaAPI.getPersonalized(page, 11);

    // 去重：loadMore 时过滤掉已存在 tid 的帖子（对齐原版 distinctById）
    // 防止个性化推荐返回重复内容导致主页循环
    if (!isRefresh && this.paginationState.dataList.length > 0) {
      const deduped = dedupByKey(
        this.paginationState.dataList,
        result.list,
        result.hasMore,
        (t: ThreadInfo) => t.tid
      );
      result.list = deduped.list;
      result.hasMore = deduped.hasMore;
    }

    return result;
  }
}

@Component
export struct HomePage {
  private viewModel: HomeViewModel = new HomeViewModel();

  private dataSource: CommonDataSource<ThreadInfo> = new CommonDataSource<ThreadInfo>();
  @State threadCount: number = 0;
  @State isLoading: boolean = false;
  @State isRefreshing: boolean = false;
  @State hasMore: boolean = true;
  @State errorMessage: string = '';
  @State searchKeyword: string = '';
  @State statusBarHeight: number = 36; // 状态栏高度（vp），默认 36，aboutToAppear 动态获取

  async aboutToAppear() {
    // 获取状态栏高度（沉浸式，issue #18）
    try {
      const mainWindow = await window.getLastWindow(getContext(this));
      const avoidArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      this.statusBarHeight = px2vp(avoidArea.topRect.height);
    } catch (err) {
      // 获取失败保留默认值 36
    }
    this.loadThreads(true);
  }

  async loadThreads(isRefresh: boolean = false): Promise<void> {
    await this.viewModel.loadData(isRefresh);
    this.syncState();
  }

  private syncState(): void {
    const paginationData = this.viewModel.paginationData;
    const loadingState = this.viewModel.loadingState;

    this.dataSource.setData(paginationData.dataList);
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
    router.pushUrl({
      url: 'pages/thread/ThreadPage',
      params: { tid: tid.toString() }
    });
  }

  /** 跳转到作者主页。ThreadInfo.author.avatar 实际是 portrait 标识 */
  navigateToUserProfile(portrait: string, userName: string, uid: number): void {
    router.pushUrl({
      url: 'pages/user/UserProfilePage',
      params: {
        portrait: portrait,
        userName: userName,
        uid: uid
      }
    });
  }

  navigateToForum(forumName: string): void {
    router.pushUrl({
      url: 'pages/forum/ForumPage',
      params: { forumName: forumName }
    });
  }

  /** 跳转到关注吧列表页（issue #43 贴吧切换入口） */
  navigateToFollowForums(): void {
    router.pushUrl({
      url: 'pages/forum/FollowForumsPage'
    });
  }

  handleSearch(): void {
    if (this.searchKeyword.length > 0) {
      router.pushUrl({
        url: 'pages/search/SearchPage',
        params: { keyword: this.searchKeyword }
      });
    }
  }

  /**
   * 点赞/取消赞（issue #17，#31 改 LazyForEach）
   * 主题帖点赞：pid=0，isComment=false
   * ThreadInfo 已 @Observed，ThreadCard @ObjectLink 引用 dataSource 内部对象，
   * handleThreadAgree 修改 target 字段会自动局部刷新
   */
  async handleAgree(thread: ThreadInfo): Promise<void> {
    await handleThreadAgree(this.dataSource, thread);
  }

  async handleDisagree(thread: ThreadInfo): Promise<void> {
    await handleThreadDisagree(this.dataSource, thread);
  }

  /** 评论按钮点击：提示功能开发中（issue #17，评论 API 后续实现） */
  showCommentToast(): void {
    promptAction.showToast({ message: getResourceString($r('app.string.page_developing')) });
  }

  async handleLogout(): Promise<void> {
    await AppStorageManager.getInstance().remove('bduss');
    await AppStorageManager.getInstance().remove('stoken');
    await AppStorageManager.getInstance().remove('tbs');
    await AppStorageManager.getInstance().remove('cuid');
    router.replaceUrl({ url: 'pages/main/LoginPage' });
  }

  build() {
    Column() {
      Row() {
        Text($r('app.string.app_name'))
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary'))

        Row() {
          // 关注吧入口（issue #43 贴吧切换入口）
          Text($r('app.string.follow_forums_entry'))
            .fontSize(14)
            .fontColor($r('app.color.primary'))
            .onClick(() => {
              this.navigateToFollowForums();
            })

          Image('')
            .width(24)
            .height(24)
            .fillColor($r('app.color.text_primary'))
            .margin({ left: 16 })
            .onClick(() => {
              this.handleSearch();
            })

          Image('')
            .width(24)
            .height(24)
            .fillColor($r('app.color.text_primary'))
            .margin({ left: 16 })
            .onClick(() => {
              // TODO: 打开设置页面
            })
        }
      }
      .width('100%')
      .height(56 + this.statusBarHeight)
      .padding({ left: 16, right: 16, top: this.statusBarHeight })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.SpaceBetween)
      .backgroundColor($r('app.color.background'))

      Row() {
        Image('')
          .width(20)
          .height(20)
          .fillColor($r('app.color.text_secondary'))

        TextInput({ placeholder: $r('app.string.search_hint'), text: $$this.searchKeyword })
          .width('100%')
          .height(40)
          .fontSize(14)
          .backgroundColor(Color.Transparent)
          .padding({ left: 8 })
          .onSubmit(() => this.handleSearch())
      }
      .width('100%')
      .height(48)
      .padding({ left: 12, right: 12 })
      .margin({ left: 12, right: 12, top: 8 })
      .backgroundColor($r('app.color.input_background'))
      .borderRadius(8)

      if (this.errorMessage.length > 0 && this.threadCount === 0) {
        ErrorView({
          message: this.errorMessage,
          onRetryClick: () => this.loadThreads(true)
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
                    console.error(`[HomePage] handleAgree failed: ${err.message}`);
                  });
                },
                onDisagreeClick: (t: ThreadInfo) => {
                  this.handleDisagree(t).catch((err: Error) => {
                    console.error(`[HomePage] handleDisagree failed: ${err.message}`);
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
