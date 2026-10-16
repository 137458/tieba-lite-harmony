import { curves } from '@kit.ArkUI';

/**
 * 通用空态占位组件（#297）
 * 视觉语言与 ErrorView 一致：柔光圆底衬 + SymbolGlyph 矢量图标 + 主文案 + 可选副文案
 * 替换各页面"一行裸文本"的简陋空态
 */
@Preview
@ComponentV2
export struct EmptyView {
  /** 图标资源，默认文档符号 */
  @Param icon: Resource = $r('sys.symbol.doc_plaintext');
  /** 主文案（必填语义，空串不渲染） */
  @Param message: ResourceStr = '';
  /** 副文案（可选操作指引） */
  @Param hint: ResourceStr = '';
  /** 图标字号（vp），默认 44 */
  @Param iconSize: number = 44;

  build() {
    Column() {
      Stack() {
        Circle({ width: 104, height: 104 })
          .fill($r('app.color.text_caption'))
          .opacity(0.06)

        SymbolGlyph(this.icon)
          .fontSize(this.iconSize)
          .fontColor([$r('app.color.text_caption')])
      }
      .width(104)
      .height(104)
      .margin({ bottom: 16 })
      // 入场动效：透明度 + 弹性缩放（组件插入时触发一次）
      .transition(TransitionEffect.OPACITY
        .combine(TransitionEffect.scale({ x: 0.7, y: 0.7 }))
        .animation({ duration: 350, curve: curves.springMotion(0.42, 0.8) }))

      if (this.message !== '') {
        Text(this.message)
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .textAlign(TextAlign.Center)
      }

      if (this.hint !== '') {
        Text(this.hint)
          .fontSize(12)
          .fontColor($r('app.color.text_caption'))
          .textAlign(TextAlign.Center)
          .margin({ top: 6 })
      }
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding(16)
  }
}
