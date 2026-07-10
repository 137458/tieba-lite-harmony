import { getResourceString } from '../utils/ResourceUtil';
import { connectTheme, ThemeState } from '../theme/ThemeManager';

@Preview
@ComponentV2
export struct LoadingView {
  @Param message: string = '';
  @Local themeState: ThemeState = connectTheme();

  private getMessage(): string {
    if (this.message.length > 0) {
      return this.message;
    }
    return getResourceString($r('app.string.loading'));
  }

  build() {
    Column() {
      LoadingProgress()
        .width(40)
        .height(40)
        .color(this.themeState.primary)

      Text(this.getMessage())
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: 12 })
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}
