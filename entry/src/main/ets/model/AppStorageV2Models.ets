/**
 * AppStorageV2 全局状态包装类（V2 状态管理迁移，issue #141 调研结论）
 *
 * V1 @StorageProp('key') → V2 AppStorageV2.connect(WrapperClass, 'key', () => new WrapperClass())
 * V1 @StorageLink('key') → V2 AppStorageV2.connect(WrapperClass, 'key', () => new WrapperClass())
 *
 * 每个全局状态 key 对应一个 @ObservedV2 包装类，包装类内用 @Trace value 字段持有实际值。
 * 组件通过 AppStorageV2.connect 连接到包装类实例，value 变化时自动触发 UI 刷新。
 * 写入方也通过 AppStorageV2.connect 获取实例，修改 value 字段即可触发所有订阅者刷新。
 */

import { AppStorageV2 } from '@kit.ArkUI';
import { hdsMaterial } from '@kit.UIDesignKit';

/**
 * 图片加载策略（0=智能原图/1=智能无图/2=始终原图/3=始终无图）
 * 写入方：StartupTask_ImageLoadType / SettingsPage
 * 订阅方：ThreadCard / ThreadPage / SubPostsPage / ForumPage / HomePage / ProfilePage / MessagePage / FollowsPage / UserProfilePage / TopicDetailPage / FollowForumsPage / SearchPage
 */
@ObservedV2
export class ImageLoadTypeState {
  @Trace value: number = 0;
}

/**
 * 是否 WiFi 网络
 * 写入方：EntryAbility 网络监听 / StartupTask_NetworkCheck
 * 订阅方：同 imageLoadType
 */
@ObservedV2
export class IsWifiState {
  @Trace value: boolean = false;
}

/**
 * 系统底部安全区域高度（手势导航条避让）
 * 写入方：EntryAbility
 * 订阅方：TopicDetailPage / ForumPage / FollowForumsPage / SearchPage / ThreadStorePage / UserProfilePage / FollowsPage / ThreadPage / SubPostsPage
 */
@ObservedV2
export class SafeBottomState {
  @Trace value: number = 0;
}

/**
 * 百度 BDUSS 登录凭证
 * 写入方：StartupTask_Bduss / LoginPage / WebLoginPage / SettingsPage（登出清空）
 * 订阅方：FavoritePage / MessagePage（登出联动）
 */
@ObservedV2
export class BdussState {
  @Trace value: string = '';
}

/**
 * 贴吧列表刷新标记（HomePage 监听，其他页面修改后递增触发 HomePage 刷新）
 * 写入方：ForumPage / FollowForumsPage（签到/关注操作后）
 * 订阅方：HomePage（@Monitor 监听 value 变化）
 */
@ObservedV2
export class ForumsNeedRefreshState {
  @Trace value: number = 0;
}

/**
 * AppLinking 待跳转帖子 ID（EntryAbility 写入，MainPage 监听跳转）
 * 写入方：EntryAbility.handleAppLinkingWant
 * 订阅方：MainPage（@Monitor 监听 value 变化触发 router.pushUrl）
 */
@ObservedV2
export class PendingAppLinkingTidState {
  @Trace value: number = 0;
}

/**
 * AppLinking 待跳转帖子是否只看楼主
 * 写入方：EntryAbility.handleAppLinkingWant
 * 订阅方：MainPage
 */
@ObservedV2
export class PendingAppLinkingSeeLzState {
  @Trace value: boolean = false;
}

/**
 * 首页双列展示开关
 * 写入方：SettingsPage
 * 订阅方：HomePage（双列 Grid / 单列 List 切换）
 */
@ObservedV2
export class HomeDualColumnState {
  @Trace value: boolean = false;
}

/**
 * 帖子详情悬浮底栏开关
 * 写入方：SettingsPage
 * 订阅方：ThreadPage（悬浮底栏 / 传统底栏切换）
 */
@ObservedV2
export class ThreadFloatingBarState {
  @Trace value: boolean = false;
}

@ObservedV2
export class ForumCommentPreviewState {
  @Trace value: boolean = false;
}

@ObservedV2
export class ThreadCommentPreviewState {
  @Trace value: boolean = true;
}

@ObservedV2
export class RecentForumsState {
  @Trace value: boolean = false;
}

@ObservedV2
export class MainTabRefreshState {
  @Trace targetIndex: number = -1;
  @Trace requestId: number = 0;
}

