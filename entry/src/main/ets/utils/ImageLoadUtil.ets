import { CircleShape } from '@kit.ArkUI';

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

// ============================================================================
// A5 图片优化：场景化 @Builder（API 8+）
// ============================================================================
//
// 设计依据：
//   - OpenHarmony 官方 Image 文档 v6.0（alt/syncLoad/sourceSize/interpolation/
//     colorFilter/objectFit/objectRepeat/renderMode/fillColor/autoResize 等）
//   - 华为官方 Image 文档（同步加载、占位图、错误兜底最佳实践）
//   - ImageComponent 示例代码（13 个源码文件 API 使用模式）
//   - ClipShape 通用属性样例（EllipseShape/CircleShape 形状裁剪）
//
// 优化策略（按场景）：
//   | 场景         | syncLoad | alt | sourceSize | interpolation | clipShape | onError |
//   |--------------|----------|-----|------------|---------------|-----------|---------|
//   | 头像         | true     | ✓   | -          | Low           | Circle    | ✓       |
//   | 帖子媒体图   | false    | ✓   | ✓          | High          | -         | ✓       |
//   | 本地 SVG 图标| true     | -   | -          | Low           | -         | -       |
//   | 网络表情图   | false    | ✓   | -          | High          | -         | ✓       |
//
// 说明：
//   - syncLoad(true)：小图同步加载避免闪烁（API 8+，官方推荐本地小图用）
//   - syncLoad(false)：大图/网络图异步加载避免阻塞 UI 线程
//   - alt：加载过程显示占位图（startIcon.png 通用占位）
//   - sourceSize：解码降分辨率，减少内存占用（仅目标尺寸<图源尺寸时生效）
//   - interpolation(High)：大图缩放时缓解锯齿
//   - clipShape(CircleShape)：圆形裁剪，比 borderRadius 更稳定（无抗锯齿问题）
//   - onError：加载失败静默处理，避免白块残留
//   - priority：跳过（华为官方 Image 文档无此属性，ImageComponent README 误写）
// ============================================================================

/**
 * 头像图片 Builder（圆形裁剪 + 同步加载 + 占位图 + 错误兜底）
 *
 * 应用场景：用户头像（小图，对齐 Android AvatarImage.kt）
 *
 * 优化点：
 *   - syncLoad(true)：小图同步加载避免闪烁（API 8+，官方推荐）
 *   - alt：加载过程显示占位图
 *   - objectFit(Cover)：默认填充效果
 *   - clipShape(CircleShape)：圆形裁剪（替代 borderRadius，更稳定）
 *   - onError：加载失败兜底（避免白块）
 *
 * 使用方式：
 *   import { AvatarImage } from '../utils/ImageLoadUtil';
 *   ...
 *   AvatarImage(this.thread.author.avatar, this.imageLoadType, this.isWifi, 36)
 *
 * @param avatar 头像 URL
 * @param imageLoadType 图片加载模式（0/1/2/3）
 * @param isWifi 当前是否 WiFi 网络
 * @param size 头像尺寸（width = height = size，单位 vp）
 */
@Builder
export function AvatarImage(
  avatar: string,
  imageLoadType: number,
  isWifi: boolean,
  size: number
) {
  Image(getAvatarImageUrl(avatar, imageLoadType, isWifi))
    .width(size)
    .height(size)
    .borderRadius(size / 2)
    .syncLoad(true)
    .alt($r('app.media.startIcon'))
    .objectFit(ImageFit.Cover)
    .interpolation(ImageInterpolation.Low)
    .clipShape(new CircleShape({ width: size, height: size }))
    .onError(() => {
      // 头像加载失败静默处理：alt 占位图会自动显示
    });
}

