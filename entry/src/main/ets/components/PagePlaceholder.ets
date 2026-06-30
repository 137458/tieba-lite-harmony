// 通用占位页组件（issue #16）
// 用于 TabBar 占位 tab（收藏/消息/我的）的占位展示

@Component
export struct PagePlaceholder {
  @Prop pageTitle: ResourceStr = '';
  @Prop tipText: ResourceStr = $r('app.string.page_developing');

  build() {
    Column() {
      Text(this.pageTitle)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: 64, bottom: 16 })

      Text(this.tipText)
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
    .justifyContent(FlexAlign.Start)
    .alignItems(HorizontalAlign.Center)
  }
}