/**
 * 系统内存压力级别（对齐 AbilityConstant.MemoryLevel）
 * 写入方：EntryAbility.onMemoryLevel
 * 订阅方：BaseViewModel（@Monitor 监听 level 变化，CRITICAL 时自动 clearCache）
 * 0=MEMORY_LEVEL_NORMAL / 1=MEMORY_LEVEL_LOW / 2=MEMORY_LEVEL_CRITICAL
 */
// 对齐 AbilityConstant.MemoryLevel：0=NORMAL / 1=LOW / 2=CRITICAL
// 用 number 而非 enum 是为了 BaseViewModel 不依赖 @kit.AbilityKit，
// 同时方便 @Trace 监听 + @Monitor 跨组件响应
export const MEMORY_LEVEL_NORMAL: number = 0;
export const MEMORY_LEVEL_LOW: number = 1;
export const MEMORY_LEVEL_CRITICAL: number = 2;

@ObservedV2
export class MemoryPressureState {
  @Trace level: number = MEMORY_LEVEL_NORMAL;
}

// ==================== #176 安全 connect 助手函数 ====================
// AppStorageV2.connect 失败返回 undefined，直接用 `!` 非空断言会导致运行时崩溃。
// 这些助手函数封装判空 + 错误日志 + 兜底返回 new 实例，保证调用方永不崩溃。
// 对齐现有 connectTheme() 模式（ThemeManager.ets），统一命名 connectXxx()
// 使用方式：@Local xxx: XxxState = connectXxx();

/**
 * #176 安全连接 ImageLoadTypeState
 * 失败时返回新实例（不影响 UI 刷新，仅丢失全局共享）
 */
export function connectImageLoadType(): ImageLoadTypeState {
  const state: ImageLoadTypeState | undefined = AppStorageV2.connect(
    ImageLoadTypeState, 'imageLoadType', () => new ImageLoadTypeState()
  );
  if (state === undefined) {
    console.error('[AppStorageV2] connect ImageLoadTypeState returned undefined, fallback to new instance');
    return new ImageLoadTypeState();
  }
  return state;
}

/**
 * #176 安全连接 IsWifiState
 * 失败时返回新实例
 */
export function connectIsWifi(): IsWifiState {
  const state: IsWifiState | undefined = AppStorageV2.connect(
    IsWifiState, 'isWifi', () => new IsWifiState()
  );
  if (state === undefined) {
    console.error('[AppStorageV2] connect IsWifiState returned undefined, fallback to new instance');
    return new IsWifiState();
  }
  return state;
}

/**
 * #176 安全连接 SafeBottomState
 * 失败时返回新实例
 */
export function connectSafeBottom(): SafeBottomState {
  const state: SafeBottomState | undefined = AppStorageV2.connect(
    SafeBottomState, 'safeBottom', () => new SafeBottomState()
  );
  if (state === undefined) {
    console.error('[AppStorageV2] connect SafeBottomState returned undefined, fallback to new instance');
    return new SafeBottomState();
  }
  return state;
}

/**
 * #176 安全连接 BdussState
 * 失败时返回新实例
 */
export function connectBduss(): BdussState {
  const state: BdussState | undefined = AppStorageV2.connect(
    BdussState, 'bduss', () => new BdussState()
  );
  if (state === undefined) {
    console.error('[AppStorageV2] connect BdussState returned undefined, fallback to new instance');
    return new BdussState();
  }
  return state;
}

/**
 * #176 安全连接 ForumsNeedRefreshState
 * 失败时返回新实例
 */
export function connectForumsNeedRefresh(): ForumsNeedRefreshState {
  const state: ForumsNeedRefreshState | undefined = AppStorageV2.connect(
    ForumsNeedRefreshState, 'forumsNeedRefresh', () => new ForumsNeedRefreshState()
  );
  if (state === undefined) {
    console.error('[AppStorageV2] connect ForumsNeedRefreshState returned undefined, fallback to new instance');
    return new ForumsNeedRefreshState();
  }
  return state;
}

/**
 * #176 安全连接 PendingAppLinkingTidState
 * 失败时返回新实例
 */
export function connectPendingAppLinkingTid(): PendingAppLinkingTidState {
  const state: PendingAppLinkingTidState | undefined = AppStorageV2.connect(
    PendingAppLinkingTidState, 'pendingAppLinkingTid', () => new PendingAppLinkingTidState()
  );
  if (state === undefined) {
    console.error('[AppStorageV2] connect PendingAppLinkingTidState returned undefined, fallback to new instance');
    return new PendingAppLinkingTidState();
  }
  return state;
}

