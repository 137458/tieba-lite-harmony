// #156 Theme-1 主题选择页
// 展示 6 种亮色预设主题色块预览，点击切换主题
// 主题色通过 AppStorageV2 ThemeState 全局共享，切换后实时生效

import { router } from '@kit.ArkUI';
import { getStatusBarHeight } from '../../utils/StatusBarUtil';
import { AppStorageManager } from '../../data/AppStorage';
import {
  ThemeState,
  ThemeConfig,
  connectTheme,
  LIGHT_THEMES
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
   * 切换主题并持久化
   * @param themeId 目标主题 ID
   */
  private async setTheme(themeId: number): Promise<void> {
    this.themeState.setTheme(themeId);
    try {
      await AppStorageManager.getInstance().setNumber('themeId', themeId);
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

      // 主题色块网格
      Grid() {
        ForEach(LIGHT_THEMES, (theme: ThemeConfig) => {
          GridItem() {
            this.ThemeCard(theme)
          }
        }, (theme: ThemeConfig) => theme.themeId.toString())
      }
      .columnsTemplate('1fr 1fr')
      .columnsGap(16)
      .rowsGap(16)
      .padding({ left: 16, right: 16, top: 20 })
      .layoutWeight(1)
      .backgroundColor($r('app.color.page_background'))
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  /**
   * 单个主题色块卡片
   * 展示主题主色预览 + 名称 + 选中标记
   */
  @Builder ThemeCard(theme: ThemeConfig) {
    Column() {
      // 主题色预览圆
      Stack() {
        Circle({ width: 56, height: 56 })
          .fill(theme.primary)
        // 选中标记
        if (this.themeState.themeId === theme.themeId) {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .fontSize(28)
            .fontColor([Color.White])
        }
      }
      .width(72)
      .height(72)
      .alignContent(Alignment.Center)

      // 主题名称
      Text(theme.nameRes)
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: 8 })
    }
    .width('100%')
    .padding({ top: 20, bottom: 20 })
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(12)
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      this.setTheme(theme.themeId).catch((err: Error) => {
        console.error(`[ThemePage] setTheme failed: ${err.message}`);
      });
    })
  }
}
