/**
 * XXHash32 算法实现
 * 对齐原项目 helios/XXHash.java，用于 helios Hasher 的第 2/3 轮 hash
 * 标准 XXHash32，seed=0
 */

// XXHash32 质数常量（无符号 32 位）
const PRIME32_1: number = 0x9E3779B1;  // 2654435761，Java 中为 -1640531535
const PRIME32_2: number = 0x85EBCA77;  // 2246822519，Java 中为 -2048144777
const PRIME32_3: number = 0xC2B2AE3D;  // 3266489917，Java 中为 -1028477379
const PRIME32_4: number = 0x27D4EB2F;  // 668265263
const PRIME32_5: number = 0x165667B1;  // 374761393

/**
 * 读取 4 字节小端序，返回无符号 32 位整数
 * 对齐 XXHash.java 的 a(byte[], int) 方法
 */
function readUInt32LE(bytes: Uint8Array, offset: number): number {
  return (bytes[offset] |
    (bytes[offset + 1] << 8) |
    (bytes[offset + 2] << 16) |
    (bytes[offset + 3] << 24)) >>> 0;
}

/**
 * 32 位循环左移
 * 对齐 Java Integer.rotateLeft
 */
function rotateLeft(x: number, distance: number): number {
  return ((x << distance) | (x >>> (32 - distance))) >>> 0;
}

/**
 * XXHash32 计算函数
 * 对齐原项目 helios/XXHash.java
 * @param bytes 输入字节
 * @param off 起始偏移
 * @param len 长度
 * @returns 无符号 32 位 hash 值
 */
export function xxhash32(bytes: Uint8Array, off: number, len: number): number {
  // 状态向量 v1..v4，对应 Java 的 i[0..3]
  let v1: number = (PRIME32_1 + PRIME32_2) >>> 0;  // seed=0
  let v2: number = PRIME32_2 >>> 0;
  let v3: number = 0;
  let v4: number = (0 - PRIME32_1) >>> 0;

  // 缓冲区（对应 Java 的 j[16]），m 为缓冲区已用长度
  const buffer: Uint8Array = new Uint8Array(16);
  let bufferSize: number = 0;
  let totalLen: number = 0;

  totalLen += len;
  const end: number = off + len;

  let pos: number = off;

  // 如果缓冲区 + 新数据 < 16，追加到缓冲区
  if (bufferSize + len < 16) {
    for (let i: number = 0; i < len; i++) {
      buffer[bufferSize + i] = bytes[pos + i];
    }
    bufferSize += len;
  } else {
    // 先填满缓冲区并处理
    if (bufferSize > 0) {
      const fillLen: number = 16 - bufferSize;
      for (let i: number = 0; i < fillLen; i++) {
        buffer[bufferSize + i] = bytes[pos + i];
      }
      // 处理缓冲区（对应 Java 的 g(this.j, 0)）
      const r0: number = Math.imul(readUInt32LE(buffer, 0), PRIME32_2) >>> 0;
      v1 = Math.imul(rotateLeft((v1 + r0) >>> 0, 13), PRIME32_1) >>> 0;
      const r1: number = Math.imul(readUInt32LE(buffer, 4), PRIME32_2) >>> 0;
      v2 = Math.imul(rotateLeft((v2 + r1) >>> 0, 13), PRIME32_1) >>> 0;
      const r2: number = Math.imul(readUInt32LE(buffer, 8), PRIME32_2) >>> 0;
      v3 = Math.imul(rotateLeft((v3 + r2) >>> 0, 13), PRIME32_1) >>> 0;
      const r3: number = Math.imul(readUInt32LE(buffer, 12), PRIME32_2) >>> 0;
      v4 = Math.imul(rotateLeft((v4 + r3) >>> 0, 13), PRIME32_1) >>> 0;
      pos += fillLen;
      bufferSize = 0;
    }

    // 处理完整的 16 字节块
    while (pos <= end - 16) {
      const r0: number = Math.imul(readUInt32LE(bytes, pos), PRIME32_2) >>> 0;
      v1 = Math.imul(rotateLeft((v1 + r0) >>> 0, 13), PRIME32_1) >>> 0;
      const r1: number = Math.imul(readUInt32LE(bytes, pos + 4), PRIME32_2) >>> 0;
      v2 = Math.imul(rotateLeft((v2 + r1) >>> 0, 13), PRIME32_1) >>> 0;
      const r2: number = Math.imul(readUInt32LE(bytes, pos + 8), PRIME32_2) >>> 0;
      v3 = Math.imul(rotateLeft((v3 + r2) >>> 0, 13), PRIME32_1) >>> 0;
      const r3: number = Math.imul(readUInt32LE(bytes, pos + 12), PRIME32_2) >>> 0;
      v4 = Math.imul(rotateLeft((v4 + r3) >>> 0, 13), PRIME32_1) >>> 0;
      pos += 16;
    }

    // 剩余字节存入缓冲区
    if (pos < end) {
      bufferSize = end - pos;
      for (let i: number = 0; i < bufferSize; i++) {
        buffer[i] = bytes[pos + i];
      }
    }
  }

  // 最终化（对应 Java 的 getValue()）
  let hash: number;
  if (totalLen > 16) {
    hash = (rotateLeft(v1, 1) + rotateLeft(v2, 7) + rotateLeft(v3, 12) + rotateLeft(v4, 18)) >>> 0;
  } else {
    hash = (v3 + PRIME32_5) >>> 0;
  }

  hash = (hash + totalLen) >>> 0;

  // 处理缓冲区中剩余的完整 4 字节块
  let i: number = 0;
  while (i <= bufferSize - 4) {
    const r: number = Math.imul(readUInt32LE(buffer, i), PRIME32_3) >>> 0;
    hash = Math.imul(rotateLeft((hash + r) >>> 0, 17), PRIME32_4) >>> 0;
    i += 4;
  }

  // 处理剩余的单字节
  while (i < bufferSize) {
    const r: number = Math.imul(buffer[i], PRIME32_5) >>> 0;
    hash = Math.imul(rotateLeft((hash + r) >>> 0, 11), PRIME32_1) >>> 0;
    i++;
  }

  // 雪崩效应
  hash = Math.imul((hash ^ (hash >>> 15)), PRIME32_2) >>> 0;
  hash = Math.imul((hash ^ (hash >>> 13)), PRIME32_3) >>> 0;
  hash = (hash ^ (hash >>> 16)) >>> 0;

  return hash;
}
