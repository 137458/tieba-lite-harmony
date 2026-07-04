// 设置页（Phase 4 设置功能实现）
// 三项菜单功能：
//   - 深色模式：bindMenu 弹出选择菜单（跟随系统/深色/浅色），setColorMode 切换 + AppStorageManager 持久化
//   - 清除缓存：递归删除 cacheDir 下文件
//   - 退出登录：弹确认对话框，清理 storage + TiebaHttpClient，跳转 LoginPage

import { router } from '@kit.ArkUI';
import { getStatusBarHeight } from '../../utils/StatusBarUtil';
import { AppStorageManager } from '../../data/AppStorage';
import { TiebaAPI } from '../../api/TiebaAPI';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { getResourceString } from '../../utils/ResourceUtil';
import fs from '@ohos.file.fs';

@Entry
@Component
struct SettingsPage {
  // 状态栏高度（vp），沉浸式避让状态栏，默认 36，aboutToAppear 动态获取
  @State statusBarHeight: number = 36;
  // 当前颜色模式：0=跟随系统(COLOR_MODE_NOT_SET) 1=深色(COLOR_MODE_DARK) 2=浅色(COLOR_MODE_LIGHT)
  @State colorMode: number = 0;
  // 退出登录进行中，防止重复点击
  @State isLoggingOut: boolean = false;

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
    } catch (err) {
      console.error(`[SettingsPage] load colorMode failed: ${(err as Error).message}`);
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
   * 清除应用缓存：递归删除 cacheDir 下所有文件和子目录
   * 失败时显示错误 Toast，成功时显示"缓存已清除"
   */
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
        // 第一组：深色模式 + 清除缓存
        Column() {
          this.colorModeMenuItemBuilder()
          this.dividerBuilder()
          this.menuItemBuilder($r('app.media.ic_settings'), $r('app.string.settings_clear_cache'), false, () => {
            this.clearCache().catch((err: Error) => {
              console.error(`[SettingsPage] clearCache failed: ${err.message}`);
            });
          })
        }
        .width('100%')
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(10)
        .clip(true)
        .margin({ bottom: 12 })

        // 第二组：退出登录（danger 红色风格）
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
