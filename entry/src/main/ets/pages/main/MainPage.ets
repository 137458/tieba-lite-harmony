// 主页面容器（issue #16 + #18）
// 悬浮导航 + 沉浸光感 TabBar（2026-07-04 按华为博客方案重写）
// #170 [A4-S2'] HdsNavDestination 包装 + 移除降级逻辑（API 23 一定支持沉浸光感）
// 架构：HdsTabs(barOverlap + barFloatingStyle + ADAPTIVE 材质)
//   - barOverlap(true)：TabBar 悬浮于内容之上（对齐博客"悬浮导航"）
//   - systemMaterialEffect: ADAPTIVE+ADAPTIVE：沉浸光感（纯自适应系统策略，无需降级）
//   - scrollable(false)：禁用左右滑动切换 tab，避免父 Tabs 手势拦截子 List 垂直滑动
//   - barHeight(60) + barBottomMargin(36) + barSideMargin(18)：悬浮样式（贴底，避免下方灰色空隙）
//   - TabBar 激活态 scale 1.06 + springMotion 弹性动画（对齐博客 customTabBar）

import { curves, router, AppStorageV2 } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { HdsNavDestination, HdsTabs, HdsTabsController, hdsMaterial } from '@kit.UIDesignKit';
import { VibratorUtil } from '../../utils/VibratorUtil';
import { HomePage } from './HomePage';
import { FavoritePage } from './FavoritePage';
import { MessagePage } from './MessagePage';
import { ProfilePage } from './ProfilePage';
import { PendingAppLinkingTidState, PendingAppLinkingSeeLzState } from '../../model/AppStorageV2Models';
import { connectTheme, ThemeState } from '../../theme/ThemeManager';

const DOMAIN: number = 0x0000;
const TAB_LOG_TAG: string = 'MainPage';

// TabBar 激活态弹性动画时长（ms），对齐华为博客 springMotion 方案
const TAB_BAR_SPRING_ANIM_MS: number = 320;
// Tab 切换内容区动画时长（ms）
const TAB_SWITCH_ANIM_MS: number = 240;

// #162 [A4-S2] Navigation 路由表 @Builder：供 router_map.json 的 buildFunction 引用
@Builder
export function MainPageBuilder() {
  MainPage()
}

@ComponentV2
export struct MainPage {
  private controller: HdsTabsController = new HdsTabsController();
  @Local currentIndex: number = 0;
  /** 主题状态（AppStorageV2 全局共享，TabBar 激活色跟随主题切换） */
  @Local themeState: ThemeState = connectTheme();
  // #109 A1 AppLinking：监听 EntryAbility 写入的待跳转帖子 ID
  // EntryAbility.onCreate / onNewWant 解析 want.uri 后写入此 key
  // @Monitor 监听变化触发 onAppLinkingTidChange，跳转 ThreadPage 后清零
  @Local pendingAppLinkingTidState: PendingAppLinkingTidState = AppStorageV2.connect(PendingAppLinkingTidState, 'pendingAppLinkingTid', () => new PendingAppLinkingTidState())!;
  @Local pendingAppLinkingSeeLzState: PendingAppLinkingSeeLzState = AppStorageV2.connect(PendingAppLinkingSeeLzState, 'pendingAppLinkingSeeLz', () => new PendingAppLinkingSeeLzState())!;

  aboutToAppear(): void {
    // #170 移除 resolveImmersiveMaterialLevel 降级逻辑（API 23 一定支持沉浸光感）
    // #109 A1 AppLinking：冷启动场景
    // EntryAbility.onCreate 在 aboutToAppear 之前执行，pendingAppLinkingTid 已写入
    // @Monitor 不会触发初始值回调，需在此显式调用一次 handleAppLinking
    this.handleAppLinking();
  }

