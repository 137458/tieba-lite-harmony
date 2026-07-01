import { router, window } from '@kit.ArkUI';
import { TiebaAPI, SearchType } from '../../api/TiebaAPI';
import { ExactSearch } from '../../model/ForumModels';
import { LoadingView } from '../../components/LoadingView';
import { ErrorView } from '../../components/ErrorView';
import { BaseViewModel, FetchDataResult } from '../../viewmodel/BaseViewModel';
import { getResourceString } from '../../utils/ResourceUtil';

/**
 * 吧内精确搜索 ViewModel
 * 调用 TiebaAPI.searchExact（POST /c/s/searchpost）
 */
class SearchViewModel extends BaseViewModel<ExactSearch> {
  private fname: string = '';
  private keyword: string = '';
  private searchType: SearchType = SearchType.ALL;

  setQuery(fname: string, keyword: string, searchType: SearchType = SearchType.ALL): void {
    this.fname = fname;
    this.keyword = keyword;
    this.searchType = searchType;
  }

  protected async fetchData(page: number, isRefresh: boolean): Promise<FetchDataResult<ExactSearch>> {
    return await TiebaAPI.searchExact(
      this.fname,
      this.keyword,
      page,
      30,
      this.searchType,
      true
    );
  }
}

@Entry
@Component
struct SearchPage {
  private viewModel: SearchViewModel = new SearchViewModel();

  @State keyword: string = '';
  @State fname: string = '';
  @State searchList: ExactSearch[] = [];
  @State isLoading: boolean = false;
  @State hasMore: boolean = true;
  @State errorMessage: string = '';
  @State hasSearched: boolean = false;
  // 状态栏高度（vp），沉浸式避让状态栏，默认 36，aboutToAppear 动态获取
  @State statusBarHeight: number = 36;

  async aboutToAppear() {
    // 获取状态栏高度（沉浸式，对齐 HomePage 实现）
    try {
      const mainWindow = await window.getLastWindow(getContext(this));
      const avoidArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      this.statusBarHeight = px2vp(avoidArea.topRect.height);
    } catch (err) {
      // 获取失败保留默认值 36
    }
    const params = router.getParams() as Record<string, string>;
    if (params) {
      // 支持吧内搜索（fname 非空）和全吧搜索（fname 为空）
      this.fname = params['fname'] || '';
      this.keyword = params['keyword'] || '';
      if (this.keyword.length > 0) {
        this.viewModel.setQuery(this.fname, this.keyword);
        this.performSearch().catch((err: Error) => {
          console.error(`[SearchPage] performSearch failed: ${err.message}`);
        });
      }
    }
  }

  async performSearch(): Promise<void> {
    if (this.keyword.length === 0) {
      return;
    }

    this.hasSearched = true;
    this.viewModel.setQuery(this.fname, this.keyword);
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

    this.searchList = paginationData.dataList;
    this.hasMore = paginationData.hasMore;
    this.isLoading = loadingState.isLoading;
    this.errorMessage = loadingState.error;
  }

  navigateToThread(tid: number): void {
    // 校验 tid 合法性，避免导航到无效帖子
    if (tid <= 0) {
      console.warn(`[SearchPage] invalid tid: ${tid}, skip navigation`);
      return;
    }
    router.pushUrl({
      url: 'pages/thread/ThreadPage',
      params: { tid: tid.toString() }
    });
  }

  private formatTime(timestamp: number): string {
    if (timestamp <= 0) {
      return '';
    }

    const now: number = Date.now() / 1000;
    const diff: number = now - timestamp;

    if (diff < 60) {
      return getResourceString($r('app.string.just_now'));
    } else if (diff < 3600) {
      return Math.floor(diff / 60) + getResourceString($r('app.string.minutes_ago'));
    } else if (diff < 86400) {
      return Math.floor(diff / 3600) + getResourceString($r('app.string.hours_ago'));
    } else if (diff < 604800) {
      return Math.floor(diff / 86400) + getResourceString($r('app.string.days_ago'));
    } else {
      const date = new Date(timestamp * 1000);
      return `${date.getFullYear()}-${(date.getMonth() + 1).toString().padStart(2, '0')}-${date.getDate().toString().padStart(2, '0')}`;
    }
  }

  build() {
    Column() {
      // 顶部搜索栏
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
      .height(56 + this.statusBarHeight)
      .padding({ left: 16, right: 16, top: this.statusBarHeight })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
      .alignItems(VerticalAlign.Center)
      .backgroundColor($r('app.color.background'))

      // 内容区
      if (this.isLoading && this.searchList.length === 0) {
        LoadingView({ message: getResourceString($r('app.string.loading')) })
          .layoutWeight(1)
      } else if (this.errorMessage.length > 0 && this.searchList.length === 0) {
        ErrorView({
          message: this.errorMessage,
          onRetryClick: () => this.performSearch()
        })
          .layoutWeight(1)
      } else if (this.hasSearched && this.searchList.length === 0) {
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
          ForEach(this.searchList, (item: ExactSearch) => {
            ListItem() {
              this.SearchPostCard(item)
            }
            .onClick(() => this.navigateToThread(item.tid))
          }, (item: ExactSearch) => `${item.tid}_${item.pid}`)

          if (this.isLoading && this.searchList.length > 0) {
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
        .onReachEnd(() => {
          // onReachEnd 回调不处理 async 返回值，需 catch 避免 unhandled rejection
          this.loadMore().catch((err: Error) => {
            console.error(`[SearchPage] loadMore failed: ${err.message}`);
          });
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  SearchPostCard(item: ExactSearch) {
    Column() {
      // 标题
      if (item.title.length > 0) {
        Text(item.title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }

      // 内容摘要
      if (item.text.length > 0) {
        Text(item.text)
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .margin({ top: item.title.length > 0 ? 6 : 0 })
      }

      // 底部元信息：作者 + 吧名 + 楼中楼标记 + 时间
      Row() {
        if (item.showName.length > 0) {
          Text(item.showName)
            .fontSize(11)
            .fontColor($r('app.color.primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }

        if (item.fname.length > 0) {
          Text(item.fname)
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ left: item.showName.length > 0 ? 8 : 0 })
        }

        if (item.isComment) {
          Text($r('app.string.comment_label'))
            .fontSize(10)
            .fontColor($r('app.color.text_secondary'))
            .padding({ left: 4, right: 4, top: 1, bottom: 1 })
            .borderRadius(3)
            .backgroundColor($r('app.color.input_background'))
            .margin({ left: 8 })
        }

        Text(this.formatTime(item.createTime))
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .margin({ left: 8 })
      }
      .width('100%')
      .margin({ top: 8 })
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .backgroundColor($r('app.color.background'))
    .borderRadius(8)
    .margin({ left: 12, right: 12, top: 8 })
  }
}
