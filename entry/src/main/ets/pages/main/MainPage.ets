// 主页面容器（issue #16 + #18）
// 悬浮 TabBar 架构（2026-07-04 重写）
// 用 Stack 布局实现悬浮：Tabs(barHeight=0) 填满 + 自定义 Row TabBar 浮在底部
//   - TabBar 悬浮于内容之上，内容可滚动到 TabBar 下方（对齐 design-prototype.html）
//   - TabBar 纯色背景，无 systemMaterialEffect（避免灰色遮罩）
//   - 不加底部避让代码（用户明确要求，内容被遮挡是预期行为）
//   - 保留 4 tab 切换 + 左右滑动切换 + 激活态样式

import { HomePage } from './HomePage';
import { FavoritePage } from './FavoritePage';
import { MessagePage } from './MessagePage';
import { ProfilePage } from './ProfilePage';

@Entry
@Component
struct MainPage {
  private controller: TabsController = new TabsController();
  @State currentIndex: number = 0;

  // 自定义页签项（图标 + 文字，激活态 primary 色 + 600 字重，对齐 design-prototype.html tab-item 规范）
  @Builder
  tabItem(text: ResourceStr, index: number, iconRes: Resource) {
    Column() {
      Image(iconRes)
        .width(22)
        .height(22)
        .fillColor(this.currentIndex === index ? $r('app.color.tab_active') : $r('app.color.tab_inactive'))
      Text(text)
        .fontSize(10)
        .fontColor(this.currentIndex === index ? $r('app.color.tab_active') : $r('app.color.tab_inactive'))
        .fontWeight(this.currentIndex === index ? 600 : FontWeight.Normal)
        .margin({ top: 1 })
    }
    .layoutWeight(1)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      this.controller.changeIndex(index);
    })
  }

  build() {
    Stack({ alignContent: Alignment.BottomStart }) {
      // 内容区：Tabs 填满整个区域，内置 barHeight=0（用自定义悬浮 TabBar 替代）
      Tabs({ controller: this.controller }) {
        TabContent() {
          HomePage()
        }
        .tabBar('')

        TabContent() {
          FavoritePage()
        }
        .tabBar('')

        TabContent() {
          MessagePage()
        }
        .tabBar('')

        TabContent() {
          ProfilePage()
        }
        .tabBar('')
      }
      .barHeight(0)                     // 隐藏内置 TabBar（用自定义悬浮 Row 替代）
      .scrollable(true)                 // 允许左右滑动切换 tab
      .animationDuration(300)           // tab 切换动画时长
      .onChange((index: number) => {
        this.currentIndex = index;
      })

      // 悬浮 TabBar：固定在底部，纯色背景（无 systemMaterialEffect 灰色遮罩）
      Row() {
        this.tabItem($r('app.string.tab_home'), 0, $r('app.media.ic_home'))
        this.tabItem($r('app.string.tab_favorite'), 1, $r('app.media.ic_favorite'))
        this.tabItem($r('app.string.tab_message'), 2, $r('app.media.ic_message'))
        this.tabItem($r('app.string.tab_profile'), 3, $r('app.media.ic_profile'))
      }
      .width('100%')
      .height(56)
      .backgroundColor($r('app.color.card_background'))
      // 顶部边框分隔线（对齐 design-prototype.html tabbar border-top）
      .border({ width: { top: 0.5 }, color: { top: $r('app.color.divider') } })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }
}
