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
