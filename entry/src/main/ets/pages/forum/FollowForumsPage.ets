import { router } from '@kit.ArkUI';
import { TiebaAPI } from '../../api/TiebaAPI';
import { SelfFollowForum } from '../../model/ForumModels';
import { LoadingView } from '../../components/LoadingView';
import { ErrorView } from '../../components/ErrorView';
import { getResourceString } from '../../utils/ResourceUtil';
import { BaseViewModel, FetchDataResult } from '../../viewmodel/BaseViewModel';
import { CommonDataSource } from '../../utils/CommonDataSource';
import { getStatusBarHeight } from '../../utils/StatusBarUtil';
import { getAvatarImageUrl } from '../../utils/ImageLoadUtil';

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
  // #80 图片加载策略：通过 AppStorage 共享，SettingsPage 修改后自动响应
  @StorageProp('imageLoadType') imageLoadType: number = 0;
  @StorageProp('isWifi') isWifi: boolean = false;

  async aboutToAppear() {
    // 获取状态栏高度，失败不阻塞列表加载，保留默认值 36
    try {
      this.statusBarHeight = await getStatusBarHeight(getContext(this));
    } catch (err) {
      console.error(`[FollowForumsPage] getStatusBarHeight failed: ${(err as Error).message}`);
    }
    this.loadForums(true).catch((err: Error) => {
      console.error(`[FollowForumsPage] loadForums failed: ${err.message}`);
    });
  }

  async loadForums(isRefresh: boolean = false): Promise<void> {
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
        console.error(`[FollowForumsPage] onReachEnd loadForums failed: ${err.message}`);
      });
    }
  }

  /** 点击吧项跳转 ForumPage 查看该吧帖子 */
  navigateToForum(forumName: string): void {
    router.pushUrl({
      url: 'pages/forum/ForumPage',
      params: { forumName: forumName }
    }).catch((err: Error) => {
      console.error(`[FollowForumsPage] navigate to forum failed: ${err.message}`);
    });
  }

  /** 获取吧名首字母大写，用于头像 fallback */
  private getForumInitial(name: string): string {
    if (name.length === 0) {
      return '?';
    }
    return name.charAt(0).toUpperCase();
  }

  build() {
    Column() {
      // 顶部导航栏（对齐原型 detail-nav，44px + 状态栏，返回按钮 primary 蓝）
      Row() {
        Image($r('app.media.ic_back'))
          .width(20)
          .height(20)
          .fillColor($r('app.color.primary'))
          .onClick(() => {
            router.back();
          })

        Text($r('app.string.follow_forums_title'))
          .fontSize(17)
          .fontWeight(600)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .margin({ left: 8, right: 8 })

        // 右侧占位，保持标题居中
        Row()
          .width(20)
          .height(20)
      }
      .width('100%')
      .height(44 + this.statusBarHeight)
      .padding({ left: 16, right: 16, top: this.statusBarHeight })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
      .alignItems(VerticalAlign.Center)
      .backgroundColor($r('app.color.page_background'))

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
        // iOS inset 分割线：从头像右侧开始（16 + 48 + 12 = 76）
        .divider({ strokeWidth: 0.5, color: $r('app.color.divider'), startMargin: 76, endMargin: 16 })
        .padding({ left: 16, right: 16 })
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .cachedCount(15)
        .nestedScroll({ scrollForward: NestedScrollMode.PARENT_FIRST, scrollBackward: NestedScrollMode.SELF_FIRST })
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
      // 左侧头像：有 URL 用网络图，无 URL 用渐变背景 + 首字母
      if (forum.avatar.length > 0) {
        // #80 接入图片加载策略：shouldLoad=false 时返回空串，Image 组件显示 alt 占位图
        Image(getAvatarImageUrl(forum.avatar, this.imageLoadType, this.isWifi))
          .width(48)
          .height(48)
          .borderRadius(24)
          .objectFit(ImageFit.Cover)
          .backgroundColor($r('app.color.input_background'))
          .alt($r('app.media.startIcon'))
      } else {
        Text(this.getForumInitial(forum.fname))
          .width(48)
          .height(48)
          .borderRadius(24)
          .textAlign(TextAlign.Center)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.card_background'))
          .backgroundColor($r('app.color.primary'))
      }

      // 中间信息：吧名 + 等级 pill + 签到 pill
      Column() {
        Row() {
          Text(forum.fname)
            .fontSize(16)
            .fontWeight(600)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          // 等级 pill：11px 600，primary_light 背景
          Text(`Lv.${forum.level}`)
            .fontSize(11)
            .fontWeight(600)
            .fontColor($r('app.color.primary'))
            .backgroundColor($r('app.color.primary_light'))
            .borderRadius(6)
            .padding({ left: 7, right: 7, top: 1, bottom: 1 })
            .margin({ left: 6 })

          // 签到 pill：11px 600，success 色 + 12% alpha 背景
          if (forum.isSigned) {
            Text($r('app.string.forum_signed'))
              .fontSize(11)
              .fontWeight(600)
              .fontColor($r('app.color.success'))
              .backgroundColor($r('app.color.success_light'))
              .borderRadius(6)
              .padding({ left: 7, right: 7, top: 1, bottom: 1 })
              .margin({ left: 6 })
          }
        }
        .alignItems(VerticalAlign.Center)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 12 })

      // 右侧箭头：SVG chevron
      Image($r('app.media.ic_chevron_right'))
        .width(14)
        .height(14)
        .fillColor($r('app.color.text_caption'))
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(10)
    .alignItems(VerticalAlign.Center)
  }
}
