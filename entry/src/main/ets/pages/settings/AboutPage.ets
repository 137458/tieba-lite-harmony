// 关于页（Phase 4 设置中心补全）
// 展示：应用图标 + 应用名 + 版本号 + 开源代码链接
// 开源链接点击后用 Want 跳转系统浏览器打开 GitHub 仓库
// 版本号通过 bundleManager.getBundleInfoForSelfSync 获取 app.json5 中的 versionName

import { router } from '@kit.ArkUI';
import { getStatusBarHeight } from '../../utils/StatusBarUtil';
import { getResourceString } from '../../utils/ResourceUtil';
import { bundleManager, common, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';

/** GitHub 开源仓库地址（与 README 保持一致） */
const GITHUB_REPO_URL: string = 'https://github.com/137458/tieba-lite-harmony';
/** 原应用 TiebaLite Android 仓库地址（上游项目，致敬 HuanCheng65） */
const UPSTREAM_REPO_URL: string = 'https://github.com/HuanCheng65/TiebaLite';

@Entry
@ComponentV2
struct AboutPage {
  // 状态栏高度（vp），沉浸式避让状态栏，默认 36，aboutToAppear 动态获取
  @Local statusBarHeight: number = 36;
  // 应用版本名（如 "1.0.0"），从 bundleManager 获取，获取失败时显示空字符串
  @Local versionName: string = '';

  async aboutToAppear(): Promise<void> {
    // 获取状态栏高度，失败不阻塞页面加载
    try {
      this.statusBarHeight = await getStatusBarHeight(getContext(this));
    } catch (err) {
      console.error(`[AboutPage] getStatusBarHeight failed: ${(err as Error).message}`);
    }
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

  build() {
    Column() {
      // 顶部导航栏（与 SettingsPage 风格一致）
      Row() {
        Image($r('app.media.ic_back'))
          .width(20)
          .height(20)
          .fillColor($r('app.color.primary'))
          // A5 图片优化：本地 SVG 图标，同步加载+低质量插值
          .syncLoad(true)
          .interpolation(ImageInterpolation.Low)
          .onClick(() => {
            router.back();
          })
        Text($r('app.string.settings_about'))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .fontSize(17)
          .fontWeight(600)
          .fontColor($r('app.color.text_primary'))
        // 右侧占位，与返回按钮等宽，保证标题视觉居中
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

      // 内容区：垂直居中
      Column() {
        // 应用图标
        Image($r('app.media.startIcon'))
          .width(96)
          .height(96)
          .borderRadius(20)
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
        Row() {
          Text(getResourceString($r('app.string.about_open_source')))
            .fontSize(15)
            .fontColor($r('app.color.primary'))
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
        .height(48)
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(10)
        .alignItems(VerticalAlign.Center)
        .onClick(() => this.openUrl(GITHUB_REPO_URL))

        // 原应用仓库按钮（上游 Android 项目 TiebaLite，致敬 HuanCheng65）
        Row() {
          Text('原应用仓库')
            .fontSize(15)
            .fontColor($r('app.color.primary'))
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
        .height(48)
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(10)
        .alignItems(VerticalAlign.Center)
        .margin({ top: 8 })
        .onClick(() => this.openUrl(UPSTREAM_REPO_URL))

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
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }
}
