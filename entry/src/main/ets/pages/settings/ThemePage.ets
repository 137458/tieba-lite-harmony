// #156 Theme-1 主题选择页
// #238 简化：删除 3 种深色主题变体（用户反馈"三个深色主题都没有变化"），
//         深色模式由 SettingsPage 的"颜色"开关单独控制，主题选择只改主题色不改 colorMode
// #158 Theme-3 新增动态取色开关（从头像提取主色）
// #170 [A4-S2'] HdsNavDestination + titleBar（滚动动态模糊 + 沉浸光感）
// 展示 6 种亮色预设主题色块预览，点击切换主题色
// 主题色通过 AppStorageV2 ThemeState 全局共享，切换后实时生效
//
// #238 简化后的主题选择不再联动 colorMode：
//   - 主题选择只改 primary/primary_light/tab_active 三个主题色
//   - 深色/浅色模式由 SettingsPage 的"颜色"菜单独立控制
//   - 删除 oldColorMode 联动逻辑，避免"选亮色主题仍显示深色模式"的状态同步问题

import { HdsNavDestination, ScrollEffectType, hdsMaterial } from '@kit.UIDesignKit';
import { getResourceString } from '../../utils/ResourceUtil';
import { AppStorageManager } from '../../data/AppStorage';
import { MaterialLevelState, connectMaterialLevel, resolveMaterialLevel, MATERIAL_TYPE_IMMERSIVE } from '../../model/AppStorageV2Models';
import { extractAvatarColor, toPrimaryLight } from '../../utils/DynamicColorUtil';
import {
  ThemeState,
  ThemeConfig,
  connectTheme,
  LIGHT_THEMES,
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
  // #201 沉浸光感材质强度档位（与 MainPage 共享，SettingsPage 修改后自动响应）
  @Local materialLevelState: MaterialLevelState = connectMaterialLevel();
  /** #158 动态取色开关状态 */
  @Local dynamicColorEnabled: boolean = false;
  /** #158 动态取色提取中（防抖） */
  @Local dynamicColorLoading: boolean = false;
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
   * #238 简化后的切换主题：只改主题色 + 持久化 themeId，不再联动 colorMode
   *
   * 简化原因：用户反馈"三个深色主题都没有变化"（实际是 darkBackground 仅用于预览，
   * 主色相同所以视觉无差异），且 oldColorMode 联动逻辑导致"选亮色主题仍显示深色模式"。
   * 简化后：深色/浅色模式由 SettingsPage 的"颜色"菜单独立控制，主题选择只改主题色。
   *
   * @param themeId 目标主题 ID
   */
  private async setTheme(themeId: number): Promise<void> {
    const storage: AppStorageManager = AppStorageManager.getInstance();
    await storage.ensureReady();

    // P2 #6：themeState 是全局 AppStorageV2（connectTheme），不依赖当前组件生命周期，
    // 即使组件销毁也应执行 setTheme，否则主题色未更新导致状态不一致。
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
      // 主题列表（可滚动，绑定 scroller 联动 titleBar 模糊）
      Scroll(this.scroller) {
        Column() {
          // #158 动态取色开关卡片（移到 Scroll 内，避免跑到 titleBar/状态栏区域）
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
          .margin({ top: 0 })
          .backgroundColor($r('app.color.card_background'))
          .borderRadius(10)

          // 亮色主题分组标题
          Row() {
            Text($r('app.string.theme_group_light'))
              .fontSize(13)
              .fontColor($r('app.color.text_caption'))
          }
          .width('100%')
          .padding({ top: 20, bottom: 12 })

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
          .padding({ bottom: 20 })
          .backgroundColor($r('app.color.page_background'))
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
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
          materialType: MATERIAL_TYPE_IMMERSIVE,
          materialLevel: resolveMaterialLevel(this.materialLevelState.value)
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
        if (!this.dynamicColorEnabled && this.themeState.themeId === theme.themeId) {
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
}
