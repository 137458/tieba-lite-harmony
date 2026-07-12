// 关于页（Phase 4 设置中心补全）
// 展示：应用图标 + 应用名 + 版本号 + 开源代码链接
// 开源链接点击后用 Want 跳转系统浏览器打开 GitHub 仓库
// 版本号通过 bundleManager.getBundleInfoForSelfSync 获取 app.json5 中的 versionName

import { HdsNavDestination, hdsMaterial } from '@kit.UIDesignKit';
import { getResourceString } from '../../utils/ResourceUtil';
import { bundleManager, common, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { connectTheme, ThemeState } from '../../theme/ThemeManager';

/** GitHub 开源仓库地址（与 README 保持一致） */
const GITHUB_REPO_URL: string = 'https://github.com/137458/tieba-lite-harmony';
/** 原应用 TiebaLite Android 仓库地址（上游项目，致敬 HuanCheng65） */
const UPSTREAM_REPO_URL: string = 'https://github.com/HuanCheng65/TiebaLite';
/** Telegram 群组链接 */
const TELEGRAM_GROUP_URL: string = 'https://t.me/tiebaliteharmony';
// 应用图标尺寸（vp）
const APP_ICON_SIZE: number = 96;
// 应用图标圆角（vp）
const APP_ICON_BORDER_RADIUS: number = 20;
// 链接按钮高度（vp）
const LINK_BUTTON_HEIGHT: number = 48;
// 链接按钮圆角（vp）
const LINK_BUTTON_BORDER_RADIUS: number = 10;
// 链接按钮之间的垂直间距（vp）
const LINK_BUTTON_VERTICAL_SPACING: number = 8;

// #162 [A4-S2] Navigation 路由表 @Builder：供 router_map.json 的 buildFunction 引用
@Builder
export function AboutPageBuilder() {
  AboutPage()
}

@ComponentV2
export struct AboutPage {
  // 应用版本名（如 "1.0.0"），从 bundleManager 获取，获取失败时显示空字符串
  @Local versionName: string = '';
  @Local themeState: ThemeState = connectTheme();

  async aboutToAppear(): Promise<void> {
    // 获取应用版本名，失败时降级为空字符串
    try {
      const bundleInfo: bundleManager.BundleInfo = bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT
      );
      this.versionName = bundleInfo.versionName;
    } catch (err) {
      console.error(`[AboutPage] getBundleInfo failed: ${(err as BusinessError).code} ${(err as BusinessError).message}`);
    }
  }

  // Toast 提示 helper
  private showToast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message });
  }

  /**
   * 用系统浏览器打开指定 URL
   * 实现：隐式 Want（action=viewData, entities=[entity.system.browsable], uri=url）+ startAbility
   * 错误码 16000019 表示设备无浏览器应用
   * @param url 要打开的网址
   */
  private openUrl(url: string): void {
    const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    const want: Want = {
      action: 'ohos.want.action.viewData',
      entities: ['entity.system.browsable'],
      uri: url
    };
    context.startAbility(want).then(() => {
      console.info(`[AboutPage] opened browser successfully: ${url}`);
    }).catch((err: BusinessError) => {
      console.error(`[AboutPage] open browser failed: code=${err.code}, msg=${err.message}`);
      if (err.code === 16000019) {
        this.showToast(getResourceString($r('app.string.about_no_browser')));
      } else {
        this.showToast(getResourceString($r('app.string.about_open_failed')));
      }
    });
  }

  /**
   * 链接按钮通用 Builder
   * 3 个外链按钮（GitHub/原应用/Telegram）结构完全相同，提取此 Builder 消除重复
   * @param label 按钮文本资源
   * @param url 点击后打开的网址
   * @param hasTopMargin 是否有顶部间距（第一个按钮无，后续按钮有）
   */
  @Builder
  linkButtonBuilder(label: Resource, url: string, hasTopMargin: boolean) {
    Row() {
      Text(getResourceString(label))
        .fontSize(15)
        .fontColor(this.themeState.primary)
        .layoutWeight(1)
        .margin({ left: 12 })
      Image($r('app.media.ic_chevron_right'))
        .width(14)
        .height(14)
        .fillColor($r('app.color.text_caption'))
        .margin({ right: 12 })
        // A5 图片优化：本地 SVG 图标，同步加载+低质量插值
        .syncLoad(true)
        .interpolation(ImageInterpolation.Low)
    }
    .width('100%')
    .height(LINK_BUTTON_HEIGHT)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(LINK_BUTTON_BORDER_RADIUS)
    .alignItems(VerticalAlign.Center)
    .margin({ top: hasTopMargin ? LINK_BUTTON_VERTICAL_SPACING : 0 })
    .onClick(() => this.openUrl(url))
  }

  build() {
    // #170 [A4-S2'] HdsNavDestination 包装：titleBar 沉浸光感材质（内容不滚动，不加 bindToScrollable）
    HdsNavDestination() {
      // 内容区：垂直居中
      Column() {
          // 应用图标
          Image($r('app.media.startIcon'))
            .width(APP_ICON_SIZE)
            .height(APP_ICON_SIZE)
            .borderRadius(APP_ICON_BORDER_RADIUS)
            .margin({ top: 40, bottom: 16 })
            // A5 图片优化：本地 SVG 图标，同步加载+低质量插值
            .syncLoad(true)
            .interpolation(ImageInterpolation.Low)

          // 应用名
          Text(getResourceString($r('app.string.app_name')))
            .fontSize(20)
            .fontWeight(600)
            .fontColor($r('app.color.text_primary'))
            .margin({ bottom: 4 })

          // 版本号
          Text(`v${this.versionName}`)
            .fontSize(13)
            .fontColor($r('app.color.text_caption'))
            .margin({ bottom: 32 })

          // 开源代码按钮
          this.linkButtonBuilder($r('app.string.about_open_source'), GITHUB_REPO_URL, false)

          // 原应用仓库按钮（上游 Android 项目 TiebaLite，致敬 HuanCheng65）
          this.linkButtonBuilder($r('app.string.about_original_repo'), UPSTREAM_REPO_URL, true)

          // Telegram 群组链接按钮
          this.linkButtonBuilder($r('app.string.about_telegram_group'), TELEGRAM_GROUP_URL, true)

          // 免责声明（与登录页保持一致）
          Text(getResourceString($r('app.string.disclaimer')))
            .fontSize(11)
            .fontColor($r('app.color.text_caption'))
            .textAlign(TextAlign.Center)
            .margin({ top: 24, left: 32, right: 32 })
        }
        .width('100%')
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Center)
        .padding({ left: 16, right: 16 })
    }
    .titleBar({
      content: {
        title: {
          mainTitle: $r('app.string.settings_about')
        }
      },
      style: {
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        }
      },
      // 避让状态栏：setWindowLayoutFullScreen(true) 全屏模式下 titleBar 默认不避让状态栏，
      // 需显式设置 avoidLayoutSafeArea: true 让 titleBar 内容（标题/按钮）避让状态栏
      // 保留 systemMaterialEffect 沉浸光感模糊效果（按钮浮在模糊层上）
      avoidLayoutSafeArea: true
    })
    .backgroundColor($r('app.color.page_background'))
  }
}
