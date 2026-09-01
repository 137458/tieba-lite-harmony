// 设置页（Phase 4 设置功能实现）
// 五项菜单功能：
//   - 深色模式：bindMenu 弹出选择菜单（跟随系统/深色/浅色），setColorMode 切换 + AppStorageManager 持久化
//   - 字体大小：bindMenu 弹出选择菜单（跟随系统/小/默认/略大/大/超大），setFontScale 切换 + AppStorageManager 持久化
//   - 复制 BDUSS：从 AppStorageManager 读取 BDUSS，pasteboard 复制到系统剪贴板
//   - 我的小尾巴：弹对话框输入，AppStorageManager 持久化，ReplyPage.onSend 末尾追加
//   - 清除缓存：递归删除 cacheDir 下文件
//   - 退出登录：弹确认对话框，清理 storage + TiebaHttpClient，跳转 LoginPage
//   - 关于：跳转 AboutPage 显示版本号 + 开源链接

import { promptAction } from '@kit.ArkUI';
import { HdsNavDestination, ScrollEffectType, hdsMaterial } from '@kit.UIDesignKit';
import { AppStorageManager } from '../../data/AppStorage';
import { CredentialVault } from '../../data/CredentialVault';
import { AuthSessionManager } from '../../data/AuthSessionManager';
import { TiebaAPI } from '../../api/TiebaAPI';
import { ConfigurationConstant, common } from '@kit.AbilityKit';
import { getResourceString } from '../../utils/ResourceUtil';
import { pasteboard, BusinessError } from '@kit.BasicServicesKit';
import fs from '@ohos.file.fs';
import {
  IMAGE_LOAD_SMART_ORIGIN,
  IMAGE_LOAD_SMART_NO,
  IMAGE_LOAD_ALL_ORIGIN,
  IMAGE_LOAD_ALL_NO
} from '../../utils/ImageLoadUtil';
import { connectImageLoadType, connectBduss, connectHomeDualColumn, connectThreadFloatingBar, ThreadFloatingBarState, connectTabVisibility, connectMaterialLevel, connectHomeListMode, TabVisibilityState, MaterialLevelState, HomeListModeState, resolveMaterialLevel, MATERIAL_TYPE_IMMERSIVE, HOME_LIST_MODE_SINGLE, HOME_LIST_MODE_DOUBLE_FULL, HOME_LIST_MODE_DOUBLE_COMPACT, HOME_LIST_MODE_WATERFALL, ForumPageVersionState, connectForumPageVersion, ForumFabFunctionState, connectForumFabFunction, DefaultHomePageState, connectDefaultHomePage, DEFAULT_HOME_PAGE_HOME, DEFAULT_HOME_PAGE_FAVORITES, DEFAULT_HOME_PAGE_MESSAGES, DEFAULT_HOME_PAGE_PROFILE, ForumCommentPreviewState, ThreadCommentPreviewState, RecentForumsState, connectForumCommentPreview, connectThreadCommentPreview, connectRecentForums } from '../../model/AppStorageV2Models';
import { VibratorUtil } from '../../utils/VibratorUtil';
import { UserAuthUtil } from '../../utils/UserAuthUtil';
import { NotificationUtil } from '../../utils/NotificationUtil';
import { connectTheme, ThemeState, getThemeConfig, THEME_DYNAMIC } from '../../theme/ThemeManager';
import { RouterUtil } from '../../utils/RouterUtil';
import { getStatusBarHeight } from '../../utils/StatusBarUtil';
import { UpdateNoticeManager } from '../../utils/UpdateNoticeManager';

// HdsNavDestination titleBar MINI 模式高度（vp）
const TITLE_BAR_HEIGHT: number = 48;

// #201 底栏 Tab 显隐位掩码（与 TabVisibilityState 对齐）
// bit0=首页（始终1）/ bit1=收藏 / bit2=消息 / bit3=我的
const TAB_BIT_FAVORITE: number = 0b0010;
const TAB_BIT_MESSAGE: number = 0b0100;
const TAB_BIT_PROFILE: number = 0b1000;
const TAB_VISIBILITY_DEFAULT: number = 0b1111;

// #201 沉浸光感材质强度档位（与 MaterialLevelState 对齐）
// 0=EXQUISITE(精致) / 1=GENTLE(柔和) / 2=SMOOTH(平滑) / 10=ADAPTIVE(自适应)
const MATERIAL_LEVEL_EXQUISITE: number = 0;
const MATERIAL_LEVEL_GENTLE: number = 1;
const MATERIAL_LEVEL_SMOOTH: number = 2;
const MATERIAL_LEVEL_ADAPTIVE: number = 10;

// 吧内 FAB 功能模式（与 ForumFabFunctionState.value 对齐）
// 0=发帖 / 1=刷新 / 2=回顶 / 3=隐藏
const FORUM_FAB_FUNCTION_POST: number = 0;
const FORUM_FAB_FUNCTION_REFRESH: number = 1;
const FORUM_FAB_FUNCTION_BACK_TO_TOP: number = 2;
const FORUM_FAB_FUNCTION_HIDE: number = 3;

/**
 * 小尾巴编辑对话框（@CustomDialog）
 * 打开时从 AppStorageManager 读取已保存的小尾巴作为 TextInput 初始值
 * 确认时回调 onConfirm(text)，由父组件 SettingsPage.saveLittleTail 持久化
 */
@CustomDialog
struct LittleTailDialog {
  controller: CustomDialogController;
  /** 确认回调，参数为用户输入的小尾巴文本（空字符串表示清除） */
  onConfirm: (text: string) => void = () => {};
  /** 用户输入的小尾巴文本，TextInput 双向绑定 */
  @State tailText: string = '';

  async aboutToAppear(): Promise<void> {
    try {
      this.tailText = await AppStorageManager.getInstance().getString('littleTail', '');
    } catch (err) {
      console.error(`[LittleTailDialog] load littleTail failed: ${(err as Error).message}`);
    }
  }

  build() {
    Column() {
      Text(getResourceString($r('app.string.settings_little_tail_dialog_title')))
        .fontSize(17)
        .fontWeight(600)
        .fontColor($r('app.color.text_primary'))
        .margin({ bottom: 8 })

      Text(getResourceString($r('app.string.settings_little_tail_dialog_message')))
        .fontSize(12)
        .fontColor($r('app.color.text_caption'))
        .margin({ bottom: 16 })

      TextInput({ text: this.tailText, placeholder: getResourceString($r('app.string.settings_little_tail_placeholder')) })
        .type(InputType.Normal)
        .maxLength(LITTLE_TAIL_MAX_LENGTH)
        .height(48)
        .fontSize(14)
        .borderRadius(8)
        .backgroundColor($r('app.color.input_background'))
        .onChange((value: string) => {
          this.tailText = value;
        })

      Row({ space: 12 }) {
        Button(getResourceString($r('app.string.cancel_button')))
          .layoutWeight(1)
          .height(40)
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .backgroundColor($r('app.color.input_background'))
          .onClick(() => {
            this.controller.close();
          })

        Button(getResourceString($r('app.string.confirm')))
          .layoutWeight(1)
          .height(40)
          .fontSize(14)
          .fontColor($r('app.color.card_background'))
          .backgroundColor($r('app.color.primary'))
          .onClick(() => {
            this.onConfirm(this.tailText);
            this.controller.close();
          })
      }
      .width('100%')
      .margin({ top: 16 })
    }
    .padding(20)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(12)
    .width('80%')
  }
}

// bindMenu 选中项标记符号（拼接到 value 末尾，标记当前选中档位）
const CHECK_MARK: string = ' ✓';
// BDUSS 剪贴板自动清除延迟（ms）：复制 BDUSS 后 60 秒自动清除，缩短凭证暴露窗口
const BDUSS_CLIPBOARD_CLEAR_DELAY_MS: number = 60000;
// 小尾巴最大长度（对齐 Android ReplyPage.littleTail 限制）
const LITTLE_TAIL_MAX_LENGTH: number = 50;
// 普通菜单项高度（vp，对齐原型 menu-item）
const MENU_ITEM_HEIGHT: number = 44;
// Toggle 菜单项高度（vp，含标题+描述两行，比普通菜单项高）
const TOGGLE_MENU_ITEM_HEIGHT: number = 56;
// 分割线左边距（vp，从图标右侧开始，对齐原型 menu-item::after）
const DIVIDER_LEFT_PADDING: number = 52;

// #162 [A4-S2] Navigation 路由表 @Builder：供 router_map.json 的 buildFunction 引用
@Builder
export function SettingsPageBuilder() {
  SettingsPage()
}

@Builder
export function PersonalizationSettingsPageBuilder() {
  SettingsPage({ category: 1 })
}

@Builder
export function ContentSettingsPageBuilder() {
  SettingsPage({ category: 2 })
}

@Builder
export function AccountSettingsPageBuilder() {
  SettingsPage({ category: 3 })
}

@Builder
export function OtherSettingsPageBuilder() {
  SettingsPage({ category: 4 })
}

@ComponentV2
export struct SettingsPage {
  @Param category: number = 0;
  // #170 滚动器，绑定到 HdsNavDestination.bindToScrollable 实现标题栏滚动动态模糊
  private scroller: Scroller = new Scroller();
  // 当前颜色模式：0=跟随系统(COLOR_MODE_NOT_SET) 1=深色(COLOR_MODE_DARK) 2=浅色(COLOR_MODE_LIGHT)
  @Local colorMode: number = 0;
  // 当前字体大小倍数：0=跟随系统 0.85=小号 1.0=默认 1.15=略大 1.3=大号 1.5=超大
  @Local fontScale: number = 0;
  // 当前图片加载模式：0=智能原图 1=智能无图 2=始终原图 3=始终无图（对齐 Android image_load_type）
  @Local imageLoadType: number = 0;
  // #121 触感反馈开关状态（持久化 key=vibratorEnabled）
  @Local vibratorEnabled: boolean = true;
  // #121 触感反馈开关切换中（防抖，避免连点）
  @Local vibratorToggling: boolean = false;
  // #234 首页列表展示模式（0=单列/1=双列完整/2=双列精简，持久化 key=homeListMode）
  @Local homeListModeState: HomeListModeState = connectHomeListMode();
  // 完整版吧内页面开关（0=简化版默认/1=完整版，持久化 key=forum_page_version）
  @Local forumPageVersionState: ForumPageVersionState = connectForumPageVersion();
  // 完整版吧内页面开关切换中（防抖，避免连点）
  @Local forumPageVersionToggling: boolean = false;
  // 吧内 FAB 功能模式（0=发帖/1=刷新/2=回顶/3=隐藏，持久化 key=forum_fab_function）
  @Local forumFabFunctionState: ForumFabFunctionState = connectForumFabFunction();
  // 吧内 FAB 功能切换中（防抖，避免连点）
  @Local forumFabFunctionToggling: boolean = false;
  // 默认启动页（0=首页/1=收藏/2=消息/3=我的，持久化 key=default_home_page）
  @Local defaultHomePageState: DefaultHomePageState = connectDefaultHomePage();
  // 默认启动页切换中（防抖，避免连点）
  @Local defaultHomePageToggling: boolean = false;
  // 帖子详情悬浮底栏开关状态（持久化 key=threadFloatingBar）
  @Local threadFloatingBarEnabled: boolean = false;
  // 帖子详情悬浮底栏开关切换中（防抖，避免连点）
  @Local threadFloatingBarToggling: boolean = false;
  @Local threadFloatingBarState: ThreadFloatingBarState = connectThreadFloatingBar();
  // #201 底栏 Tab 显隐（bitmask）+ 沉浸光感强度
  @Local tabVisibilityState: TabVisibilityState = connectTabVisibility();
  @Local materialLevelState: MaterialLevelState = connectMaterialLevel();
  // Tab 显隐本地状态（bit 解析后的 boolean，供 Toggle 绑定）
  @Local tabFavoriteVisible: boolean = true;
  @Local tabMessageVisible: boolean = true;
  @Local tabProfileVisible: boolean = true;
  // Tab 显隐切换中（防抖，避免连点导致 bitmask 状态错乱）
  @Local tabFavoriteToggling: boolean = false;
  @Local tabMessageToggling: boolean = false;
  @Local tabProfileToggling: boolean = false;
  // 沉浸光感强度切换中（防抖，避免弹窗期间重复触发）
  @Local materialLevelToggling: boolean = false;
  // 待应用的强度档位（弹窗确认后应用）
  @Local pendingMaterialLevel: number = MATERIAL_LEVEL_ADAPTIVE;
  // #135 应用锁开关状态（持久化 key=appLockEnabled）
  @Local appLockEnabled: boolean = false;
  // #135 设备是否支持生物识别（canUseUserAuth 检测，false 时隐藏设置项）
  @Local appLockSupported: boolean = false;
  // #135 应用锁开关切换中（防抖，避免连点）
  @Local appLockToggling: boolean = false;
  // #127 消息通知开关状态（持久化 key=notificationEnabled）
  @Local notificationEnabled: boolean = false;
  // #127 消息通知开关切换中（防抖，避免连点）
  @Local notificationToggling: boolean = false;
  @Local forumCommentPreviewState: ForumCommentPreviewState = connectForumCommentPreview();
  @Local threadCommentPreviewState: ThreadCommentPreviewState = connectThreadCommentPreview();
  @Local receivePrereleaseUpdates: boolean = false;
  @Local forumCommentPreview: boolean = false; // Toggle 状态（同步 forumCommentPreviewState）
  @Local recentForumsState: RecentForumsState = connectRecentForums();
  // 退出登录进行中，防止重复点击
  @Local isLoggingOut: boolean = false;
  @Local isSigningAllForums: boolean = false;
  // #156 主题状态（AppStorageV2 全局共享，主题色实时刷新）
  @Local themeState: ThemeState = connectTheme();
  // 状态栏高度（vp），沉浸式避让状态栏，默认 36，aboutToAppear 动态获取
  @Local statusBarHeight: number = 36;
  // 小尾巴编辑对话框 controller（@CustomDialog 实现，支持 TextInput 输入）
  private littleTailDialogController: CustomDialogController = new CustomDialogController({
    builder: LittleTailDialog({
      onConfirm: (text: string): void => {
        this.saveLittleTail(text).catch((err: Error) => {
          console.error(`[SettingsPage] saveLittleTail failed: ${err.message}`);
        });
      }
    }),
    alignment: DialogAlignment.Center,
    customStyle: false
  });

