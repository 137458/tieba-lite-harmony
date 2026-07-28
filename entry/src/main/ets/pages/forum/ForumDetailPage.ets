import { HdsNavDestination, ScrollEffectType } from '@kit.UIDesignKit';
import { TiebaAPI } from '../../api/TiebaAPI';
import { ForumDetailInfo } from '../../model/ForumModels';
import {
  MaterialLevelState,
  resolveMaterialLevel,
  connectMaterialLevel,
  MATERIAL_TYPE_IMMERSIVE
} from '../../model/AppStorageV2Models';
import { connectTheme, ThemeState } from '../../theme/ThemeManager';
import { LoadingView } from '../../components/LoadingView';
import { ErrorView } from '../../components/ErrorView';
import { getResourceString } from '../../utils/ResourceUtil';
import { RouterUtil, ForumDetailNavParams } from '../../utils/RouterUtil';
import { getStatusBarHeight } from '../../utils/StatusBarUtil';

// #164 [A4-S4] Navigation 路由表 @Builder：供 router_map.json 的 buildFunction 引用
@Builder
export function ForumDetailPageBuilder() {
  ForumDetailPage()
}

/**
 * 吧详情页（严格对齐安卓版 ForumDetailPage.kt 4 元素）
 * 1. 顶部居中标题栏（HdsNavDestination titleBar）：返回按钮 + "吧资料"
 * 2. 吧头像 + 吧名横向 Row
 * 3. 2 列统计卡片：关注数（memberCount）+ 帖子数（threadCount）
 * 4. 吧简介区块：标题 Chip "吧简介" + slogan + 正文
 * 不包含吧主/吧务/吧规/签到入口/推荐吧等元素
 */
@ComponentV2
export struct ForumDetailPage {
  @Local forumId: number = 0;
  @Local forumName: string = '';
  @Local forumDetail: ForumDetailInfo = new ForumDetailInfo();
  @Local isLoading: boolean = true;
  @Local errorMessage: string = '';
  // 状态栏高度（HdsNavDestination titleBar 已避让状态栏，但页面 build 内部仍需感知）
  @Local statusBarHeight: number = 36;
  // #201 沉浸光感材质强度档位（与 MainPage 共享，SettingsPage 修改后自动响应）
  @Local materialLevelState: MaterialLevelState = connectMaterialLevel();
  // 主题色（用于头像 fallback 渐变，与 ForumPage 保持一致）
  @Local themeState: ThemeState = connectTheme();

  async aboutToAppear() {
    // #164 路由迁移：router.getParams() → NavPathStack.getParamByName()
    // SDK 返回 Array<unknown>，ArkTS 不支持 unknown，用 as Object[] 断言
    const paramsStack: Object[] = RouterUtil.getStack().getParamByName(RouterUtil.ROUTE_FORUM_DETAIL_PAGE) as Object[];
    if (paramsStack && paramsStack.length > 0) {
      const params = paramsStack[paramsStack.length - 1] as ForumDetailNavParams;
      if (params) {
        this.forumId = params.forumId;
        this.forumName = params.forumName;
      }
    }
    // 获取状态栏高度，作为兜底避让值（titleBar avoidLayoutSafeArea 已处理大部分情况）
    try {
      this.statusBarHeight = await getStatusBarHeight(getContext(this));
    } catch (err) {
      console.error(`[ForumDetailPage] getStatusBarHeight failed: ${(err as Error).message}`);
    }
    // 加载吧详情数据（forumId 必需，未传入则保持 loading 状态由错误视图处理）
    if (this.forumId > 0) {
      this.loadForumDetail();
    } else {
      this.isLoading = false;
      this.errorMessage = getResourceString($r('app.string.error_invalid_params'));
    }
  }

  async loadForumDetail(): Promise<void> {
    this.isLoading = true;
    this.errorMessage = '';
    try {
      this.forumDetail = await TiebaAPI.getForumDetail(this.forumId);
    } catch (err) {
      this.errorMessage = (err as Error).message || getResourceString($r('app.string.error_load_failed'));
      console.error(`[ForumDetailPage] loadForumDetail failed: ${this.errorMessage}`);
    } finally {
      this.isLoading = false;
    }
  }

