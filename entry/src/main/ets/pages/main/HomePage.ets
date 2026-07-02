// 主页（"主页"tab）
// 展示当前账号关注的贴吧列表（issue #48 切片1）
// 数据来源：TiebaAPI.getFollowForums（/c/f/forum/forumGuide）
// 点击吧项跳转 ForumPage 查看该吧帖子

import { router } from '@kit.ArkUI';
import { TiebaAPI } from '../../api/TiebaAPI';
import { SelfFollowForum } from '../../model/ForumModels';
import { LoadingView } from '../../components/LoadingView';
import { ErrorView } from '../../components/ErrorView';
import { BaseViewModel, FetchDataResult } from '../../viewmodel/BaseViewModel';
import { CommonDataSource } from '../../utils/CommonDataSource';
import { getResourceString } from '../../utils/ResourceUtil';
import { getStatusBarHeight } from '../../utils/StatusBarUtil';

/**
 * 主页 ViewModel：关注贴吧列表
 * 调用 TiebaAPI.getFollowForums（web 端 /c/f/forum/forumGuide）
 */
class HomeForumsViewModel extends BaseViewModel<SelfFollowForum> {
  // 每页拉取吧数量（对齐 aiotieba 默认 rn）
  private static readonly PAGE_SIZE: number = 20;

  protected async fetchData(page: number, isRefresh: boolean): Promise<FetchDataResult<SelfFollowForum>> {
    return await TiebaAPI.getFollowForums(page, HomeForumsViewModel.PAGE_SIZE);
  }
}

@Component
export struct HomePage {
  private viewModel: HomeForumsViewModel = new HomeForumsViewModel();
  private dataSource: CommonDataSource<SelfFollowForum> = new CommonDataSource<SelfFollowForum>();

  @State forumCount: number = 0;
  @State isLoading: boolean = false;
  @State isRefreshing: boolean = false;
  @State hasMore: boolean = true;
  @State errorMessage: string = '';
  @State searchKeyword: string = '';
  // 状态栏高度（vp），沉浸式避让状态栏，默认 36，aboutToAppear 动态获取
  @State statusBarHeight: number = 36;

  async aboutToAppear() {
    // 获取状态栏高度（沉浸式，P1 重构提取为 StatusBarUtil）
    this.statusBarHeight = await getStatusBarHeight(getContext(this));
    this.loadForums(true).catch((err: Error) => {
      console.error(`[HomePage] loadForums failed: ${err.message}`);
    });
  }

  async loadForums(isRefresh: boolean = false): Promise<void> {
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
    this.forumCount = this.dataSource.totalCount();
    this.hasMore = paginationData.hasMore;
    this.isLoading = loadingState.isLoading;
    this.isRefreshing = loadingState.isRefreshing;
    this.errorMessage = loadingState.error;
  }

  onReachEnd(): void {
    if (this.viewModel.canLoadMore()) {
      this.loadForums(false);
    }
  }

  /** 点击吧项跳转 ForumPage 查看该吧帖子 */
  navigateToForum(forumName: string): void {
    if (forumName.length === 0) {
      console.warn(`[HomePage] empty forumName, skip navigation`);
      return;
    }
    router.pushUrl({
      url: 'pages/forum/ForumPage',
      params: { forumName: forumName }
    }).catch((err: Error) => {
      console.error(`[HomePage] navigate to forum failed: ${err.message}`);
    });
  }

  handleSearch(): void {
    // 长条搜索框：有关键词时携带关键词跳转
    if (this.searchKeyword.length > 0) {
      router.pushUrl({
        url: 'pages/search/SearchPage',
        params: { keyword: this.searchKeyword }
      }).catch((err: Error) => {
        console.error(`[HomePage] navigate to search failed: ${err.message}`);
      });
    }
  }

  /** 右上角"搜索"按钮：直接跳转搜索页（不要求先输入关键词） */
  navigateToSearch(): void {
    router.pushUrl({
      url: 'pages/search/SearchPage'
    }).catch((err: Error) => {
      console.error(`[HomePage] navigate to search failed: ${err.message}`);
    });
  }

  build() {
    Column() {
      // 顶部标题栏（标题左对齐）
      Row() {
        Text($r('app.string.app_name'))
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary'))
          .layoutWeight(1)

        Text($r('app.string.search_button'))
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .onClick(() => {
            this.navigateToSearch();
          })

        Text($r('app.string.settings_title'))
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .margin({ left: 16 })
          .onClick(() => {
            router.pushUrl({ url: 'pages/settings/SettingsPage' }).catch((err: Error) => {
              console.error(`[HomePage] navigate to settings failed: ${err.message}`);
            });
          })
      }
      .width('100%')
      .height(56 + this.statusBarHeight)
      .padding({ left: 16, right: 16, top: this.statusBarHeight })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
      .alignItems(VerticalAlign.Center)
      .backgroundColor($r('app.color.background'))

      // 搜索框
      Row() {
        Text($r('app.string.search_button'))
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .margin({ right: 4 })

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

      // 内容区
      if (this.errorMessage.length > 0 && this.forumCount === 0) {
        ErrorView({
          message: this.errorMessage,
          onRetryClick: () => this.loadForums(true)
        })
          .layoutWeight(1)
      } else if (this.forumCount === 0 && !this.isLoading) {
        // 空状态
        Column() {
          Text($r('app.string.follow_forums_empty'))
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List() {
          LazyForEach(this.dataSource, (forum: SelfFollowForum) => {
            ListItem() {
              this.ForumItemBuilder(forum)
            }
            .margin({ top: 4, bottom: 4 })
            .onClick(() => this.navigateToForum(forum.fname))
          }, (forum: SelfFollowForum) => forum.fid.toString())

          if (this.isLoading && this.forumCount > 0) {
            ListItem() {
              LoadingView({ message: getResourceString($r('app.string.loading_more')) })
                .height(60)
            }
          }
        }
        .width('100%')
        .layoutWeight(1)
        .divider({ strokeWidth: 0 })
        .padding({ left: 12, right: 12 })
        .edgeEffect(EdgeEffect.Spring)
        .cachedCount(5)
        .onReachEnd(() => this.onReachEnd())
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  // 吧列表项：吧名 + 等级 + 签到状态 + 进入箭头
  @Builder
  ForumItemBuilder(forum: SelfFollowForum) {
    Row() {
      Column() {
        Text(forum.fname)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Row() {
          Text(`Lv.${forum.level}`)
            .fontSize(12)
            .fontColor($r('app.color.primary'))
            .margin({ right: 8 })

          if (forum.isSigned) {
            Text($r('app.string.forum_signed'))
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
          }
        }
        .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      // 右侧进入箭头
      Text('>')
        .fontSize(16)
        .fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor($r('app.color.background'))
    .borderRadius(8)
  }
}