  async aboutToAppear() {
    // 获取状态栏高度，用于内容区 padding top 避让 titleBar
    try {
      this.statusBarHeight = await getStatusBarHeight(this.getUIContext());
    } catch (err) {
      console.error(`[SettingsPage] getStatusBarHeight failed: ${(err as Error).message}`);
    }
    // 读取持久化的颜色模式偏好
    try {
      const storage: AppStorageManager = AppStorageManager.getInstance();
      await storage.ensureReady();
      this.colorMode = await storage.getNumber('colorMode', 0);
      this.fontScale = await storage.getNumber('fontScale', 0);
      this.imageLoadType = await storage.getNumber('imageLoadType', 0);
      // #121/#135 读取触感反馈/应用锁偏好
      this.vibratorEnabled = await storage.getBoolean('vibratorEnabled', true);
      this.appLockEnabled = await storage.getBoolean('appLockEnabled', false);
      // #234 首页列表模式：先读新 key，不存在则回退读旧 key homeDualColumn 做迁移
      let listMode: number = await storage.getNumber('homeListMode', -1);
      if (listMode < 0) {
        const oldDualColumn: boolean = await storage.getBoolean('homeDualColumn', false);
        listMode = oldDualColumn ? HOME_LIST_MODE_DOUBLE_FULL : HOME_LIST_MODE_SINGLE;
        await storage.setNumber('homeListMode', listMode);
      }
      this.homeListModeState.value = listMode;
      // 读取帖子详情悬浮底栏偏好
      this.threadFloatingBarEnabled = await storage.getBoolean('threadFloatingBar', false);
      this.threadFloatingBarState.value = this.threadFloatingBarEnabled;
      // 读取完整版吧内页面开关偏好（默认 0=简化版）
      // 新 key 启用迁移：先读新 key（默认 -1），不存在则写入默认值 0 并立即 setNumber 持久化
      let forumPageVersionValue: number = await storage.getNumber('forum_page_version', -1);
      if (forumPageVersionValue < 0) {
        forumPageVersionValue = 0;
        await storage.setNumber('forum_page_version', forumPageVersionValue);
      }
      this.forumPageVersionState.value = forumPageVersionValue;
      // #201 读取底栏 Tab 显隐 + 沉浸光感强度偏好
      const tabVisibility: number = await storage.getNumber('tabVisibility', TAB_VISIBILITY_DEFAULT);
      this.tabVisibilityState.value = tabVisibility;
      this.tabFavoriteVisible = (tabVisibility & TAB_BIT_FAVORITE) !== 0;
      this.tabMessageVisible = (tabVisibility & TAB_BIT_MESSAGE) !== 0;
      this.tabProfileVisible = (tabVisibility & TAB_BIT_PROFILE) !== 0;
      const materialLevel: number = await storage.getNumber('materialLevel', MATERIAL_LEVEL_EXQUISITE);
      this.materialLevelState.value = materialLevel;
      // #127 读取消息通知偏好
      this.notificationEnabled = await storage.getBoolean('notificationEnabled', false);
      this.forumCommentPreviewState.value = await storage.getBoolean('forumCommentPreview', false);
      this.threadCommentPreviewState.value = await storage.getBoolean('threadCommentPreview', true);
      this.receivePrereleaseUpdates = await storage.getBoolean('receivePrereleaseUpdates', false);
      this.forumCommentPreview = this.forumCommentPreviewState.value; // 同步状态
      this.recentForumsState.value = await storage.getBoolean('showRecentForums', false);
    } catch (err) {
      console.error(`[SettingsPage] load colorMode/fontScale/imageLoadType failed: ${(err as Error).message}`);
    }
    // #135 检测设备是否支持生物识别认证（FACE/FINGERPRINT，无副作用）
    this.appLockSupported = UserAuthUtil.canUseUserAuth();
    // #121 初始化 VibratorUtil 内存状态（读取偏好到静态字段，供全局调用）
    try {
      await VibratorUtil.init();
    } catch (err) {
      console.error(`[SettingsPage] VibratorUtil.init failed: ${(err as Error).message}`);
    }
  }

  /**
   * 组件销毁前清理资源
   * 关闭 CustomDialogController，防止对话框引用残留导致内存泄漏
   * （CustomDialogController 不在 aboutToDisappear 中关闭时，组件销毁后对话框
   *   可能仍持有组件实例引用，造成内存泄漏）
   */
  aboutToDisappear(): void {
    try {
      this.littleTailDialogController.close();
    } catch (err) {
      console.warn(`[SettingsPage] close littleTailDialog failed: ${(err as Error).message}`);
    }
  }

