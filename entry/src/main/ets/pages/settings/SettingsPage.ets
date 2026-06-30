import { router } from '@kit.ArkUI';

@Entry
@Component
struct SettingsPage {
  build() {
    Column() {
      Row() {
        Image('')
          .width(24)
          .height(24)
          .fillColor($r('app.color.text_primary'))
          .onClick(() => {
            router.back();
          })

        Text($r('app.string.settings_title'))
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)

        Blank()
          .width(24)
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .alignItems(VerticalAlign.Center)
      .backgroundColor($r('app.color.background'))

      Text($r('app.string.settings_placeholder'))
        .fontSize(16)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: 40 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }
}
