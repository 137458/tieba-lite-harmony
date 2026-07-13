// #156 Theme-1 主题管理器
// #157 Theme-2 新增 3 种深色主题变体 + colorMode 联动
// 对齐 Android 原版 ThemeUtil.kt 主题切换逻辑
// 6 种亮色预设主题：tieba/blue/black/pink/red/purple
// 3 种深色主题变体：blue_dark/grey_dark/amoled_dark（主色均为 #4477E0，差异在背景色）
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
/** #157 静谧蓝深色变体（对齐 Android THEME_BLUE_DARK，背景 #17212B） */
export const THEME_BLUE_DARK: number = 6;
/** #157 深邃灰深色变体（对齐 Android THEME_GREY_DARK，背景 #202020） */
export const THEME_GREY_DARK: number = 7;
/** #157 纯黑深色变体（对齐 Android THEME_AMOLED_DARK，背景 #000000） */
export const THEME_AMOLED_DARK: number = 8;
/** #158 动态取色主题（从头像提取主色，非预设主题） */
export const THEME_DYNAMIC: number = 100;

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
  /** #157 是否深色主题变体（true 时选择该主题需联动 colorMode=1） */
  isDark: boolean = false;
  /** #157 深色变体背景色（仅 isDark=true 时有效，用于 ThemePage 预览展示） */
  darkBackground: string = '#000000';

  constructor(
    themeId: number,
    nameRes: Resource,
    primary: string,
    primary_light: string,
    tab_active: string,
    isDark: boolean = false,
    darkBackground: string = '#000000'
  ) {
    this.themeId = themeId;
    this.nameRes = nameRes;
    this.primary = primary;
    this.primary_light = primary_light;
    this.tab_active = tab_active;
    this.isDark = isDark;
    this.darkBackground = darkBackground;
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
 * #157 3 种深色主题变体配置
 * 对齐 Android TiebaLite.Dark.Blue/Grey/Amoled：
 *   - 主色均为 #4477E0（贴吧蓝）
 *   - 背景色差异：blue_dark(#17212B 蓝灰) / grey_dark(#202020 纯灰) / amoled_dark(#000000 纯黑)
 *   - 选择深色变体时联动 colorMode=1（深色模式），背景色/文本色由系统深色模式控制
 *   - darkBackground 字段仅用于 ThemePage 预览展示
 */
export const DARK_THEMES: ThemeConfig[] = [
  new ThemeConfig(THEME_BLUE_DARK, $r('app.string.theme_blue_dark'), '#4477E0', '#1F4477E0', '#4477E0', true, '#17212B'),
  new ThemeConfig(THEME_GREY_DARK, $r('app.string.theme_grey_dark'), '#4477E0', '#1F4477E0', '#4477E0', true, '#202020'),
  new ThemeConfig(THEME_AMOLED_DARK, $r('app.string.theme_amoled_dark'), '#4477E0', '#1F4477E0', '#4477E0', true, '#000000'),
];

/**
 * 根据主题 ID 获取主题配置（搜索亮色 + 深色变体）
 * @param themeId 主题 ID
 * @returns 主题配置，找不到时返回默认主题（tieba）
 */
export function getThemeConfig(themeId: number): ThemeConfig {
  let i: number = 0;
  for (i = 0; i < LIGHT_THEMES.length; i++) {
    if (LIGHT_THEMES[i].themeId === themeId) {
      return LIGHT_THEMES[i];
    }
  }
  for (i = 0; i < DARK_THEMES.length; i++) {
    if (DARK_THEMES[i].themeId === themeId) {
      return DARK_THEMES[i];
    }
  }
  return LIGHT_THEMES[THEME_TIEBA];
}

/**
 * #157 判断主题 ID 是否为深色主题变体
 * 对齐 Android ThemeUtil.isNightMode（主题名含 "dark"）
 * @param themeId 主题 ID
 * @returns true=深色变体 false=亮色主题
 */
export function isDarkTheme(themeId: number): boolean {
  return themeId === THEME_BLUE_DARK || themeId === THEME_GREY_DARK || themeId === THEME_AMOLED_DARK;
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

  /**
   * #158 设置动态取色主题（从头像提取的颜色覆盖预设主题色）
   * @param primaryHex 提取的主色 hex 字符串（如 '#4477E0'）
   * @param primaryLightHex 主色 12% 透明度 hex 字符串（如 '#1F4477E0'）
   */
  setDynamicColor(primaryHex: string, primaryLightHex: string): void {
    this.themeId = THEME_DYNAMIC;
    this.primary = primaryHex;
    this.primary_light = primaryLightHex;
    this.tab_active = primaryHex;
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
  // #176 AppStorageV2.connect 失败返回 undefined，判空 + 日志 + 兜底 new 实例
  const state: ThemeState | undefined = AppStorageV2.connect(
    ThemeState, 'theme', () => new ThemeState()
  );
  if (state === undefined) {
    console.error('[AppStorageV2] connect ThemeState returned undefined, fallback to new instance');
    return new ThemeState();
  }
  return state;
}
