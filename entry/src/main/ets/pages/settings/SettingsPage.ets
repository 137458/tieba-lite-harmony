// 设置页（Phase 4 设置功能实现）
// 五项菜单功能：
//   - 深色模式：bindMenu 弹出选择菜单（跟随系统/深色/浅色），setColorMode 切换 + AppStorageManager 持久化
//   - 字体大小：bindMenu 弹出选择菜单（跟随系统/小/默认/略大/大/超大），setFontScale 切换 + AppStorageManager 持久化
//   - 复制 BDUSS：从 AppStorageManager 读取 BDUSS，pasteboard 复制到系统剪贴板
//   - 我的小尾巴：弹对话框输入，AppStorageManager 持久化，ReplyPage.onSend 末尾追加
//   - 清除缓存：递归删除 cacheDir 下文件
//   - 退出登录：弹确认对话框，清理 storage + TiebaHttpClient，跳转 LoginPage
//   - 关于：跳转 AboutPage 显示版本号 + 开源链接

import { AppStorageV2, promptAction } from '@kit.ArkUI';
import { HdsNavDestination, ScrollEffectType, hdsMaterial } from '@kit.UIDesignKit';
import { AppStorageManager } from '../../data/AppStorage';
import { TiebaAPI } from '../../api/TiebaAPI';
import { ConfigurationConstant, common } from '@kit.AbilityKit';
import { getResourceString } from '../../utils/ResourceUtil';
import { pasteboard, BusinessError } from '@kit.BasicServicesKit';
import { dlpAntiPeep } from '@kit.DeviceSecurityKit';
import fs from '@ohos.file.fs';
import {
  IMAGE_LOAD_SMART_ORIGIN,
  IMAGE_LOAD_SMART_NO,
  IMAGE_LOAD_ALL_ORIGIN,
  IMAGE_LOAD_ALL_NO
} from '../../utils/ImageLoadUtil';
import { ImageLoadTypeState, BdussState, HomeDualColumnState } from '../../model/AppStorageV2Models';
import { VibratorUtil } from '../../utils/VibratorUtil';
import { UserAuthUtil } from '../../utils/UserAuthUtil';
import { AntiPeepUtil, AntiPeepCallback } from '../../utils/AntiPeepUtil';
import { NotificationUtil } from '../../utils/NotificationUtil';
import { connectTheme, ThemeState, getThemeConfig } from '../../theme/ThemeManager';
import { RouterUtil } from '../../utils/RouterUtil';

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

