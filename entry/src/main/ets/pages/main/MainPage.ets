// 主页面容器（issue #16 + #18）
// 底部悬浮 TabBar + 沉浸光感材质
// 4 个 tab：首页 / 收藏 / 消息 / 我的
// 架构：HdsTabs(barOverlap + barFloatingStyle + systemMaterialEffect)
// UI 设计：iOS 系统配色 + SF Symbols 风格 SVG 图标（对齐 design-spec.md 第4节）

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

  // TabBar 图标 SVG path（对齐 design-prototype.html SF Symbols 风格）
  // 首页 house.fill / 收藏 heart.fill / 消息 bubble.left.fill / 我的 person.fill
  @Builder
  tabIconBuilder(svgPath: string, index: number) {
    Path()
      .commands(svgPath)
      .fillColor(this.currentIndex === index ? $r('app.color.tab_active') : $r('app.color.tab_inactive'))
      .width(22)
      .height(22)
  }

  // 自定义页签栏内容：图标 + 文字（对齐 design-spec.md 第4节规格）
  @Builder
  tabBuilder(text: ResourceStr, index: number, iconPath: string) {
    Column() {
      this.tabIconBuilder(iconPath, index)
      Text(text)
        .fontSize(10)
        .fontColor(this.currentIndex === index ? $r('app.color.tab_active') : $r('app.color.tab_inactive'))
        .fontWeight(this.currentIndex === index ? FontWeight.Medium : FontWeight.Normal)
        .margin({ top: 1 })
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
        .tabBar(this.tabBuilder($r('app.string.tab_home'), 0,
          'M12 3L4 9v12h5v-7h6v7h5V9z'))

        TabContent() {
          FavoritePage()
        }
        .tabBar(this.tabBuilder($r('app.string.tab_favorite'), 1,
          'M12 21.35l-1.45-1.32C5.4 15.36 2 12.28 2 8.5 2 5.42 4.42 3 7.5 3c1.74 0 3.41.81 4.5 2.09C13.09 3.81 14.76 3 16.5 3 19.58 3 22 5.42 22 8.5c0 3.78-3.4 6.86-8.55 11.54L12 21.35z'))

        TabContent() {
          MessagePage()
        }
        .tabBar(this.tabBuilder($r('app.string.tab_message'), 2,
          'M20 2H4c-1.1 0-2 .9-2 2v18l4-4h14c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2zm0 14H6l-2 2V4h16v12z'))

        TabContent() {
          ProfilePage()
        }
        .tabBar(this.tabBuilder($r('app.string.tab_profile'), 3,
          'M12 12c2.21 0 4-1.79 4-4s-1.79-4-4-4-4 1.79-4 4 1.79 4 4 4zm0 2c-2.67 0-8 1.34-8 4v2h16v-2c0-2.66-5.33-4-8-4z'))
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
