// 消息页（"消息"tab，占位实现）
// UI 设计：iOS Large Title + empty-state 卡片（对齐 design-prototype.html L453-460）
// 后续迭代接入消息列表 API

import { getStatusBarHeight } from '../../utils/StatusBarUtil';

@Component
export struct MessagePage {
  // 状态栏高度（vp），沉浸式避让状态栏
  @State statusBarHeight: number = 36;

  async aboutToAppear() {
    // 获取状态栏高度，失败不阻塞页面渲染，保留默认值 36
    try {
      this.statusBarHeight = await getStatusBarHeight(getContext(this));
    } catch (err) {
      console.error(`[MessagePage] getStatusBarHeight failed: ${(err as Error).message}`);
    }
  }

  build() {
    Column() {
      // iOS Large Title 顶部栏（34px Bold）
      Row() {
        Text($r('app.string.message_page_title'))
          .fontSize(34)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
      }
      .width('100%')
      .height(56 + this.statusBarHeight)
      .padding({ left: 20, right: 20, top: this.statusBarHeight, bottom: 8 })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
      .alignItems(VerticalAlign.Center)

      // empty-state 卡片（居中显示，对齐 design-prototype.html L455-459）
      Column() {
        // 64x64 chat.bubble SVG，opacity 0.4 — Shape 包裹 Path 提供 viewPort
        Shape() {
          Path()
            .width(24)
            .height(24)
            .commands('M20 2H4c-1.1 0-2 .9-2 2v18l4-4h14c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2z')
            .fill($r('app.color.text_caption'))
        }
        .width(64)
        .height(64)
        .viewPort({ x: 0, y: 0, width: 24, height: 24 })
        .opacity(0.4)
        .margin({ bottom: 20 })

        // title 20px 600
        Text($r('app.string.message_empty_title'))
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .margin({ bottom: 8 })

        // desc 14px text_caption 1.5 行高
        Text($r('app.string.message_empty_desc'))
          .fontSize(14)
          .fontColor($r('app.color.text_caption'))
          .lineHeight(21)
          .textAlign(TextAlign.Center)
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 40, right: 40 })
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }
}
