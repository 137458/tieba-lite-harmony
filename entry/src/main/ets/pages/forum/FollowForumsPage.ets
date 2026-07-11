import { router, AppStorageV2 } from '@kit.ArkUI';
import { TiebaAPI } from '../../api/TiebaAPI';
import { SelfFollowForum } from '../../model/ForumModels';
import { ImageLoadTypeState, IsWifiState, SafeBottomState } from '../../model/AppStorageV2Models';
import { LoadingView } from '../../components/LoadingView';
import { ErrorView } from '../../components/ErrorView';
import { getResourceString } from '../../utils/ResourceUtil';
import { BaseViewModel, FetchDataResult } from '../../viewmodel/BaseViewModel';
import { CommonDataSource } from '../../utils/CommonDataSource';
import { getStatusBarHeight } from '../../utils/StatusBarUtil';
import { shouldLoad } from '../../utils/ImageLoadUtil';
import { connectTheme, ThemeState } from '../../theme/ThemeManager';
import { VibratorUtil } from '../../utils/VibratorUtil';

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
@ComponentV2
struct FollowForumsPage {
  private viewModel: FollowForumsViewModel = new FollowForumsViewModel();
  private dataSource: CommonDataSource<SelfFollowForum> = new CommonDataSource<SelfFollowForum>();

  @Local forumCount: number = 0;
  @Local isLoading: boolean = false;
  @Local isRefreshing: boolean = false;
  @Local hasMore: boolean = true;
  @Local errorMessage: string = '';
  // 状态栏高度（vp），沉浸式避让，默认 36，aboutToAppear 动态获取
  @Local statusBarHeight: number = 36;
  // #80 图片加载策略：通过 AppStorageV2 共享，SettingsPage 修改后自动响应
  @Local imageLoadTypeState: ImageLoadTypeState = AppStorageV2.connect(ImageLoadTypeState, 'imageLoadType', () => new ImageLoadTypeState())!;
  @Local isWifiState: IsWifiState = AppStorageV2.connect(IsWifiState, 'isWifi', () => new IsWifiState())!;
  // #93 底部安全高度，避让系统手势条
  @Local safeBottomState: SafeBottomState = AppStorageV2.connect(SafeBottomState, 'safeBottom', () => new SafeBottomState())!;
  // 签到中的吧 fname 集合（用于按钮 loading 态防抖，避免连点）
  @Local signingForumName: string = '';
  @Local themeState: ThemeState = connectTheme();

  // Toast 提示 helper（API 12+ 推荐用 UIContext.getPromptAction()）
  private showToast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message });
  }

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

  /** 签到（issue 功能2），成功后更新本地状态并刷新 dataSource */
  async handleSignForum(forum: SelfFollowForum): Promise<void> {
    // 防抖：已签到或签到进行中时直接返回
    if (forum.isSigned || this.signingForumName.length > 0) {
      return;
    }
    this.signingForumName = forum.fname;
    // #121 触感反馈：签到属于强调交互，触发重震动
    VibratorUtil.heavy();
    try {
      await TiebaAPI.signForum(forum.fname);
      // 签到成功：本地更新 isSigned，用 setData 触发 LazyForEach 刷新
      forum.isSigned = true;
      this.dataSource.setData(this.dataSource.getAllData());
      this.showToast(getResourceString($r('app.string.sign_success')));
    } catch (err) {
      const msg: string = (err as Error).message || getResourceString($r('app.string.sign_failed'));
      this.showToast(msg);
    } finally {
      this.signingForumName = '';
    }
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
          .fillColor(this.themeState.primary)
          // A5 图片优化：SVG 图标同步加载
          .syncLoad(true)
          // A5 图片优化：SVG 图标低质量插值
          .interpolation(ImageInterpolation.Low)
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
              // #138 改用独立子组件 + @Require @Param，签到状态变化时精准触发 UI 更新
              FollowForumItem({
                forum: forum,
                imageLoadType: this.imageLoadTypeState.value,
                isWifi: this.isWifiState.value,
                signingForumName: this.signingForumName,
                onSignClick: (f: SelfFollowForum) => {
                  this.handleSignForum(f).catch((err: Error) => {
                    console.error(`[FollowForumsPage] handleSignForum failed: ${err.message}`);
                  });
                },
                onItemClick: (fname: string) => this.navigateToForum(fname)
              })
            }
          }, (forum: SelfFollowForum, index: number) => `${forum.fid}`)

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
        .backgroundColor($r('app.color.page_background'))
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .cachedCount(5)
        .onReachEnd(() => this.onReachEnd())
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  // #138 ForumItemBuilder 已抽为独立 @ComponentV2 FollowForumItem（文件末尾定义）
  // @ObservedV2 SelfFollowForum + @Require @Param forum 字段变化时精准触发 UI 更新
}

