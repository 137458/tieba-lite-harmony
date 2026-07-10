// #156 Theme-1 主题管理器
// 对齐 Android 原版 ThemeUtil.kt 主题切换逻辑
// 6 种亮色预设主题：tieba/blue/black/pink/red/purple
// 主题色通过 AppStorageV2 全局共享，@Trace 变化触发 UI 刷新
//
// 主题色方案包含 primary + primary_light + tab_active 三个关联色
// 背景色/文本色等由深色/浅色模式（colorMode）控制，不随主题切换

import { AppStorageV2 } from '@kit.ArkUI';

// ============================================================================
// 主题 ID 常量（对齐 Android ThemeUtil.kt THEME_* 常量）
// ============================================================================

/** 深海蓝（默认主题，对齐 Android THEME_DEFAULT = "tieba"） */
export const THEME_TIEBA: number = 0;
/** 清新蓝（对齐 Android THEME_BLUE，回退到 tieba 主色） */
export const THEME_BLUE: number = 1;
/** 高级黑（对齐 Android THEME_BLACK） */
export const THEME_BLACK: number = 2;
/** 少女粉（对齐 Android THEME_PINK） */
export const THEME_PINK: number = 3;
/** 新年红（对齐 Android THEME_RED） */
export const THEME_RED: number = 4;
/** 星空紫（对齐 Android THEME_PURPLE） */
export const THEME_PURPLE: number = 5;

// ============================================================================
// 主题配置数据结构
// ============================================================================

/**
 * 单套主题的配色方案
 * 包含主色调及关联色，背景色/文本色由 colorMode 控制
 */
export class ThemeConfig {
  /** 主题 ID */
  themeId: number = THEME_TIEBA;
  /** 主题名称资源 ID */
  nameRes: Resource = $r('app.string.theme_tieba');
  /** 主色（对齐 Android colorPrimary） */
  primary: string = '#4477E0';
  /** 主色 12% 透明度（用于标签/徽章背景，对齐 primary_light） */
  primary_light: string = '#1F4477E0';
  /** Tab 激活色（与主色一致） */
  tab_active: string = '#4477E0';

  constructor(themeId: number, nameRes: Resource, primary: string, primary_light: string, tab_active: string) {
    this.themeId = themeId;
    this.nameRes = nameRes;
    this.primary = primary;
    this.primary_light = primary_light;
    this.tab_active = tab_active;
  }
}

// ============================================================================
// 预设主题列表（对齐 Android styles.xml 主题色定义）
// ============================================================================

/** 6 种亮色预设主题配置 */
export const LIGHT_THEMES: ThemeConfig[] = [
  new ThemeConfig(THEME_TIEBA, $r('app.string.theme_tieba'), '#4477E0', '#1F4477E0', '#4477E0'),
  new ThemeConfig(THEME_BLUE, $r('app.string.theme_blue'), '#4477E0', '#1F4477E0', '#4477E0'),
  new ThemeConfig(THEME_BLACK, $r('app.string.theme_black'), '#000000', '#1F000000', '#000000'),
  new ThemeConfig(THEME_PINK, $r('app.string.theme_pink'), '#FF9A9E', '#1FFF9A9E', '#FF9A9E'),
  new ThemeConfig(THEME_RED, $r('app.string.theme_red'), '#C51100', '#1FC51100', '#C51100'),
  new ThemeConfig(THEME_PURPLE, $r('app.string.theme_purple'), '#512DA8', '#1F512DA8', '#512DA8'),
];

/**
 * 根据主题 ID 获取主题配置
 * @param themeId 主题 ID
 * @returns 主题配置，找不到时返回默认主题（tieba）
 */
export function getThemeConfig(themeId: number): ThemeConfig {
  for (let i = 0; i < LIGHT_THEMES.length; i++) {
    if (LIGHT_THEMES[i].themeId === themeId) {
      return LIGHT_THEMES[i];
    }
  }
  return LIGHT_THEMES[THEME_TIEBA];
}

// ============================================================================
// 主题状态类（AppStorageV2 全局共享）
// ============================================================================

/**
 * 主题状态（@ObservedV2，通过 AppStorageV2 全局共享）
 *
 * 组件通过 AppStorageV2.connect(ThemeState, 'theme', ...) 连接，
 * themeId/primary/primary_light/tab_active 变化时自动触发 UI 刷新。
 *
 * 写入方：ThemePage.setTheme / StartupTask_Theme
 * 订阅方：所有使用主题色的组件（SettingsPage/HomePage/ThreadPage 等）
 */
@ObservedV2
export class ThemeState {
  /** 当前主题 ID */
  @Trace themeId: number = THEME_TIEBA;
  /** 主色（string 类型，可直接用于 fillColor/fontColor 等） */
  @Trace primary: string = '#4477E0';
  /** 主色 12% 透明度（用于背景） */
  @Trace primary_light: string = '#1F4477E0';
  /** Tab 激活色 */
  @Trace tab_active: string = '#4477E0';

  /**
   * 切换主题（更新所有 @Trace 字段，触发 UI 刷新）
   * @param themeId 目标主题 ID
   */
  setTheme(themeId: number): void {
    const config: ThemeConfig = getThemeConfig(themeId);
    this.themeId = config.themeId;
    this.primary = config.primary;
    this.primary_light = config.primary_light;
    this.tab_active = config.tab_active;
  }
}

/**
 * 连接到主题状态（组件辅助函数）
 *
 * 使用方式：
 *   @Local themeState: ThemeState = connectTheme();
 *
 * @returns ThemeState 实例（通过 AppStorageV2 全局共享）
 */
export function connectTheme(): ThemeState {
  return AppStorageV2.connect(ThemeState, 'theme', () => new ThemeState())!;
}
