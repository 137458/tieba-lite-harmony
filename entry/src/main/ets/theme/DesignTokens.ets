// 设计令牌（Design Tokens）单一事实源
// 统一圆角/描边/间距/字阶，替代散落各页面的魔术数字
// 原则：
//   - 圆角体系：小元素 8 / 标签 Chip 999 / 卡片 16 / 浮层 20，禁止 10/12 混用
//   - 卡片分层：只用「页面底色 vs 卡片底色差 + 0.5vp 发丝描边」定义边界，禁止投影
//     依据：Android 原版 TiebaLite 的 FeedCard 无 elevation，HDS 官方 HdsListItemCard
//     同样只用背景色 + 圆角 + 状态反馈；纯色底上叠投影会糊成灰晕，反而显廉价
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
 * 卡片发丝描边线宽（vp）
 * 卡片边界定义手段：页面底色与卡片底色差不足时，用 0.5vp 描边补一条清晰边缘，
 * 替代原先的柔和投影（投影在浅色纯底上会形成灰晕，视觉上更廉价）
 * 描边颜色直接复用 app.color.divider，自动适配亮/暗色
 */
export const BORDER_HAIRLINE: number = 0.5;
