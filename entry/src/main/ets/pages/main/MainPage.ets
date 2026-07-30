// 主页面容器（issue #16 + #18）
// 悬浮导航 + 沉浸光感 TabBar（2026-07-04 按华为博客方案重写）
// #170 [A4-S2'] HdsNavDestination 包装 + 移除降级逻辑（API 23 一定支持沉浸光感）
// #201 架构：HdsTabs(barOverlap + barFloatingStyle + IMMERSIVE 材质)
//   - barOverlap(true)：TabBar 悬浮于内容之上（对齐博客"悬浮导航"）
//   - systemMaterialEffect: IMMERSIVE+用户设置强度：真正沉浸光感材质（之前 ADAPTIVE 跟随系统策略导致部分设备不渲染）
//   - scrollable(false)：禁用左右滑动切换 tab，避免父 Tabs 手势拦截子 List 垂直滑动
//   - barHeight(60) + barBottomMargin(36) + barSideMargin(18)：悬浮样式（贴底，避免下方灰色空隙）
//   - TabBar 激活态 scale 1.06 + springMotion 弹性动画（对齐博客 customTabBar）

import { curves } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { HdsNavDestination, HdsTabs, HdsTabsController, hdsMaterial } from '@kit.UIDesignKit';
import { VibratorUtil } from '../../utils/VibratorUtil';
import { HomePage } from './HomePage';
import { FavoritePage } from './FavoritePage';
import { MessagePage } from './MessagePage';
import { ProfilePage } from './ProfilePage';
import { PendingAppLinkingTidState, PendingAppLinkingSeeLzState, connectPendingAppLinkingTid, connectPendingAppLinkingSeeLz, TabVisibilityState, MaterialLevelState, DefaultHomePageState, MainTabRefreshState, connectTabVisibility, connectMaterialLevel, connectDefaultHomePage, connectMainTabRefresh, resolveMaterialLevel, MATERIAL_TYPE_IMMERSIVE } from '../../model/AppStorageV2Models';
import { connectTheme, ThemeState } from '../../theme/ThemeManager';
import { RouterUtil, ThreadNavParams } from '../../utils/RouterUtil';

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
  /** 当前激活的原始 Tab index（0=首页/1=收藏/2=消息/3=我的），不随 Tab 显隐变化 */
  @Local currentOriginalIndex: number = 0;
  /** 主题状态（AppStorageV2 全局共享，TabBar 激活色跟随主题切换） */
  @Local themeState: ThemeState = connectTheme();
  // #109 A1 AppLinking：监听 EntryAbility 写入的待跳转帖子 ID
  // EntryAbility.onCreate / onNewWant 解析 want.uri 后写入此 key
  // @Monitor 监听变化触发 onAppLinkingTidChange，跳转 ThreadPage 后清零
  @Local pendingAppLinkingTidState: PendingAppLinkingTidState = connectPendingAppLinkingTid();
  @Local pendingAppLinkingSeeLzState: PendingAppLinkingSeeLzState = connectPendingAppLinkingSeeLz();
  /** #201 底栏 Tab 显隐控制（位掩码，bit0=首页/bit1=收藏/bit2=消息/bit3=我的） */
  @Local tabVisibilityState: TabVisibilityState = connectTabVisibility();
  /** #201 沉浸光感材质强度档位（0=精致/1=柔和/2=平滑/10=自适应） */
  @Local materialLevelState: MaterialLevelState = connectMaterialLevel();
  /** 默认启动页（0=首页/1=收藏/2=消息/3=我的），aboutToAppear 读取后设置 currentOriginalIndex */
  @Local defaultHomePageState: DefaultHomePageState = connectDefaultHomePage();
  @Local mainTabRefreshState: MainTabRefreshState = connectMainTabRefresh();

  aboutToAppear(): void {
    // 读取默认启动页偏好：若目标 Tab 可见则切换到该 Tab，否则回退到首页
    // 注意：Index.ets 已在启动时将 preferences 值写入 AppStorageV2，此处直接读取即可
    const targetIndex: number = this.defaultHomePageState.value;
    if (targetIndex > 0 && targetIndex <= 3
      && (this.tabVisibilityState.value & (1 << targetIndex)) !== 0) {
      this.currentOriginalIndex = targetIndex;
      // 延迟到下一帧调用 changeIndex：HdsTabs 子组件树需先完成首次渲染
      const targetVisible: number = this.visibleIndexOf(targetIndex);
      setTimeout(() => {
        this.controller.changeIndex(targetVisible);
      }, 0);
    }
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

    // #177 路由栈混用修复：ThreadPage 已迁移为 NavDestination，
    // 从 MainPage（NavDestination）内应用 RouterUtil.push 在同一 Navigation 栈中跳转，
    // 不用 router.pushUrl（会脱离 Navigation 栈导致返回行为异常）
    RouterUtil.push(RouterUtil.ROUTE_THREAD_PAGE, new ThreadNavParams(tid, seeLz));
  }

  /**
   * #170 [A4-S2'] 已移除 resolveImmersiveMaterialLevel + buildAdaptiveMaterialEffect + retryLoad
   * 原因：项目 compatibleSdkVersion = 6.1.0(23)，API 23 一定支持沉浸光感，无需动态降级
   * HdsTabs barFloatingStyle.systemMaterialEffect 直接用静态 ADAPTIVE + ADAPTIVE
   */

  /**
   * #201 原始 Tab index → 可见位置 index 映射
   * 用于动态隐藏 Tab 后 tabBuilder/onChange 的索引对齐
   * 例：隐藏收藏(bit1)后，消息的 originalIndex=2 → visibleIndex=1
   */
  private visibleIndexOf(originalIndex: number): number {
    let visibleIndex: number = 0;
    for (let i: number = 0; i < originalIndex; i++) {
      if ((this.tabVisibilityState.value & (1 << i)) !== 0) {
        visibleIndex++;
      }
    }
    return visibleIndex;
  }

  /**
   * #201 可见位置 index → 原始 Tab index 映射（visibleIndexOf 的逆运算）
   * 用于 HdsTabs.onChange 回调：HdsTabs 传入的是可见 index，
   * 需反向找出对应的原始 index 来更新 currentOriginalIndex
   */
  private originalIndexOf(visibleIndex: number): number {
    let count: number = 0;
    for (let i: number = 0; i < 4; i++) {
      if ((this.tabVisibilityState.value & (1 << i)) !== 0) {
        if (count === visibleIndex) {
          return i;
        }
        count++;
      }
    }
    return 0;
  }

  /**
   * #201 Tab 显隐变化监听：当用户在 SettingsPage 切换 Tab 可见性时
   * 如果当前激活的 Tab 被隐藏，自动切回首页（原始 index=0）
   * 并延迟调用 controller.changeIndex 让 HdsTabs 重建后再切，避免越界
   */
  @Monitor('tabVisibilityState.value')
  onTabVisibilityChange(monitor: IMonitor): void {
    if ((this.tabVisibilityState.value & (1 << this.currentOriginalIndex)) === 0) {
      this.currentOriginalIndex = 0;
    }
    // 延迟到下一帧：HdsTabs 子组件树需先完成 if 条件重建
    const targetVisible: number = this.visibleIndexOf(this.currentOriginalIndex);
    setTimeout(() => {
      this.controller.changeIndex(targetVisible);
    }, 0);
  }

  private requestCurrentTabRefresh(index: number): void {
    this.mainTabRefreshState.targetIndex = index;
    this.mainTabRefreshState.requestId++;
  }

  // 自定义页签项（图标 + 文字 + 激活态弹性动画，对齐博客 customTabBar）
  // #201 参数 index 为原始 index（0-3），高亮对比 currentOriginalIndex，
  // 切换调用 controller.changeIndex(visibleIndexOf(index)) 转为可见 index
  @Builder
  tabBuilder(text: ResourceStr, index: number, iconRes: Resource) {
    Column() {
      Image(iconRes)
        .width(22)
        .height(22)
        .fillColor(this.currentOriginalIndex === index ? this.themeState.tab_active : $r('app.color.tab_inactive'))
        // A5 图片优化：本地 SVG 图标（TabBar），同步加载避免闪烁 + 低质量插值
        .syncLoad(true)
        .interpolation(ImageInterpolation.Low)
      Text(text)
        .fontSize(10)
        .fontColor(this.currentOriginalIndex === index ? this.themeState.tab_active : $r('app.color.tab_inactive'))
        .fontWeight(this.currentOriginalIndex === index ? 600 : FontWeight.Normal)
        .margin({ top: 1 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    // 激活态弹性动画（对齐博客 scale 1.06 + translate -2 + opacity）
    .scale({ x: this.currentOriginalIndex === index ? 1.06 : 0.96, y: this.currentOriginalIndex === index ? 1.06 : 0.96 })
    .translate({ y: this.currentOriginalIndex === index ? -2 : 0 })
    .opacity(this.currentOriginalIndex === index ? 1 : 0.82)
    .animation({ duration: TAB_BAR_SPRING_ANIM_MS, curve: curves.springMotion() })
    .onClick(() => {
      if (this.currentOriginalIndex === index) {
        this.requestCurrentTabRefresh(index);
        return;
      }
      this.controller.changeIndex(this.visibleIndexOf(index));
    })
  }

  build() {
    // #170 [A4-S2'] HdsNavDestination 包装：作为 HdsNavigation 栈中的目标页面
    // MainPage 无标题栏（hideTitleBar(true)），Tab 子页面有自己的顶部栏（Slice 6 改为 backdropFilter）
    // #201 Tab 显隐动态渲染：根据 tabVisibilityState 位掩码条件渲染 TabContent
    HdsNavDestination() {
      HdsTabs({ controller: this.controller }) {
        // bit0=首页（始终渲染，不可隐藏）
        TabContent() {
          HomePage()
        }
        .tabBar(this.tabBuilder($r('app.string.tab_home'), 0, $r('app.media.ic_home')))

        // bit1=收藏
        if ((this.tabVisibilityState.value & 0b0010) !== 0) {
          TabContent() {
            FavoritePage()
          }
          .tabBar(this.tabBuilder($r('app.string.tab_favorite'), 1, $r('app.media.ic_favorite')))
        }

        // bit2=消息
        if ((this.tabVisibilityState.value & 0b0100) !== 0) {
          TabContent() {
            MessagePage()
          }
          .tabBar(this.tabBuilder($r('app.string.tab_message'), 2, $r('app.media.ic_message')))
        }

        // bit3=我的
        if ((this.tabVisibilityState.value & 0b1000) !== 0) {
          TabContent() {
            ProfilePage()
          }
          .tabBar(this.tabBuilder($r('app.string.tab_profile'), 3, $r('app.media.ic_profile')))
        }
      }
      .vertical(false)
      .barPosition(BarPosition.End)      // 页签栏放底部
      .barMode(BarMode.Fixed)            // 固定均分宽度
      .scrollable(false)                 // 禁用左右滑动切换 tab，避免手势拦截子 List
      .animationDuration(TAB_SWITCH_ANIM_MS)            // tab 切换动画时长
      .barHeight(60)                     // 页签栏高度
      .barOverlap(true)                  // 页签栏悬浮于内容之上
      .barFloatingStyle({                // 悬浮样式 + 沉浸光感（#201 materialType=IMMERSIVE 真正沉浸光感材质，materialLevel 跟随用户设置）
        barSideMargin: 18,
        barBottomMargin: 36,             // 抬高 36vp，对齐用户反馈"底部栏再抬高一点"
        thermoCtrl: true,
        systemMaterialEffect: {
          materialType: MATERIAL_TYPE_IMMERSIVE,
          materialLevel: resolveMaterialLevel(this.materialLevelState.value)
        }
      })
      .onChange((index: number) => {
        // #121 触感反馈：切换 Tab 触发轻震动
        VibratorUtil.light();
        // #201 HdsTabs 传入的 index 是可见位置，需反向映射到原始 index
        this.currentOriginalIndex = this.originalIndexOf(index);
      })
    }
    .hideTitleBar(true)
    .backgroundColor($r('app.color.page_background'))
  }
}
