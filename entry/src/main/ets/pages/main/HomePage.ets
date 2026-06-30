import { router, window, promptAction } from '@kit.ArkUI';
import { TiebaAPI } from '../../api/TiebaAPI';
import { ThreadInfo } from '../../model/ForumModels';
import { ThreadCard } from '../../components/ThreadCard';
import { LoadingView } from '../../components/LoadingView';
import { ErrorView } from '../../components/ErrorView';
import { AppStorageManager } from '../../data/AppStorage';
import { BaseViewModel, FetchDataResult } from '../../viewmodel/BaseViewModel';
import { getResourceString } from '../../utils/ResourceUtil';

class HomeViewModel extends BaseViewModel<ThreadInfo> {
  private forumName: string = 'steam';
  private sortType: number = 1;
  private isGood: boolean = false;

  protected async fetchData(page: number, isRefresh: boolean): Promise<FetchDataResult<ThreadInfo>> {
    return await TiebaAPI.getThreads(
      this.forumName,
      page,
      this.sortType,
      this.isGood
    );
  }
}

@Component
export struct HomePage {
  private viewModel: HomeViewModel = new HomeViewModel();

  @State threadList: ThreadInfo[] = [];
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

    this.threadList = paginationData.dataList;
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

  handleSearch(): void {
    if (this.searchKeyword.length > 0) {
      router.pushUrl({
        url: 'pages/search/SearchPage',
        params: { keyword: this.searchKeyword }
      });
    }
  }

  /**
   * 点赞/取消赞（issue #17）
   * 主题帖点赞：pid=0，isComment=false
   */
  async handleAgree(thread: ThreadInfo): Promise<void> {
    try {
      if (thread.isAgreed) {
        await TiebaAPI.unagree(thread.tid, 0, false);
        thread.isAgreed = false;
        thread.agreeNum = Math.max(0, thread.agreeNum - 1);
      } else {
        await TiebaAPI.agree(thread.tid, 0, false);
        thread.isAgreed = true;
        thread.agreeNum += 1;
      }
      // 触发 List 重新渲染
      this.threadList = this.threadList.slice();
    } catch (err) {
      promptAction.showToast({ message: (err as Error).message || getResourceString($r('app.string.follow_operation_failed')) });
    }
  }

  /**
   * 点踩/取消点踩（issue #17）
   */
  async handleDisagree(thread: ThreadInfo): Promise<void> {
    try {
      if (thread.isDisagreed) {
        await TiebaAPI.undisagree(thread.tid, 0, false);
        thread.isDisagreed = false;
        thread.disagreeNum = Math.max(0, thread.disagreeNum - 1);
      } else {
        await TiebaAPI.disagree(thread.tid, 0, false);
        thread.isDisagreed = true;
        thread.disagreeNum += 1;
      }
      this.threadList = this.threadList.slice();
    } catch (err) {
      promptAction.showToast({ message: (err as Error).message || getResourceString($r('app.string.follow_operation_failed')) });
    }
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
          Image('')
            .width(24)
            .height(24)
            .fillColor($r('app.color.text_primary'))
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
      .expandSafeArea([SafeAreaType.SYS], [SafeAreaEdge.TOP])
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

      if (this.errorMessage.length > 0 && this.threadList.length === 0) {
        ErrorView({
          message: this.errorMessage,
          onRetryClick: () => this.loadThreads(true)
        })
          .layoutWeight(1)
      } else {
        List() {
          ForEach(this.threadList, (thread: ThreadInfo) => {
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

          if (this.isLoading && this.threadList.length > 0) {
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
        .onReachEnd(() => this.onReachEnd())
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }
}
