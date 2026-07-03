import { router } from '@kit.ArkUI';
import { getStatusBarHeight } from '../../utils/StatusBarUtil';

@Entry
@Component
struct SettingsPage {
  // 状态栏高度（vp），沉浸式避让状态栏，默认 36，aboutToAppear 动态获取
  @State statusBarHeight: number = 36;

  async aboutToAppear() {
    // 获取状态栏高度（沉浸式，P1 重构提取为 StatusBarUtil）
    this.statusBarHeight = await getStatusBarHeight(getContext(this));
  }

  // 菜单项构建器：左侧图标 + 文字 + 右侧箭头，isDanger 控制红色退出风格
  @Builder menuItemBuilder(icon: Resource, label: Resource, isDanger: boolean) {
    Row() {
      Image(icon)
        .width(22)
        .height(22)
        .fillColor(isDanger ? $r('app.color.error') : $r('app.color.primary'))
      Text(label)
        .layoutWeight(1)
        .fontSize(16)
        .fontColor(isDanger ? $r('app.color.error') : $r('app.color.text_primary'))
        .margin({ left: 12 })
      Image($r('app.media.ic_chevron_right'))
        .width(14)
        .height(14)
        .fillColor($r('app.color.text_caption'))
    }
    .width('100%')
    .height(44)
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor($r('app.color.card_background'))
  }

  // 分割线构建器：从图标右侧开始（left 52），0.5vp 细线，参考原型 menu-item::after
  @Builder dividerBuilder() {
    Row() {
      Row()
        .height(0.5)
        .backgroundColor($r('app.color.divider'))
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 52 })
  }

  build() {
    Column() {
      // 顶部导航栏（参考原型 detail-nav：44 + statusBarHeight，标题居中）
      Row() {
        Image($r('app.media.ic_back'))
          .width(20)
          .height(20)
          .fillColor($r('app.color.primary'))
          .onClick(() => {
            router.back();
          })
        Text($r('app.string.settings_title'))
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

      // 菜单容器：左右 16，顶部 20
      Column() {
        // 第一组：深色模式 + 清除缓存
        Column() {
          this.menuItemBuilder($r('app.media.ic_settings'), $r('app.string.settings_dark_mode'), false)
          this.dividerBuilder()
          this.menuItemBuilder($r('app.media.ic_settings'), $r('app.string.settings_clear_cache'), false)
        }
        .width('100%')
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(10)
        .clip(true)
        .margin({ bottom: 12 })

        // 第二组：退出登录（danger 红色风格）
        Column() {
          this.menuItemBuilder($r('app.media.ic_logout'), $r('app.string.profile_logout'), true)
        }
        .width('100%')
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(10)
        .clip(true)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 20 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }
}
