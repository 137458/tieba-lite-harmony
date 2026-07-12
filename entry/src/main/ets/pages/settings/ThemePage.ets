// #156 Theme-1 主题选择页
// #157 Theme-2 新增深色主题变体分组 + colorMode 联动
// #158 Theme-3 新增动态取色开关（从头像提取主色）
// #170 [A4-S2'] HdsNavDestination + titleBar（滚动动态模糊 + 沉浸光感）
// 展示 6 种亮色预设 + 3 种深色变体主题色块预览，点击切换主题
// 主题色通过 AppStorageV2 ThemeState 全局共享，切换后实时生效
//
// colorMode 联动逻辑（对齐 Android ThemeUtil.switchTheme 三键联动模型）：
//   - 选择深色变体：记录当前 colorMode 到 oldColorMode，切换到 colorMode=1（深色）
//   - 选择亮色主题：从 oldColorMode 恢复之前的 colorMode 设置
//
// #158 动态取色：
//   - 开启：从头像 portrait 下载图片 → effectKit 提取主色 → setDynamicColor
//   - 关闭：恢复到之前持久化的预设主题 themeId

import { ConfigurationConstant } from '@kit.AbilityKit';
import { HdsNavDestination, ScrollEffectType, hdsMaterial } from '@kit.UIDesignKit';
import { getResourceString } from '../../utils/ResourceUtil';
import { AppStorageManager } from '../../data/AppStorage';
import { extractAvatarColor, toPrimaryLight } from '../../utils/DynamicColorUtil';
import {
  ThemeState,
  ThemeConfig,
  connectTheme,
  LIGHT_THEMES,
  DARK_THEMES,
  isDarkTheme,
  THEME_TIEBA
} from '../../theme/ThemeManager';
import { VibratorUtil } from '../../utils/VibratorUtil';

// #162 [A4-S2] Navigation 路由表 @Builder：供 router_map.json 的 buildFunction 引用
@Builder
export function ThemePageBuilder() {
  ThemePage()
}

@ComponentV2
export struct ThemePage {
  /** 主题状态（AppStorageV2 全局共享） */
  @Local themeState: ThemeState = connectTheme();
  /** #158 动态取色开关状态 */
  @Local dynamicColorEnabled: boolean = false;
  /** #158 动态取色提取中（防抖） */
  @Local dynamicColorLoading: boolean = false;
  /** #157 当前系统颜色模式（0=跟随系统 1=深色 2=浅色），与 AppStorageManager 持久化值保持同步 */
  @Local colorMode: number = 0;
  /** 组件销毁标志：async await 后检查，避免写入已销毁组件的 @Local 触发 "state lock on destroyed component" 告警 */
  @Local isDestroyed: boolean = false;
  /** #170 滚动器，绑定到 HdsNavDestination.bindToScrollable 实现标题栏滚动动态模糊 */
  private scroller: Scroller = new Scroller();

  async aboutToAppear(): Promise<void> {
    try {
      // #158 读取动态取色开关偏好
      const storage: AppStorageManager = AppStorageManager.getInstance();
      await storage.ensureReady();
      if (this.isDestroyed) return;
      // P2 #5：await 后赋值 @Local 前必须检查 isDestroyed，避免写入已销毁组件触发告警
      const persistedColorMode: number = await storage.getNumber('colorMode', 0);
      if (this.isDestroyed) return;
      this.colorMode = persistedColorMode;
      const persistedDynamicEnabled: boolean = await storage.getBoolean('dynamicColorEnabled', false);
      if (this.isDestroyed) return;
      this.dynamicColorEnabled = persistedDynamicEnabled;

      // #158 如果动态取色已开启，重新提取头像颜色（头像可能已变化）
      if (this.dynamicColorEnabled) {
        const portrait: string = await storage.getString('avatar', '');
        if (this.isDestroyed) return;
        if (portrait.length > 0) {
          const primaryHex: string | null = await extractAvatarColor(portrait);
          // 销毁保护：extractAvatarColor 是异步 HTTP 取色（最长 5s），await 后组件可能已销毁，
          // 写入 @Local/@State 会触发 "state lock on destroyed component" 告警
          if (this.isDestroyed) return;
          // 竞态修复：extractAvatarColor 期间用户可能在 Toggle 上关闭动态取色
          // （onDynamicColorToggle(false) 已 setTheme 回预设 + 置 dynamicColorEnabled=false）。
          // 若不二次校验，aboutToAppear 的延迟结果会调用 setDynamicColor 覆盖用户刚执行的
          // 关闭操作，导致 Toggle 显示 OFF 但 UI 仍为动态色。
          if (primaryHex !== null && this.dynamicColorEnabled) {
            const primaryLightHex: string = toPrimaryLight(primaryHex);
            this.themeState.setDynamicColor(primaryHex, primaryLightHex);
          }
        }
      }
    } catch (err) {
      console.error(`[ThemePage] aboutToAppear failed: ${(err as Error).message}`);
    }
  }

  aboutToDisappear(): void {
    // #158 销毁标志：供 async 方法 await 后检查，避免写入已销毁组件的 @Local
    this.isDestroyed = true;
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
        // 销毁保护：await 期间组件可能已销毁，避免写入 @Local colorMode 触发告警
        if (this.isDestroyed) return;
        // 切换到深色模式：三处同步 ①@Local colorMode ②appContext.setColorMode ③storage 持久化
        appContext.setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
        this.colorMode = 1;
        await storage.setNumber('colorMode', 1);
      } else {
        // 选择亮色主题：从 oldColorMode 恢复之前的颜色模式设置
        const oldColorMode: number = await storage.getNumber('oldColorMode', 0);
        // 销毁保护：await 期间组件可能已销毁，避免写入 @Local colorMode 触发告警
        if (this.isDestroyed) return;
        const colorModeValue: number = oldColorMode === 1
          ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK
          : (oldColorMode === 2
            ? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
            : ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
        appContext.setColorMode(colorModeValue);
        this.colorMode = oldColorMode;
        await storage.setNumber('colorMode', oldColorMode);
      }
    } catch (err) {
      console.error(`[ThemePage] colorMode linkage failed: ${(err as Error).message}`);
    }