  // Toast 提示 helper（API 12+ 推荐用 UIContext.getPromptAction() 替代全局 promptAction）
  private showToast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message });
  }

  /**
   * 统一的 Toggle 切换触感反馈 helper
   * 所有 Toggle 的 onChange 回调统一调用此方法，避免每个 onXxxToggle 方法内部重复写 VibratorUtil.light()
   * @param isOn Toggle 目标状态
   * @param callback 实际的切换逻辑回调
   */
  private onToggleWithFeedback(isOn: boolean, callback: (isOn: boolean) => void): void {
    VibratorUtil.light();
    callback(isOn);
  }

  /**
   * 切换颜色模式并持久化
   * @param mode 0=跟随系统 1=深色 2=浅色
   */
  private async setColorMode(mode: number): Promise<void> {
    this.colorMode = mode;
    try {
      const hostContext: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const appContext = hostContext.getApplicationContext();
      const colorModeValue: number = mode === 1
        ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK
        : (mode === 2
          ? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
          : ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
      appContext.setColorMode(colorModeValue);
      await AppStorageManager.getInstance().setNumber('colorMode', mode);
    } catch (err) {
      console.error(`[SettingsPage] setColorMode failed: ${(err as Error).message}`);
      this.showToast(getResourceString($r('app.string.settings_color_mode_failed')));
    }
  }

  /**
   * 切换字体大小倍数并持久化
   * @param scale 0=跟随系统 0.85=小号 1.0=默认 1.15=略大 1.3=大号 1.5=超大
   * 调用 setFontSizeScale 后应用字体不再跟随系统变化（HarmonyOS API 13+ 行为）
   */
  private async setFontScale(scale: number): Promise<void> {
    this.fontScale = scale;
    try {
      const hostContext: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const appContext = hostContext.getApplicationContext();
      if (scale > 0) {
        // 用户主动设定倍数：调用 setFontSizeScale 锁定应用字体
        appContext.setFontSizeScale(scale);
      } else {
        // 0=跟随系统：传 1.0 重置为系统默认（API 13+ setFontSizeScale 不可取消，只能恢复为 1.0）
        appContext.setFontSizeScale(1.0);
      }
      await AppStorageManager.getInstance().setNumber('fontScale', scale);
    } catch (err) {
      console.error(`[SettingsPage] setFontScale failed: ${(err as Error).message}`);
      this.showToast(getResourceString($r('app.string.settings_font_size_failed')));
    }
  }

  /**
   * 切换图片加载模式并持久化
   * @param type 0=智能原图 1=智能无图 2=始终原图 3=始终无图
   * 持久化后立即生效：
   *   - 同步更新 AppStorage('imageLoadType')，触发所有 @StorageProp 订阅者重绘（ThreadCard / ThreadPage / SubPostsPage 等）
   *   - 持久化到 preferences 供下次启动读取
   */
  private async setImageLoadType(type: number): Promise<void> {
    // 验证 type 范围（0-3），非法值忽略避免持久化非法状态
    if (type < 0 || type > 3) {
      console.warn(`[SettingsPage] setImageLoadType invalid type: ${type}, ignored`);
      return;
    }
    this.imageLoadType = type;
    try {
      // 先同步 AppStorageV2（触发订阅者重绘），再持久化到 preferences
      const imageLoadTypeState = connectImageLoadType();
      imageLoadTypeState.value = type;
      await AppStorageManager.getInstance().setNumber('imageLoadType', type);
    } catch (err) {
      console.error(`[SettingsPage] setImageLoadType failed: ${(err as Error).message}`);
      this.showToast(getResourceString($r('app.string.settings_image_load_type_failed')));
    }
  }


  /**
   * #121 触感反馈开关切换
   * @param isOn true=开启 false=关闭
   *
   * 开启流程：持久化偏好为 true + 调用 VibratorUtil.setEnabled + 触发一次轻震动反馈
   * 关闭流程：持久化偏好为 false
   */
  private async onVibratorToggle(isOn: boolean): Promise<void> {
    if (this.vibratorToggling) {
      return;
    }
    this.vibratorToggling = true;
    try {
      // 先更新内存状态，确保 light() 能触发（开启时 enabled 需先为 true）
      VibratorUtil.setEnabled(isOn);
      this.vibratorEnabled = isOn;
      // 切换开关后立即触发一次轻震动，让用户感知效果（开启时震动，关闭时因 enabled=false 静默跳过）
      if (isOn) {
        VibratorUtil.light();
      }
      // 持久化到 preferences
      await AppStorageManager.getInstance().setBoolean('vibratorEnabled', isOn);
    } catch (err) {
      console.error(`[SettingsPage] onVibratorToggle failed: ${(err as Error).message}`);
      // 失败回滚
      this.vibratorEnabled = !isOn;
      this.showToast(getResourceString($r('app.string.settings_toggle_failed')));
    } finally {
      this.vibratorToggling = false;
    }
  }

  /**
   * #234 首页列表模式切换（3档：单列/双列完整/双列精简）
   * @param mode 0=SINGLE / 1=DOUBLE_FULL / 2=DOUBLE_COMPACT
   *
   * 流程：
   * 1. 同步更新 AppStorageV2（HomeListModeState，HomePage 订阅后自动响应布局切换）
   * 2. 持久化到 preferences（key='homeListMode'）供下次启动读取
   * 3. 同步旧 dualColumnState（向后兼容，HomePage 切换为读 HomeListModeState 后可移除）
   */
  private async onHomeListModeChange(mode: number): Promise<void> {
    const previousMode: number = this.homeListModeState.value;
    const dualColumnState = connectHomeDualColumn();
    const previousDualColumn: boolean = dualColumnState.value;
    try {
      this.homeListModeState.value = mode;
      dualColumnState.value = mode !== HOME_LIST_MODE_SINGLE;
      await AppStorageManager.getInstance().setNumber('homeListMode', mode);
    } catch (err) {
      console.error(`[SettingsPage] onHomeListModeChange failed: ${(err as Error).message}`);
      this.homeListModeState.value = previousMode;
      dualColumnState.value = previousDualColumn;
      this.showToast(getResourceString($r('app.string.settings_toggle_failed')));
    }
  }

  @Builder booleanPreferenceBuilder(label: Resource, description: Resource, isOn: boolean,
    onChange: (value: boolean) => void) {
    Row() {
      Column() {
        Text(label)
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))
        Text(description)
          .fontSize(12)
          .fontColor($r('app.color.text_caption'))
          .margin({ top: 2 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Toggle({ type: ToggleType.Switch, isOn: isOn })
        .selectedColor(this.themeState.primary)
        .onChange((value: boolean) => this.onToggleWithFeedback(value, onChange))
    }
    .width('100%')
    .height(TOGGLE_MENU_ITEM_HEIGHT)
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor($r('app.color.card_background'))
  }

  @Builder categoryEntryBuilder(label: Resource, route: string) {
    Row() {
      Text(label)
        .layoutWeight(1)
        .fontSize(16)
        .fontColor($r('app.color.text_primary'))
      Image($r('app.media.ic_chevron_right'))
        .width(14)
        .height(14)
        .fillColor($r('app.color.text_caption'))
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 16 })
    .backgroundColor($r('app.color.card_background'))
    .onClick(() => RouterUtil.push(route))
  }

  private async setBooleanPreference(key: string, value: boolean): Promise<void> {
    await AppStorageManager.getInstance().setBoolean(key, value);
  }

  private getPageTitle(): Resource {
    if (this.category === 1) {
      return $r('app.string.settings_category_personalization');
    }
    if (this.category === 2) {
      return $r('app.string.settings_category_content');
    }
    if (this.category === 3) {
      return $r('app.string.settings_category_account');
    }
    if (this.category === 4) {
      return $r('app.string.settings_category_other');
    }
    return $r('app.string.settings_title');
  }

  /** #234 获取当前列表模式显示文本 */
  private getHomeListModeText(): string {
    const mode: number = this.homeListModeState.value;
    if (mode === HOME_LIST_MODE_DOUBLE_FULL) {
      return getResourceString($r('app.string.settings_home_list_mode_double_full'));
    }
    if (mode === HOME_LIST_MODE_DOUBLE_COMPACT) {
      return getResourceString($r('app.string.settings_home_list_mode_double_compact'));
    }
    if (mode === HOME_LIST_MODE_WATERFALL) {
      return getResourceString($r('app.string.settings_home_list_mode_waterfall'));
    }
    return getResourceString($r('app.string.settings_home_list_mode_single'));
  }

  /**
   * 帖子详情悬浮底栏开关切换
   * @param isOn true=悬浮底栏 false=传统底栏
   */
  private async onThreadFloatingBarToggle(isOn: boolean): Promise<void> {
    if (this.threadFloatingBarToggling) {
      return;
    }
    this.threadFloatingBarToggling = true;
    try {
      this.threadFloatingBarEnabled = isOn;
      this.threadFloatingBarState.value = isOn;
      await AppStorageManager.getInstance().setBoolean('threadFloatingBar', isOn);
    } catch (err) {
      console.error(`[SettingsPage] onThreadFloatingBarToggle failed: ${(err as Error).message}`);
      this.threadFloatingBarEnabled = !isOn;
      this.threadFloatingBarState.value = !isOn;
      this.showToast(getResourceString($r('app.string.settings_toggle_failed')));
    } finally {
      this.threadFloatingBarToggling = false;
    }
  }

  /**
   * 完整版吧内页面开关切换
   * @param isOn true=完整版(1) false=简化版(0)
   *
   * 流程：
   * 1. 同步更新 AppStorageV2（ForumPageVersionState，HomePage/SearchPage/FollowForumsPage 路由跳转时读取）
   * 2. 持久化到 preferences（key='forum_page_version'）供下次启动读取
   */
  private async onForumPageVersionToggle(isOn: boolean): Promise<void> {
    if (this.forumPageVersionToggling) {
      return;
    }
    this.forumPageVersionToggling = true;
    try {
      const newValue: number = isOn ? 1 : 0;
      this.forumPageVersionState.value = newValue;
      await AppStorageManager.getInstance().setNumber('forum_page_version', newValue);
    } catch (err) {
      console.error(`[SettingsPage] onForumPageVersionToggle failed: ${(err as Error).message}`);
      // 失败回滚
      const rollbackValue: number = isOn ? 0 : 1;
      this.forumPageVersionState.value = rollbackValue;
      this.showToast(getResourceString($r('app.string.settings_toggle_failed')));
    } finally {
      this.forumPageVersionToggling = false;
    }
  }

  /**
   * 吧内 FAB 功能切换
   * @param value 0=发帖 1=刷新 2=回顶 3=隐藏
   *
   * 流程：
   * 1. 同步更新 AppStorageV2（ForumFabFunctionState，ForumPage/ForumPageFull 订阅后 FAB 行为切换）
   * 2. 持久化到 preferences（key='forum_fab_function'）供下次启动读取
   */
  private async onForumFabFunctionChange(value: number): Promise<void> {
    if (this.forumFabFunctionToggling) {
      return;
    }
    this.forumFabFunctionToggling = true;
    const oldValue: number = this.forumFabFunctionState.value;
    try {
      this.forumFabFunctionState.value = value;
      await AppStorageManager.getInstance().setNumber('forum_fab_function', value);
    } catch (err) {
      console.error(`[SettingsPage] onForumFabFunctionChange failed: ${(err as Error).message}`);
      // 失败回滚
      this.forumFabFunctionState.value = oldValue;
      this.showToast(getResourceString($r('app.string.settings_toggle_failed')));
    } finally {
      this.forumFabFunctionToggling = false;
    }
  }

  /** 获取当前 FAB 功能显示文本 */
  private getFabFunctionText(): string {
    const value: number = this.forumFabFunctionState.value;
    if (value === FORUM_FAB_FUNCTION_POST) {
      return getResourceString($r('app.string.forum_fab_post'));
    } else if (value === FORUM_FAB_FUNCTION_REFRESH) {
      return getResourceString($r('app.string.forum_fab_refresh'));
    } else if (value === FORUM_FAB_FUNCTION_BACK_TO_TOP) {
      return getResourceString($r('app.string.forum_fab_back_to_top'));
    }
    return getResourceString($r('app.string.forum_fab_hide'));
  }

  /**
   * 默认启动页切换
   * @param value 0=首页 1=收藏 2=消息 3=我的
   *
   * 流程：
   * 1. 同步更新 AppStorageV2（DefaultHomePageState，MainPage 启动时读取 value 决定初始 Tab）
   * 2. 持久化到 preferences（key='default_home_page'）供下次启动读取
   *
   * 注：仅修改状态值，不立即切换 Tab；下次应用启动时 MainPage.aboutToAppear 会读取并切换
   */
  private async onDefaultHomePageChange(value: number): Promise<void> {
    if (this.defaultHomePageToggling) {
      return;
    }
    this.defaultHomePageToggling = true;
    const oldValue: number = this.defaultHomePageState.value;
    try {
      this.defaultHomePageState.value = value;
      await AppStorageManager.getInstance().setNumber('default_home_page', value);
    } catch (err) {
      console.error(`[SettingsPage] onDefaultHomePageChange failed: ${(err as Error).message}`);
      // 失败回滚
      this.defaultHomePageState.value = oldValue;
      this.showToast(getResourceString($r('app.string.settings_toggle_failed')));
    } finally {
      this.defaultHomePageToggling = false;
    }
  }

  /** 获取当前默认启动页显示文本 */
  private getDefaultHomePageText(): string {
    const value: number = this.defaultHomePageState.value;
    if (value === DEFAULT_HOME_PAGE_FAVORITES) {
      return getResourceString($r('app.string.tab_favorite'));
    } else if (value === DEFAULT_HOME_PAGE_MESSAGES) {
      return getResourceString($r('app.string.tab_message'));
    } else if (value === DEFAULT_HOME_PAGE_PROFILE) {
      return getResourceString($r('app.string.tab_profile'));
    }
    return getResourceString($r('app.string.tab_home'));
  }

  /**
   * #201 Tab 显隐切换核心逻辑（收藏/消息/我的共用）
   * 注：ArkTS 禁止 this[字段名] 动态访问，故抽取 applyTabVisibility
   * 负责 bitmask 更新 + AppStorageV2 同步 + 持久化，各 onXxxToggle 负责防抖和回滚
   * @param bit TAB_BIT_FAVORITE / TAB_BIT_MESSAGE / TAB_BIT_PROFILE
   * @param isOn true=显示 false=隐藏
   */
  private async applyTabVisibility(bit: number, isOn: boolean): Promise<void> {
    // 更新 bitmask（isOn 置位，否则清位）
    const newValue: number = isOn
      ? (this.tabVisibilityState.value | bit)
      : (this.tabVisibilityState.value & ~bit);
    // 至少保留首页（bit0=1），防止全部隐藏
    const safeValue: number = newValue | 0b0001;
    this.tabVisibilityState.value = safeValue;
    await AppStorageManager.getInstance().setNumber('tabVisibility', safeValue);
  }

  /** #201 收藏 Tab 显隐切换 */
  private async onTabFavoriteToggle(isOn: boolean): Promise<void> {
    if (this.tabFavoriteToggling) {
      return;
    }
    this.tabFavoriteToggling = true;
    // 立即更新本地状态（Toggle 视觉跟随），失败时在 catch 中回滚
    this.tabFavoriteVisible = isOn;
    try {
      await this.applyTabVisibility(TAB_BIT_FAVORITE, isOn);
    } catch (err) {
      console.error(`[SettingsPage] onTabFavoriteToggle failed: ${(err as Error).message}`);
      this.tabFavoriteVisible = !isOn;
      this.showToast(getResourceString($r('app.string.settings_toggle_failed')));
    } finally {
      this.tabFavoriteToggling = false;
    }
  }

  /** #201 消息 Tab 显隐切换 */
  private async onTabMessageToggle(isOn: boolean): Promise<void> {
    if (this.tabMessageToggling) {
      return;
    }
    this.tabMessageToggling = true;
    this.tabMessageVisible = isOn;
    try {
      await this.applyTabVisibility(TAB_BIT_MESSAGE, isOn);
    } catch (err) {
      console.error(`[SettingsPage] onTabMessageToggle failed: ${(err as Error).message}`);
      this.tabMessageVisible = !isOn;
      this.showToast(getResourceString($r('app.string.settings_toggle_failed')));
    } finally {
      this.tabMessageToggling = false;
    }
  }

  /** #201 我的 Tab 显隐切换 */
  private async onTabProfileToggle(isOn: boolean): Promise<void> {
    if (this.tabProfileToggling) {
      return;
    }
    this.tabProfileToggling = true;
    this.tabProfileVisible = isOn;
    try {
      await this.applyTabVisibility(TAB_BIT_PROFILE, isOn);
    } catch (err) {
      console.error(`[SettingsPage] onTabProfileToggle failed: ${(err as Error).message}`);
      this.tabProfileVisible = !isOn;
      this.showToast(getResourceString($r('app.string.settings_toggle_failed')));
    } finally {
      this.tabProfileToggling = false;
    }
  }

  /**
   * #201 沉浸光感强度档位切换
   * @param level MATERIAL_LEVEL_EXQUISITE / GENTLE / SMOOTH / ADAPTIVE
   *
   * 设备支持策略（用户确认采用 IMMERSIVE 类型支持作为代理判断）：
   * - ADAPTIVE：直接应用（系统默认安全档位）
   * - 非 ADAPTIVE（EXQUISITE/GENTLE/SMOOTH）：调用 getSystemMaterialTypes() 检测
   *   - 设备支持 IMMERSIVE 类型 → 直接应用
   *   - 设备不支持 IMMERSIVE → 弹窗二次确认，确认后强行应用
   */
  private async setMaterialLevel(level: number): Promise<void> {
    if (this.materialLevelToggling) {
      return;
    }
    this.materialLevelToggling = true;
    try {
      if (level === MATERIAL_LEVEL_ADAPTIVE) {
        // ADAPTIVE 是安全档位，直接应用
        await this.applyMaterialLevel(level);
        return;
      }
      // 非 ADAPTIVE：检测设备是否支持 IMMERSIVE 类型
      const isSupported: boolean = this.isImmersiveMaterialSupported();
      if (isSupported) {
        await this.applyMaterialLevel(level);
      } else {
        // 设备不支持 IMMERSIVE：弹窗二次确认
        this.pendingMaterialLevel = level;
        this.showMaterialLevelUnsupportedDialog();
      }
    } catch (err) {
      console.error(`[SettingsPage] setMaterialLevel failed: ${(err as Error).message}`);
      this.showToast(getResourceString($r('app.string.settings_toggle_failed')));
    } finally {
      this.materialLevelToggling = false;
    }
  }

  /**
   * #201 检测设备是否支持 IMMERSIVE 沉浸光感材质类型
   * 调用 hdsMaterial.getSystemMaterialTypes() 返回设备支持的 MaterialType 数组
   * @returns true=支持 IMMERSIVE 类型 false=不支持
   */
  private isImmersiveMaterialSupported(): boolean {
    try {
      const supportedTypes: Array<hdsMaterial.MaterialType> = hdsMaterial.getSystemMaterialTypes();
      for (let i: number = 0; i < supportedTypes.length; i++) {
        if (supportedTypes[i] === hdsMaterial.MaterialType.IMMERSIVE) {
          return true;
        }
      }
      return false;
    } catch (err) {
      // API 调用失败时保守返回 true（避免误弹窗打扰用户）
      // 项目记忆已确认 API 23+ 设备一定支持 IMMERSIVE
      console.warn(`[SettingsPage] getSystemMaterialTypes failed: ${(err as Error).message}, assume supported`);
      return true;
    }
  }

  /**
   * #201 实际应用材质强度（同步 AppStorageV2 + 持久化 preferences）
   * MainPage 和 ThreadPage 订阅 MaterialLevelState 自动响应
   */
  private async applyMaterialLevel(level: number): Promise<void> {
    this.materialLevelState.value = level;
    await AppStorageManager.getInstance().setNumber('materialLevel', level);
  }

  /**
   * #201 设备不支持 IMMERSIVE 时的二次确认弹窗
   * 用户确认后强行应用 pendingMaterialLevel，取消则不修改
   */
  private showMaterialLevelUnsupportedDialog(): void {
    this.getUIContext().getPromptAction().showDialog({
      title: getResourceString($r('app.string.settings_material_level_unsupported_title')),
      message: getResourceString($r('app.string.settings_material_level_unsupported_message')),
      buttons: [
        { text: getResourceString($r('app.string.cancel_button')), color: $r('app.color.text_secondary') },
        { text: getResourceString($r('app.string.settings_material_level_force_enable')), color: $r('app.color.error') }
      ]
    }).then((result: promptAction.ShowDialogSuccessResponse) => {
      if (result.index === 1) {
        // 用户确认强行开启
        this.applyMaterialLevel(this.pendingMaterialLevel).catch((err: Error) => {
          console.error(`[SettingsPage] applyMaterialLevel failed: ${err.message}`);
          this.showToast(getResourceString($r('app.string.settings_toggle_failed')));
        });
      }
    }).catch((err: Error) => {
      console.error(`[SettingsPage] materialLevel unsupported dialog failed: ${err.message}`);
    });
  }

  /**
   * 启用"吧内帖子评论预览"时的性能警告弹窗
   * 该功能会为每个帖子额外请求 PbPage API 获取前几楼回复，增加流量消耗
   * 用户确认后才真正启用，取消则保持关闭
   */
  private showForumCommentPreviewWarningDialog(): Promise<boolean> {
    return new Promise<boolean>((resolve: (value: boolean) => void) => {
      this.getUIContext().getPromptAction().showDialog({
        title: getResourceString($r('app.string.settings_forum_comment_preview_warning_title')),
        message: getResourceString($r('app.string.settings_forum_comment_preview_warning_message')),
        buttons: [
          { text: getResourceString($r('app.string.cancel_button')), color: $r('app.color.text_secondary') },
          { text: getResourceString($r('app.string.settings_forum_comment_preview_warning_confirm')), color: $r('app.color.primary') }
        ]
      }).then((result: promptAction.ShowDialogSuccessResponse) => {
        resolve(result.index === 1);
      }).catch((err: Error) => {
        console.error(`[SettingsPage] forumCommentPreview warning dialog failed: ${err.message}`);
        resolve(false);
      });
    });
  }

  /**
   * 切换吧内帖子评论预览功能（乐观更新 + 二次确认）
   * 开启流程：弹确认对话框，用户确认后才持久化
   * 关闭流程：直接持久化为 false
   */
  private async onForumCommentPreviewToggle(isOn: boolean): Promise<void> {
    // 记录旧值用于回滚
    const previousValue = this.forumCommentPreview;

    // 如果值没有变化，直接返回（避免初始化时触发）
    if (isOn === previousValue) {
      return;
    }

    // 乐观更新 UI（同时更新 Toggle 状态和全局状态）
    this.forumCommentPreview = isOn;
    this.forumCommentPreviewState.value = isOn;

    try {
      if (isOn) {
        // 开启：等待对话框结果
        const confirmed = await this.showForumCommentPreviewWarningDialog();
        if (!confirmed) {
          // 用户取消，回滚状态
          this.forumCommentPreview = previousValue;
          this.forumCommentPreviewState.value = previousValue;
          return;
        }
        // 用户确认，持久化
        await this.setBooleanPreference('forumCommentPreview', true);
      } else {
        // 关闭：直接持久化
        await this.setBooleanPreference('forumCommentPreview', false);
      }
    } catch (err) {
      // 任何失败回滚状态
      this.forumCommentPreview = previousValue;
      this.forumCommentPreviewState.value = previousValue;
      this.showToast(getResourceString($r('app.string.settings_toggle_failed')));
      console.error(`[SettingsPage] forumCommentPreview toggle failed: ${(err as Error).message}`);
    }
  }

  private async showPrereleaseUpdatesWarningDialog(): Promise<boolean> {
    try {
      const result: promptAction.ShowDialogSuccessResponse = await this.getUIContext().getPromptAction().showDialog({
        title: getResourceString($r('app.string.settings_receive_prerelease_updates_warning_title')),
        message: getResourceString($r('app.string.settings_receive_prerelease_updates_warning_message')),
        buttons: [
          { text: getResourceString($r('app.string.cancel_button')), color: $r('app.color.text_secondary') },
          { text: getResourceString($r('app.string.settings_receive_prerelease_updates_warning_confirm')), color: $r('app.color.primary') }
        ]
      });
      return result.index === 1;
    } catch (err) {
      console.error(`[SettingsPage] prerelease updates warning dialog failed: ${(err as Error).message}`);
      return false;
    }
  }

  /** 获取当前沉浸光感强度档位显示文本 */
  private getMaterialLevelText(): string {
    const level: number = this.materialLevelState.value;
    if (level === MATERIAL_LEVEL_EXQUISITE) {
      return getResourceString($r('app.string.settings_material_level_exquisite'));
    } else if (level === MATERIAL_LEVEL_GENTLE) {
      return getResourceString($r('app.string.settings_material_level_gentle'));
    } else if (level === MATERIAL_LEVEL_SMOOTH) {
      return getResourceString($r('app.string.settings_material_level_smooth'));
    }
    return getResourceString($r('app.string.settings_material_level_adaptive'));
  }

  /**
   * #135 应用锁开关切换
   * @param isOn true=开启 false=关闭
   *
   * 开启流程：拉起系统生物识别认证，认证通过后持久化偏好为 true
   *          认证失败/取消：恢复开关为 false + Toast 提示
   * 关闭流程：持久化偏好为 false
   *
   * 触发验证逻辑由 EntryAbility.onForeground 负责（应用从后台切回前台时验证）
   */
  private async onAppLockToggle(isOn: boolean): Promise<void> {
    if (this.appLockToggling) {
      return;
    }
    this.appLockToggling = true;
    try {
      if (isOn) {
        // 拉起系统生物识别认证，验证通过后才开启应用锁
        const authed: boolean = await UserAuthUtil.authenticate(
          getResourceString($r('app.string.settings_app_lock'))
        );
        if (authed) {
          this.appLockEnabled = true;
          await AppStorageManager.getInstance().setBoolean('appLockEnabled', true);
        } else {
          // 认证失败/取消：恢复开关为 false
          this.appLockEnabled = false;
          this.showToast(getResourceString($r('app.string.settings_app_lock_open_failed')));
        }
      } else {
        this.appLockEnabled = false;
        await AppStorageManager.getInstance().setBoolean('appLockEnabled', false);
      }
    } catch (err) {
      console.error(`[SettingsPage] onAppLockToggle failed: ${(err as Error).message}`);
      this.appLockEnabled = false;
      this.showToast(getResourceString($r('app.string.settings_app_lock_open_failed')));
    } finally {
      this.appLockToggling = false;
    }
  }

  /**
   * #127 消息通知开关切换
   * @param isOn true=开启 false=关闭
   *
   * 开启流程：
   * 1. 检查系统通知权限（NotificationUtil.isEnabled）
   * 2. 未授权时请求授权（NotificationUtil.requestEnable）
   * 3. 授权通过：持久化偏好 + 注册 workScheduler 延迟任务
   * 4. 授权拒绝：恢复开关为 false + Toast 提示
   *
   * 关闭流程：持久化偏好 + 取消 workScheduler 延迟任务
   */
  private async onNotificationToggle(isOn: boolean): Promise<void> {
    if (this.notificationToggling) {
      return;
    }
    this.notificationToggling = true;
    try {
      if (isOn) {
        // 检查系统通知权限，未授权时请求授权
        const systemEnabled: boolean = await NotificationUtil.isEnabled();
        if (!systemEnabled) {
          const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
          const granted: boolean = await NotificationUtil.requestEnable(context);
          if (!granted) {
            this.notificationEnabled = false;
            this.showToast(getResourceString($r('app.string.settings_toggle_failed')));
            return;
          }
        }
        this.notificationEnabled = true;
        await AppStorageManager.getInstance().setBoolean('notificationEnabled', true);
        NotificationUtil.startWorkScheduler();
      } else {
        this.notificationEnabled = false;
        await AppStorageManager.getInstance().setBoolean('notificationEnabled', false);
        NotificationUtil.stopWorkScheduler();
      }
    } catch (err) {
      console.error(`[SettingsPage] onNotificationToggle failed: ${(err as Error).message}`);
      this.notificationEnabled = !isOn;
      this.showToast(getResourceString($r('app.string.settings_toggle_failed')));
    } finally {
      this.notificationToggling = false;
    }
  }


  /**
   * 接收预发行版更新开关切换
   * @param isOn true=开启 false=关闭
   *
   * 开启流程：弹确认对话框，用户确认后才持久化（showPrereleaseUpdatesWarningDialog 内 await 持久化）
   * 关闭流程：直接持久化为 false，并立即关闭已弹出的预发行版 UpdateDialog
   */
  private async onReceivePrereleaseUpdatesToggle(isOn: boolean): Promise<void> {
    // 记录旧值用于回滚
    const previousValue = this.receivePrereleaseUpdates;

    // 如果值没有变化，直接返回（避免初始化时触发）
    if (isOn === previousValue) {
      return;
    }

    // 乐观更新 UI（如果绑定到变量）
    this.receivePrereleaseUpdates = isOn;

    try {
      if (isOn) {
        // 开启：等待对话框结果，内部负责持久化，返回是否确认
        const confirmed = await this.showPrereleaseUpdatesWarningDialog();
        if (!confirmed) {
          // 用户取消，回滚状态（注意：对话框内部不应持久化）
          this.receivePrereleaseUpdates = previousValue;                                                                                                                                                                                                                                            
          return;
        }
        // 对话框确认后，持久化可能已在内部完成；若未完成，在此显式持久化
        // 但建议由调用者统一持久化，对话框仅返回确认结果
        await AppStorageManager.getInstance().setBoolean('receivePrereleaseUpdates', true);
      } else {
        // 关闭：直接持久化并关闭弹窗
        await AppStorageManager.getInstance().setBoolean('receivePrereleaseUpdates', false);
        UpdateNoticeManager.closeIfShowingPrerelease();
      }
    } catch (err) {
      // 任何失败回滚状态
      this.receivePrereleaseUpdates = previousValue;
      this.showToast(getResourceString($r('app.string.settings_toggle_failed')));
      console.error(`[SettingsPage] toggle failed: ${(err as Error).message}`);
    }
  }
  /**
   * 复制 BDUSS 到系统剪贴板
   * 用于调试场景：用户在其他应用/网页需要 BDUSS 时可快速复制
   * 实现：从 AppStorageManager 读取 BDUSS → pasteboard.createData + setData
   * 权限：写入剪贴板无需权限（API 12+ 仅读取需权限）
   *
   * 【安全风险说明】
   * BDUSS 是百度登录态的核心凭证，等同于会话 Token。一旦泄露，攻击者可冒充用户
   * 调用任意贴吧接口（发帖/删帖/关注等）。系统剪贴板是全局共享的，任何应用都可在
   * 用户无感知的情况下读取剪贴板内容（HarmonyOS API 12+ 已对读取加了权限限制，
   * 但仍不能完全排除风险）。因此：
   *   1. 复制后 60 秒自动清除剪贴板，缩短暴露窗口
   *   2. 提示用户尽快粘贴使用，使用完毕后立即清除
   *   3. 不建议在公共环境/不信任设备上使用此功能
   */
  private async copyBdussToClipboard(): Promise<void> {
    try {
      const bduss: string = await CredentialVault.getBduss();
      if (bduss.length === 0) {
        this.showToast(getResourceString($r('app.string.settings_copy_bduss_empty')));
        return;
      }
      const pasteData: pasteboard.PasteData = pasteboard.createData(
        pasteboard.MIMETYPE_TEXT_PLAIN,
        bduss
      );
      const systemPasteboard: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
      await systemPasteboard.setData(pasteData);
      this.showToast(getResourceString($r('app.string.settings_copy_bduss_success')));
      // 【安全】60 秒后自动清除剪贴板，避免 BDUSS 长时间暴露被其他应用读取
      // 此回调仅引用局部变量 systemPasteboard，不依赖组件状态，组件销毁后执行亦安全
      setTimeout(() => {
        systemPasteboard.clearData().catch((clearErr: BusinessError) => {
          console.warn(`[SettingsPage] clear pasteboard failed: ${clearErr.code} ${clearErr.message}`);
        });
      }, BDUSS_CLIPBOARD_CLEAR_DELAY_MS);
    } catch (err) {
      console.error(`[SettingsPage] copyBduss failed: ${(err as BusinessError).code} ${(err as BusinessError).message}`);
      this.showToast(getResourceString($r('app.string.settings_copy_bduss_failed')));
    }
  }

  /**
   * 弹出"我的小尾巴"编辑对话框（CustomDialog 含 TextInput）
   * 用户输入小尾巴内容，保存后将在发帖/回帖时追加到 content 末尾
   * 持久化 key='littleTail'，ReplyPage.onSend 读取并追加
   */
  private showLittleTailDialog(): void {
    this.littleTailDialogController.open();
  }

  /**
   * 保存小尾巴内容到 AppStorageManager
   * @param text 用户输入的小尾巴文本（可能为空字符串表示清除）
   */
  private async saveLittleTail(text: string): Promise<void> {
    try {
      await AppStorageManager.getInstance().setString('littleTail', text);
      this.showToast(getResourceString($r('app.string.settings_little_tail_saved')));
    } catch (err) {
      console.error(`[SettingsPage] saveLittleTail failed: ${(err as Error).message}`);
      this.showToast(getResourceString($r('app.string.settings_little_tail_save_failed')));
    }
  }
  private async clearCache(): Promise<void> {
    try {
      const cacheDir: string = (this.getUIContext().getHostContext() as common.UIAbilityContext).cacheDir;
      await this.removeDirRecursive(cacheDir);
      this.showToast(getResourceString($r('app.string.settings_cache_cleared')));
    } catch (err) {
      console.error(`[SettingsPage] clearCache failed: ${(err as Error).message}`);
      this.showToast(getResourceString($r('app.string.settings_cache_clear_failed')));
    }
  }

  /**
   * 检查更新（手动触发）
   * 调用 UpdateNoticeManager.checkManually 弹 Toast 提示 + 弹窗显示结果
   */
  private checkUpdate(): void {
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    UpdateNoticeManager.checkManually(context).catch((err: Error) => {
      console.error(`[SettingsPage] checkUpdate failed: ${err.message}`);
      this.showToast(getResourceString($r('app.string.update_check_failed')));
    });
  }

  /**
   * 递归删除目录下所有文件和子目录
   * @param dirPath 目录绝对路径
   *
   * 【路径校验】删除前必须校验 dirPath 在应用沙箱目录（cacheDir 或 filesDir）内，
   * 防止路径遍历攻击（如传入 / 或 ../ 跳出沙箱删除系统/其他应用文件）。
   * 递归调用时子目录路径以已校验的父路径为前缀，校验会自动通过。
   */
  private async removeDirRecursive(dirPath: string): Promise<void> {
    // 路径校验：dirPath 必须以应用 cacheDir 或 filesDir 开头，否则拒绝操作
    const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const cacheDir: string = context.cacheDir;
    const filesDir: string = context.filesDir;
    if (!dirPath.startsWith(cacheDir) && !dirPath.startsWith(filesDir)) {
      console.error(`[SettingsPage] removeDirRecursive rejected: path not in sandbox, dirPath=${dirPath}`);
      return;
    }
    const entries: string[] = await fs.listFile(dirPath);
    for (let i: number = 0; i < entries.length; i++) {
      const entry: string = entries[i];
      const entryPath: string = `${dirPath}/${entry}`;
      try {
        const stat: fs.Stat = await fs.stat(entryPath);
        if (stat.isDirectory()) {
          // 子目录：递归删除
          await this.removeDirRecursive(entryPath);
          await fs.rmdir(entryPath);
        } else {
          await fs.unlink(entryPath);
        }
      } catch (e) {
        // 单个条目删除失败不阻塞，继续删除其他条目
        console.warn(`[SettingsPage] remove ${entry} failed: ${(e as Error).message}`);
      }
    }
  }

  /** 弹出"退出登录"确认弹窗 */
  private showLogoutConfirm(): void {
    if (this.isLoggingOut) {
      return;
    }
    this.getUIContext().getPromptAction().showDialog({
      title: getResourceString($r('app.string.settings_logout_confirm_title')),
      message: getResourceString($r('app.string.settings_logout_confirm_message')),
      buttons: [
        { text: getResourceString($r('app.string.cancel_button')), color: $r('app.color.text_secondary') },
        { text: getResourceString($r('app.string.profile_logout_button')), color: $r('app.color.error') }
      ]
    }).then((result: promptAction.ShowDialogSuccessResponse) => {
      if (result.index === 1) {
        this.performLogout();
      }
    }).catch((err: Error) => {
      console.error(`[SettingsPage] logout dialog failed: ${err.message}`);
    });
  }

  /**
   * 执行退出登录：清理 storage + TiebaHttpClient，跳转 LoginPage
   * 清理范围对齐 ProfilePage.performLogout（凭证 + 设备标识 + 用户资料缓存）
   */
  private async performLogout(): Promise<void> {
    if (this.isLoggingOut) {
      return;
    }
    this.isLoggingOut = true;
    try {
      await AuthSessionManager.logout();
      // 清 TiebaHttpClient 内存态凭证
      TiebaAPI.setAuth('', '');
      // #90 同步清空 AppStorageV2 中的 bduss，触发订阅方联动
      const bdussState = connectBduss();
      bdussState.value = '';
      // #195 路由清理：router.replaceUrl → RouterUtil.replace
      // 退出登录后直接 replace 到 LoginPage（方案 A）
      // 栈变为 [MainPage, LoginPage]，用户按返回回到 MainPage 未登录态
      // #177 原注释：router.replaceUrl 会脱离 Navigation 栈，已修复
      RouterUtil.replace(RouterUtil.ROUTE_LOGIN_PAGE);
    } catch (err) {
      console.error(`[SettingsPage] logout failed: ${(err as Error).message}`);
      this.showToast(getResourceString($r('app.string.settings_logout_failed')));
    } finally {
      this.isLoggingOut = false;
    }
  }

  /** 获取当前颜色模式显示文本 */
  private getColorModeText(): string {
    if (this.colorMode === 1) {
      return getResourceString($r('app.string.settings_color_mode_dark'));
    } else if (this.colorMode === 2) {
      return getResourceString($r('app.string.settings_color_mode_light'));
    }
    return getResourceString($r('app.string.settings_color_mode_auto'));
  }

  /** 获取当前字体大小显示文本 */
  private getFontScaleText(): string {
    if (this.fontScale === 0.85) {
      return getResourceString($r('app.string.settings_font_size_small'));
    } else if (this.fontScale === 1.0) {
      return getResourceString($r('app.string.settings_font_size_default'));
    } else if (this.fontScale === 1.15) {
      return getResourceString($r('app.string.settings_font_size_slightly_large'));
    } else if (this.fontScale === 1.3) {
      return getResourceString($r('app.string.settings_font_size_large'));
    } else if (this.fontScale === 1.5) {
      return getResourceString($r('app.string.settings_font_size_extra_large'));
    }
    return getResourceString($r('app.string.settings_font_size_follow_system'));
  }

  /** 获取当前图片加载模式显示文本 */
  private getImageLoadTypeText(): string {
    if (this.imageLoadType === IMAGE_LOAD_SMART_NO) {
      return getResourceString($r('app.string.settings_image_load_type_smart_no'));
    } else if (this.imageLoadType === IMAGE_LOAD_ALL_ORIGIN) {
      return getResourceString($r('app.string.settings_image_load_type_all_origin'));
    } else if (this.imageLoadType === IMAGE_LOAD_ALL_NO) {
      return getResourceString($r('app.string.settings_image_load_type_all_no'));
    }
    return getResourceString($r('app.string.settings_image_load_type_smart_origin'));
  }

  // 菜单项构建器：左侧图标 + 文字 + 右侧箭头，isDanger 控制红色退出风格
  @Builder menuItemBuilder(icon: Resource, label: Resource, isDanger: boolean, onClick: () => void) {
    Row() {
      Image(icon)
        .width(22)
        .height(22)
        .fillColor(isDanger ? $r('app.color.error') : this.themeState.primary)
        // A5 图片优化：本地 SVG 图标，同步加载+低质量插值
        .syncLoad(true)
        .interpolation(ImageInterpolation.Low)
      Text(label)
        .layoutWeight(1)
        .fontSize(16)
        .fontColor(isDanger ? $r('app.color.error') : $r('app.color.text_primary'))
        .margin({ left: 12 })
      Image($r('app.media.ic_chevron_right'))
        .width(14)
        .height(14)
        .fillColor($r('app.color.text_caption'))
        // A5 图片优化：本地 SVG 图标，同步加载+低质量插值
        .syncLoad(true)
        .interpolation(ImageInterpolation.Low)
    }
    .width('100%')
    .height(MENU_ITEM_HEIGHT)
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor($r('app.color.card_background'))
    .onClick(() => onClick())
  }

  // #156 主题菜单项构建器：点击跳转 ThemePage 选择主题
  @Builder themeMenuItemBuilder() {
    Row() {
      Image($r('app.media.ic_settings'))
        .width(22)
        .height(22)
        .fillColor(this.themeState.primary)
        .syncLoad(true)
        .interpolation(ImageInterpolation.Low)
      Text($r('app.string.settings_theme'))
        .layoutWeight(1)
        .fontSize(16)
        .fontColor($r('app.color.text_primary'))
        .margin({ left: 12 })
      if (this.themeState.themeId === THEME_DYNAMIC) {
        Text($r('app.string.theme_dynamic_color'))
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
      } else {
        Text(getThemeConfig(this.themeState.themeId).nameRes)
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
      }
      Image($r('app.media.ic_chevron_right'))
        .width(14)
        .height(14)
        .fillColor($r('app.color.text_caption'))
        .margin({ left: 4 })
        .syncLoad(true)
        .interpolation(ImageInterpolation.Low)
    }
    .width('100%')
    .height(MENU_ITEM_HEIGHT)
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor($r('app.color.card_background'))
    .onClick(() => {
      RouterUtil.push(RouterUtil.ROUTE_THEME_PAGE);
    })
  }

  // 深色模式菜单项构建器：右侧显示当前模式文本 + bindMenu 弹出选择菜单
  @Builder colorModeMenuItemBuilder() {
    Row() {
      Image($r('app.media.ic_settings'))
        .width(22)
        .height(22)
        .fillColor(this.themeState.primary)
        // A5 图片优化：本地 SVG 图标，同步加载+低质量插值
        .syncLoad(true)
        .interpolation(ImageInterpolation.Low)
      Text($r('app.string.settings_dark_mode'))
        .layoutWeight(1)
        .fontSize(16)
        .fontColor($r('app.color.text_primary'))
        .margin({ left: 12 })
      Text(this.getColorModeText())
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
      Image($r('app.media.ic_chevron_right'))
        .width(14)
        .height(14)
        .fillColor($r('app.color.text_caption'))
        .margin({ left: 4 })
        // A5 图片优化：本地 SVG 图标，同步加载+低质量插值
        .syncLoad(true)
        .interpolation(ImageInterpolation.Low)
    }
    .width('100%')
    .height(MENU_ITEM_HEIGHT)
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor($r('app.color.card_background'))
    .bindMenu([
      {
        value: getResourceString($r('app.string.settings_color_mode_auto')) + (this.colorMode === 0 ? ' ✓' : ''),
        action: () => { this.setColorMode(0); }
      },
      {
        value: getResourceString($r('app.string.settings_color_mode_dark')) + (this.colorMode === 1 ? ' ✓' : ''),
        action: () => { this.setColorMode(1); }
      },
      {
        value: getResourceString($r('app.string.settings_color_mode_light')) + (this.colorMode === 2 ? ' ✓' : ''),
        action: () => { this.setColorMode(2); }
      }
    ], {
      // #238 菜单从按钮下方右对齐展开（菜单往左延伸，不超出屏幕右边）
      placement: Placement.BottomRight,
      enableArrow: false
    })
  }

  // 字体大小菜单项构建器：右侧显示当前档位 + bindMenu 弹出 6 档选择
  @Builder fontScaleMenuItemBuilder() {
    Row() {
      Image($r('app.media.ic_settings'))
        .width(22)
        .height(22)
        .fillColor(this.themeState.primary)
        // A5 图片优化：本地 SVG 图标，同步加载+低质量插值
        .syncLoad(true)
        .interpolation(ImageInterpolation.Low)
      Text($r('app.string.settings_font_size'))
        .layoutWeight(1)
        .fontSize(16)
        .fontColor($r('app.color.text_primary'))
        .margin({ left: 12 })
      Text(this.getFontScaleText())
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
      Image($r('app.media.ic_chevron_right'))
        .width(14)
        .height(14)
        .fillColor($r('app.color.text_caption'))
        .margin({ left: 4 })
        // A5 图片优化：本地 SVG 图标，同步加载+低质量插值
        .syncLoad(true)
        .interpolation(ImageInterpolation.Low)
    }
    .width('100%')
    .height(MENU_ITEM_HEIGHT)
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor($r('app.color.card_background'))
    .bindMenu([
      {
        value: getResourceString($r('app.string.settings_font_size_follow_system')) + (this.fontScale === 0 ? ' ✓' : ''),
        action: () => { this.setFontScale(0); }
      },
      {
        value: getResourceString($r('app.string.settings_font_size_small')) + (this.fontScale === 0.85 ? ' ✓' : ''),
        action: () => { this.setFontScale(0.85); }
      },
      {
        value: getResourceString($r('app.string.settings_font_size_default')) + (this.fontScale === 1.0 ? ' ✓' : ''),
        action: () => { this.setFontScale(1.0); }
      },
      {
        value: getResourceString($r('app.string.settings_font_size_slightly_large')) + (this.fontScale === 1.15 ? ' ✓' : ''),
        action: () => { this.setFontScale(1.15); }
      },
      {
        value: getResourceString($r('app.string.settings_font_size_large')) + (this.fontScale === 1.3 ? ' ✓' : ''),
        action: () => { this.setFontScale(1.3); }
      },
      {
        value: getResourceString($r('app.string.settings_font_size_extra_large')) + (this.fontScale === 1.5 ? ' ✓' : ''),
        action: () => { this.setFontScale(1.5); }
      }
    ], {
      placement: Placement.BottomRight,
      enableArrow: false
    })
  }

  // 图片加载设置菜单项构建器：右侧显示当前档位 + bindMenu 弹出 4 档选择
  @Builder imageLoadTypeMenuItemBuilder() {
    Row() {
      Image($r('app.media.ic_settings'))
        .width(22)
        .height(22)
        .fillColor(this.themeState.primary)
        // A5 图片优化：本地 SVG 图标，同步加载+低质量插值
        .syncLoad(true)
        .interpolation(ImageInterpolation.Low)
      Text($r('app.string.settings_image_load_type'))
        .layoutWeight(1)
        .fontSize(16)
        .fontColor($r('app.color.text_primary'))
        .margin({ left: 12 })
      Text(this.getImageLoadTypeText())
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
      Image($r('app.media.ic_chevron_right'))
        .width(14)
        .height(14)
        .fillColor($r('app.color.text_caption'))
        .margin({ left: 4 })
        // A5 图片优化：本地 SVG 图标，同步加载+低质量插值
        .syncLoad(true)
        .interpolation(ImageInterpolation.Low)
    }
    .width('100%')
    .height(MENU_ITEM_HEIGHT)
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor($r('app.color.card_background'))
    .bindMenu([
      {
        value: getResourceString($r('app.string.settings_image_load_type_smart_origin')) + (this.imageLoadType === IMAGE_LOAD_SMART_ORIGIN ? CHECK_MARK : ''),
        action: () => { this.setImageLoadType(IMAGE_LOAD_SMART_ORIGIN); }
      },
      {
        value: getResourceString($r('app.string.settings_image_load_type_smart_no')) + (this.imageLoadType === IMAGE_LOAD_SMART_NO ? CHECK_MARK : ''),
        action: () => { this.setImageLoadType(IMAGE_LOAD_SMART_NO); }
      },
      {
        value: getResourceString($r('app.string.settings_image_load_type_all_origin')) + (this.imageLoadType === IMAGE_LOAD_ALL_ORIGIN ? CHECK_MARK : ''),
        action: () => { this.setImageLoadType(IMAGE_LOAD_ALL_ORIGIN); }
      },
      {
        value: getResourceString($r('app.string.settings_image_load_type_all_no')) + (this.imageLoadType === IMAGE_LOAD_ALL_NO ? CHECK_MARK : ''),
        action: () => { this.setImageLoadType(IMAGE_LOAD_ALL_NO); }
      }
    ], {
      placement: Placement.BottomRight,
      enableArrow: false
    })
  }

  // #121 触感反馈菜单项构建器：左侧图标 + 中间标题/描述 + 右侧 Toggle 开关
  @Builder vibratorMenuItemBuilder() {
    Row() {
      Image($r('app.media.ic_like'))
        .width(22)
        .height(22)
        .fillColor(this.themeState.primary)
        .syncLoad(true)
        .interpolation(ImageInterpolation.Low)
      Column() {
        Text($r('app.string.settings_vibrator'))
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))
        Text($r('app.string.settings_vibrator_desc'))
          .fontSize(12)
          .fontColor($r('app.color.text_caption'))
          .margin({ top: 2 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 })
      Toggle({ type: ToggleType.Switch, isOn: this.vibratorEnabled })
        .selectedColor(this.themeState.primary)
        .onChange((isOn: boolean) => {
          this.onToggleWithFeedback(isOn, (on: boolean) => {
            this.onVibratorToggle(on).catch((err: Error) => {
              console.error(`[SettingsPage] onVibratorToggle failed: ${err.message}`);
            });
          });
        })
    }
    .width('100%')
    .height(TOGGLE_MENU_ITEM_HEIGHT)
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor($r('app.color.card_background'))
  }

  // #234 首页列表模式菜单项构建器：右侧显示当前档位 + bindMenu 弹出 3 档选择
  // 0=单列(List + 完整 FeedCard) / 1=双列完整(Grid + 完整 FeedCard) / 2=双列精简(Grid + 紧凑卡片只显示吧等级+吧名)
  @Builder homeListModeMenuItemBuilder() {
    Row() {
      Image($r('app.media.ic_home'))
        .width(22)
        .height(22)
        .fillColor(this.themeState.primary)
        .syncLoad(true)
        .interpolation(ImageInterpolation.Low)
      Column() {
        Text($r('app.string.settings_home_list_mode'))
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))
        Text($r('app.string.settings_home_list_mode_desc'))
          .fontSize(12)
          .fontColor($r('app.color.text_caption'))
          .margin({ top: 2 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 })
      Text(this.getHomeListModeText())
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
      Image($r('app.media.ic_chevron_right'))
        .width(14)
        .height(14)
        .fillColor($r('app.color.text_caption'))
        .margin({ left: 4 })
        .syncLoad(true)
        .interpolation(ImageInterpolation.Low)
    }
    .width('100%')
    .height(MENU_ITEM_HEIGHT)
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor($r('app.color.card_background'))
    .bindMenu([
      {
        value: getResourceString($r('app.string.settings_home_list_mode_single'))
          + (this.homeListModeState.value === HOME_LIST_MODE_SINGLE ? CHECK_MARK : ''),
        action: () => { this.onHomeListModeChange(HOME_LIST_MODE_SINGLE).catch((err: Error) => { console.error(`[SettingsPage] onHomeListModeChange failed: ${err.message}`); }); }
      },
      {
        value: getResourceString($r('app.string.settings_home_list_mode_double_full'))
          + (this.homeListModeState.value === HOME_LIST_MODE_DOUBLE_FULL ? CHECK_MARK : ''),
        action: () => { this.onHomeListModeChange(HOME_LIST_MODE_DOUBLE_FULL).catch((err: Error) => { console.error(`[SettingsPage] onHomeListModeChange failed: ${err.message}`); }); }
      },
      {
        value: getResourceString($r('app.string.settings_home_list_mode_double_compact'))
          + (this.homeListModeState.value === HOME_LIST_MODE_DOUBLE_COMPACT ? CHECK_MARK : ''),
        action: () => { this.onHomeListModeChange(HOME_LIST_MODE_DOUBLE_COMPACT).catch((err: Error) => { console.error(`[SettingsPage] onHomeListModeChange failed: ${err.message}`); }); }
      },
      {
        value: getResourceString($r('app.string.settings_home_list_mode_waterfall'))
          + (this.homeListModeState.value === HOME_LIST_MODE_WATERFALL ? CHECK_MARK : ''),
        action: () => { this.onHomeListModeChange(HOME_LIST_MODE_WATERFALL).catch((err: Error) => { console.error(`[SettingsPage] onHomeListModeChange failed: ${err.message}`); }); }
      }
    ], {
      placement: Placement.BottomRight,
      enableArrow: false
    })
  }

  // 分类标题构建器：用于在分类间显示标题（如"个性化"、"内容"、"账号"、"其他"）
  // 视觉风格：左侧 4vp 主题色短竖条 + 标题文字（15sp Medium），上方 12vp 留白
  @Builder sectionHeaderBuilder(titleRes: Resource) {
    Row() {
      Row()
        .width(4)
        .height(16)
        .borderRadius(2)
        .backgroundColor(this.themeState.primary)
      Text(titleRes)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .margin({ left: 8 })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .margin({ top: 12, bottom: 8 })
  }

  // 帖子详情悬浮底栏开关菜单项构建器
  @Builder threadFloatingBarMenuItemBuilder() {
    Row() {
      Image($r('app.media.ic_message'))
        .width(22)
        .height(22)
        .fillColor(this.themeState.primary)
        .syncLoad(true)
        .interpolation(ImageInterpolation.Low)
      Column() {
        Text('帖子详情悬浮底栏')
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))
        Text('沉浸式光感样式')
          .fontSize(12)
          .fontColor($r('app.color.text_caption'))
          .margin({ top: 2 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 })
      Toggle({ type: ToggleType.Switch, isOn: this.threadFloatingBarEnabled })
        .selectedColor(this.themeState.primary)
        .enabled(!this.threadFloatingBarToggling)
        .onChange((isOn: boolean) => {
          this.onToggleWithFeedback(isOn, (on: boolean) => {
            this.onThreadFloatingBarToggle(on).catch((err: Error) => {
              console.error(`[SettingsPage] onThreadFloatingBarToggle failed: ${err.message}`);
            });
          });
        })
    }
    .width('100%')
    .height(TOGGLE_MENU_ITEM_HEIGHT)
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor($r('app.color.card_background'))
  }

  // 完整版吧内页面开关菜单项构建器
  // Toggle 绑定 ForumPageVersionState.value（0=关/1=开），切换时同步 AppStorageV2 + preferences
  @Builder forumPageVersionMenuItemBuilder() {
    Row() {
      Image($r('app.media.ic_home'))
        .width(22)
        .height(22)
        .fillColor(this.themeState.primary)
        .syncLoad(true)
        .interpolation(ImageInterpolation.Low)
      Text($r('app.string.settings_forum_page_full'))
        .layoutWeight(1)
        .fontSize(16)
        .fontColor($r('app.color.text_primary'))
        .margin({ left: 12 })
      // 直接读 state.value 计算 isOn，建立响应式依赖
      // state 是 @ObservedV2 实例，value 是 @Trace，任何修改都会触发重渲染
      Toggle({ type: ToggleType.Switch, isOn: this.forumPageVersionState.value === 1 })
        .selectedColor(this.themeState.primary)
        .enabled(!this.forumPageVersionToggling)
        .onChange((isOn: boolean) => {
          this.onToggleWithFeedback(isOn, (on: boolean) => {
            this.onForumPageVersionToggle(on).catch((err: Error) => {
              console.error(`[SettingsPage] onForumPageVersionToggle failed: ${err.message}`);
            });
          });
        })
    }
    .width('100%')
    .height(TOGGLE_MENU_ITEM_HEIGHT)
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor($r('app.color.card_background'))
  }

  // 吧内 FAB 功能菜单项构建器：右侧显示当前档位 + bindMenu 弹出 4 档选择
  // 0=发帖 / 1=刷新 / 2=回顶 / 3=隐藏
  @Builder forumFabFunctionMenuItemBuilder() {
    Row() {
      Image($r('app.media.ic_add'))
        .width(22)
        .height(22)
        .fillColor(this.themeState.primary)
        .syncLoad(true)
        .interpolation(ImageInterpolation.Low)
      Text($r('app.string.settings_forum_fab_function'))
        .layoutWeight(1)
        .fontSize(16)
        .fontColor($r('app.color.text_primary'))
        .margin({ left: 12 })
      Text(this.getFabFunctionText())
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
      Image($r('app.media.ic_chevron_right'))
        .width(14)
        .height(14)
        .fillColor($r('app.color.text_caption'))
        .margin({ left: 4 })
        .syncLoad(true)
        .interpolation(ImageInterpolation.Low)
    }
    .width('100%')
    .height(MENU_ITEM_HEIGHT)
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor($r('app.color.card_background'))
    .bindMenu([
      {
        value: getResourceString($r('app.string.forum_fab_post'))
          + (this.forumFabFunctionState.value === FORUM_FAB_FUNCTION_POST ? CHECK_MARK : ''),
        action: () => {
          this.onForumFabFunctionChange(FORUM_FAB_FUNCTION_POST).catch((err: Error) => {
            console.error(`[SettingsPage] onForumFabFunctionChange failed: ${err.message}`);
          });
        }
      },
      {
        value: getResourceString($r('app.string.forum_fab_refresh'))
          + (this.forumFabFunctionState.value === FORUM_FAB_FUNCTION_REFRESH ? CHECK_MARK : ''),
        action: () => {
          this.onForumFabFunctionChange(FORUM_FAB_FUNCTION_REFRESH).catch((err: Error) => {
            console.error(`[SettingsPage] onForumFabFunctionChange failed: ${err.message}`);
          });
        }
      },
      {
        value: getResourceString($r('app.string.forum_fab_back_to_top'))
          + (this.forumFabFunctionState.value === FORUM_FAB_FUNCTION_BACK_TO_TOP ? CHECK_MARK : ''),
        action: () => {
          this.onForumFabFunctionChange(FORUM_FAB_FUNCTION_BACK_TO_TOP).catch((err: Error) => {
            console.error(`[SettingsPage] onForumFabFunctionChange failed: ${err.message}`);
          });
        }
      },
      {
        value: getResourceString($r('app.string.forum_fab_hide'))
          + (this.forumFabFunctionState.value === FORUM_FAB_FUNCTION_HIDE ? CHECK_MARK : ''),
        action: () => {
          this.onForumFabFunctionChange(FORUM_FAB_FUNCTION_HIDE).catch((err: Error) => {
            console.error(`[SettingsPage] onForumFabFunctionChange failed: ${err.message}`);
          });
        }
      }
    ], {
      placement: Placement.BottomRight,
      enableArrow: false
    })
  }

  // 默认启动页菜单项构建器：右侧显示当前档位 + bindMenu 弹出 4 档选择
  // 0=首页 / 1=收藏 / 2=消息 / 3=我的
  @Builder defaultHomePageMenuItemBuilder() {
    Row() {
      Image($r('app.media.ic_home'))
        .width(22)
        .height(22)
        .fillColor(this.themeState.primary)
        .syncLoad(true)
        .interpolation(ImageInterpolation.Low)
      Text($r('app.string.settings_default_home_page'))
        .layoutWeight(1)
        .fontSize(16)
        .fontColor($r('app.color.text_primary'))
        .margin({ left: 12 })
      Text(this.getDefaultHomePageText())
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
      Image($r('app.media.ic_chevron_right'))
        .width(14)
        .height(14)
        .fillColor($r('app.color.text_caption'))
        .margin({ left: 4 })
        .syncLoad(true)
        .interpolation(ImageInterpolation.Low)
    }
    .width('100%')
    .height(MENU_ITEM_HEIGHT)
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor($r('app.color.card_background'))
    .bindMenu([
      {
        value: getResourceString($r('app.string.tab_home'))
          + (this.defaultHomePageState.value === DEFAULT_HOME_PAGE_HOME ? CHECK_MARK : ''),
        action: () => {
          this.onDefaultHomePageChange(DEFAULT_HOME_PAGE_HOME).catch((err: Error) => {
            console.error(`[SettingsPage] onDefaultHomePageChange failed: ${err.message}`);
          });
        }
      },
      {
        value: getResourceString($r('app.string.tab_favorite'))
          + (this.defaultHomePageState.value === DEFAULT_HOME_PAGE_FAVORITES ? CHECK_MARK : ''),
        action: () => {
          this.onDefaultHomePageChange(DEFAULT_HOME_PAGE_FAVORITES).catch((err: Error) => {
            console.error(`[SettingsPage] onDefaultHomePageChange failed: ${err.message}`);
          });
        }
      },
      {
        value: getResourceString($r('app.string.tab_message'))
          + (this.defaultHomePageState.value === DEFAULT_HOME_PAGE_MESSAGES ? CHECK_MARK : ''),
        action: () => {
          this.onDefaultHomePageChange(DEFAULT_HOME_PAGE_MESSAGES).catch((err: Error) => {
            console.error(`[SettingsPage] onDefaultHomePageChange failed: ${err.message}`);
          });
        }
      },
      {
        value: getResourceString($r('app.string.tab_profile'))
          + (this.defaultHomePageState.value === DEFAULT_HOME_PAGE_PROFILE ? CHECK_MARK : ''),
        action: () => {
          this.onDefaultHomePageChange(DEFAULT_HOME_PAGE_PROFILE).catch((err: Error) => {
            console.error(`[SettingsPage] onDefaultHomePageChange failed: ${err.message}`);
          });
        }
      }
    ], {
      placement: Placement.BottomRight,
      enableArrow: false
    })
  }

  // #135 应用锁菜单项构建器：仅当 appLockSupported=true 时在 build() 中渲染
  @Builder appLockMenuItemBuilder() {
    Row() {
      Image($r('app.media.ic_warning'))
        .width(22)
        .height(22)
        .fillColor(this.themeState.primary)
        .syncLoad(true)
        .interpolation(ImageInterpolation.Low)
      Column() {
        Text($r('app.string.settings_app_lock'))
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))
        Text($r('app.string.settings_app_lock_desc'))
          .fontSize(12)
          .fontColor($r('app.color.text_caption'))
          .margin({ top: 2 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 })
      Toggle({ type: ToggleType.Switch, isOn: this.appLockEnabled })
        .selectedColor(this.themeState.primary)
        .onChange((isOn: boolean) => {
          this.onToggleWithFeedback(isOn, (on: boolean) => {
            this.onAppLockToggle(on).catch((err: Error) => {
              console.error(`[SettingsPage] onAppLockToggle failed: ${err.message}`);
            });
          });
        })
    }
    .width('100%')
    .height(TOGGLE_MENU_ITEM_HEIGHT)
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor($r('app.color.card_background'))
  }

  // #201 底栏 Tab 显隐开关构建器（收藏/消息/我的共用结构）
  // #238 修复持久化 Toggle 不响应：原 isOn: boolean 参数是 primitive，@Builder 不会追踪其变化
  // 改为传入 state: TabVisibilityState + bit: number，在 @Builder 内部读 state.value 计算布尔
  // 因为 state 是 @ObservedV2 + @Trace value，@Builder 内读取 state.value 会建立依赖，变化时触发重渲染
  // 参数：icon 图标 / label 标题 / state AppStorageV2 共享状态 / bit 位掩码 / isToggling 防抖标志 / onChange 回调
  @Builder tabToggleBuilder(icon: Resource, label: Resource, state: TabVisibilityState,
    bit: number, isToggling: boolean, onChange: (isOn: boolean) => void) {
    Row() {
      Image(icon)
        .width(22)
        .height(22)
        .fillColor(this.themeState.primary)
        .syncLoad(true)
        .interpolation(ImageInterpolation.Low)
      Text(label)
        .layoutWeight(1)
        .fontSize(16)
        .fontColor($r('app.color.text_primary'))
        .margin({ left: 12 })
      // 在 @Builder 内部直接读 state.value 计算 isOn，建立响应式依赖
      // state 是 @ObservedV2 实例，value 是 @Trace，任何修改（包括 Index.ets 启动时恢复）都会触发重渲染
      Toggle({ type: ToggleType.Switch, isOn: (state.value & bit) !== 0 })
        .selectedColor(this.themeState.primary)
        .enabled(!isToggling)
        .onChange((on: boolean) => {
          this.onToggleWithFeedback(on, onChange);
        })
    }
    .width('100%')
    .height(TOGGLE_MENU_ITEM_HEIGHT)
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor($r('app.color.card_background'))
  }

  // #201 沉浸光感强度菜单项构建器：右侧显示当前档位 + bindMenu 弹出 4 档选择
  @Builder materialLevelMenuItemBuilder() {
    Row() {
      Image($r('app.media.ic_settings'))
        .width(22)
        .height(22)
        .fillColor(this.themeState.primary)
        .syncLoad(true)
        .interpolation(ImageInterpolation.Low)
      Column() {
        Text($r('app.string.settings_material_level'))
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))
        Text($r('app.string.settings_material_level_desc'))
          .fontSize(12)
          .fontColor($r('app.color.text_caption'))
          .margin({ top: 2 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 })
      Text(this.getMaterialLevelText())
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
      Image($r('app.media.ic_chevron_right'))
        .width(14)
        .height(14)
        .fillColor($r('app.color.text_caption'))
        .margin({ left: 4 })
        .syncLoad(true)
        .interpolation(ImageInterpolation.Low)
    }
    .width('100%')
    .height(MENU_ITEM_HEIGHT)
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor($r('app.color.card_background'))
    .bindMenu([
      {
        value: getResourceString($r('app.string.settings_material_level_exquisite'))
          + (this.materialLevelState.value === MATERIAL_LEVEL_EXQUISITE ? CHECK_MARK : ''),
        action: () => { this.setMaterialLevel(MATERIAL_LEVEL_EXQUISITE); }
      },
      {
        value: getResourceString($r('app.string.settings_material_level_gentle'))
          + (this.materialLevelState.value === MATERIAL_LEVEL_GENTLE ? CHECK_MARK : ''),
        action: () => { this.setMaterialLevel(MATERIAL_LEVEL_GENTLE); }
      },
      {
        value: getResourceString($r('app.string.settings_material_level_smooth'))
          + (this.materialLevelState.value === MATERIAL_LEVEL_SMOOTH ? CHECK_MARK : ''),
        action: () => { this.setMaterialLevel(MATERIAL_LEVEL_SMOOTH); }
      },
      {
        value: getResourceString($r('app.string.settings_material_level_adaptive'))
          + (this.materialLevelState.value === MATERIAL_LEVEL_ADAPTIVE ? CHECK_MARK : ''),
        action: () => { this.setMaterialLevel(MATERIAL_LEVEL_ADAPTIVE); }
      }
    ], {
      placement: Placement.BottomRight,
      enableArrow: false
    })
  }

  // #127 消息通知菜单项构建器：左侧图标 + 中间标题/描述 + 右侧 Toggle 开关
  @Builder notificationMenuItemBuilder() {
    Row() {
      Image($r('app.media.ic_message'))
        .width(22)
        .height(22)
        .fillColor(this.themeState.primary)
        .syncLoad(true)
        .interpolation(ImageInterpolation.Low)
      Column() {
        Text($r('app.string.settings_notification'))
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))
        Text($r('app.string.settings_notification_desc'))
          .fontSize(12)
          .fontColor($r('app.color.text_caption'))
          .margin({ top: 2 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 })
      Toggle({ type: ToggleType.Switch, isOn: this.notificationEnabled })
        .selectedColor(this.themeState.primary)
        .onChange((isOn: boolean) => {
          this.onToggleWithFeedback(isOn, (on: boolean) => {
            this.onNotificationToggle(on).catch((err: Error) => {
              console.error(`[SettingsPage] onNotificationToggle failed: ${err.message}`);
            });
          });
        })
    }
    .width('100%')
    .height(TOGGLE_MENU_ITEM_HEIGHT)
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor($r('app.color.card_background'))
  }

  // 分割线构建器：从图标右侧开始（left 52），0.5vp 细线，参考原型 menu-item::after
  @Builder dividerBuilder() {
    Row() {
      Row()
        .height(0.5)
        .backgroundColor($r('app.color.divider'))
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: DIVIDER_LEFT_PADDING })
  }

  build() {
    // #170 [A4-S2'] HdsNavDestination 包装：titleBar 滚动动态模糊 + 沉浸光感材质
    // titleBar 配置 GRADIENT_BLUR 渐变模糊 + ADAPTIVE 自适应材质，bindToScrollable 绑定 Scroll
    HdsNavDestination() {
      // 菜单容器：Column 包裹（对齐 SubPostsPage 写法，Scroll 会自动避让导致间距过大）
      // #238 scrollBar(BarState.Off) 隐藏滚动条，避免设置项多时右侧出现滚动条影响视觉
      Scroll(this.scroller) {
        Column() {
          if (this.category === 0) {
            Column() {
              this.categoryEntryBuilder($r('app.string.settings_category_personalization'),
                RouterUtil.ROUTE_PERSONALIZATION_SETTINGS_PAGE)
              this.dividerBuilder()
              this.categoryEntryBuilder($r('app.string.settings_category_content'),
                RouterUtil.ROUTE_CONTENT_SETTINGS_PAGE)
              this.dividerBuilder()
              this.categoryEntryBuilder($r('app.string.settings_category_account'),
                RouterUtil.ROUTE_ACCOUNT_SETTINGS_PAGE)
              this.dividerBuilder()
              this.categoryEntryBuilder($r('app.string.settings_category_other'),
                RouterUtil.ROUTE_OTHER_SETTINGS_PAGE)
            }
            .width('100%')
            .borderRadius(10)
            .clip(true)
            .margin({ top: 12 })
          }
          if (this.category === 1) {
          // ==================== 个性化分组 ====================
          // 包含：主题、深色模式、字体大小、沉浸光感强度、触感反馈
          this.sectionHeaderBuilder($r('app.string.settings_category_personalization'))
          Column() {
            this.themeMenuItemBuilder()
            this.dividerBuilder()
            this.colorModeMenuItemBuilder()
            this.dividerBuilder()
            this.fontScaleMenuItemBuilder()
            this.dividerBuilder()
            this.materialLevelMenuItemBuilder()
            this.dividerBuilder()
            this.vibratorMenuItemBuilder()
          }
          .width('100%')
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(10)
          .clip(true)
          .margin({ top: 0, bottom: 12 })

          Column() {
            Row() {
              Column() {
                Text($r('app.string.settings_forum_comment_preview'))
                  .fontSize(16)
                  .fontColor($r('app.color.text_primary'))
                Text($r('app.string.settings_forum_comment_preview_desc'))
                  .fontSize(12)
                  .fontColor($r('app.color.text_caption'))
                  .margin({ top: 2 })
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)

              Toggle({ type: ToggleType.Switch, isOn: this.forumCommentPreview })
                .selectedColor(this.themeState.primary)
                .onChange((value: boolean) => {
                  this.onToggleWithFeedback(value, (v: boolean) => {
                    this.onForumCommentPreviewToggle(v).catch((err: Error) => {
                      console.error(`[SettingsPage] onForumCommentPreviewToggle failed: ${err.message}`);
                    });
                  });
                })
            }
            .width('100%')
            .height(64)
            .padding({ left: 16, right: 16 })
            .alignItems(VerticalAlign.Center)
            .backgroundColor($r('app.color.card_background'))
            .onClick(() => {
              // 点击行也能切换
              this.onToggleWithFeedback(!this.forumCommentPreview, (v: boolean) => {
                this.onForumCommentPreviewToggle(v).catch((err: Error) => {
                  console.error(`[SettingsPage] onForumCommentPreviewToggle failed: ${err.message}`);
                });
              });
            })

            this.dividerBuilder()
            this.booleanPreferenceBuilder(
              $r('app.string.settings_thread_comment_preview'),
              $r('app.string.settings_thread_comment_preview_desc'),
              this.threadCommentPreviewState.value,
              (value: boolean) => {
                this.threadCommentPreviewState.value = value;
                this.setBooleanPreference('threadCommentPreview', value).catch((err: Error) => {
                  console.error(`[SettingsPage] save threadCommentPreview failed: ${err.message}`);
                });
              })
            this.dividerBuilder()
            this.booleanPreferenceBuilder(
              $r('app.string.settings_recent_forums'),
              $r('app.string.settings_recent_forums_desc'),
              this.recentForumsState.value,
              (value: boolean) => {
                this.recentForumsState.value = value;
                this.setBooleanPreference('showRecentForums', value).catch((err: Error) => {
                  console.error(`[SettingsPage] save showRecentForums failed: ${err.message}`);
                });
              })
          }
          .width('100%')
          .borderRadius(10)
          .clip(true)
          .margin({ bottom: 12 })
          }

          // ==================== 内容分组 ====================
          if (this.category === 2) {
          // 包含：图片加载设置、首页列表模式、帖子详情悬浮底栏、完整版吧内页面、吧内 FAB 功能、默认启动页、底栏 Tab 显隐
          this.sectionHeaderBuilder($r('app.string.settings_category_content'))
          Column() {
            this.imageLoadTypeMenuItemBuilder()
            this.dividerBuilder()
            this.homeListModeMenuItemBuilder()
            this.dividerBuilder()
            this.threadFloatingBarMenuItemBuilder()
            this.dividerBuilder()
            this.forumPageVersionMenuItemBuilder()
            this.dividerBuilder()
            this.forumFabFunctionMenuItemBuilder()
            this.dividerBuilder()
            this.defaultHomePageMenuItemBuilder()
          }
          .width('100%')
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(10)
          .clip(true)
          .margin({ bottom: 12 })

          // 底栏 Tab 显隐分组（动态/消息/我的，首页始终显示不可关闭）
          Column() {
            this.tabToggleBuilder(
              $r('app.media.ic_favorite'),
              $r('app.string.settings_tab_favorite'),
              this.tabVisibilityState,
              TAB_BIT_FAVORITE,
              this.tabFavoriteToggling,
              (on: boolean) => {
                this.onTabFavoriteToggle(on).catch((err: Error) => {
                  console.error(`[SettingsPage] onTabFavoriteToggle failed: ${err.message}`);
                });
              }
            )
            this.dividerBuilder()
            this.tabToggleBuilder(
              $r('app.media.ic_message'),
              $r('app.string.settings_tab_message'),
              this.tabVisibilityState,
              TAB_BIT_MESSAGE,
              this.tabMessageToggling,
              (on: boolean) => {
                this.onTabMessageToggle(on).catch((err: Error) => {
                  console.error(`[SettingsPage] onTabMessageToggle failed: ${err.message}`);
                });
              }
            )
            this.dividerBuilder()
            this.tabToggleBuilder(
              $r('app.media.ic_profile'),
              $r('app.string.settings_tab_profile'),
              this.tabVisibilityState,
              TAB_BIT_PROFILE,
              this.tabProfileToggling,
              (on: boolean) => {
                this.onTabProfileToggle(on).catch((err: Error) => {
                  console.error(`[SettingsPage] onTabProfileToggle failed: ${err.message}`);
                });
              }
            )
          }
          .width('100%')
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(10)
          .clip(true)
          .margin({ bottom: 12 })
          }

          // ==================== 账号分组 ====================
          if (this.category === 3) {
          // 包含：复制 BDUSS、我的小尾巴、应用锁（条件渲染）、消息通知
          this.sectionHeaderBuilder($r('app.string.settings_category_account'))
          Column() {
            this.menuItemBuilder($r('app.media.ic_switch_account'), $r('app.string.settings_copy_bduss'), false, () => {
              this.copyBdussToClipboard().catch((err: Error) => {
                console.error(`[SettingsPage] copyBduss failed: ${err.message}`);
              });
            })
            this.dividerBuilder()
            this.menuItemBuilder($r('app.media.ic_emoji'), $r('app.string.settings_little_tail'), false, () => {
              this.showLittleTailDialog();
            })
          }
          .width('100%')
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(10)
          .clip(true)
          .margin({ bottom: 12 })

          // #135 应用锁（仅当设备支持生物识别时渲染）
          if (this.appLockSupported) {
            Column() {
              this.appLockMenuItemBuilder()
            }
            .width('100%')
            .backgroundColor($r('app.color.card_background'))
            .borderRadius(10)
            .clip(true)
            .margin({ bottom: 12 })
          }

          // #127 消息通知开关
          Column() {
            this.notificationMenuItemBuilder()
          }
          .width('100%')
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(10)
          .clip(true)
          .margin({ bottom: 12 })
          Column() {
            this.menuItemBuilder($r('app.media.ic_logout'), $r('app.string.profile_logout'), true, () => {
              this.showLogoutConfirm();
            })
          }
          .width('100%')
          .borderRadius(10)
          .clip(true)
          }

          // ==================== 其他分组 ====================
          if (this.category === 4) {
          // 包含：清除缓存、检查更新、关于、退出登录
          this.sectionHeaderBuilder($r('app.string.settings_category_other'))
          Column() {
            this.menuItemBuilder($r('app.media.ic_settings'), $r('app.string.settings_clear_cache'), false, () => {
              this.clearCache().catch((err: Error) => {
                console.error(`[SettingsPage] clearCache failed: ${err.message}`);
              });
            })
            this.dividerBuilder()
            this.menuItemBuilder($r('app.media.ic_settings'), $r('app.string.settings_check_update'), false, () => {
              this.checkUpdate();
            })
            this.dividerBuilder()
            this.menuItemBuilder($r('app.media.ic_settings'), $r('app.string.settings_about'), false, () => {
              RouterUtil.push(RouterUtil.ROUTE_ABOUT_PAGE);
            })
          }
          .width('100%')
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(10)
          .clip(true)
          .margin({ bottom: 12 })
          Column() {
            Row() {
              Column() {
                Text($r('app.string.settings_receive_prerelease_updates'))
                  .fontSize(16)
                  .fontColor($r('app.color.text_primary'))
                Text($r('app.string.settings_receive_prerelease_updates_desc'))
                  .fontSize(12)
                  .fontColor($r('app.color.text_caption'))
                  .margin({ top: 2 })
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)

              Toggle({ type: ToggleType.Switch, isOn: this.receivePrereleaseUpdates })
                .selectedColor(this.themeState.primary)
                .onChange((value: boolean) => {
                  VibratorUtil.light();
                  this.onReceivePrereleaseUpdatesToggle(value).catch((err: Error) => {
                    console.error(`[SettingsPage] onReceivePrereleaseUpdatesToggle failed: ${err.message}`);
                  });
                })
            }
            .width('100%')
            .height(TOGGLE_MENU_ITEM_HEIGHT)
            .padding({ left: 16, right: 16 })
            .alignItems(VerticalAlign.Center)
            .backgroundColor($r('app.color.card_background'))
          }
          .width('100%')
          .borderRadius(10)
          .clip(true)
          .margin({ bottom: 12 })
        }
        }
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 24 })
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .height('100%')
      .padding({ top: this.statusBarHeight + TITLE_BAR_HEIGHT })
      .backgroundColor($r('app.color.page_background'))
      .scrollBar(BarState.Off)
    }
    .titleBar({
      content: {
        title: {
          mainTitle: this.getPageTitle()
        }
      },
      style: {
        scrollEffectOpts: {
          enableScrollEffect: true,
          scrollEffectType: ScrollEffectType.COMMON_BLUR
        },
        systemMaterialEffect: {
          materialType: MATERIAL_TYPE_IMMERSIVE,
          materialLevel: resolveMaterialLevel(this.materialLevelState.value)
        }
      },
      avoidLayoutSafeArea: true
    })
    .bindToScrollable([this.scroller])
    .backgroundColor($r('app.color.page_background'))
  }
}
