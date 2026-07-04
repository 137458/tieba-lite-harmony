// 主页面容器（issue #16 + #18）
// 底部固定 TabBar（非悬浮），4 个 tab：首页 / 动态 / 消息 / 我的
// 架构：原生 Tabs + 自定义底部 TabBar
// 重写说明（2026-07-04）：弃用 HdsTabs(barOverlap + systemMaterialEffect)
//   原因 1：barOverlap(true) 让 TabBar 悬浮覆盖内容底部，导致底部手势被拦截，滑动卡顿
//   原因 2：systemMaterialEffect IMMERSIVE 沉浸光感材质在 page_background 上显示为固定灰色块
//   原因 3：HdsTabs 内部手势与子页 List 滚动冲突，导致"点击后滑动无响应"
//   方案：原生 Tabs + 自定义 tabBuilder，barOverlap 默认 false，TabBar 不再悬浮

import { HomePage } from './HomePage';
import { FavoritePage } from './FavoritePage';
import { MessagePage } from './MessagePage';
import { ProfilePage } from './ProfilePage';

@Entry
@Component
struct MainPage {
  private controller: TabsController = new TabsController();
  @State currentIndex: number = 0;

  // 自定义页签栏内容（图标 + 文字，激活态 primary 色 + 600 字重，对齐 design-prototype.html tab-item 规范）
  @Builder
  tabBuilder(text: ResourceStr, index: number, iconRes: Resource) {
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
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      this.controller.changeIndex(index);
    })
  }

  build() {
    Column() {
      Tabs({ controller: this.controller }) {
        TabContent() {
          HomePage()
        }
        .tabBar(this.tabBuilder($r('app.string.tab_home'), 0, $r('app.media.ic_home')))

        TabContent() {
          FavoritePage()
        }
        .tabBar(this.tabBuilder($r('app.string.tab_favorite'), 1, $r('app.media.ic_favorite')))

        TabContent() {
          MessagePage()
        }
        .tabBar(this.tabBuilder($r('app.string.tab_message'), 2, $r('app.media.ic_message')))

        TabContent() {
          ProfilePage()
        }
        .tabBar(this.tabBuilder($r('app.string.tab_profile'), 3, $r('app.media.ic_profile')))
      }
      .barPosition(BarPosition.End)      // 页签栏放底部
      .vertical(false)                   // 横向页签
      .barHeight(56)                     // 固定高度，不再悬浮
      .scrollable(true)                  // 允许左右滑动切换 tab
      .animationDuration(300)            // tab 切换动画时长
      .barMode(BarMode.Fixed)            // 固定均分宽度
      .onChange((index: number) => {
        this.currentIndex = index;
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }
}
