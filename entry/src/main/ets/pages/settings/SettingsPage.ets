// 设置页（Phase 4 设置功能实现）
// 五项菜单功能：
//   - 深色模式：bindMenu 弹出选择菜单（跟随系统/深色/浅色），setColorMode 切换 + AppStorageManager 持久化
//   - 字体大小：bindMenu 弹出选择菜单（跟随系统/小/默认/略大/大/超大），setFontScale 切换 + AppStorageManager 持久化
//   - 复制 BDUSS：从 AppStorageManager 读取 BDUSS，pasteboard 复制到系统剪贴板
//   - 我的小尾巴：弹对话框输入，AppStorageManager 持久化，ReplyPage.onSend 末尾追加
//   - 清除缓存：递归删除 cacheDir 下文件
//   - 退出登录：弹确认对话框，清理 storage + TiebaHttpClient，跳转 LoginPage
//   - 关于：跳转 AboutPage 显示版本号 + 开源链接

import { router } from '@kit.ArkUI';
import { getStatusBarHeight } from '../../utils/StatusBarUtil';
import { AppStorageManager } from '../../data/AppStorage';
import { TiebaAPI } from '../../api/TiebaAPI';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { getResourceString } from '../../utils/ResourceUtil';
import { pasteboard, BusinessError } from '@kit.BasicServicesKit';
import fs from '@ohos.file.fs';
import {
  IMAGE_LOAD_SMART_ORIGIN,
  IMAGE_LOAD_SMART_NO,
  IMAGE_LOAD_ALL_ORIGIN,
  IMAGE_LOAD_ALL_NO
} from '../../utils/ImageLoadUtil';

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
        .maxLength(50)
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