/**
 * #176 安全连接 PendingAppLinkingSeeLzState
 * 失败时返回新实例
 */
export function connectPendingAppLinkingSeeLz(): PendingAppLinkingSeeLzState {
  const state: PendingAppLinkingSeeLzState | undefined = AppStorageV2.connect(
    PendingAppLinkingSeeLzState, 'pendingAppLinkingSeeLz', () => new PendingAppLinkingSeeLzState()
  );
  if (state === undefined) {
    console.error('[AppStorageV2] connect PendingAppLinkingSeeLzState returned undefined, fallback to new instance');
    return new PendingAppLinkingSeeLzState();
  }
  return state;
}

/**
 * #176 安全连接 HomeDualColumnState
 * 失败时返回新实例
 */
export function connectHomeDualColumn(): HomeDualColumnState {
  const state: HomeDualColumnState | undefined = AppStorageV2.connect(
    HomeDualColumnState, 'homeDualColumn', () => new HomeDualColumnState()
  );
  if (state === undefined) {
    console.error('[AppStorageV2] connect HomeDualColumnState returned undefined, fallback to new instance');
    return new HomeDualColumnState();
  }
  return state;
}

/**
 * #176 安全连接 ThreadFloatingBarState
 * 失败时返回新实例
 */
export function connectThreadFloatingBar(): ThreadFloatingBarState {
  const state: ThreadFloatingBarState | undefined = AppStorageV2.connect(
    ThreadFloatingBarState, 'threadFloatingBar', () => new ThreadFloatingBarState()
  );
  if (state === undefined) {
    console.error('[AppStorageV2] connect ThreadFloatingBarState returned undefined, fallback to new instance');
    return new ThreadFloatingBarState();
  }
  return state;
}

export function connectForumCommentPreview(): ForumCommentPreviewState {
  const state: ForumCommentPreviewState | undefined = AppStorageV2.connect(
    ForumCommentPreviewState, 'forumCommentPreview', () => new ForumCommentPreviewState()
  );
  if (state === undefined) {
    console.error('[AppStorageV2] connect ForumCommentPreviewState returned undefined, fallback to new instance');
    return new ForumCommentPreviewState();
  }
  return state;
}

export function connectThreadCommentPreview(): ThreadCommentPreviewState {
  const state: ThreadCommentPreviewState | undefined = AppStorageV2.connect(
    ThreadCommentPreviewState, 'threadCommentPreview', () => new ThreadCommentPreviewState()
  );
  if (state === undefined) {
    console.error('[AppStorageV2] connect ThreadCommentPreviewState returned undefined, fallback to new instance');
    return new ThreadCommentPreviewState();
  }
  return state;
}

export function connectRecentForums(): RecentForumsState {
  const state: RecentForumsState | undefined = AppStorageV2.connect(
    RecentForumsState, 'showRecentForums', () => new RecentForumsState()
  );
  if (state === undefined) {
    console.error('[AppStorageV2] connect RecentForumsState returned undefined, fallback to new instance');
    return new RecentForumsState();
  }
  return state;
}

export function connectMainTabRefresh(): MainTabRefreshState {
  const state: MainTabRefreshState | undefined = AppStorageV2.connect(
    MainTabRefreshState, 'mainTabRefresh', () => new MainTabRefreshState()
  );
  if (state === undefined) {
    console.error('[AppStorageV2] connect MainTabRefreshState returned undefined, fallback to new instance');
    return new MainTabRefreshState();
  }
  return state;
}

/**
 * #176 安全连接 MemoryPressureState
 * 失败时返回新实例
 */
export function connectMemoryPressure(): MemoryPressureState {
  const state: MemoryPressureState | undefined = AppStorageV2.connect(
    MemoryPressureState, 'memoryPressure', () => new MemoryPressureState()
  );
  if (state === undefined) {
    console.error('[AppStorageV2] connect MemoryPressureState returned undefined, fallback to new instance');
    return new MemoryPressureState();
  }
  return state;
}

// ==================== #201 Tab 显隐 + 沉浸光感强度 ====================

