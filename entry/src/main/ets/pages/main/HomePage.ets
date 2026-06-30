import { router } from '@kit.ArkUI';
import { TiebaAPI } from '../../api/TiebaAPI';
import { ThreadInfo } from '../../model/ForumModels';
import { ThreadCard } from '../../components/ThreadCard';
import { LoadingView } from '../../components/LoadingView';
import { ErrorView } from '../../components/ErrorView';
import { AppStorageManager } from '../../data/AppStorage';
import { BaseViewModel, FetchDataResult } from '../../viewmodel/BaseViewModel';

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

@Entry
@Component
struct HomePage {
  private viewModel: HomeViewModel = new HomeViewModel();

  @State threadList: ThreadInfo[] = [];
  @State isLoading: boolean = false;
  @State isRefreshing: boolean = false;
  @State hasMore: boolean = true;
  @State errorMessage: string = '';
  @State searchKeyword: string = '';

  aboutToAppear() {
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
              // TODO: 打开搜索页面
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
      .height(56)
      .padding({ left: 16, right: 16 })
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
                  thread.author.avatar,
                  thread.author.name,
                  thread.author.uid
                )
              })
                .margin({ left: 12, right: 12, top: 8 })
            }
          }, (thread: ThreadInfo) => thread.tid.toString())

          if (this.isLoading && this.threadList.length > 0) {
            ListItem() {
              LoadingView({ message: $r('app.string.loading_more').toString() })
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
