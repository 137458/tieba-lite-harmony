import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { heliosHash } from './helios/Hasher';
import { base32Encode } from './helios/Base32';
import { AppStorageManager } from '../data/AppStorage';
import * as Pako from 'pako_arkts';

export class CryptoUtil {
  private static readonly ZID_KEY: string = 'tiebaclient!!!';
  private static readonly DEVICE_ID_KEY: string = 'device_id';
  private static readonly ANDROID_ID_KEY: string = 'android_id';
  private static readonly UUID_KEY: string = 'uuid';
  private static readonly AES_CBC_SEC_KEY: string = 'aes_cbc_sec_key';
  // TextEncoder 实例复用：md5/sha1/rc442/generateCuid 每次网络请求都会调用，
  // 避免每次新建实例造成 GC 压力
  private static readonly textEncoder: util.TextEncoder = new util.TextEncoder();
  // Promise 缓存：防止首调并发时多个 await 同时读到空值各自生成不同标识
  // 首次调用保存进行中的 Promise，后续调用复用同一 Promise，保证设备标识稳定
  private static deviceIdPromise: Promise<string> | null = null;
  private static androidIdPromise: Promise<string> | null = null;
  private static uuidPromise: Promise<string> | null = null;
  private static aesCbcSecKeyPromise: Promise<Uint8Array> | null = null;

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
    // 并发竞态修复：复用进行中的 Promise，避免并发调用各自生成不同 deviceId
    if (CryptoUtil.deviceIdPromise !== null) {
      return CryptoUtil.deviceIdPromise;
    }
    CryptoUtil.deviceIdPromise = (async (): Promise<string> => {
      try {
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
      } catch (e) {
        // 失败时清除 Promise 缓存，允许后续调用重试，避免永久不可恢复
        CryptoUtil.deviceIdPromise = null;
        // ArkTS 严格模式禁止 throw e（e 是无类型 catch 变量），包装为 Error 抛出
        throw new Error((e as Error).message);
      }
    })();
    return CryptoUtil.deviceIdPromise;
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
    const md5Bytes: Uint8Array = CryptoUtil.textEncoder.encodeInto(md5Hex);
    const hashBytes: Uint8Array = heliosHash(md5Bytes);

    // step 3: Base32(hashBytes) → 8 字符
    const base32Str: string = base32Encode(hashBytes);