  build() {
    HdsNavDestination() {
      Column() {
        if (this.isLoading) {
          LoadingView({ message: getResourceString($r('app.string.loading')) })
            .layoutWeight(1)
        } else if (this.errorMessage.length > 0) {
          ErrorView({
            message: this.errorMessage,
            onRetryClick: (): void => {
              this.loadForumDetail().catch((err: Error) => {
                console.error(`[ForumDetailPage] retry failed: ${err.message}`);
              });
            }
          })
            .layoutWeight(1)
        } else {
          // 4 元素内容（严格对齐安卓版：头像+吧名、统计、简介）
          Scroll() {
            Column() {
              // 1. 吧头像 + 吧名横向 Row
              this.AvatarRowBuilder()
              // 2. 统计卡片（关注数 + 帖子数）
              this.StatsCardBuilder()
              // 3. 吧简介区块
              this.IntroBuilder()
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 16, bottom: 16 })
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.page_background'))
    }
    .titleBar({
      content: {
        // 标题"吧资料"，对齐安卓版 ForumDetailPage.kt
        title: { mainTitle: getResourceString($r('app.string.title_forum_info')) }
      },
      style: {
        scrollEffectOpts: {
          enableScrollEffect: true,
          scrollEffectType: ScrollEffectType.GRADIENT_BLUR
        },
        systemMaterialEffect: {
          materialType: MATERIAL_TYPE_IMMERSIVE,
          materialLevel: resolveMaterialLevel(this.materialLevelState.value)
        }
      },
      avoidLayoutSafeArea: true
    })
    .backgroundColor($r('app.color.page_background'))
  }

  /**
   * 元素 1：吧头像 + 吧名横向 Row
   * 头像 64vp 圆形，网络图优先；无 avatar 时用首字母 fallback（与 ForumPage titleBar 一致风格）
   */
  @Builder
  AvatarRowBuilder() {
    Row() {
      // 吧头像（64vp 圆形）
      if (this.forumDetail.avatar.length > 0) {
        Image(this.forumDetail.avatar)
          .width(64)
          .height(64)
          .borderRadius(32)
          .objectFit(ImageFit.Cover)
          .backgroundColor($r('app.color.input_background'))
          .alt($r('app.media.startIcon'))
          .syncLoad(true)
          .interpolation(ImageInterpolation.Low)
      } else {
        // 首字母 fallback（与 ForumPage.forumAvatarBuilder 风格一致）
        Column() {
          Text(this.forumName.length > 0 ? this.forumName.charAt(0).toUpperCase() : '?')
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
        }
        .width(64)
        .height(64)
        .borderRadius(32)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .linearGradient({
          angle: 135,
          colors: [[this.themeState.primary, 0.0], [$r('app.color.accent_blue'), 1.0]]
        })
      }
      // 吧名（响应数据优先，路由参数兜底）
      Text(this.forumDetail.forumName.length > 0 ? this.forumDetail.forumName : this.forumName)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ left: 16 })
        .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  /**
   * 元素 2：2 列统计卡片
   * 左：关注数（memberCount）  右：帖子数（threadCount）
   * 安卓版仅有这两个统计字段，不臆想其他字段
   */
  @Builder
  StatsCardBuilder() {
    Row() {
      // 关注数
      Column() {
        Text(this.forumDetail.memberCount.toString())
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Text(getResourceString($r('app.string.forum_member_count')))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Center)
      // 帖子数
      Column() {
        Text(this.forumDetail.threadCount.toString())
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Text(getResourceString($r('app.string.forum_thread_count')))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .padding({ top: 24, bottom: 24 })
  }

  /**
   * 元素 3：吧简介区块
   * 标题 Chip"吧简介" + slogan + 正文
   * 安卓版 ForumDetailInfo 仅有 slogan 字段作为简介正文，不臆想 content/介绍 等字段
   */
  @Builder
  IntroBuilder() {
    Column() {
      // 标题 Chip"吧简介"
      Text(getResourceString($r('app.string.forum_intro')))
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .backgroundColor($r('app.color.input_background'))
        .padding({ left: 12, right: 12, top: 4, bottom: 4 })
        .borderRadius(12)
        .margin({ bottom: 12 })
      // slogan（斜体强调，作为简介的"标语"）
      if (this.forumDetail.slogan.length > 0) {
        Text(this.forumDetail.slogan)
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .fontStyle(FontStyle.Italic)
          .margin({ bottom: 8 })
      }
      // 正文（安卓版无独立 content 字段，slogan 同时作为简介正文展示；无 slogan 时显示"暂无简介"）
      Text(this.forumDetail.slogan.length > 0
        ? this.forumDetail.slogan
        : getResourceString($r('app.string.forum_no_intro')))
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .lineHeight(22)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: 16 })
  }
}