/**
 * 帖子媒体图片 Builder（异步加载 + 解码降采样 + 高质量插值 + 错误兜底）
 *
 * 应用场景：帖子列表/详情页的媒体图片（ThreadCard / ThreadPage）
 *
 * 优化点：
 *   - syncLoad(false)：大图异步加载避免阻塞 UI（官方推荐网络大图异步）
 *   - alt：加载过程显示占位图
 *   - objectFit(Cover)：默认填充效果
 *   - interpolation(High)：缩放时缓解锯齿
 *   - autoResize(true)：根据显示区域自动降采样解码，减少内存（API 9+）
 *   - sourceSize：解码尺寸限制（仅在目标尺寸<图源尺寸时生效）
 *   - onError：加载失败兜底
 *   - onComplete：加载完成回调（可选，调用方可在外部链式追加）
 *
 * 使用方式：
 *   import { PostMediaImage } from '../utils/ImageLoadUtil';
 *   ...
 *   PostMediaImage(thumbnail, url, imageLoadType, isWifi, width, height)
 *
 * @param thumbnail 缩略图 URL
 * @param url 原图 URL
 * @param imageLoadType 图片加载模式（0/1/2/3）
 * @param isWifi 当前是否 WiFi 网络
 * @param width 显示宽度（vp）
 * @param height 显示高度（vp）
 */
@Builder
export function PostMediaImage(
  thumbnail: string,
  url: string,
  imageLoadType: number,
  isWifi: boolean,
  width: number,
  height: number
) {
  Image(getMediaImageUrl(thumbnail, url, imageLoadType, isWifi))
    .width(width)
    .height(height)
    .syncLoad(false)
    .alt($r('app.media.startIcon'))
    .objectFit(ImageFit.Cover)
    .interpolation(ImageInterpolation.High)
    .autoResize(true)
    .sourceSize({ width: Math.ceil(width), height: Math.ceil(height) })
    .onError(() => {
      // 媒体图加载失败静默处理：alt 占位图会自动显示
    });
}

/**
 * 本地 SVG 图标 Builder（同步加载 + 填充色）
 *
 * 应用场景：本地 SVG 图标（ic_back / ic_like / ic_settings 等 $r 引用）
 *
 * 优化点：
 *   - syncLoad(true)：小图同步加载避免闪烁
 *   - objectFit(Contain)：图标完整显示不裁剪
 *   - interpolation(Low)：图标无需高质量插值
 *   - fillColor：填充色（调用方传参，用于状态变色）
 *
 * 使用方式：
 *   import { LocalIconImage } from '../utils/ImageLoadUtil';
 *   ...
 *   LocalIconImage($r('app.media.ic_back'), 24, $r('app.color.primary'))
 *
 * @param src 图片资源（$r('app.media.xxx')）
 * @param size 图标尺寸（width = height = size，单位 vp）
 * @param color 填充颜色（ResourceColor，用于 SVG 着色）
 */
@Builder
export function LocalIconImage(
  src: Resource,
  size: number,
  color: ResourceColor
) {
  Image(src)
    .width(size)
    .height(size)
    .syncLoad(true)
    .objectFit(ImageFit.Contain)
    .interpolation(ImageInterpolation.Low)
    .fillColor(color);
}

/**
 * 网络表情图 Builder（异步加载 + 高质量插值 + 错误兜底）
 *
 * 应用场景：网络表情图（ReplyBox 中的 EmoticonManager 表情）
 *
 * 优化点：
 *   - syncLoad(false)：网络图异步加载避免阻塞 UI
 *   - alt：加载过程显示占位图
 *   - objectFit(Contain)：表情完整显示不裁剪
 *   - interpolation(High)：缩放时缓解锯齿
 *   - onError：加载失败兜底
 *
 * 使用方式：
 *   import { EmojiImage } from '../utils/ImageLoadUtil';
 *   ...
 *   EmojiImage(EmoticonManager.getEmoticonUrl(emoticon.id), 32)
 *
 * @param url 表情图 URL
 * @param size 表情尺寸（width = height = size，单位 vp）
 */
@Builder
export function EmojiImage(url: string, size: number) {
  Image(url)
    .width(size)
    .height(size)
    .syncLoad(false)
    .alt($r('app.media.startIcon'))
    .objectFit(ImageFit.Contain)
    .interpolation(ImageInterpolation.High)
    .onError(() => {
      // 表情图加载失败静默处理：alt 占位图会自动显示
    });
}
