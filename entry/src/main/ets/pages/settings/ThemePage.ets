// #156 Theme-1 主题选择页
// #157 Theme-2 新增深色主题变体分组 + colorMode 联动
// 展示 6 种亮色预设 + 3 种深色变体主题色块预览，点击切换主题
// 主题色通过 AppStorageV2 ThemeState 全局共享，切换后实时生效
//
// colorMode 联动逻辑（对齐 Android ThemeUtil.switchTheme 三键联动模型）：
//   - 选择深色变体：记录当前 colorMode 到 oldColorMode，切换到 colorMode=1（深色）
//   - 选择亮色主题：从 oldColorMode 恢复之前的 colorMode 设置

import { router } from '@kit.ArkUI';
import { ConfigurationConstant } from '@kit.AbilityKit';
import { getStatusBarHeight } from '../../utils/StatusBarUtil';
import { AppStorageManager } from '../../data/AppStorage';
import {
  ThemeState,
  ThemeConfig,
  connectTheme,
  LIGHT_THEMES,
  DARK_THEMES,
  isDarkTheme
} from '../../theme/ThemeManager';

@Entry
@ComponentV2
export struct ThemePage {
  /** 主题状态（AppStorageV2 全局共享） */
  @Local themeState: ThemeState = connectTheme();
  /** 状态栏高度 */
  @Local statusBarHeight: number = 36;

  async aboutToAppear(): Promise<void> {
    try {
      this.statusBarHeight = await getStatusBarHeight(getContext(this));
    } catch (err) {
      console.error(`[ThemePage] getStatusBarHeight failed: ${(err as Error).message}`);
    }
  }

