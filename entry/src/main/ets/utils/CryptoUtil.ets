import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';

export class CryptoUtil {
  private static readonly ZID_KEY: string = 'tiebaclient!!!';

  static generateCuid(): string {
    const chars: string = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    let result: string = '';
    for (let i: number = 0; i < 40; i++) {
      result += chars.charAt(Math.floor(Math.random() * chars.length));
    }
    return result;
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
    const sortedKeys: string[] = Object.keys(params).sort();
    let signStr: string = '';

    for (let i: number = 0; i < sortedKeys.length; i++) {
      const key: string = sortedKeys[i];
      const value = params[key];
      if (value !== undefined && value !== null && String(value).length > 0) {
        signStr += `${key}=${value}`;
      }
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
