// 图片加载策略工具（对齐 Android TiebaLite-4.0-dev ImageUtil.kt:492-498, 563-568）
// 4 档省流模式（对齐 Android image_load_type）：
//   0 = 智能原图：WiFi 加载原图，移动网络加载小图
//   1 = 智能无图：移动网络不加载，WiFi 加载小图
//   2 = 始终原图：始终加载原图
//   3 = 始终无图：始终不加载
//
// 加载策略矩阵（shouldLoad × shouldLoadOrigin）：
// | imageLoadType | isWifi | shouldLoad | shouldLoadOrigin |
// |---------------|--------|------------|------------------|
// | 0 智能原图     | true   | true       | true（原图）      |
// | 0 智能原图     | false  | true       | false（小图）     |
// | 1 智能无图     | true   | true       | false（小图）     |
// | 1 智能无图     | false  | false      | -（不加载）       |
// | 2 始终原图     | true   | true       | true（原图）      |
// | 2 始终原图     | false  | true       | true（原图）      |
// | 3 始终无图     | true   | false      | -（不加载）       |
// | 3 始终无图     | false  | false      | -（不加载）       |
//
// 注：SMART_NO(1) + WiFi 加载小图而非原图，依据 Android ImageUtil.kt:563-568 needReverse 逻辑
//     Android 端该模式叫 SETTINGS_SMART_LOAD，needReverse 在 SMART_LOAD + WiFi 下返回 true
//     （用更高质量小图），但仍是小图非原图

/** 图片加载模式：智能原图（默认，WiFi 原图/移动网络小图） */
export const IMAGE_LOAD_SMART_ORIGIN: number = 0;
/** 图片加载模式：智能无图（移动网络不加载，WiFi 加载小图） */
export const IMAGE_LOAD_SMART_NO: number = 1;
/** 图片加载模式：始终原图（任何网络都加载原图） */
export const IMAGE_LOAD_ALL_ORIGIN: number = 2;
/** 图片加载模式：始终无图（任何网络都不加载） */
export const IMAGE_LOAD_ALL_NO: number = 3;

/**
 * 判断是否应该加载图片
 *
 * 对齐 Android ImageUtil.kt:492-498 的加载判断逻辑：
 * - ALL_NO(3)：始终不加载
 * - SMART_NO(1)：仅 WiFi 加载
 * - SMART_ORIGIN(0) / ALL_ORIGIN(2)：始终加载
 *
 * @param imageLoadType 图片加载模式（0/1/2/3）
 * @param isWifi 当前是否 WiFi 网络
 * @returns true=加载图片，false=不加载（显示占位图）
 */
export function shouldLoad(imageLoadType: number, isWifi: boolean): boolean {
  if (imageLoadType === IMAGE_LOAD_ALL_NO) {
    return false;
  }
  if (imageLoadType === IMAGE_LOAD_SMART_NO) {
    return isWifi;
  }
  // IMAGE_LOAD_SMART_ORIGIN(0) 和 IMAGE_LOAD_ALL_ORIGIN(2) 始终加载
  return true;
}

/**
 * 判断是否应该加载原图（否则加载小图）
 *
 * 对齐 Android ImageUtil.kt:563-568 needReverse 逻辑：
 * - ALL_ORIGIN(2)：始终原图
 * - SMART_ORIGIN(0) + WiFi：原图
 * - SMART_ORIGIN(0) + 非WiFi：小图
 * - SMART_NO(1) + WiFi：小图（needReverse=true，用高质量小图但仍非原图）
 *
 * 防御性检查：shouldLoad=false 时（ALL_NO 或 SMART_NO+非WiFi）直接返回 false，
 * 避免调用方误用时返回错误结果（如 ALL_NO 误返回小图而非不加载）
 *
 * @param imageLoadType 图片加载模式（0/1/2/3）
 * @param isWifi 当前是否 WiFi 网络
 * @returns true=加载原图，false=加载小图
 */
export function shouldLoadOrigin(imageLoadType: number, isWifi: boolean): boolean {
  // 防御性检查：shouldLoad=false 时不应加载原图，直接返回 false
  if (!shouldLoad(imageLoadType, isWifi)) {
    return false;
  }
  if (imageLoadType === IMAGE_LOAD_ALL_ORIGIN) {
    return true;
  }
  if (imageLoadType === IMAGE_LOAD_SMART_ORIGIN && isWifi) {
    return true;
  }
  // SMART_ORIGIN + 非WiFi → 小图
  // SMART_NO + WiFi → 小图
  return false;
}

/**
 * 获取帖子媒体图片 URL
 *
 * 调用方：ThreadCard / ThreadPage 等含媒体图片的组件
 *
 * @param thumbnail 缩略图 URL（可能为空字符串）
 * @param url 原图 URL
 * @param imageLoadType 图片加载模式（0/1/2/3）
 * @param isWifi 当前是否 WiFi 网络
 * @returns 图片 URL；shouldLoad=false 时返回空字符串（Image 组件显示 alt 占位图）
 */
export function getMediaImageUrl(
  thumbnail: string,
  url: string,
  imageLoadType: number,
  isWifi: boolean
): string {
  if (!shouldLoad(imageLoadType, isWifi)) {
    return '';
  }
  if (shouldLoadOrigin(imageLoadType, isWifi)) {
    return url;
  }
  return thumbnail.length > 0 ? thumbnail : url;
}

/**
 * 获取头像 URL
 *
 * 头像本身是小图，无需 shouldLoadOrigin 判断，仅根据 shouldLoad 决定是否加载
 *
 * @param avatar 头像 URL
 * @param imageLoadType 图片加载模式（0/1/2/3）
 * @param isWifi 当前是否 WiFi 网络
 * @returns 头像 URL；shouldLoad=false 时返回空字符串（Image 组件显示 alt 占位图）
 */
export function getAvatarImageUrl(
  avatar: string,
  imageLoadType: number,
  isWifi: boolean
): string {
  if (!shouldLoad(imageLoadType, isWifi)) {
    return '';
  }
  return avatar;
}