  /**
   * #109 A1 AppLinking：监听 pendingAppLinkingTidState.value 变化跳转 ThreadPage
   * 触发场景：
   *   1. 冷启动：aboutToAppear 显式调用 handleAppLinking
   *   2. 热启动：EntryAbility.onNewWant 写入 AppStorageV2 触发 @Monitor
   * 跳转后立即清零，避免用户返回 MainPage 时重复跳转
   * 注：@Monitor 方法签名需 monitor: IMonitor 参数，aboutToAppear 显式调用无法传 monitor，
   * 故抽取原逻辑到 handleAppLinking()，本方法只做转发
   */
  @Monitor('pendingAppLinkingTidState.value')
  onAppLinkingTidChange(monitor: IMonitor): void {
    this.handleAppLinking();
  }

  /**
   * AppLinking 跳转核心逻辑（冷启动 + 热启动共用）
   * 抽取为独立方法：aboutToAppear 显式调用不需要 monitor 参数，
   * @Monitor 方法只做转发，保持 V2 方法签名规范
   */
  private handleAppLinking(): void {
    const tid: number = this.pendingAppLinkingTidState.value;
    if (tid <= 0) {
      return;
    }

    // 立即清零，避免重复跳转（用户返回后再次触发）
    this.pendingAppLinkingTidState.value = 0;
    const seeLz: boolean = this.pendingAppLinkingSeeLzState.value;
    this.pendingAppLinkingSeeLzState.value = false;

    hilog.info(DOMAIN, TAB_LOG_TAG,
      'AppLinking navigate to ThreadPage: tid=%{public}d, seeLz=%{public}s',
      tid, String(seeLz));

    // 跳转 ThreadPage，对齐现有 router.pushUrl 调用方式
    // ThreadPage.aboutToAppear 通过 router.getParams() 读取 tid（string 类型）
    // 其他调用方（TopicDetailPage/SearchPage/FavoritePage 等）均用 tid.toString()，
    // 此处保持一致避免类型差异
    router.pushUrl({
      url: 'pages/thread/ThreadPage',
      params: { tid: tid.toString(), seeLz: seeLz }
    }).then(() => {
      hilog.info(DOMAIN, TAB_LOG_TAG, 'AppLinking navigate success: tid=%{public}d', tid);
    }).catch((err: Error) => {
      hilog.error(DOMAIN, TAB_LOG_TAG,
        'AppLinking navigate failed: tid=%{public}d, err=%{public}s',
        tid, err.message);
    });
  }

  /**
   * #170 [A4-S2'] 已移除 resolveImmersiveMaterialLevel + buildAdaptiveMaterialEffect + retryLoad
   * 原因：项目 compatibleSdkVersion = 6.1.0(23)，API 23 一定支持沉浸光感，无需动态降级
   * HdsTabs barFloatingStyle.systemMaterialEffect 直接用静态 ADAPTIVE + ADAPTIVE
   */

  // 自定义页签项（图标 + 文字 + 激活态弹性动画，对齐博客 customTabBar）
  @Builder
  tabBuilder(text: ResourceStr, index: number, iconRes: Resource) {
    Column() {
      Image(iconRes)
        .width(22)
        .height(22)
        .fillColor(this.currentIndex === index ? this.themeState.tab_active : $r('app.color.tab_inactive'))
        // A5 图片优化：本地 SVG 图标（TabBar），同步加载避免闪烁 + 低质量插值
        .syncLoad(true)
        .interpolation(ImageInterpolation.Low)
      Text(text)
        .fontSize(10)
        .fontColor(this.currentIndex === index ? this.themeState.tab_active : $r('app.color.tab_inactive'))
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
    // #170 [A4-S2'] HdsNavDestination 包装：作为 HdsNavigation 栈中的目标页面
    // MainPage 无标题栏（hideTitleBar(true)），Tab 子页面有自己的顶部栏（Slice 6 改为 backdropFilter）
    HdsNavDestination() {
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
      .barFloatingStyle({                // 悬浮样式 + 沉浸光感（ADAPTIVE 材质，API 23 一定支持）
        barSideMargin: 18,
        barBottomMargin: 36,             // 抬高 36vp，对齐用户反馈"底部栏再抬高一点"
        thermoCtrl: true,
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        }
      })
      .onChange((index: number) => {
        // #121 触感反馈：切换 Tab 触发轻震动
        VibratorUtil.light();
        this.currentIndex = index;
      })
    }
    .hideTitleBar(true)
    .backgroundColor($r('app.color.page_background'))
  }
}
