import { getResourceString } from '../utils/ResourceUtil';

@Preview
@ComponentV2
export struct ErrorView {
  @Param message: string = '';
  // V2 @Event 支持可选回调（不传时为 undefined），调用方不传 onRetryClick 时按钮不显示
  @Event onRetryClick?: () => void;

  private getMessage(): string {
    if (this.message.length > 0) {
      return this.message;
    }
    return getResourceString($r('app.string.error_load_failed'));
  }

  build() {
    Column() {
      Image($r('app.media.ic_warning'))
        .width(48)
        .height(48)
        .fillColor($r('app.color.text_caption'))
        .opacity(0.4)
        .margin({ bottom: 16 })
        // A5 图片优化：SVG 图标同步加载
        .syncLoad(true)
        // A5 图片优化：SVG 图标低质量插值
        .interpolation(ImageInterpolation.Low)

      Text(this.getMessage())
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
        .margin({ bottom: 16 })

      if (this.onRetryClick) {
        Button($r('app.string.retry'))
          .fontSize(14)
          .fontColor($r('app.color.primary'))
          .backgroundColor(Color.Transparent)
          .border({ width: 1, color: $r('app.color.primary'), radius: 20 })
          .padding({ left: 24, right: 24, top: 8, bottom: 8 })
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
