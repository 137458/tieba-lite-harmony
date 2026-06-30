import { router } from '@kit.ArkUI';
import { TiebaAPI } from '../../api/TiebaAPI';
import { ThreadInfo } from '../../model/ForumModels';
import { ThreadCard } from '../../components/ThreadCard';
import { LoadingView } from '../../components/LoadingView';
import { ErrorView } from '../../components/ErrorView';
import { BaseViewModel, FetchDataResult } from '../../viewmodel/BaseViewModel';
import { getResourceString } from '../../utils/ResourceUtil';

class SearchViewModel extends BaseViewModel<ThreadInfo> {
  private keyword: string = '';

  setKeyword(word: string): void {
    this.keyword = word;
  }

  protected async fetchData(page: number, isRefresh: boolean): Promise<FetchDataResult<ThreadInfo>> {
    return await TiebaAPI.search(
      this.keyword,
      page,
      0
    );
  }
}

@Entry
@Component
struct SearchPage {
  private viewModel: SearchViewModel = new SearchViewModel();

  @State keyword: string = '';
  @State threadList: ThreadInfo[] = [];
  @State isLoading: boolean = false;
  @State hasMore: boolean = true;
  @State errorMessage: string = '';
  @State hasSearched: boolean = false;

  aboutToAppear() {
    const params = router.getParams() as Record<string, string>;
    if (params && params['keyword']) {
      this.keyword = params['keyword'];
      this.viewModel.setKeyword(this.keyword);
      this.performSearch();
    }
  }

  async performSearch(): Promise<void> {
    if (this.keyword.length === 0) {
      return;
    }

    this.hasSearched = true;
    await this.viewModel.loadData(true);
    this.syncState();
  }

  async loadMore(): Promise<void> {
    if (this.viewModel.canLoadMore()) {
      await this.viewModel.loadData(false);
      this.syncState();
    }
  }

  private syncState(): void {
    const paginationData = this.viewModel.paginationData;
    const loadingState = this.viewModel.loadingState;

    this.threadList = paginationData.dataList;
    this.hasMore = paginationData.hasMore;
    this.isLoading = loadingState.isLoading;
    this.errorMessage = loadingState.error;
  }

  navigateToThread(tid: number): void {
    router.pushUrl({
      url: 'pages/thread/ThreadPage',
      params: { tid: tid.toString() }
    });
  }

  build() {
    Column() {
      Row() {
        Image('')
          .width(24)
          .height(24)
          .fillColor($r('app.color.text_primary'))
          .onClick(() => {
            router.back();
          })

        Row() {
          Image('')
            .width(20)
            .height(20)
            .fillColor($r('app.color.text_secondary'))

          TextInput({ placeholder: $r('app.string.search_hint'), text: $$this.keyword })
            .width('100%')
            .height(40)
            .fontSize(14)
            .backgroundColor(Color.Transparent)
            .padding({ left: 8 })
            .onSubmit(() => this.performSearch())
        }
        .width('100%')
        .height(44)
        .padding({ left: 12, right: 12 })
        .backgroundColor($r('app.color.input_background'))
        .borderRadius(8)
        .layoutWeight(1)
        .margin({ left: 12 })

        Text($r('app.string.search_button'))
          .fontSize(15)
          .fontColor($r('app.color.primary'))
          .margin({ left: 12 })
          .onClick(() => this.performSearch())
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .alignItems(VerticalAlign.Center)
      .backgroundColor($r('app.color.background'))

      if (this.isLoading && this.threadList.length === 0) {
        LoadingView({ message: getResourceString($r('app.string.loading')) })
          .layoutWeight(1)
      } else if (this.errorMessage.length > 0 && this.threadList.length === 0) {
        ErrorView({
          message: this.errorMessage,
          onRetryClick: () => this.performSearch()
        })
          .layoutWeight(1)
      } else if (this.hasSearched && this.threadList.length === 0) {
        Column() {
          Image('')
            .width(80)
            .height(80)
            .fillColor($r('app.color.text_secondary'))

          Text($r('app.string.search_no_result'))
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 12 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List() {
          ForEach(this.threadList, (thread: ThreadInfo) => {
            ListItem() {
              ThreadCard({
                thread: thread,
                onCardClick: () => this.navigateToThread(thread.tid)
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
        .onReachEnd(() => this.loadMore())
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }
}
