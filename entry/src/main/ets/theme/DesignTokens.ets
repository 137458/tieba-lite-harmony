// 设计令牌（Design Tokens）单一事实源
// 统一圆角/阴影/间距/字阶，替代散落各页面的魔术数字
// 原则：
//   - 圆角体系：小元素 8 / 标签 Chip 999 / 卡片 16 / 浮层 20，禁止 10/12 混用
//   - 阴影体系：三级海拔（卡片 resting / 悬浮件 raised / 弹层 overlay），颜色带透明度，禁止纯黑
//   - 间距体系：4 的倍数，页面左右安全边距 16，区块间距 12/16/24

/** 页面左右安全边距（vp） */
export const SPACE_PAGE: number = 16;
/** 卡片内边距（vp） */
export const SPACE_CARD: number = 16;
/** 同组元素间距（vp） */
export const SPACE_ITEM: number = 8;
/** 区块间距（vp） */
export const SPACE_BLOCK: number = 12;
/** 大区块间距（vp） */
export const SPACE_SECTION: number = 24;

/** 小元素圆角：输入框内嵌、缩略图（vp） */
export const RADIUS_SM: number = 8;
/** 卡片圆角（vp） */
export const RADIUS_CARD: number = 16;
/** 浮层圆角：弹窗/抽屉/悬浮底栏（vp） */
export const RADIUS_OVERLAY: number = 20;
/** 胶囊标签圆角（vp） */
export const RADIUS_PILL: number = 999;

/**
 * 卡片静止态阴影：柔和环境光 + 低强度投影
 * 替代原 radius 8 + #18000000 的硬阴影
 */
export const SHADOW_CARD: ShadowOptions = {
  radius: 16,
  color: '#14000000',
  offsetX: 0,
  offsetY: 4
};

/**
 * 悬浮件阴影（悬浮底栏/FAB 级别）：海拔更高，投影更实
 */
export const SHADOW_RAISED: ShadowOptions = {
  radius: 24,
  color: '#1F000000',
  offsetX: 0,
  offsetY: 8
};
