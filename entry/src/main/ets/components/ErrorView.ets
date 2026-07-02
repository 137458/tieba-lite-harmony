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
      // 警告图标（exclamationmark.triangle SVG，对齐 design-spec.md 第8节）
      Shape() {
        Path()
          .width(24)
          .height(24)
          .commands('M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm1 15h-2v-2h2v2zm0-4h-2V7h2v6z')
          .fill($r('app.color.text_caption'))
      }
      .width(48)
      .height(48)
      .viewPort({ x: 0, y: 0, width: 24, height: 24 })
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