    // step 4: 拼接 md5Hex + "|V" + base32
    return `${md5Hex}|V${base32Str}`;
  }

  static async md5(input: string): Promise<string> {
    const md = cryptoFramework.createMd('MD5');
    const data = CryptoUtil.textEncoder.encodeInto(input);
    await md.update({ data: data });
    const result = await md.digest();
    return CryptoUtil.bytesToHex(result.data);
  }

  static async sha1(input: string): Promise<string> {
    const md = cryptoFramework.createMd('SHA1');
    const data = CryptoUtil.textEncoder.encodeInto(input);
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

  /**
   * 获取或创建 android_id
   * 对齐 aiotieba Account.android_id：8 字节随机 → 16 字符小写 hex
   * 持久化到 preferences，首次调用生成，后续稳定不变
   * @returns 16 字符小写 hex 字符串
   */
  static async getOrCreateAndroidId(): Promise<string> {
    // 并发竞态修复：复用进行中的 Promise
    if (CryptoUtil.androidIdPromise !== null) {
      return CryptoUtil.androidIdPromise;
    }
    CryptoUtil.androidIdPromise = (async (): Promise<string> => {
      try {
        const storage: AppStorageManager = AppStorageManager.getInstance();
        await storage.ensureReady();
        let androidId: string = await storage.getString(CryptoUtil.ANDROID_ID_KEY, '');
        if (androidId.length === 0) {
          // 取 RFC 4122 v4 UUID 前 16 个 hex 字符（含 8 字节熵）
          const uuid: string = util.generateRandomUUID(false).replace(/-/g, '');
          androidId = uuid.substring(0, 16).toLowerCase();
          await storage.setString(CryptoUtil.ANDROID_ID_KEY, androidId);
        }
        return androidId;
      } catch (e) {
        // 失败时清除 Promise 缓存，允许后续调用重试
        CryptoUtil.androidIdPromise = null;
        throw new Error((e as Error).message);
      }
    })();
    return CryptoUtil.androidIdPromise;
  }

  /**
   * 获取或创建 uuid（带连字符的 36 字符 v4 UUID）
   * 对齐 aiotieba Account.uuid：用作 init_z_id 的 xyus 计算
   * @returns 36 字符 UUID v4 字符串
   */
  static async getOrCreateUuid(): Promise<string> {
    // 并发竞态修复：复用进行中的 Promise
    if (CryptoUtil.uuidPromise !== null) {
      return CryptoUtil.uuidPromise;
    }
    CryptoUtil.uuidPromise = (async (): Promise<string> => {
      try {
        const storage: AppStorageManager = AppStorageManager.getInstance();
        await storage.ensureReady();
        let uuid: string = await storage.getString(CryptoUtil.UUID_KEY, '');
        if (uuid.length === 0) {
          uuid = util.generateRandomUUID(false);
          await storage.setString(CryptoUtil.UUID_KEY, uuid);
        }
        return uuid;
      } catch (e) {
        // 失败时清除 Promise 缓存，允许后续调用重试
        CryptoUtil.uuidPromise = null;
        throw new Error((e as Error).message);
      }
    })();
    return CryptoUtil.uuidPromise;
  }

  /**
   * 获取或创建 AES-CBC-128 密钥（16 字节随机）
   * 对齐 aiotieba Account.aes_cbc_sec_key：用于 init_z_id 的请求/响应 AES 加解密
   * 持久化为 base64 字符串（16 字节 → 24 字符 base64）
   * @returns 16 字节 Uint8Array
   */
  static async getOrCreateAesCbcSecKey(): Promise<Uint8Array> {
    // 并发竞态修复：复用进行中的 Promise
    if (CryptoUtil.aesCbcSecKeyPromise !== null) {
      return CryptoUtil.aesCbcSecKeyPromise;
    }
    CryptoUtil.aesCbcSecKeyPromise = (async (): Promise<Uint8Array> => {
      try {
        const storage: AppStorageManager = AppStorageManager.getInstance();
        await storage.ensureReady();
        let b64: string = await storage.getString(CryptoUtil.AES_CBC_SEC_KEY, '');
        if (b64.length === 0) {
          // 取 UUID v4 全部 32 hex 字符（16 字节熵）
          const uuid: string = util.generateRandomUUID(false).replace(/-/g, '');
          const keyBytes: Uint8Array = CryptoUtil.hexToBytes(uuid);
          b64 = CryptoUtil.bytesToBase64(keyBytes);
          await storage.setString(CryptoUtil.AES_CBC_SEC_KEY, b64);
        }
        return CryptoUtil.base64ToBytes(b64);
      } catch (e) {
        // 失败时清除 Promise 缓存，允许后续调用重试
        CryptoUtil.aesCbcSecKeyPromise = null;
        throw new Error((e as Error).message);
      }
    })();
    return CryptoUtil.aesCbcSecKeyPromise;
  }

  /**
   * MD5 哈希，返回原始 16 字节
   * 用于 init_z_id 中 req_body_md5 计算
   */
  static async md5Bytes(data: Uint8Array): Promise<Uint8Array> {
    const md = cryptoFramework.createMd('MD5');
    await md.update({ data: data });
    const result = await md.digest();
    return result.data;
  }

  /**
   * RC4-42 算法（贴吧定制版 RC4：标准 RC4 输出后额外 XOR 42）
   * 对齐 aiotieba helper/crypto/src/tbcrypto/rc442.c
   * 用途：init_z_id 中派生 skey（aes_cbc_sec_key 与 xyus_md5_str 双向加密）
   *
   * @param xyusMd5Str 32 字符 hex 字符串（ASCII 字节作为 RC4 key）
   * @param cbcSecKey 16 字节待加密数据
   * @returns 16 字节加密结果
   */
  static rc442(xyusMd5Str: string, cbcSecKey: Uint8Array): Uint8Array {
    // 入口校验空 key，避免 KSA 中 keyBytes[i % keyBytes.length] 触发除零
    if (xyusMd5Str.length === 0) {
      throw new Error('rc442 key must not be empty');
    }
    const keyBytes: Uint8Array = CryptoUtil.textEncoder.encodeInto(xyusMd5Str);

    // KSA：初始化 S 盒
    const s: Uint8Array = new Uint8Array(256);
    for (let i: number = 0; i < 256; i++) {
      s[i] = i;
    }
    let j: number = 0;
    for (let i: number = 0; i < 256; i++) {
      const k: number = keyBytes[i % keyBytes.length];
      j = (j + s[i] + k) & 0xFF;
      const tmp: number = s[i];
      s[i] = s[j];
      s[j] = tmp;
    }

    // PRGA + XOR 42
    const result: Uint8Array = new Uint8Array(cbcSecKey.length);
    let x: number = 0;
    let y: number = 0;
    for (let n: number = 0; n < cbcSecKey.length; n++) {
      x = (x + 1) & 0xFF;
      const a: number = s[x];
      y = (y + a) & 0xFF;
      const b: number = s[y];
      s[x] = b;
      s[y] = a;
      const prgaByte: number = s[(a + b) & 0xFF];
      result[n] = (cbcSecKey[n] ^ prgaByte) ^ 42;
    }
    return result;
  }

  /**
   * AES-CBC-128 加密（PKCS7 padding，IV = 16 字节全 0）
   * 对齐 aiotieba init_z_id 请求体加密
   * @param plaintext 原始数据（不需预先 padding，cryptoFramework 自动处理）
   * @param key 16 字节密钥
   * @returns 加密后的密文
   */
  static async aesCbcEncrypt(plaintext: Uint8Array, key: Uint8Array): Promise<Uint8Array> {
    const cipher = cryptoFramework.createCipher('AES128|CBC|PKCS7');
    const symKeyGenerator = cryptoFramework.createSymKeyGenerator('AES128');
    const symKey = await symKeyGenerator.convertKey({ data: key });

    // IV = 16 字节全 0
    const iv: Uint8Array = new Uint8Array(16);
    const paramsSpec: cryptoFramework.IvParamsSpec = {
      algName: 'IvParamsSpec',
      iv: { data: iv }
    };

    await cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, symKey, paramsSpec);
    const result = await cipher.doFinal({ data: plaintext });
    return result.data;
  }

  /**
   * AES-CBC-128 解密（NoPadding 模式，IV = 16 字节全 0）
   * 对齐 aiotieba init_z_id 响应解密：响应体 = AES_CBC(PKCS7(gzip(JSON)) + md5(gzip(JSON)))
   * 用 NoPadding 拿到原始解密结果，由调用方移除末尾 16 字节 md5 后再 PKCS7 unpad
   * @param ciphertext 密文
   * @param key 16 字节密钥
   * @returns 解密后的原始数据（含末尾 md5 + PKCS7 padding）
   */
  static async aesCbcDecryptRaw(ciphertext: Uint8Array, key: Uint8Array): Promise<Uint8Array> {
    const cipher = cryptoFramework.createCipher('AES128|CBC|NoPadding');
    const symKeyGenerator = cryptoFramework.createSymKeyGenerator('AES128');
    const symKey = await symKeyGenerator.convertKey({ data: key });

    const iv: Uint8Array = new Uint8Array(16);
    const paramsSpec: cryptoFramework.IvParamsSpec = {
      algName: 'IvParamsSpec',
      iv: { data: iv }
    };

    await cipher.init(cryptoFramework.CryptoMode.DECRYPT_MODE, symKey, paramsSpec);
    const result = await cipher.doFinal({ data: ciphertext });
    return result.data;
  }

  /**
   * PKCS7 去填充
   * 末字节值 = padding 长度 N，移除末尾 N 字节
   * 安全校验：所有 padding 字节必须都等于 N，否则抛错（防止填充预言攻击）
   */
  static pkcs7Unpad(data: Uint8Array): Uint8Array {
    if (data.length === 0) {
      return data;
    }
    const padLen: number = data[data.length - 1];
    if (padLen <= 0 || padLen > 16 || padLen > data.length) {
      throw new Error(`Invalid PKCS7 padding length: ${padLen}`);
    }
    // 校验最后 N 个字节全部等于 N，任一不匹配则数据已损坏或被篡改
    for (let i: number = 0; i < padLen; i++) {
      if (data[data.length - 1 - i] !== padLen) {
        throw new Error(`Invalid PKCS7 padding byte at offset ${data.length - 1 - i}`);
      }
    }
    return data.subarray(0, data.length - padLen);
  }

  /**
   * gzip 压缩（对齐 Python gzip.compress(data, compresslevel=6, mtime=0)）
   * 使用 pako_arkts 库的 gzip 模式，产出标准 gzip 流
   * pako_arkts 的 gzip/ungzip 返回 Promise，故此方法为 async
   */
  static async gzipCompress(data: Uint8Array): Promise<Uint8Array> {
    return await Pako.gzip(data, { level: 6 });
  }

  /**
   * gzip 解压（对齐 Python gzip.decompress）
   * pako_arkts 的 ungzip 返回 Promise，故此方法为 async
   */
  static async gzipDecompress(data: Uint8Array): Promise<Uint8Array> {
    return await Pako.ungzip(data);
  }

  static bytesToHex(bytes: Uint8Array): string {
    const hexChars: string[] = [];
    for (let i: number = 0; i < bytes.length; i++) {
      const hex: string = bytes[i].toString(16);
      hexChars.push(hex.length === 1 ? '0' + hex : hex);
    }
    return hexChars.join('');
  }

  /** hex 字符串转字节数组（输入须为偶数长度） */
  static hexToBytes(hex: string): Uint8Array {
    if (hex.length % 2 !== 0) {
      throw new Error(`Invalid hex string length: ${hex.length}`);
    }
    const bytes: Uint8Array = new Uint8Array(hex.length / 2);
    for (let i: number = 0; i < bytes.length; i++) {
      bytes[i] = parseInt(hex.substring(i * 2, i * 2 + 2), 16);
    }
    return bytes;
  }

  /** 字节数组转 base64 字符串
   *  委托 util.Base64Helper（issue #37）：HarmonyOS 标准库提供同步实现，
   *  避免自实现 base64 的代码冗余与潜在边界 bug
   */
  static bytesToBase64(bytes: Uint8Array): string {
    const base64Helper: util.Base64Helper = new util.Base64Helper();
    return base64Helper.encodeToStringSync(bytes);
  }

  /** base64 字符串转字节数组
   *  委托 util.Base64Helper（issue #37），与 bytesToBase64 互逆
   */
  static base64ToBytes(input: string): Uint8Array {
    const base64Helper: util.Base64Helper = new util.Base64Helper();
    return base64Helper.decodeSync(input);
  }
}
