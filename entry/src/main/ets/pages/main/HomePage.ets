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
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)

        // 搜索图标按钮（对齐 design-prototype.html SF Symbols magnifyingglass）
        Row() {
          Shape() {
            Path()
              .commands('M15.5 14h-.79l-.28-.27A6.47 6.47 0 0 0 16 9.5 6.5 6.5 0 1 0 9.5 16c1.61 0 3.09-.59 4.23-1.57l.27.28v.79l5 4.99L20.49 19l-4.99-5zm-6 0C7.01 14 5 11.99 5 9.5S7.01 5 9.5 5 14 7.01 14 9.5 11.99 14 9.5 14z')
              .fill($r('app.color.primary'))
          }
          .width(20)
          .height(20)
          .viewPort({ x: 0, y: 0, width: 24, height: 24 })
        }
        .width(30)
        .height(30)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .onClick(() => this.navigateToSearch())

        // 设置图标按钮（SF Symbols gearshape）— Shape 包裹 Path 提供 viewPort
        Row() {
          Shape() {
            Path()
              .commands('M19.14 12.94c.04-.3.06-.61.06-.94 0-.32-.02-.64-.07-.94l2.03-1.58a.49.49 0 0 0 .12-.61l-1.92-3.32a.49.49 0 0 0-.59-.22l-2.39.96c-.5-.38-1.03-.7-1.62-.94l-.36-2.54a.48.48 0 0 0-.48-.41h-3.84a.48.48 0 0 0-.48.41l-.36 2.54c-.59.24-1.13.57-1.62.94l-2.39-.96a.49.49 0 0 0-.59.22L2.74 8.87c-.12.21-.08.47.12.61l2.03 1.58c-.05.3-.07.62-.07.94s.02.64.07.94l-2.03 1.58a.49.49 0 0 0-.12.61l1.92 3.32c.12.22.37.29.59.22l2.39-.96c.5.38 1.03.7 1.62.94l.36 2.54c.05.24.24.41.48.41h3.84c.24 0 .44-.17.48-.41l.36-2.54c.59-.24 1.13-.56 1.62-.94l2.39.96c.22.08.47 0 .59-.22l1.92-3.32c.12-.22.07-.47-.12-.61l-2.01-1.58zM12 15.6A3.6 3.6 0 1 1 12 8.4a3.6 3.6 0 0 1 0 7.2z')
              .fill($r('app.color.primary'))
          }
          .width(20)
          .height(20)
          .viewPort({ x: 0, y: 0, width: 24, height: 24 })
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
      .padding({ left: 20, right: 20, top: this.statusBarHeight, bottom: 8 })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
      .alignItems(VerticalAlign.Center)

      // iOS 搜索框（36px 高度，10px 圆角，对齐 design-spec.md 第3节）— Shape 包裹 Path 提供 viewPort
      Row() {
        Shape() {
          Path()
            .commands('M15.5 14h-.79l-.28-.27A6.47 6.47 0 0 0 16 9.5 6.5 6.5 0 1 0 9.5 16c1.61 0 3.09-.59 4.23-1.57l.27.28v.79l5 4.99L20.49 19l-4.99-5zm-6 0C7.01 14 5 11.99 5 9.5S7.01 5 9.5 5 14 7.01 14 9.5 11.99 14 9.5 14z')
            .fill($r('app.color.text_caption'))
        }
        .width(16)
        .height(16)
        .viewPort({ x: 0, y: 0, width: 24, height: 24 })
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
        .padding({ left: 16, right: 16 })
        .edgeEffect(EdgeEffect.Spring)
        .cachedCount(5)
        .onReachEnd(() => this.onReachEnd())
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  // iOS Grouped List 吧列表项（对齐 design-spec.md 第6节 ForumItem 规格）
  // 左侧头像(48px 圆形) + 中部吧名(16px SemiBold)+等级 pill(11px) + 已签到 pill(11px) + 右侧 chevron.right
  @Builder
  ForumItemBuilder(forum: SelfFollowForum) {
    Row() {
      // 吧头像：avatar URL 非空用 Image，空则用首字符占位（无 avatar 字段时 fallback）
      if (forum.avatar.length > 0) {
        Image(forum.avatar)
          .width(48)
          .height(48)
          .borderRadius(24)
          .objectFit(ImageFit.Cover)
          .backgroundColor($r('app.color.input_background'))
          .alt($r('app.media.startIcon'))
      } else {
        // Fallback：渐变色背景 + fname 首字符（白色 20px Bold）
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
          colors: [[$r('app.color.primary'), 0.0], [$r('app.color.tag_top'), 1.0]]
        })
      }

      // 中部信息：吧名 + 等级 pill + 已签到 pill
      Column() {
        Row() {
          Text(forum.fname)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ right: 6 })

          // 等级 pill（11px Medium，primary_light 背景 + primary 文字）
          Text(`Lv.${forum.level}`)
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.primary'))
            .backgroundColor($r('app.color.primary_light'))
            .padding({ left: 7, right: 7, top: 1, bottom: 1 })
            .borderRadius(6)

          // 已签到 pill（11px Medium，success 浅色背景 + success 文字）
          if (forum.isSigned) {
            Text($r('app.string.forum_signed'))
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.success'))
              .backgroundColor($r('app.color.primary_light'))
              .padding({ left: 7, right: 7, top: 1, bottom: 1 })
              .borderRadius(6)
              .margin({ left: 6 })
          }
        }
        .alignItems(VerticalAlign.Center)
      }
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 })
      .layoutWeight(1)

      // 右侧 chevron.right SVG 箭头（14px text_caption 色）— Shape 包裹 Path 提供 viewPort
      Shape() {
        Path()
          .commands('M10 6L8.59 7.41 13.17 12l-4.58 4.59L10 18l6-6z')
          .fill($r('app.color.text_caption'))
      }
      .width(14)
      .height(14)
      .viewPort({ x: 0, y: 0, width: 24, height: 24 })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(10)
    .alignItems(VerticalAlign.Center)
  }
}