/**
 * #201 底栏 Tab 显隐控制（位掩码）
 * bit0=首页(始终1,不可隐藏) / bit1=收藏 / bit2=消息 / bit3=我的
 * 默认 0b1111=15（全显），隐藏收藏则 value &= ~0b0010
 * 写入方：SettingsPage
 * 订阅方：MainPage（动态渲染 TabContent）
 */
@ObservedV2
export class TabVisibilityState {
  @Trace value: number = 0b1111;
}

/**
 * #201 沉浸光感材质强度档位
 * 对应 hdsMaterial.MaterialLevel 枚举：0=EXQUISITE(精致) / 1=GENTLE(柔和) / 2=SMOOTH(平滑) / 10=ADAPTIVE(自适应)
 * 默认 10(ADAPTIVE) 跟随系统策略
 * 写入方：SettingsPage
 * 订阅方：MainPage(HdsTabs barFloatingStyle) / ThreadPage(titleBar systemMaterialEffect)
 */
@ObservedV2
export class MaterialLevelState {
  @Trace value: number = 10;
}

/**
 * #234 首页列表展示模式（3档枚举，替代 HomeDualColumnState 的 boolean）
 * 0=SINGLE 单列（List + 完整 FeedCard）
 * 1=DOUBLE_FULL 双列完整（Grid + 完整 FeedCard）
 * 2=DOUBLE_COMPACT 双列精简（Grid + ForumCardCompact 仅显示吧等级+吧名称）
 * 默认 0=SINGLE（与 HomeDualColumnState 默认 false=单列保持一致，避免迁移时行为变化）
 * 写入方：SettingsPage
 * 订阅方：HomePage（@Monitor 自动响应切换布局）
 */
@ObservedV2
export class HomeListModeState {
  @Trace value: number = 0;
}

/**
 * 完整版吧内页面开关（0=简化版默认，1=完整版）
 * 写入方：SettingsPage（Toggle 切换）
 * 订阅方：HomePage / SearchPage / FollowForumsPage（路由跳转时根据 value 决定路由目标）
 * 持久化 key='forum_page_version'，Index.ets 启动时从 preferences 读回写入 AppStorageV2
 */
@ObservedV2
export class ForumPageVersionState {
  @Trace value: number = 0;
}

/**
 * 吧内页面 FAB 功能模式（0=发帖默认，1=刷新，2=回顶，3=隐藏）
 * 写入方：SettingsPage（后续切片将添加 UI）
 * 订阅方：ForumPageFull / ForumPage（FAB 点击行为根据 value 切换）
 * 持久化 key='forum_fab_function'，Index.ets 启动时从 preferences 读回写入 AppStorageV2
 */
@ObservedV2
export class ForumFabFunctionState {
  @Trace value: number = 0;
}

/**
 * 默认启动页（0=首页默认 / 1=收藏 / 2=消息 / 3=我的）
 * 写入方：SettingsPage（bindMenu 4 档选择）
 * 订阅方：MainPage（aboutToAppear 读取 value 设置 currentOriginalIndex 初始值）
 * 持久化 key='default_home_page'，Index.ets 启动时从 preferences 读回写入 AppStorageV2
 * 注意：MainPage 读取时会检查 Tab 可见性（TabVisibilityState），若目标 Tab 被隐藏则回退到首页
 */
@ObservedV2
export class DefaultHomePageState {
  @Trace value: number = 0;
}

/**
 * #201 安全连接 TabVisibilityState
 * 失败时返回新实例
 */
export function connectTabVisibility(): TabVisibilityState {
  const state: TabVisibilityState | undefined = AppStorageV2.connect(
    TabVisibilityState, 'tabVisibility', () => new TabVisibilityState()
  );
  if (state === undefined) {
    console.error('[AppStorageV2] connect TabVisibilityState returned undefined, fallback to new instance');
    return new TabVisibilityState();
  }
  return state;
}

/**
 * #201 安全连接 MaterialLevelState
 * 失败时返回新实例
 */
export function connectMaterialLevel(): MaterialLevelState {
  const state: MaterialLevelState | undefined = AppStorageV2.connect(
    MaterialLevelState, 'materialLevel', () => new MaterialLevelState()
  );
  if (state === undefined) {
    console.error('[AppStorageV2] connect MaterialLevelState returned undefined, fallback to new instance');
    return new MaterialLevelState();
  }
  return state;
}

/**
 * #234 安全连接 HomeListModeState
 * 失败时返回新实例
 */
