/**
 * Hasher - helios 4 轮 hash 主逻辑
 * 对齐原项目 helios/Hasher.java
 * 4 轮：CRC32(AND) → XXHash32(XOR) → XXHash32(XOR) → CRC32(XOR)
 * 输入 bytes，输出 5 字节 hash
 */

import { crc32 } from './CRC32';
import { xxhash32 } from './XXHash32';
import { HashResult } from './HashResult';

// 4 个 encoder 的配置：[type, start, flag]
// type: 0=CRC32, 1=XXHash32
// flag: 0=AND, 1=XOR
interface EncoderConfig {
  type: number;
  start: number;
  flag: number;
}

const ENCODERS: EncoderConfig[] = [
  { type: 0, start: 8, flag: 0 },  // CRC32, AND
  { type: 1, start: 0, flag: 1 },  // XXHash32, XOR
  { type: 1, start: 1, flag: 1 },  // XXHash32, XOR
  { type: 0, start: 7, flag: 1 }   // CRC32, XOR
];

const ENCODER_LENGTH: number = 32;  // 每轮 hash 更新 32 位

/**
 * helios hash：4 轮 CRC32/XXHash32 迭代
 * 对齐 Hasher.hash(byte[])
 * @param bytes 输入字节
 * @returns 5 字节 hash
 */
export function heliosHash(bytes: Uint8Array): Uint8Array {
  const result: HashResult = new HashResult();

  // 扩展缓冲区：原始 bytes + 25 字节（5 轮 * 5 字节）
  const newBytes: Uint8Array = new Uint8Array(bytes.length + 25);
  // 复制原始 bytes
  for (let i: number = 0; i < bytes.length; i++) {
    newBytes[i] = bytes[i];
  }
  // 初始 result（40 位全 1 = 0xFF*5）复制到 newBytes[bytes.length]
  result.copyTo(newBytes, bytes.length);

  // 4 轮 hash
  for (let i: number = 0; i < ENCODERS.length; i++) {
    const encoder: EncoderConfig = ENCODERS[i];
    const len: number = bytes.length + (i + 1) * 5;

    // 计算 hash 值
    let hashValue: number;
    if (encoder.type === 0) {
      hashValue = crc32(newBytes, 0, len);
    } else {
      hashValue = xxhash32(newBytes, 0, len);
    }

    // 更新 result 状态
    result.update(hashValue, encoder.start, ENCODER_LENGTH, encoder.flag);

    // 把 result 复制到 newBytes[len]
    result.copyTo(newBytes, len);
  }

  return result.toBytes();
}
