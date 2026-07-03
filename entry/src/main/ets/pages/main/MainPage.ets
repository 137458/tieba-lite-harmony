// 主页面容器（issue #16 + #18）
// 底部悬浮 TabBar + 沉浸光感材质
// 4 个 tab：首页 / 动态 / 消息 / 我的
// 架构：HdsTabs(barOverlap + barFloatingStyle + systemMaterialEffect)

import { HdsTabs, HdsTabsController, hdsMaterial } from '@kit.UIDesignKit';
import { HomePage } from './HomePage';
import { FavoritePage } from './FavoritePage';
import { MessagePage } from './MessagePage';
import { ProfilePage } from './ProfilePage';

@Entry
@Component
struct MainPage {
  private controller: HdsTabsController = new HdsTabsController();
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
      HdsTabs({ controller: this.controller }) {
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
      .barOverlap(true)                  // 页签栏悬浮于内容之上
      .barPosition(BarPosition.End)      // 页签栏放底部
      .vertical(false)                   // 横向页签
      .barFloatingStyle({                // 悬浮样式 + 沉浸光感
        barWidth: { smallWidth: 320, mediumWidth: 360, largeWidth: 420 },
        barBottomMargin: 28,
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.IMMERSIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        }
      })
      .onChange((index: number) => {
        this.currentIndex = index;
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }
}
