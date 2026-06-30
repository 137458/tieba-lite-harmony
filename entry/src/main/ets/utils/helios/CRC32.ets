/**
 * CRC32 标准算法实现
 * 对齐 java.util.zip.CRC32，用于 helios Hasher 的第 1/4 轮 hash
 * 参考原项目 helios/CRC32Encoder.java
 */

const CRC32_TABLE: Uint32Array = (() => {
  const table: Uint32Array = new Uint32Array(256);
  for (let i: number = 0; i < 256; i++) {
    let crc: number = i;
    for (let j: number = 0; j < 8; j++) {
      // 无符号右移处理：JS 位操作是 32 位有符号，需 >>> 0 保持无符号
      crc = (crc & 1) !== 0 ? (0xEDB88320 ^ (crc >>> 1)) >>> 0 : (crc >>> 1) >>> 0;
    }
    table[i] = crc >>> 0;
  }
  return table;
})();

/**
 * 计算 bytes[off..off+len] 的 CRC32 值
 * 返回无符号 32 位整数（用 number 表示，范围 0..4294967295）
 */
export function crc32(bytes: Uint8Array, off: number, len: number): number {
  let crc: number = 0xFFFFFFFF;
  for (let i: number = 0; i < len; i++) {
    const idx: number = ((crc ^ bytes[off + i]) & 0xFF) >>> 0;
    crc = (CRC32_TABLE[idx] ^ (crc >>> 8)) >>> 0;
  }
  return (crc ^ 0xFFFFFFFF) >>> 0;
}
