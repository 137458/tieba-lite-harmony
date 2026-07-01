import { router, window } from '@kit.ArkUI';
import { TiebaAPI } from '../../api/TiebaAPI';
import { SelfFollowForum } from '../../model/ForumModels';
import { LoadingView } from '../../components/LoadingView';
import { ErrorView } from '../../components/ErrorView';
import { getResourceString } from '../../utils/ResourceUtil';
import { BaseViewModel, FetchDataResult } from '../../viewmodel/BaseViewModel';
import { CommonDataSource } from '../../utils/CommonDataSource';

/**
 * 关注吧列表 ViewModel
 * 调用 TiebaAPI.getFollowForums（web 端 /c/f/forum/forumGuide）
 */
class FollowForumsViewModel extends BaseViewModel<SelfFollowForum> {
  protected async fetchData(page: number, isRefresh: boolean): Promise<FetchDataResult<SelfFollowForum>> {
    return await TiebaAPI.getFollowForums(page);
  }
}

@Entry
@Component
struct FollowForumsPage {
  private viewModel: FollowForumsViewModel = new FollowForumsViewModel();
  private dataSource: CommonDataSource<SelfFollowForum> = new CommonDataSource<SelfFollowForum>();

  @State forumCount: number = 0;
  @State isLoading: boolean = false;
  @State isRefreshing: boolean = false;
  @State hasMore: boolean = true;
  @State errorMessage: string = '';
  // 状态栏高度（vp），沉浸式避让，默认 36，aboutToAppear 动态获取
  @State statusBarHeight: number = 36;

  async aboutToAppear() {
    // 获取状态栏高度（沉浸式，对齐 HomePage/ForumPage 实现）
    try {
      const mainWindow = await window.getLastWindow(getContext(this));
      const avoidArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      this.statusBarHeight = px2vp(avoidArea.topRect.height);
    } catch (err) {
      // 获取失败保留默认值 36，记录日志便于排查（issue #33）
      console.warn(`[FollowForumsPage] getStatusBarHeight failed: ${(err as Error).message || err}`);
    }
    this.loadForums(true);
  }

  async loadForums(isRefresh: boolean = false): Promise<void> {
    await this.viewModel.loadData(isRefresh);
    this.syncState();
  }

  private syncState(): void {
    const paginationData = this.viewModel.paginationData;
    const loadingState = this.viewModel.loadingState;

    this.dataSource.setData(paginationData.dataList);
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
    router.pushUrl({
      url: 'pages/forum/ForumPage',
      params: { forumName: forumName }
    });
  }

  build() {
    Column() {
      // 顶部工具栏（沉浸式避让状态栏）
      Row() {
        Image($r('app.media.ic_back'))
          .width(24)
          .height(24)
          .fillColor($r('app.color.text_primary'))
          .onClick(() => {
            router.back();
          })

        Text($r('app.string.follow_forums_title'))
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .textAlign(TextAlign.Start)
          .margin({ left: 12 })
      }
      .width('100%')
      .height(56 + this.statusBarHeight)
      .padding({ left: 16, right: 16, top: this.statusBarHeight })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
      .alignItems(VerticalAlign.Center)
      .backgroundColor($r('app.color.background'))

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
        .edgeEffect(EdgeEffect.Spring)
        .cachedCount(5)
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
      // 左侧吧名 + 等级
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
    .margin({ left: 12, right: 12, top: 6, bottom: 6 })
  }
}