@ComponentV2
export struct SettingsPage {
  // #170 滚动器，绑定到 HdsNavDestination.bindToScrollable 实现标题栏滚动动态模糊
  private scroller: Scroller = new Scroller();
  // 当前颜色模式：0=跟随系统(COLOR_MODE_NOT_SET) 1=深色(COLOR_MODE_DARK) 2=浅色(COLOR_MODE_LIGHT)
  @Local colorMode: number = 0;
  // 当前字体大小倍数：0=跟随系统 0.85=小号 1.0=默认 1.15=略大 1.3=大号 1.5=超大
  @Local fontScale: number = 0;
  // 当前图片加载模式：0=智能原图 1=智能无图 2=始终原图 3=始终无图（对齐 Android image_load_type）
  @Local imageLoadType: number = 0;
  // #148 [AntiPeep-2] 防窥保护开关状态（持久化 key=antiPeepEnabled）
  @Local antiPeepEnabled: boolean = false;
  // #148 设备是否支持 DLP 防窥保护（canIUse 检测 SystemCapability，false 时隐藏设置项）
  @Local antiPeepSupported: boolean = false;
  // #148 防窥保护开关切换中（防抖，避免连点）
  @Local antiPeepToggling: boolean = false;
  // #121 触感反馈开关状态（持久化 key=vibratorEnabled）
  @Local vibratorEnabled: boolean = true;
  // #121 触感反馈开关切换中（防抖，避免连点）
  @Local vibratorToggling: boolean = false;
  // 首页双列展示开关状态（持久化 key=homeDualColumn）
  @Local homeDualColumnEnabled: boolean = false;
  // 首页双列展示开关切换中（防抖，避免连点）
  @Local homeDualColumnToggling: boolean = false;
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
  // 退出登录进行中，防止重复点击
  @Local isLoggingOut: boolean = false;
  // #156 主题状态（AppStorageV2 全局共享，主题色实时刷新）
  @Local themeState: ThemeState = connectTheme();
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
    // 读取持久化的颜色模式偏好
    try {
      const storage: AppStorageManager = AppStorageManager.getInstance();
      await storage.ensureReady();
      this.colorMode = await storage.getNumber('colorMode', 0);
      this.fontScale = await storage.getNumber('fontScale', 0);
      this.imageLoadType = await storage.getNumber('imageLoadType', 0);
      // #148 读取防窥保护偏好
      this.antiPeepEnabled = await storage.getBoolean('antiPeepEnabled', false);
      // #121/#135 读取触感反馈/应用锁偏好
      this.vibratorEnabled = await storage.getBoolean('vibratorEnabled', true);
      this.appLockEnabled = await storage.getBoolean('appLockEnabled', false);
      // 读取首页双列展示偏好
      this.homeDualColumnEnabled = await storage.getBoolean('homeDualColumn', false);
      // #127 读取消息通知偏好
      this.notificationEnabled = await storage.getBoolean('notificationEnabled', false);
    } catch (err) {
      console.error(`[SettingsPage] load colorMode/fontScale/imageLoadType failed: ${(err as Error).message}`);
    }
    // #148 检测设备是否支持 DLP 防窥保护（canIUse，无副作用）
    this.antiPeepSupported = AntiPeepUtil.canUseAntiPeep();
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
      const appContext = getContext(this).getApplicationContext();
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
      const appContext = getContext(this).getApplicationContext();
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
      const imageLoadTypeState = AppStorageV2.connect(ImageLoadTypeState, 'imageLoadType', () => new ImageLoadTypeState())!;
      imageLoadTypeState.value = type;
      await AppStorageManager.getInstance().setNumber('imageLoadType', type);
    } catch (err) {
      console.error(`[SettingsPage] setImageLoadType failed: ${(err as Error).message}`);
      this.showToast(getResourceString($r('app.string.settings_image_load_type_failed')));
    }
  }

  /**
   * #148 [AntiPeep-2] 防窥保护开关切换
   * @param isOn true=开启 false=关闭
   *
   * 开启流程（对齐官方示例）：
   * 1. 拉起系统设置弹窗引导用户开启防窥保护（requestAntiPeepOptions）
   * 2. SUCCESS（用户已开启）或 ALREADY_ON（原本已开启）：持久化偏好为 true
   * 3. 通过 eventHub 通知 EntryAbility 立即注册防窥监听器（无需重启应用）
   * 4. 其他结果（用户取消/失败）：恢复开关为 false + Toast 提示
   *
   * 关闭流程：持久化偏好为 false + 通知 EntryAbility 注销监听器
   *
   * 监听器注册/注销：由 EntryAbility.setupAntiPeepGuard 统一管理，
   * SettingsPage 通过 eventHub.emit('setupAntiPeepGuard') 触发重新注册/注销。
   */
  private async onAntiPeepToggle(isOn: boolean): Promise<void> {
    if (this.antiPeepToggling) {
      return;
    }
    this.antiPeepToggling = true;
    try {
      const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
      if (isOn) {
        // 拉起系统设置弹窗，引导用户完成人脸验证 + 开启防窥保护
        const result: dlpAntiPeep.AntiPeepOptionsResult = await AntiPeepUtil.requestAntiPeepOptions(context);
        if (result === dlpAntiPeep.AntiPeepOptionsResult.SUCCESS ||
            result === dlpAntiPeep.AntiPeepOptionsResult.ALREADY_ON) {
          this.antiPeepEnabled = true;
          await AppStorageManager.getInstance().setBoolean('antiPeepEnabled', true);
          // 通知 EntryAbility 立即注册防窥监听器（无需重启应用即生效）
          context.eventHub.emit('setupAntiPeepGuard');
        } else {
          // 用户取消或系统未开启，恢复开关为 false
          this.antiPeepEnabled = false;
          this.showToast(getResourceString($r('app.string.settings_anti_peep_open_failed')));
        }
      } else {
        this.antiPeepEnabled = false;
        await AppStorageManager.getInstance().setBoolean('antiPeepEnabled', false);
        // 通知 EntryAbility 注销防窥监听器
        context.eventHub.emit('setupAntiPeepGuard');
      }
    } catch (err) {
      console.error(`[SettingsPage] onAntiPeepToggle failed: ${(err as Error).message}`);
      this.antiPeepEnabled = false;
      this.showToast(getResourceString($r('app.string.settings_anti_peep_open_failed')));
    } finally {
      this.antiPeepToggling = false;
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
   * 首页双列展示开关切换
   * @param isOn true=双列展示 false=单列展示
   *
   * 流程：
   * 1. 同步更新 AppStorageV2（HomePage 订阅后自动响应布局切换）
   * 2. 持久化到 preferences 供下次启动读取
   */
  private async onHomeDualColumnToggle(isOn: boolean): Promise<void> {
    if (this.homeDualColumnToggling) {
      return;
    }
    this.homeDualColumnToggling = true;
    try {
      this.homeDualColumnEnabled = isOn;
      // 同步 AppStorageV2，HomePage 自动响应
      const dualColumnState = AppStorageV2.connect(HomeDualColumnState, 'homeDualColumn', () => new HomeDualColumnState())!;
      dualColumnState.value = isOn;
      await AppStorageManager.getInstance().setBoolean('homeDualColumn', isOn);
    } catch (err) {
      console.error(`[SettingsPage] onHomeDualColumnToggle failed: ${(err as Error).message}`);
      this.homeDualColumnEnabled = !isOn;
      this.showToast(getResourceString($r('app.string.settings_toggle_failed')));
    } finally {
      this.homeDualColumnToggling = false;
    }
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
          const granted: boolean = await NotificationUtil.requestEnable();
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
      const bduss: string = await AppStorageManager.getInstance().getString('bduss', '');
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
        systemPasteboard.clear().catch((clearErr: BusinessError) => {
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
      const cacheDir: string = getContext(this).cacheDir;
      await this.removeDirRecursive(cacheDir);
      this.showToast(getResourceString($r('app.string.settings_cache_cleared')));
    } catch (err) {
      console.error(`[SettingsPage] clearCache failed: ${(err as Error).message}`);
      this.showToast(getResourceString($r('app.string.settings_cache_clear_failed')));
    }
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
    const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
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
      const storage: AppStorageManager = AppStorageManager.getInstance();
      const keysToRemove: string[] = [
        'bduss', 'stoken', 'tbs', 'cuid', 'baiduid',
        'z_id', 'client_id', 'sample_id', 'tieba_uid',
        'uid', 'name', 'avatar', 'nickname'
      ];
      for (let i: number = 0; i < keysToRemove.length; i++) {
        try {
          await storage.remove(keysToRemove[i]);
        } catch (err) {
          console.warn(`[SettingsPage] remove ${keysToRemove[i]} failed: ${(err as Error).message}`);
        }
      }
      // 清 TiebaHttpClient 内存态凭证
      TiebaAPI.setAuth('', '');
      // #90 同步清空 AppStorageV2 中的 bduss，触发订阅方联动
      const bdussState = AppStorageV2.connect(BdussState, 'bduss', () => new BdussState())!;
      bdussState.value = '';
      // #195 路由清理：router.replaceUrl → RouterUtil.replace
      // 退出登录后直接 replace 到 LoginPage（方案 A）
      // 栈变为 [MainPage, LoginPage]，用户按返回回到 MainPage 未登录态
      // #177 原注释：router.replaceUrl 会脱离 Navigation 栈，已修复
      RouterUtil.replace(RouterUtil.ROUTE_LOGIN_PAGE);
    } catch (err) {
      console.error(`[SettingsPage] logout failed: ${(err as Error).message}`);
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
      Text(getThemeConfig(this.themeState.themeId).nameRes)
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
    ])
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
    ])
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
    ])
  }

  // #148 [AntiPeep-2] 防窥保护菜单项构建器：左侧图标 + 中间标题/描述 + 右侧 Toggle 开关
  // 仅当 antiPeepSupported=true 时在 build() 中渲染此 builder
  @Builder antiPeepMenuItemBuilder() {
    Row() {
      Image($r('app.media.ic_eye'))
        .width(22)
        .height(22)
        .fillColor(this.themeState.primary)
        .syncLoad(true)
        .interpolation(ImageInterpolation.Low)
      Column() {
        Text($r('app.string.settings_anti_peep'))
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))
        Text($r('app.string.settings_anti_peep_desc'))
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 2 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 })
      Toggle({ type: ToggleType.Switch, isOn: this.antiPeepEnabled })
        .selectedColor(this.themeState.primary)
        .onChange((isOn: boolean) => {
          this.onToggleWithFeedback(isOn, (on: boolean) => {
            this.onAntiPeepToggle(on).catch((err: Error) => {
              console.error(`[SettingsPage] onAntiPeepToggle failed: ${err.message}`);
            });
          });
        })
    }
    .width('100%')
    .height(TOGGLE_MENU_ITEM_HEIGHT)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(10)
    .alignItems(VerticalAlign.Center)
    .padding({ left: 16, right: 16 })
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

  // 首页双列展示菜单项构建器：左侧图标 + 中间标题/描述 + 右侧 Toggle 开关
  @Builder homeDualColumnMenuItemBuilder() {
    Row() {
      Image($r('app.media.ic_home'))
        .width(22)
        .height(22)
        .fillColor(this.themeState.primary)
        .syncLoad(true)
        .interpolation(ImageInterpolation.Low)
      Column() {
        Text($r('app.string.settings_home_dual_column'))
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))
        Text($r('app.string.settings_home_dual_column_desc'))
          .fontSize(12)
          .fontColor($r('app.color.text_caption'))
          .margin({ top: 2 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 })
      Toggle({ type: ToggleType.Switch, isOn: this.homeDualColumnEnabled })
        .selectedColor(this.themeState.primary)
        .onChange((isOn: boolean) => {
          this.onToggleWithFeedback(isOn, (on: boolean) => {
            this.onHomeDualColumnToggle(on).catch((err: Error) => {
              console.error(`[SettingsPage] onHomeDualColumnToggle failed: ${err.message}`);
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
      // 菜单容器：Scroll 包裹，绑定 scroller 联动 titleBar 模糊
      Scroll(this.scroller) {
        Column() {
        // 第一组：显示设置（主题 + 深色模式 + 字体大小 + 图片加载设置）
        Column() {
          this.themeMenuItemBuilder()
          this.dividerBuilder()
          this.colorModeMenuItemBuilder()
          this.dividerBuilder()
          this.fontScaleMenuItemBuilder()
          this.dividerBuilder()
          this.imageLoadTypeMenuItemBuilder()
        }
        .width('100%')
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(10)
        .clip(true)
        .margin({ bottom: 12 })

        // 第二组：账号设置（复制 BDUSS + 我的小尾巴）
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

        // #121 反馈分组：触感反馈
        Column() {
          this.vibratorMenuItemBuilder()
        }
        .width('100%')
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(10)
        .clip(true)
        .margin({ bottom: 12 })

        // 首页双列展示开关
        Column() {
          this.homeDualColumnMenuItemBuilder()
        }
        .width('100%')
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(10)
        .clip(true)
        .margin({ bottom: 12 })

        // #148 [AntiPeep-2] 隐私分组：防窥保护开关（仅当设备支持时渲染）
        if (this.antiPeepSupported) {
          Column() {
            this.antiPeepMenuItemBuilder()
          }
          .width('100%')
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(10)
          .clip(true)
          .margin({ bottom: 12 })
        }

        // #135 安全分组：应用锁开关（仅当设备支持生物识别时渲染）
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

        // #127 通知分组：消息通知开关
        Column() {
          this.notificationMenuItemBuilder()
        }
        .width('100%')
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(10)
        .clip(true)
        .margin({ bottom: 12 })

        // 第三组：应用设置（清除缓存 + 关于）
        Column() {
          this.menuItemBuilder($r('app.media.ic_settings'), $r('app.string.settings_clear_cache'), false, () => {
            this.clearCache().catch((err: Error) => {
              console.error(`[SettingsPage] clearCache failed: ${err.message}`);
            });
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

        // 第四组：退出登录（danger 红色风格）
        Column() {
          this.menuItemBuilder($r('app.media.ic_logout'), $r('app.string.profile_logout'), true, () => {
            this.showLogoutConfirm();
          })
        }
        .width('100%')
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(10)
        .clip(true)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 20 })
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.page_background'))
    }
    .titleBar({
      content: {
        title: {
          mainTitle: $r('app.string.settings_title')
        }
      },
      style: {
        scrollEffectOpts: {
          enableScrollEffect: true,
          scrollEffectType: ScrollEffectType.GRADIENT_BLUR
        },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        }
      },
      // 避让状态栏：setWindowLayoutFullScreen(true) 全屏模式下 titleBar 默认不避让状态栏，
      // 需显式设置 avoidLayoutSafeArea: true 让 titleBar 内容（标题/按钮）避让状态栏
      // 保留 systemMaterialEffect 沉浸光感模糊效果（按钮浮在模糊层上）
      avoidLayoutSafeArea: true
    })
    .bindToScrollable([this.scroller])
    .backgroundColor($r('app.color.page_background'))
  }
}
