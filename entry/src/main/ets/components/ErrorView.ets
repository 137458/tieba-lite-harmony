import { curves } from '@kit.ArkUI';
import { getResourceString } from '../utils/ResourceUtil';
import { connectTheme, ThemeState } from '../theme/ThemeManager';

@Preview
@ComponentV2
export struct ErrorView {
  @Param message: string = '';
  // V2 @Event 支持可选回调（不传时为 undefined），调用方不传 onRetryClick 时按钮不显示
  @Event onRetryClick?: () => void;
  @Local themeState: ThemeState = connectTheme();

  private getMessage(): string {
    if (this.message.length > 0) {
      return this.message;
    }
    return getResourceString($r('app.string.error_load_failed'));
  }

  build() {
    Column() {
      // #297 图标区：主色柔光圆底衬 + 警告矢量符号（SymbolGlyph 随主题/字重自适应），
      // 替换原灰色 PNG 图标（ic_warning 40% 透明度），提升错误态视觉层次
      Stack() {
        Circle({ width: 104, height: 104 })
          .fill(this.themeState.primary)
          .opacity(0.08)

        SymbolGlyph($r('sys.symbol.exclamationmark_triangle'))
          .fontSize(44)
          .fontColor([this.themeState.primary])
      }
      .width(104)
      .height(104)
      .margin({ bottom: 20 })
      // 入场动效：透明度 + 弹性缩放（组件插入时触发一次）
      .transition(TransitionEffect.OPACITY
        .combine(TransitionEffect.scale({ x: 0.7, y: 0.7 }))
        .animation({ duration: 350, curve: curves.springMotion(0.42, 0.8) }))

      Text(this.getMessage())
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
        .margin({ bottom: 20 })

      if (this.onRetryClick) {
        // 重试按钮：实心主色胶囊（与签到/发送等主操作按钮一致），强化点击引导
        Button($r('app.string.retry'))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.card_background'))
          .backgroundColor(this.themeState.primary)
          .padding({ left: 28, right: 28, top: 9, bottom: 9 })
          .onClick(() => {
            if (this.onRetryClick) {
              this.onRetryClick();
            }
          })
      }
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}
