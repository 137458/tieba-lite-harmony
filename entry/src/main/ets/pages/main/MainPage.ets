// 主页面容器（issue #16 + #18）
// 底部悬浮 TabBar + 沉浸光感材质
// 4 个 tab：首页 / 收藏 / 消息 / 我的
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

  // 自定义页签栏内容（当前仅文字，后续可换图标+文字）
  @Builder
  tabBuilder(text: ResourceStr, index: number) {
    Column() {
      Text(text)
        .fontSize(12)
        .fontColor(this.currentIndex === index ? $r('app.color.tab_active') : $r('app.color.tab_inactive'))
        .fontWeight(this.currentIndex === index ? FontWeight.Bold : FontWeight.Normal)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
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
        .tabBar(this.tabBuilder($r('app.string.tab_home'), 0))

        TabContent() {
          FavoritePage()
        }
        .tabBar(this.tabBuilder($r('app.string.tab_favorite'), 1))

        TabContent() {
          MessagePage()
        }
        .tabBar(this.tabBuilder($r('app.string.tab_message'), 2))

        TabContent() {
          ProfilePage()
        }
        .tabBar(this.tabBuilder($r('app.string.tab_profile'), 3))
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
