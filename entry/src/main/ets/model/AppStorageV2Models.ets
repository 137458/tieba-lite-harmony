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

import { AppStorageV2, curves, UIContext } from '@kit.ArkUI';

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
 * #132 图片查看器全局模态状态（bindContentCover + geometryTransition 共享元素转场）
 * 写入方：ThreadCard / ThreadPage 的 4 个图片点击调用点
 * 订阅方：Index.ets 的 bindContentCover（监听 isVisible 触发模态显示/隐藏）
 *
 * 字段说明：
 * - isVisible: 模态是否显示（true=弹出查看器，false=关闭）
 * - urls: 大图 URL 数组（Swiper 切换用）
 * - index: 当前展示的图片索引
 * - shareId: 共享元素转场 ID（列表端 Image 与模态端 Image 绑定同 id 实现转场动画）
 * - thumbnailUrl: 转场期间显示的缩略图 URL（转场结束后切换为大图 url 避免闪烁）
 */
@ObservedV2
export class ImageViewerState {
  @Trace isVisible: boolean = false;
  @Trace urls: string[] = [];
  @Trace index: number = 0;
  @Trace shareId: string = '';
  @Trace thumbnailUrl: string = '';

  /**
   * #132 打开图片查看器模态（共享元素转场）
   * 一次性设置 urls/index/shareId/thumbnailUrl，并以 springMotion 弹性回弹动画驱动
   * isVisible=true 触发 Index.ets 的 bindContentCover 模态弹出。
   * 提取自 ThreadCard.openImageViewer / ThreadPage.openPostImageViewer /
   * ThreadPage.openFirstPostImageViewer 三处重复逻辑。
   *
   * @param urls 大图 URL 数组
   * @param index 当前展示图片索引
   * @param shareId 共享元素转场 ID（与列表端 Image 的 geometryTransition 一致）
   * @param thumbnailUrl 转场期间显示的缩略图 URL
   * @param uiContext 调用方 UIContext（组件销毁后可能为 undefined，传入则不触发动画）
   */
  open(urls: string[], index: number, shareId: string, thumbnailUrl: string,
    uiContext: UIContext | undefined): void {
    this.urls = urls;
    this.index = index;
    this.shareId = shareId;
    this.thumbnailUrl = thumbnailUrl;
    if (uiContext === undefined) {
      // 组件已销毁，直接置 isVisible=true 兜底（无动画但保证模态可弹出）
      this.isVisible = true;
      return;
    }
    uiContext.animateTo({
      duration: 350,
      curve: curves.springMotion()
    }, () => {
      this.isVisible = true;
    });
  }
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

/**
 * #132 安全连接 ImageViewerState
 * 失败时返回新实例
 */
export function connectImageViewer(): ImageViewerState {
  const state: ImageViewerState | undefined = AppStorageV2.connect(
    ImageViewerState, 'imageViewer', () => new ImageViewerState()
  );
  if (state === undefined) {
    console.error('[AppStorageV2] connect ImageViewerState returned undefined, fallback to new instance');
    return new ImageViewerState();
  }
  return state;
}
