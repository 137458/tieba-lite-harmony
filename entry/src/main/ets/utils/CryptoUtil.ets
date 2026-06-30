import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { heliosHash } from './helios/Hasher';
import { base32Encode } from './helios/Base32';
import { AppStorageManager } from '../data/AppStorage';

export class CryptoUtil {
  private static readonly ZID_KEY: string = 'tiebaclient!!!';
  private static readonly DEVICE_ID_KEY: string = 'device_id';

  /**
   * 获取或创建设备标识
   *
   * 替代 Android Settings.Secure.ANDROID_ID（HarmonyOS 无等效 API）。
   * 策略：首次调用生成随机 UUID（去除连字符得到 32 位 hex），持久化到 preferences；
   * 后续调用直接读取。保证同一设备同一应用包名下 cuid 稳定。
   *
   * 选择持久化 UUID 而非 OAID 的原因：
   * - OAID 需要用户授权 ohos.permission.APP_TRACKING_CONSENT，可能返回全零字符串
   * - 持久化 UUID 始终可用，无权限依赖，符合原项目 uUID 字段的处理模式
   * - aiotieba cuid_galaxy2 算法对 androidId 输入无格式限制，只要稳定即可
   *
   * @returns 32 位 hex 字符串
   */
  static async getOrCreateDeviceId(): Promise<string> {
    const storage: AppStorageManager = AppStorageManager.getInstance();
    await storage.ensureReady();
    let deviceId: string = await storage.getString(CryptoUtil.DEVICE_ID_KEY, '');
    if (deviceId.length === 0) {
      // 生成 RFC 4122 v4 UUID 并去除连字符，得到 32 位 hex 字符串
      const uuid: string = util.generateRandomUUID(false);
      deviceId = uuid.replace(/-/g, '');
      await storage.setString(CryptoUtil.DEVICE_ID_KEY, deviceId);
    }
    return deviceId;
  }

  /**
   * 生成 cuid_galaxy2 格式的 cuid
   * 对齐 aiotieba cuid_galaxy2 算法 + 原项目 CuidUtils.getNewCuid
   * 格式：MD5("com.baidu" + androidId).uppercase() + "|V" + Base32(heliosHash(md5hex))
   * 总长度：32 + 2 + 8 = 42 字符
   *
   * @param androidId 设备标识（32 位 hex 字符串，由 getOrCreateDeviceId 生成）
   * @returns cuid 字符串（42 字符）
   */
  static async generateCuid(androidId: string): Promise<string> {
    // step 1: MD5("com.baidu" + androidId) → 32 字符大写 hex
    const raw: string = `com.baidu${androidId}`;
    const md5Hex: string = (await CryptoUtil.md5(raw)).toUpperCase();

    // step 2: heliosHash(md5Hex 的 ASCII 字节) → 5 字节
    const encoder: util.TextEncoder = new util.TextEncoder();
    const md5Bytes: Uint8Array = encoder.encodeInto(md5Hex);
    const hashBytes: Uint8Array = heliosHash(md5Bytes);

    // step 3: Base32(hashBytes) → 8 字符
    const base32Str: string = base32Encode(hashBytes);

    // step 4: 拼接 md5Hex + "|V" + base32
    return `${md5Hex}|V${base32Str}`;
  }

  static async md5(input: string): Promise<string> {
    const md = cryptoFramework.createMd('MD5');
    const encoder = new util.TextEncoder();
    const data = encoder.encodeInto(input);
    await md.update({ data: data });
    const result = await md.digest();
    return CryptoUtil.bytesToHex(result.data);
  }

  static async sha1(input: string): Promise<string> {
    const md = cryptoFramework.createMd('SHA1');
    const encoder = new util.TextEncoder();
    const data = encoder.encodeInto(input);
    await md.update({ data: data });
    const result = await md.digest();
    return CryptoUtil.bytesToHex(result.data);
  }

  static async generateSign(params: Record<string, string | number>, secretKey: string): Promise<string> {
    // 对齐 aiotieba sign.py：所有参数全集参与 MD5，无空值过滤
    const sortedKeys: string[] = Object.keys(params).sort();
    let signStr: string = '';

    for (let i: number = 0; i < sortedKeys.length; i++) {
      const key: string = sortedKeys[i];
      const value = params[key];
      signStr += `${key}=${value}`;
    }

    signStr += secretKey;
    return await CryptoUtil.md5(signStr);
  }

  static generateZid(): string {
    const timestamp: number = Date.now();
    const randomStr: string = Math.random().toString(36).substring(2, 10);
    return `${timestamp}_${randomStr}`;
  }

  static bytesToHex(bytes: Uint8Array): string {
    const hexChars: string[] = [];
    for (let i: number = 0; i < bytes.length; i++) {
      const hex: string = bytes[i].toString(16);
      hexChars.push(hex.length === 1 ? '0' + hex : hex);
    }
    return hexChars.join('');
  }

  static base64Encode(input: string): string {
    const encoder = new util.TextEncoder();
    const bytes = encoder.encodeInto(input);
    return CryptoUtil.bytesToBase64(bytes);
  }

  static base64Decode(input: string): string {
    const bytes = CryptoUtil.base64ToBytes(input);
    const decoder = new util.TextDecoder();
    return decoder.decodeWithStream(bytes);
  }

  private static bytesToBase64(bytes: Uint8Array): string {
    const chars: string = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    let result: string = '';
    let i: number = 0;

    while (i < bytes.length) {
      const byte1: number = bytes[i++];
      const byte2: number = i < bytes.length ? bytes[i++] : 0;
      const byte3: number = i < bytes.length ? bytes[i++] : 0;

      const bitmap: number = (byte1 << 16) | (byte2 << 8) | byte3;

      result += chars.charAt((bitmap >> 18) & 63);
      result += chars.charAt((bitmap >> 12) & 63);
      result += i - 2 < bytes.length ? chars.charAt((bitmap >> 6) & 63) : '=';
      result += i - 1 < bytes.length ? chars.charAt(bitmap & 63) : '=';
    }

    return result;
  }

  private static base64ToBytes(input: string): Uint8Array {
    const chars: string = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    const normalized: string = input.replace(/=+$/, '');
    const bytes: number[] = [];
    const totalLen: number = normalized.length;
    let i: number = 0;

    while (i < totalLen) {
      const c1: number = chars.indexOf(normalized.charAt(i++));
      const c2: number = i < totalLen ? chars.indexOf(normalized.charAt(i++)) : 0;
      const c3: number = i < totalLen ? chars.indexOf(normalized.charAt(i++)) : 0;
      const c4: number = i < totalLen ? chars.indexOf(normalized.charAt(i++)) : 0;

      const bitmap: number = (c1 << 18) | (c2 << 12) | (c3 << 6) | c4;

      // 按 base64 4字符组对应 3字节的规则：
      // - 4 个字符完整：解码 3 字节
      // - 3 个字符（原串长度 mod 4 == 3）：解码 2 字节
      // - 2 个字符（原串长度 mod 4 == 2）：解码 1 字节
      bytes.push((bitmap >> 16) & 255);
      if (i - 2 < totalLen) bytes.push((bitmap >> 8) & 255);
      if (i - 1 < totalLen) bytes.push(bitmap & 255);
    }

    return new Uint8Array(bytes);
  }
}
