@Preview
@Component
export struct LoadingView {
  @Prop message: string = '';

  private getMessage(): string {
    if (this.message.length > 0) {
      return this.message;
    }
    return $r('app.string.loading').toString();
  }

  build() {
    Column() {
      LoadingProgress()
        .width(40)
        .height(40)
        .color($r('app.color.primary'))

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
