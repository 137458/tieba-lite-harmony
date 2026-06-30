/**
 * Base32 编码（helios 变体）
 * 对齐原项目 helios/Base32.kt
 * 字符表：ABCDEFGHIJKLMNOPQRSTUVWXYZ234567=
 */

const ALPHABET: string = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567=';

/**
 * 根据有效字节数返回需要截断的字符数
 * 对齐 Base32.kt 的 transformInt
 */
function getTruncateCount(validBytes: number): number {
  switch (validBytes) {
    case 1: return 6;
    case 2: return 4;
    case 3: return 3;
    case 4: return 1;
    case 5: return 0;
    default: return -1;
  }
}

/**
 * Base32 编码（helios 变体）
 * 对齐 Base32.kt 的 encode
 * @param bytes 输入字节
 * @returns Base32 编码字符串
 */
export function base32Encode(bytes: Uint8Array): string {
  let result: string = '';
  const groupCount: number = Math.floor((bytes.length + 4) / 5);

  for (let g: number = 0; g < groupCount; g++) {
    // 读取 5 字节为一组，不足补 0
    const shorts: number[] = [0, 0, 0, 0, 0];
    let validBytes: number = 5;
    for (let i: number = 0; i < 5; i++) {
      const idx: number = g * 5 + i;
      if (idx < bytes.length) {
        shorts[i] = bytes[idx] & 0xFF;
      } else {
        shorts[i] = 0;
        validBytes--;
      }
    }

    const dt: number = getTruncateCount(validBytes);

    // 将 5 字节（40 位）拆分为 8 个 5 位组
    const ints: number[] = [
      (shorts[0] >>> 3) & 31,
      ((shorts[0] & 7) << 2) | ((shorts[1] >>> 6) & 3),
      (shorts[1] >>> 1) & 31,
      ((shorts[1] & 1) << 4) | ((shorts[2] >>> 4) & 15),
      ((shorts[2] & 15) << 1) | ((shorts[3] >>> 7) & 1),
      (shorts[3] >>> 2) & 31,
      ((shorts[3] & 3) << 3) | ((shorts[4] >>> 5) & 7),
      shorts[4] & 31
    ];

    // 输出 8 - dt 个字符
    for (let i: number = 0; i < 8 - dt; i++) {
      result += ALPHABET.charAt(ints[i]);
    }
  }

  return result;
}