@Entry
@Component
struct SettingsPage {
  // 状态栏高度（vp），沉浸式避让状态栏，默认 36，aboutToAppear 动态获取
  @State statusBarHeight: number = 36;
  // 当前颜色模式：0=跟随系统(COLOR_MODE_NOT_SET) 1=深色(COLOR_MODE_DARK) 2=浅色(COLOR_MODE_LIGHT)
  @State colorMode: number = 0;
  // 当前字体大小倍数：0=跟随系统 0.85=小号 1.0=默认 1.15=略大 1.3=大号 1.5=超大
  @State fontScale: number = 0;
  // 当前图片加载模式：0=智能原图 1=智能无图 2=始终原图 3=始终无图（对齐 Android image_load_type）
  @State imageLoadType: number = 0;
  // 退出登录进行中，防止重复点击
  @State isLoggingOut: boolean = false;
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
    // 获取状态栏高度，失败不阻塞页面加载，保留默认值 36
    try {
      this.statusBarHeight = await getStatusBarHeight(getContext(this));
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
    } catch (err) {
      console.error(`[SettingsPage] load colorMode/fontScale/imageLoadType failed: ${(err as Error).message}`);
    }
  }

  // Toast 提示 helper（API 12+ 推荐用 UIContext.getPromptAction() 替代全局 promptAction）
  private showToast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message });
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
    this.imageLoadType = type;
    AppStorage.setOrCreate('imageLoadType', type);
    try {
      await AppStorageManager.getInstance().setNumber('imageLoadType', type);
    } catch (err) {
      console.error(`[SettingsPage] setImageLoadType failed: ${(err as Error).message}`);
      this.showToast(getResourceString($r('app.string.settings_image_load_type_failed')));
    }
  }

  /**
   * 复制 BDUSS 到系统剪贴板
   * 用于调试场景：用户在其他应用/网页需要 BDUSS 时可快速复制
   * 实现：从 AppStorageManager 读取 BDUSS → pasteboard.createData + setData
   * 权限：写入剪贴板无需权限（API 12+ 仅读取需权限）
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
   */
  private async removeDirRecursive(dirPath: string): Promise<void> {
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
    }).then((result) => {
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
      // 替换路由栈，避免返回到 MainPage
      router.replaceUrl({ url: 'pages/main/LoginPage' }).catch((err: Error) => {
        console.error(`[SettingsPage] replaceUrl to LoginPage failed: ${err.message}`);
      });
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
        .fillColor(isDanger ? $r('app.color.error') : $r('app.color.primary'))
      Text(label)
        .layoutWeight(1)
        .fontSize(16)
        .fontColor(isDanger ? $r('app.color.error') : $r('app.color.text_primary'))
        .margin({ left: 12 })
      Image($r('app.media.ic_chevron_right'))
        .width(14)
        .height(14)
        .fillColor($r('app.color.text_caption'))
    }
    .width('100%')
    .height(44)
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor($r('app.color.card_background'))
    .onClick(() => onClick())
  }

  // 深色模式菜单项构建器：右侧显示当前模式文本 + bindMenu 弹出选择菜单
  @Builder colorModeMenuItemBuilder() {
    Row() {
      Image($r('app.media.ic_settings'))
        .width(22)
        .height(22)
        .fillColor($r('app.color.primary'))
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
    }
    .width('100%')
    .height(44)
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
        .fillColor($r('app.color.primary'))
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
    }
    .width('100%')
    .height(44)
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
        .fillColor($r('app.color.primary'))
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
    }
    .width('100%')
    .height(44)
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor($r('app.color.card_background'))
    .bindMenu([
      {
        value: getResourceString($r('app.string.settings_image_load_type_smart_origin')) + (this.imageLoadType === IMAGE_LOAD_SMART_ORIGIN ? ' ✓' : ''),
        action: () => { this.setImageLoadType(IMAGE_LOAD_SMART_ORIGIN); }
      },
      {
        value: getResourceString($r('app.string.settings_image_load_type_smart_no')) + (this.imageLoadType === IMAGE_LOAD_SMART_NO ? ' ✓' : ''),
        action: () => { this.setImageLoadType(IMAGE_LOAD_SMART_NO); }
      },
      {
        value: getResourceString($r('app.string.settings_image_load_type_all_origin')) + (this.imageLoadType === IMAGE_LOAD_ALL_ORIGIN ? ' ✓' : ''),
        action: () => { this.setImageLoadType(IMAGE_LOAD_ALL_ORIGIN); }
      },
      {
        value: getResourceString($r('app.string.settings_image_load_type_all_no')) + (this.imageLoadType === IMAGE_LOAD_ALL_NO ? ' ✓' : ''),
        action: () => { this.setImageLoadType(IMAGE_LOAD_ALL_NO); }
      }
    ])
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
    .padding({ left: 52 })
  }

  build() {
    Column() {
      // 顶部导航栏（参考原型 detail-nav：44 + statusBarHeight，标题居中）
      Row() {
        Image($r('app.media.ic_back'))
          .width(20)
          .height(20)
          .fillColor($r('app.color.primary'))
          .onClick(() => {
            router.back();
          })
        Text($r('app.string.settings_title'))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .fontSize(17)
          .fontWeight(600)
          .fontColor($r('app.color.text_primary'))
        // 右侧占位，与返回按钮等宽，保证标题视觉居中
        Row()
          .width(20)
          .height(20)
      }
      .width('100%')
      .height(44 + this.statusBarHeight)
      .padding({ left: 16, right: 16, top: this.statusBarHeight })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
      .alignItems(VerticalAlign.Center)
      .backgroundColor($r('app.color.page_background'))

      // 菜单容器：左右 16，顶部 20
      Column() {
        // 第一组：显示设置（深色模式 + 字体大小 + 图片加载设置）
        Column() {
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

        // 第三组：应用设置（清除缓存 + 关于）
        Column() {
          this.menuItemBuilder($r('app.media.ic_settings'), $r('app.string.settings_clear_cache'), false, () => {
            this.clearCache().catch((err: Error) => {
              console.error(`[SettingsPage] clearCache failed: ${err.message}`);
            });
          })
          this.dividerBuilder()
          this.menuItemBuilder($r('app.media.ic_settings'), $r('app.string.settings_about'), false, () => {
            router.pushUrl({ url: 'pages/settings/AboutPage' }).catch((err: Error) => {
              console.error(`[SettingsPage] navigate to AboutPage failed: ${err.message}`);
            });
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
}