export function connectHomeListMode(): HomeListModeState {
  const state: HomeListModeState | undefined = AppStorageV2.connect(
    HomeListModeState, 'homeListMode', () => new HomeListModeState()
  );
  if (state === undefined) {
    console.error('[AppStorageV2] connect HomeListModeState returned undefined, fallback to new instance');
    return new HomeListModeState();
  }
  return state;
}

/**
 * 安全连接 ForumPageVersionState
 * 失败时返回新实例
 */
export function connectForumPageVersion(): ForumPageVersionState {
  const state: ForumPageVersionState | undefined = AppStorageV2.connect(
    ForumPageVersionState, 'forum_page_version', () => new ForumPageVersionState()
  );
  if (state === undefined) {
    console.error('[AppStorageV2] connect ForumPageVersionState returned undefined, fallback to new instance');
    return new ForumPageVersionState();
  }
  return state;
}

/**
 * 安全连接 ForumFabFunctionState
 * 失败时返回新实例
 */
export function connectForumFabFunction(): ForumFabFunctionState {
  const state: ForumFabFunctionState | undefined = AppStorageV2.connect(
    ForumFabFunctionState, 'forum_fab_function', () => new ForumFabFunctionState()
  );
  if (state === undefined) {
    console.error('[AppStorageV2] connect ForumFabFunctionState returned undefined, fallback to new instance');
    return new ForumFabFunctionState();
  }
  return state;
}

/**
 * 安全连接 DefaultHomePageState
 * 失败时返回新实例
 */
export function connectDefaultHomePage(): DefaultHomePageState {
  const state: DefaultHomePageState | undefined = AppStorageV2.connect(
    DefaultHomePageState, 'default_home_page', () => new DefaultHomePageState()
  );
  if (state === undefined) {
    console.error('[AppStorageV2] connect DefaultHomePageState returned undefined, fallback to new instance');
    return new DefaultHomePageState();
  }
  return state;
}

/**
 * 默认启动页常量（与 DefaultHomePageState.value 对齐）
 * 0=首页 / 1=收藏 / 2=消息 / 3=我的（与 MainPage 的 originalIndex 对齐）
 */
export const DEFAULT_HOME_PAGE_HOME: number = 0;
export const DEFAULT_HOME_PAGE_FAVORITES: number = 1;
export const DEFAULT_HOME_PAGE_MESSAGES: number = 2;
export const DEFAULT_HOME_PAGE_PROFILE: number = 3;

/**
 * #234 首页列表模式常量（与 HomeListModeState.value 对齐）
 * 供 HomePage 和 SettingsPage 引用，避免魔数
 */
export const HOME_LIST_MODE_SINGLE: number = 0;
export const HOME_LIST_MODE_DOUBLE_FULL: number = 1;
export const HOME_LIST_MODE_DOUBLE_COMPACT: number = 2;
// #117 瀑布流模式：DynamicLayout 自定义瀑布流布局，卡片高度自适应
export const HOME_LIST_MODE_WATERFALL: number = 3;

/**
 * #201 沉浸光感材质类型常量（固定 IMMERSIVE，真正沉浸光感材质）
 * 之前用 ADAPTIVE（跟随系统策略）导致部分设备不渲染沉浸光感，用户反馈"很明显不是沉浸光感材质"
 * 全局所有 systemMaterialEffect 配置处统一使用 IMMERSIVE 类型
 */
export const MATERIAL_TYPE_IMMERSIVE: hdsMaterial.MaterialType = hdsMaterial.MaterialType.IMMERSIVE;

/**
 * #201 解析沉浸光感材质强度（从 MaterialLevelState 数字值 → hdsMaterial.MaterialLevel 枚举）
 * 共享函数，避免每个页面重复实现 resolveMaterialLevel 方法
 * @param level MaterialLevelState.value 数字值（0=EXQUISITE / 1=GENTLE / 2=SMOOTH / 10=ADAPTIVE）
 * @returns 对应的 hdsMaterial.MaterialLevel 枚举值
 */
export function resolveMaterialLevel(level: number): hdsMaterial.MaterialLevel {
  if (level === 0) {
    return hdsMaterial.MaterialLevel.EXQUISITE;
  }
  if (level === 1) {
    return hdsMaterial.MaterialLevel.GENTLE;
  }
  if (level === 2) {
    return hdsMaterial.MaterialLevel.SMOOTH;
  }
  return hdsMaterial.MaterialLevel.ADAPTIVE;
}