/**
 * #138 关注吧列表项独立子组件（FollowForumsPage 用）
 * @Require @Param forum：@ObservedV2 SelfFollowForum 字段变化时精准触发 UI 更新
 * 解决 LazyForEach keyGenerator 用 fid 导致相同 fid item 复用旧实例、isSigned 变化不刷新的问题
 * A11 GlobalReuse：加 @ReusableV2，吧列表滚动时复用减少创建/销毁开销（无 @Local 字段，无需 aboutToReuse）
 */
@ReusableV2
@ComponentV2
struct FollowForumItem {
  @Require @Param forum: SelfFollowForum;
  @Param imageLoadType: number = 0;
  @Param isWifi: boolean = false;
  @Param signingForumName: string = '';
  @Event onSignClick: (forum: SelfFollowForum) => void = () => {};
  @Event onItemClick: (fname: string) => void = () => {};
  @Local themeState: ThemeState = connectTheme();

  /** 获取吧名首字母大写，用于头像 fallback */
  private getForumInitial(name: string): string {
    if (name.length === 0) {
      return '?';
    }
    return name.charAt(0).toUpperCase();
  }

  build() {
    Row() {
      // 左侧头像：有 URL 且策略允许加载时用网络图，否则用渐变背景 + 首字母
      // #80 shouldLoad=false（如智能无图+移动网络）时走首字母 fallback，省流且 UX 一致
      if (this.forum.avatar.length > 0 && shouldLoad(this.imageLoadType, this.isWifi)) {
        Image(this.forum.avatar)
          .width(48)
          .height(48)
          .borderRadius(24)
          .objectFit(ImageFit.Cover)
          .backgroundColor($r('app.color.input_background'))
          .alt($r('app.media.startIcon'))
          // A5 图片优化：吧头像同步加载（与 ForumItem 一致，避免快速滑动 High 插值解码波动）
          .syncLoad(true)
          // A5 图片优化：吧头像低质量插值（与 ForumItem 一致）
          .interpolation(ImageInterpolation.Low)
          // A5 图片优化：吧头像自适应尺寸
          .autoResize(true)
          // A5 图片优化：吧头像加载失败静默
          .onError(() => { /* 吧头像加载失败静默处理 */ })
          // #92 HitTestMode.Transparent：让触控穿透到父 List，避免 fling 期间碰到图片导致触控丢失
          .hitTestBehavior(HitTestMode.Transparent)
      } else {
        Text(this.getForumInitial(this.forum.fname))
          .width(48)
          .height(48)
          .borderRadius(24)
          .textAlign(TextAlign.Center)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.card_background'))
          .backgroundColor(this.themeState.primary)
      }

      // 中间信息：吧名 + 等级 pill + 签到 pill
      Column() {
        Row() {
          Text(this.forum.fname)
            .fontSize(16)
            .fontWeight(600)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          // 等级 pill：11px 600，primary_light 背景
          Text(`Lv.${this.forum.level}`)
            .fontSize(11)
            .fontWeight(600)
            .fontColor(this.themeState.primary)
            .backgroundColor(this.themeState.primary_light)
            .borderRadius(6)
            .padding({ left: 7, right: 7, top: 1, bottom: 1 })
            .margin({ left: 6 })

          // 签到状态 pill 已移到右侧（签到按钮区域），避免重复展示
        }
        .alignItems(VerticalAlign.Center)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 12 })

      // 右侧：签到按钮（未签到）/ 已签到 pill（已签到）
      // issue 功能2：替换原 chevron 箭头，签到状态直接在右侧体现
      // #138 @Require @Param forum.isSigned 变化时自动触发本 if 分支重新求值
      if (this.forum.isSigned) {
        // 已签到 pill：不可点击，仅展示
        Text($r('app.string.forum_signed'))
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.success'))
          .backgroundColor($r('app.color.success_light'))
          .borderRadius(6)
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          // 已签到状态下允许触控穿透到父 ListItem，保留点击跳转吧页能力
          .hitTestBehavior(HitTestMode.Transparent)
      } else {
        // 签到按钮：可点击，调用 signForum
        Text(this.signingForumName === this.forum.fname ? $r('app.string.loading') : $r('app.string.forum_sign'))
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.themeState.primary)
          .backgroundColor(this.themeState.primary_light)
          .borderRadius(6)
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          // Block：阻止触控穿透到父 ListItem，避免签到时同时触发跳转
          .hitTestBehavior(HitTestMode.Block)
          .onClick(() => {
            this.onSignClick(this.forum);
          })
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(10)
    .alignItems(VerticalAlign.Center)
    .onClick(() => this.onItemClick(this.forum.fname))
  }
}
