// 主页面容器（issue #16 + #18）
// 悬浮导航 + 沉浸光感 TabBar（2026-07-04 按华为博客方案重写）
// 博客：https://developer.huawei.com/consumer/cn/blog/topic/03212369425758084
// 架构：HdsTabs(barOverlap + barFloatingStyle + ADAPTIVE 材质)
//   - barOverlap(true)：TabBar 悬浮于内容之上（对齐博客"悬浮导航"）
//   - systemMaterialEffect: ADAPTIVE：沉浸光感（自动降级 SMOOTH，避免 IMMERSIVE 灰色遮罩）
//   - scrollable(false)：禁用左右滑动切换 tab，避免父 Tabs 手势拦截子 List 垂直滑动
//   - barHeight(60) + barBottomMargin(0) + barSideMargin(18)：悬浮样式（贴底，避免下方灰色空隙）
//   - 子页面底部 padding 100：让内容让位，避免被 TabBar 遮挡导致手势被拦截
//   - TabBar 激活态 scale 1.06 + springMotion 弹性动画（对齐博客 customTabBar）

import { curves } from '@kit.ArkUI';
import { HdsTabs, HdsTabsController, SystemMaterialParams, hdsMaterial } from '@kit.UIDesignKit';
import { HomePage } from './HomePage';
import { FavoritePage } from './FavoritePage';
import { MessagePage } from './MessagePage';
import { ProfilePage } from './ProfilePage';

// TabBar 激活态弹性动画时长（ms），对齐华为博客 springMotion 方案
const TAB_BAR_SPRING_ANIM_MS: number = 320;
// Tab 切换内容区动画时长（ms）
const TAB_SWITCH_ANIM_MS: number = 240;

@Entry
@Component
struct MainPage {
  private controller: HdsTabsController = new HdsTabsController();
  @State currentIndex: number = 0;
  // 沉浸光感材质等级：支持 IMMERSIVE 用 ADAPTIVE，不支持降级 SMOOTH
  @State immersiveMaterialLevel: hdsMaterial.MaterialLevel = hdsMaterial.MaterialLevel.ADAPTIVE;

  aboutToAppear(): void {
    this.resolveImmersiveMaterialLevel();
  }

  /**
   * 沉浸光感材质等级解析（对齐博客 resolveImmersiveMaterialLevel）
   * 优先用 ADAPTIVE（系统自动调整），不支持 IMMERSIVE 时降级 SMOOTH
   * 注意：之前用 IMMERSIVE 导致灰色遮罩，博客用 ADAPTIVE 不会有此问题
   */
  private resolveImmersiveMaterialLevel(): void {
    let materialTypes: Array<hdsMaterial.MaterialType> = hdsMaterial.getSystemMaterialTypes();
    if (materialTypes.indexOf(hdsMaterial.MaterialType.IMMERSIVE) < 0) {
      this.immersiveMaterialLevel = hdsMaterial.MaterialLevel.SMOOTH;
      return;
    }
    this.immersiveMaterialLevel = hdsMaterial.MaterialLevel.ADAPTIVE;
  }

  /**
   * 构建自适应材质参数（对齐博客 buildAdaptiveMaterialEffect）
   */
  private buildAdaptiveMaterialEffect(): SystemMaterialParams {
    return {
      materialType: hdsMaterial.MaterialType.ADAPTIVE,
      materialLevel: this.immersiveMaterialLevel
    };
  }

  // 自定义页签项（图标 + 文字 + 激活态弹性动画，对齐博客 customTabBar）
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
    // 激活态弹性动画（对齐博客 scale 1.06 + translate -2 + opacity）
    .scale({ x: this.currentIndex === index ? 1.06 : 0.96, y: this.currentIndex === index ? 1.06 : 0.96 })
    .translate({ y: this.currentIndex === index ? -2 : 0 })
    .opacity(this.currentIndex === index ? 1 : 0.82)
    .animation({ duration: TAB_BAR_SPRING_ANIM_MS, curve: curves.springMotion() })
    .onClick(() => {
      this.controller.changeIndex(index);
    })
  }

  build() {
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
    .vertical(false)
    .barPosition(BarPosition.End)      // 页签栏放底部
    .barMode(BarMode.Fixed)            // 固定均分宽度
    .scrollable(false)                 // 禁用左右滑动切换 tab，避免手势拦截子 List
    .animationDuration(TAB_SWITCH_ANIM_MS)            // tab 切换动画时长
    .barHeight(60)                     // 页签栏高度
    .barOverlap(true)                  // 页签栏悬浮于内容之上
    .barFloatingStyle({                // 悬浮样式 + 沉浸光感（ADAPTIVE 材质，不是 IMMERSIVE）
      barSideMargin: 18,
      barBottomMargin: 0,              // #93 贴底，避免 TabBar 下方产生灰色空隙遮罩
      thermoCtrl: true,
      systemMaterialEffect: this.buildAdaptiveMaterialEffect()
    })
    .onChange((index: number) => {
      this.currentIndex = index;
    })
  }
}
