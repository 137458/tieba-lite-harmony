import { getResourceString } from '../utils/ResourceUtil';

@Preview
@Component
export struct ErrorView {
  @Prop message: string = '';
  onRetryClick?: () => void;

  private getMessage(): string {
    if (this.message.length > 0) {
      return this.message;
    }
    return getResourceString($r('app.string.error_load_failed'));
  }

  build() {
    Column() {
      Text('⚠️')
        .fontSize(48)
        .margin({ bottom: 16 })

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
