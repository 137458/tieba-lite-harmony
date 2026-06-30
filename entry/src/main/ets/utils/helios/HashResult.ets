/**
 * HashResult - helios Hasher 的 40 位状态容器
 * 对齐原项目 helios/HashResult.java + EncodeResult.java
 * 简化：heliosHash 只用 40 位，用 BigInt 替代完整 BitSet
 */

const STATE_BITS: bigint = 40n;
const STATE_MASK: bigint = (1n << STATE_BITS) - 1n;  // 0xFFFFFFFFFFn

/**
 * helios Hash 的 40 位状态
 * 初始为 40 位全 1（对齐 HashResult 构造函数 a(0, 40, true)）
 */
export class HashResult {
  private state: bigint = STATE_MASK;

  /**
   * 用 hash 值更新状态的 [start..start+length) 位
   * 对齐 HashResult.update(EncodeResult, start, length, flag)
   * @param hashValue 32 位无符号 hash 值
   * @param start 起始位
   * @param length 位数（固定 32）
   * @param flag 0=AND, 1=XOR, 2=AND NOT, 3=OR
   */
  update(hashValue: number, start: number, length: number, flag: number): void {
    const hashBig: bigint = BigInt(hashValue >>> 0);
    const startBig: bigint = BigInt(start);
    const lengthBig: bigint = BigInt(length);
    const mask: bigint = ((1n << lengthBig) - 1n) << startBig;
    const currentBits: bigint = (this.state & mask) >> startBig;

    let newBits: bigint;
    if (flag === 0) {
      // AND (对应 EncodeResult.b)
      newBits = currentBits & hashBig;
    } else if (flag === 1) {
      // XOR (对应 EncodeResult.d，default 分支)
      newBits = currentBits ^ hashBig;
    } else if (flag === 2) {
      // AND NOT (对应 EncodeResult.e)
      newBits = currentBits & ~hashBig;
    } else {
      // OR (对应 EncodeResult.c，flag=3)
      newBits = currentBits | hashBig;
    }

    // 清除原位，写入新位
    this.state = (this.state & ~mask) | (newBits << startBig);
    this.state &= STATE_MASK;
  }

  /**
   * 获取状态的前 5 字节（小端序）
   * 对齐 EncodeResult.a() + Hasher 的 copyOf(result.getValue(), 5)
   */
  toBytes(): Uint8Array {
    const bytes: Uint8Array = new Uint8Array(5);
    let temp: bigint = this.state;
    for (let i: number = 0; i < 5; i++) {
      bytes[i] = Number(temp & 0xFFn);
      temp >>= 8n;
    }
    return bytes;
  }

  /**
   * 获取状态字节并拼接到目标数组指定位置
   * 对齐 ByteArrayUtils.copyArray(dest, result.getValue(), destPos)
   */
  copyTo(dest: Uint8Array, destPos: number): void {
    const bytes: Uint8Array = this.toBytes();
    for (let i: number = 0; i < bytes.length; i++) {
      dest[destPos + i] = bytes[i];
    }
  }
}
