// 主页（"主页"tab）
// 展示当前账号关注的贴吧列表（issue #48 切片1）
// 数据来源：TiebaAPI.getFollowForums（/c/f/forum/forumGuide）
// 点击吧项跳转 ForumPage 查看该吧帖子
// UI 设计：iOS Large Title + 搜索框 + 圆角卡片列表（对齐 design-spec.md 第6节 ForumItem 规格）

import { router } from '@kit.ArkUI';
import { TiebaAPI } from '../../api/TiebaAPI';
import { SelfFollowForum } from '../../model/ForumModels';
import { LoadingView } from '../../components/LoadingView';
import { ErrorView } from '../../components/ErrorView';
import { BaseViewModel, FetchDataResult } from '../../viewmodel/BaseViewModel';
import { CommonDataSource } from '../../utils/CommonDataSource';
import { getResourceString } from '../../utils/ResourceUtil';
import { getStatusBarHeight } from '../../utils/StatusBarUtil';
import { formatCount } from '../../utils/FormatUtil';

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
    // 失败不阻塞后续加载，保留默认值 36
    try {
      this.statusBarHeight = await getStatusBarHeight(getContext(this));
    } catch (err) {
      console.error(`[HomePage] getStatusBarHeight failed: ${(err as Error).message}`);
    }
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
      // onReachEnd 回调不处理 async 返回值，需 catch 避免 unhandled rejection
      this.loadForums(false).catch((err: Error) => {
        console.error(`[HomePage] onReachEnd loadForums failed: ${err.message}`);
      });
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

  /** 右上角"搜索"图标：直接跳转搜索页 */
  navigateToSearch(): void {
    router.pushUrl({
      url: 'pages/search/SearchPage'
    }).catch((err: Error) => {
      console.error(`[HomePage] navigate to search failed: ${err.message}`);
    });
  }

  /** 点击"设置"图标跳转设置页 */
  navigateToSettings(): void {
    router.pushUrl({ url: 'pages/settings/SettingsPage' }).catch((err: Error) => {
      console.error(`[HomePage] navigate to settings failed: ${err.message}`);
    });
  }

  build() {
    Column() {
      // iOS Large Title 顶部栏（对齐 design-spec.md 第6节）
      // 左侧 Large Title 34px 800 + 右侧 搜索/设置图标按钮
      Row() {
        Text($r('app.string.app_name'))
          .fontSize(34)
          .fontWeight(800)
          .fontColor($r('app.color.text_primary'))
          .letterSpacing(0.37)
          .layoutWeight(1)

        Row() {
          Image($r('app.media.ic_search'))
            .width(20)
            .height(20)
            .fillColor($r('app.color.primary'))
        }
        .width(30)
        .height(30)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .onClick(() => this.navigateToSearch())

        Row() {
          Image($r('app.media.ic_settings'))
            .width(20)
            .height(20)
            .fillColor($r('app.color.primary'))
        }
        .width(30)
        .height(30)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .margin({ left: 2 })
        .onClick(() => this.navigateToSettings())
      }
      .width('100%')
      .height(56 + this.statusBarHeight)
      .padding({ left: 16, right: 16, top: this.statusBarHeight, bottom: 8 })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
      .alignItems(VerticalAlign.Center)

      // iOS 搜索框（36px 高度，10px 圆角，对齐 design-spec.md 第3节）
      Row() {
        Image($r('app.media.ic_search'))
          .width(16)
          .height(16)
          .fillColor($r('app.color.text_caption'))
          .margin({ right: 6 })

        Text($r('app.string.search_hint'))
          .fontSize(15)
          .fontColor($r('app.color.text_caption'))
      }
      .width('100%')
      .height(36)
      .padding({ left: 10, right: 8 })
      .margin({ left: 16, right: 16, bottom: 16 })
      .backgroundColor($r('app.color.input_background'))
      .borderRadius(10)
      .onClick(() => this.navigateToSearch())

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
        List({ space: 0 }) {
          LazyForEach(this.dataSource, (forum: SelfFollowForum) => {
            ListItem() {
              this.ForumItemBuilder(forum)
            }
          }, (forum: SelfFollowForum, index: number) => `${forum.fid}_${index}`)

          if (this.isLoading && this.forumCount > 0) {
            ListItem() {
              LoadingView({ message: getResourceString($r('app.string.loading_more')) })
                .height(60)
            }
          }
        }
        .width('100%')
        .layoutWeight(1)
        .divider({ strokeWidth: 0.5, color: $r('app.color.divider'), startMargin: 76, endMargin: 0 })
        // bottom 77vp 避让悬浮 TabBar（barHeight 49 + barBottomMargin 28）
        // 已弃用：MainPage 改用原生 Tabs + 固定 barHeight(56)，TabBar 不再悬浮
        .margin({ left: 16, right: 16 })
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .cachedCount(10)
        .nestedScroll({ scrollForward: NestedScrollMode.PARENT_FIRST, scrollBackward: NestedScrollMode.SELF_FIRST })
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(10)
        .onReachEnd(() => this.onReachEnd())
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  ForumItemBuilder(forum: SelfFollowForum) {
    Row() {
      if (forum.avatar.length > 0) {
        Image(forum.avatar)
          .width(48)
          .height(48)
          .borderRadius(24)
          .objectFit(ImageFit.Cover)
          .backgroundColor($r('app.color.input_background'))
          .alt($r('app.media.startIcon'))
      } else {
        Column() {
          Text(forum.fname.length > 0 ? forum.fname.charAt(0).toUpperCase() : '?')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
        }
        .width(48)
        .height(48)
        .borderRadius(24)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .linearGradient({
          angle: 135,
          colors: [[$r('app.color.primary'), 0.0], [$r('app.color.accent_blue'), 1.0]]
        })
      }

      Column() {
        Row() {
          Text(forum.fname)
            .fontSize(16)
            .fontWeight(600)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ right: 6 })

          Text(`Lv.${forum.level}`)
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.primary'))
            .backgroundColor($r('app.color.primary_light'))
            .padding({ left: 7, right: 7, top: 1, bottom: 1 })
            .borderRadius(6)

          if (forum.isSigned) {
            Text($r('app.string.forum_signed'))
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.success'))
              .backgroundColor($r('app.color.success_light'))
              .padding({ left: 7, right: 7, top: 1, bottom: 1 })
              .borderRadius(6)
              .margin({ left: 6 })
          }
        }
        .alignItems(VerticalAlign.Center)

        // meta 行：关注数 · 帖子数（对齐 design-prototype.html forum-item meta）
        Text($r('app.string.forum_meta_format', formatCount(forum.memberCount), formatCount(forum.threadNum)))
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 3 })
      }
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 })
      .layoutWeight(1)

      Image($r('app.media.ic_chevron_right'))
        .width(14)
        .height(14)
        .fillColor($r('app.color.text_caption'))
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => this.navigateToForum(forum.fname))
  }
}