  /**
   * #157 切换主题并持久化 + colorMode 联动
   *
   * 联动规则（对齐 Android ThemeUtil 三键联动）：
   *   - 目标是深色变体：保存当前 colorMode → oldColorMode，然后 setColorMode=1（深色）
   *   - 目标是亮色主题：从 oldColorMode 恢复（默认 0=跟随系统）
   *
   * @param themeId 目标主题 ID
   */
  private async setTheme(themeId: number): Promise<void> {
    const storage: AppStorageManager = AppStorageManager.getInstance();
    await storage.ensureReady();
    const appContext = getContext(this).getApplicationContext();

    try {
      if (isDarkTheme(themeId)) {
        // 选择深色变体：记录当前 colorMode（仅当当前非深色时记录，避免深色→深色覆盖）
        const currentColorMode: number = await storage.getNumber('colorMode', 0);
        if (currentColorMode !== 1) {
          await storage.setNumber('oldColorMode', currentColorMode);
        }
        // 切换到深色模式
        appContext.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
        await storage.setNumber('colorMode', 1);
      } else {
        // 选择亮色主题：从 oldColorMode 恢复之前的颜色模式设置
        const oldColorMode: number = await storage.getNumber('oldColorMode', 0);
        const colorModeValue: number = oldColorMode === 1
          ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK
          : (oldColorMode === 2
            ? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
            : ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
        appContext.setColorMode(colorModeValue);
        await storage.setNumber('colorMode', oldColorMode);
      }
    } catch (err) {
      console.error(`[ThemePage] colorMode linkage failed: ${(err as Error).message}`);
    }

    // 更新主题状态 + 持久化 themeId
    this.themeState.setTheme(themeId);
    try {
      await storage.setNumber('themeId', themeId);
    } catch (err) {
      console.error(`[ThemePage] persist themeId failed: ${(err as Error).message}`);
    }
  }

  build() {
    Column() {
      // 标题栏（与 SettingsPage 一致的样式）
      Row() {
        Image($r('app.media.ic_back'))
          .width(24)
          .height(24)
          .fillColor($r('app.color.text_primary'))
          .syncLoad(true)
          .interpolation(ImageInterpolation.Low)
          .onClick(() => router.back())
        Text($r('app.string.theme_title'))
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .margin({ left: 12 })
      }
      .width('100%')
      .height(this.statusBarHeight + 44)
      .padding({ top: this.statusBarHeight, left: 16, right: 16 })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
      .alignItems(VerticalAlign.Center)
      .backgroundColor($r('app.color.page_background'))

      // 主题列表（可滚动）
      Scroll() {
        Column() {
          // 亮色主题分组标题
          Row() {
            Text($r('app.string.theme_group_light'))
              .fontSize(13)
              .fontColor($r('app.color.text_caption'))
          }
          .width('100%')
          .padding({ top: 20, bottom: 12, left: 16, right: 16 })

          // 亮色主题色块网格
          Grid() {
            ForEach(LIGHT_THEMES, (theme: ThemeConfig) => {
              GridItem() {
                this.ThemeCard(theme)
              }
            }, (theme: ThemeConfig) => theme.themeId.toString())
          }
          .columnsTemplate('1fr 1fr 1fr')
          .columnsGap(12)
          .rowsGap(12)
          .padding({ left: 16, right: 16 })
          .backgroundColor($r('app.color.page_background'))

          // 深色主题变体分组标题
          Row() {
            Text($r('app.string.theme_group_dark'))
              .fontSize(13)
              .fontColor($r('app.color.text_caption'))
          }
          .width('100%')
          .padding({ top: 24, bottom: 12, left: 16, right: 16 })

          // 深色主题变体色块网格
          Grid() {
            ForEach(DARK_THEMES, (theme: ThemeConfig) => {
              GridItem() {
                this.DarkThemeCard(theme)
              }
            }, (theme: ThemeConfig) => theme.themeId.toString())
          }
          .columnsTemplate('1fr 1fr 1fr')
          .columnsGap(12)
          .rowsGap(12)
          .padding({ left: 16, right: 16, bottom: 20 })
          .backgroundColor($r('app.color.page_background'))
        }
        .width('100%')
      }
      .layoutWeight(1)
      .backgroundColor($r('app.color.page_background'))
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  /**
   * 亮色主题色块卡片
   * 展示主题主色预览圆 + 名称 + 选中标记
   */
  @Builder ThemeCard(theme: ThemeConfig) {
    Column() {
      // 主题色预览圆
      Stack() {
        Circle({ width: 48, height: 48 })
          .fill(theme.primary)
        // 选中标记
        if (this.themeState.themeId === theme.themeId) {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .fontSize(24)
            .fontColor([Color.White])
        }
      }
      .width(60)
      .height(60)
      .alignContent(Alignment.Center)

      // 主题名称
      Text(theme.nameRes)
        .fontSize(13)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: 8 })
    }
    .width('100%')
    .padding({ top: 16, bottom: 16 })
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(12)
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      this.setTheme(theme.themeId).catch((err: Error) => {
        console.error(`[ThemePage] setTheme failed: ${err.message}`);
      });
    })
  }

  /**
   * #157 深色主题变体色块卡片
   * 展示深色背景预览 + 主色边框 + 月亮图标 + 名称 + 选中标记
   */
  @Builder DarkThemeCard(theme: ThemeConfig) {
    Column() {
      // 深色背景预览圆 + 月亮图标 + 选中标记
      Stack() {
        // 深色背景圆（展示该变体的背景色）+ 主色边框
        Circle({ width: 48, height: 48 })
          .fill(theme.darkBackground)
          .stroke(theme.primary)
          .strokeWidth(3)
        // 月亮图标（标识深色主题）
        SymbolGlyph($r('sys.symbol.moon'))
          .fontSize(22)
          .fontColor([Color.White])
        // 选中标记（右上角小圆点）
        if (this.themeState.themeId === theme.themeId) {
          Circle({ width: 16, height: 16 })
            .fill(this.themeState.primary)
            .offset({ x: 20, y: -20 })
        }
      }
      .width(60)
      .height(60)
      .alignContent(Alignment.Center)

      // 主题名称
      Text(theme.nameRes)
        .fontSize(13)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: 8 })
    }
    .width('100%')
    .padding({ top: 16, bottom: 16 })
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(12)
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      this.setTheme(theme.themeId).catch((err: Error) => {
        console.error(`[ThemePage] setTheme dark failed: ${err.message}`);
      });
    })
  }
}