    // P2 #6：themeState 是全局 AppStorageV2（connectTheme），不依赖当前组件生命周期，
    // 即使组件销毁也应执行 setTheme，否则 setColorMode 已改但主题色未更新导致状态不一致。
    // 移除原 isDestroyed 提前 return，让 setTheme 总是执行。
    this.themeState.setTheme(themeId);
    try {
      await storage.setNumber('themeId', themeId);
      if (this.isDestroyed) return;
      // #158 切换预设主题时自动关闭动态取色
      if (this.dynamicColorEnabled) {
        this.dynamicColorEnabled = false;
        await storage.setBoolean('dynamicColorEnabled', false);
      }
    } catch (err) {
      console.error(`[ThemePage] persist themeId failed: ${(err as Error).message}`);
    }
  }

  /**
   * #158 动态取色开关切换
   *
   * 开启流程：
   *   1. 从 AppStorageManager 读取头像 portrait
   *   2. 调用 extractAvatarColor 下载头像 + effectKit 提取主色
   *   3. 成功：setDynamicColor 应用提取的颜色 + 持久化 dynamicColorEnabled=true
   *   4. 失败：恢复开关为 false + Toast 提示
   *
   * 关闭流程：
   *   1. 从 AppStorageManager 读取之前持久化的 themeId
   *   2. setTheme 恢复到预设主题 + 持久化 dynamicColorEnabled=false
   *
   * @param isOn 开关目标状态
   */
  private async onDynamicColorToggle(isOn: boolean): Promise<void> {
    if (this.dynamicColorLoading) {
      return;
    }
    this.dynamicColorLoading = true;
    const storage: AppStorageManager = AppStorageManager.getInstance();
    await storage.ensureReady();
    if (this.isDestroyed) return;

    try {
      if (isOn) {
        // 开启动态取色：从头像提取主色
        const portrait: string = await storage.getString('avatar', '');
        if (this.isDestroyed) return;
        if (portrait.length === 0) {
          this.getUIContext().getPromptAction().showToast({
            message: getResourceString($r('app.string.theme_dynamic_color_no_avatar'))
          });
          this.dynamicColorEnabled = false;
          return;
        }
        const primaryHex: string | null = await extractAvatarColor(portrait);
        // 销毁保护：extractAvatarColor 异步取色（最长 5s），await 后组件可能已销毁
        if (this.isDestroyed) return;
        if (primaryHex === null) {
          this.getUIContext().getPromptAction().showToast({
            message: getResourceString($r('app.string.theme_dynamic_color_failed'))
          });
          this.dynamicColorEnabled = false;
          return;
        }
        // 应用动态取色
        const primaryLightHex: string = toPrimaryLight(primaryHex);
        this.themeState.setDynamicColor(primaryHex, primaryLightHex);
        this.dynamicColorEnabled = true;
        await storage.setBoolean('dynamicColorEnabled', true);
      } else {
        // 关闭动态取色：恢复到之前持久化的预设主题
        const themeId: number = await storage.getNumber('themeId', THEME_TIEBA);
        if (this.isDestroyed) return;
        this.themeState.setTheme(themeId);
        this.dynamicColorEnabled = false;
        await storage.setBoolean('dynamicColorEnabled', false);
      }
    } catch (err) {
      console.error(`[ThemePage] onDynamicColorToggle failed: ${(err as Error).message}`);
      if (!this.isDestroyed) {
        this.dynamicColorEnabled = false;
      }
    } finally {
      if (!this.isDestroyed) {
        this.dynamicColorLoading = false;
      }
    }
  }

  build() {
    // #170 [A4-S2'] HdsNavDestination 包装：titleBar 滚动动态模糊 + 沉浸光感材质
    // titleBar 配置 GRADIENT_BLUR 渐变模糊 + ADAPTIVE 自适应材质，bindToScrollable 绑定 Scroll
    HdsNavDestination() {
      Column() {
        // #158 动态取色开关卡片
        Row() {
          Column() {
            Text($r('app.string.theme_dynamic_color'))
              .fontSize(15)
              .fontColor($r('app.color.text_primary'))
            Text($r('app.string.theme_dynamic_color_desc'))
              .fontSize(12)
              .fontColor($r('app.color.text_caption'))
              .margin({ top: 4 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Toggle({ type: ToggleType.Switch, isOn: this.dynamicColorEnabled })
            .selectedColor(this.themeState.primary)
            .onChange((isOn: boolean) => {
              VibratorUtil.light();
              this.onDynamicColorToggle(isOn).catch((err: Error) => {
                console.error(`[ThemePage] onDynamicColorToggle failed: ${err.message}`);
              });
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 16, bottom: 16 })
        .margin({ left: 16, right: 16, top: 12 })
        .backgroundColor($r('app.color.card_background'))
        .borderRadius(10)

        // 主题列表（可滚动，绑定 scroller 联动 titleBar 模糊）
        Scroll(this.scroller) {
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
    .titleBar({
      content: {
        title: {
          mainTitle: $r('app.string.theme_title')
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
      avoidLayoutSafeArea: true
    })
    .bindToScrollable([this.scroller])
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
