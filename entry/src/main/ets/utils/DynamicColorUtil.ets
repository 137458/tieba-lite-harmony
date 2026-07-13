// #158 Theme-3 动态取色工具
// 从头像图片 URL 提取主色，用于伪 Material You 动态主题
//
// 实现流程：
//   1. HTTP 下载头像图片 → ArrayBuffer
//   2. image.createImageSource → createPixelMap
//   3. effectKit.createColorPicker → getLargestProportionColor()
//   4. Color (ARGB number) → hex 字符串 (#RRGGBB)
//
// API 参考：
//   - effectKit: @kit.ArkGraphics2D, API 9+
//   - image: @kit.ImageKit
//   - http: @kit.NetworkKit
//   - getLargestProportionColor: API 10+（同步返回 Color）

import { http } from '@kit.NetworkKit';
import { image } from '@kit.ImageKit';
import { effectKit } from '@kit.ArkGraphics2D';
import { BusinessError } from '@kit.BasicServicesKit';
import { getAvatarUrl } from './AvatarUtil';

/**
 * 从头像 portrait 标识符提取主色
 *
 * @param portrait 百度用户头像标识符（存储在 AppStorageManager key='avatar'）
 * @returns hex 颜色字符串（如 '#4477E0'），失败时返回 null
 */
export async function extractAvatarColor(portrait: string): Promise<string | null> {
  const avatarUrl: string = getAvatarUrl(portrait, 's');
  if (avatarUrl.length === 0) {
    console.warn('[DynamicColorUtil] avatar portrait is empty');
    return null;
  }

  try {
    // 1. HTTP 下载头像图片
    // 资源泄漏修复：request() 可能在超时/网络错误时抛出，原代码仅在成功路径调用 destroy()，
    // 失败时 httpInstance 泄漏。改用 try-finally 保证 destroy() 总被调用（对齐 HttpClient.ets 模式）。
    const httpInstance = http.createHttp();
    try {
      const response = await httpInstance.request(avatarUrl, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: 5000,
        readTimeout: 5000
      });

      const buffer: ArrayBuffer = response.result as ArrayBuffer;
      if (buffer.byteLength === 0) {
        console.warn('[DynamicColorUtil] downloaded image buffer is empty');
        return null;
      }

      // 2. 创建 ImageSource → PixelMap
      const imageSource: image.ImageSource = image.createImageSource(buffer);
      const pixelMap: image.PixelMap = await imageSource.createPixelMap({
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888
      });

      // 资源泄漏修复：createColorPicker/getLargestProportionColor/colorToHex 抛出时
      // pixelMap 不会 release，PixelMap 持有原生位图内存，重复泄漏可致 OOM。
      // 改用 try-finally 保证 release() 总被调用。
      try {
        // 3. effectKit 取色
        const colorPicker: effectKit.ColorPicker = await effectKit.createColorPicker(pixelMap);
        const color: effectKit.Color = colorPicker.getLargestProportionColor();

        // 4. 转换为 hex 字符串
        const hex: string = colorToHex(color);

        console.info(`[DynamicColorUtil] extracted color: ${hex} from portrait: ${portrait.substring(0, 10)}...`);
        return hex;
      } finally {
        pixelMap.release();
        imageSource.release();
      }
    } finally {
      httpInstance.destroy();
    }
  } catch (err) {
    console.error(`[DynamicColorUtil] extractAvatarColor failed: ${(err as BusinessError).code} ${(err as BusinessError).message}`);
    return null;
  }
}

/**
 * 将 effectKit.Color 转换为 hex 字符串 (#RRGGBB)
 * 忽略 alpha 通道，仅取 RGB
 */
function colorToHex(color: effectKit.Color): string {
  const r: string = color.red.toString(16).padStart(2, '0');
  const g: string = color.green.toString(16).padStart(2, '0');
  const b: string = color.blue.toString(16).padStart(2, '0');
  return `#${r}${g}${b}`.toUpperCase();
}

/**
 * 生成主色 12% 透明度的前景色（用于 primary_light）
 * 格式：#1F + RRGGBB（对齐 ThemeConfig.primary_light 格式）
 *
 * @param primaryHex 主色 hex 字符串（如 '#4477E0'）
 * @returns 12% 透明度 hex 字符串（如 '#1F4477E0'）
 */
export function toPrimaryLight(primaryHex: string): string {
  // 去掉开头的 '#'
  const hex: string = primaryHex.startsWith('#') ? primaryHex.substring(1) : primaryHex;
  return `#1F${hex}`.toUpperCase();
}
