import { AppStorageV2 } from '@kit.ArkUI';
import { HdsNavDestination, ScrollEffectType, hdsMaterial } from '@kit.UIDesignKit';
import { TiebaAPI } from '../../api/TiebaAPI';
import { SelfFollowForum } from '../../model/ForumModels';
import { ImageLoadTypeState, IsWifiState, SafeBottomState } from '../../model/AppStorageV2Models';
import { LoadingView } from '../../components/LoadingView';
import { ErrorView } from '../../components/ErrorView';
import { getResourceString } from '../../utils/ResourceUtil';
import { BaseViewModel, FetchDataResult } from '../../viewmodel/BaseViewModel';
import { CommonDataSource } from '../../utils/CommonDataSource';
import { shouldLoad } from '../../utils/ImageLoadUtil';
import { connectTheme, ThemeState } from '../../theme/ThemeManager';
import { VibratorUtil } from '../../utils/VibratorUtil';
import { RouterUtil, ForumNavParams } from '../../utils/RouterUtil';

/**
 * 关注吧列表 ViewModel
 * 调用 TiebaAPI.getFollowForums（web 端 /c/f/forum/forumGuide）
 */
class FollowForumsViewModel extends BaseViewModel<SelfFollowForum> {
  protected async fetchData(page: number, isRefresh: boolean): Promise<FetchDataResult<SelfFollowForum>> {
    return await TiebaAPI.getFollowForums(page);
  }
}

// #164 [A4-S4] Navigation 路由表 @Builder：供 router_map.json 的 buildFunction 引用
@Builder
export function FollowForumsPageBuilder() {
  FollowForumsPage()
}

@ComponentV2
export struct FollowForumsPage {
  private viewModel: FollowForumsViewModel = new FollowForumsViewModel();
  private dataSource: CommonDataSource<SelfFollowForum> = new CommonDataSource<SelfFollowForum>();

  @Local forumCount: number = 0;
  @Local isLoading: boolean = false;
  @Local isRefreshing: boolean = false;
  @Local hasMore: boolean = true;
  @Local errorMessage: string = '';
  // #164 滚动器，绑定到 HdsNavDestination.bindToScrollable 实现标题栏滚动动态模糊
  private scroller: Scroller = new Scroller();
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
    // #203 注入 DataSource 引用，供 BaseViewModel 内存压力时自动 clearCache
    this.viewModel.setDataSource(this.dataSource);
    this.loadForums(true).catch((err: Error) => {
      console.error(`[FollowForumsPage] loadForums failed: ${err.message}`);
    });
  }

  aboutToDisappear(): void {
    // #203 清理 ViewModel 持有的 DataSource 引用，防止 ViewModel 被全局缓存时引用泄漏
    this.viewModel.setDataSource(null);
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
    // #164 路由迁移：router.pushUrl → RouterUtil.push
    RouterUtil.push(RouterUtil.ROUTE_FORUM_PAGE, new ForumNavParams(forumName));
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
      // 签到成功：@ObservedV2 SelfFollowForum + @Trace isSigned 字段级更新
      // FollowForumItem 通过 @Require @Param forum 自动感知 isSigned 变化触发 UI 刷新
      // 不能调用 setData(getAllData())——传入同一数组引用时 LazyForEach 按 fid key
      // 复用旧组件实例，框架检测不到变化反而抑制字段级刷新，导致 UI 不更新
      forum.isSigned = true;
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
    // #164 [A4-S4] HdsNavDestination 包装：替代 @Entry + router，纳入 HdsNavigation 路由栈
    // 顶部栏简单（仅标题），用 titleBar 配置 + scrollEffectOpts + systemMaterialEffect
    HdsNavDestination() {
      Column() {
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
        List({ scroller: this.scroller }) {
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
    .titleBar({
      content: { title: { mainTitle: $r('app.string.follow_forums_title') } },
      style: {
        scrollEffectOpts: { enableScrollEffect: true, scrollEffectType: ScrollEffectType.GRADIENT_BLUR },
        systemMaterialEffect: { materialType: hdsMaterial.MaterialType.ADAPTIVE, materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE }
      },
      // 避让状态栏：setWindowLayoutFullScreen(true) 全屏模式下 titleBar 默认不避让状态栏，
      // 需显式设置 avoidLayoutSafeArea: true 让 titleBar 内容（标题/按钮）避让状态栏
      avoidLayoutSafeArea: true
    })
    .bindToScrollable([this.scroller])
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
