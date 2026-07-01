// 共享 protobuf wire format 编解码器（issue #7 抽取）
// 提供 varint / length-delimited wire format，无第三方依赖
// 被 FrsPageProto.ets / PbPageProto.ets / 后续 SearchProto.ets 复用
// int64 用 number 表示（贴吧 tid/uid 实际值 < 2^53，安全）

import { util } from '@kit.ArkTS';

/** tag 信息 */
export class ProtoTag {
  fieldNumber: number = 0;
  wireType: number = 0;
}

/** protobuf 编码器 */
export class ProtoWriter {
  private buffer: number[] = [];

  /** 写 varint（支持 < 2^53 的正整数，用 Math 运算避免位运算 32 位限制） */
  writeVarint(value: number): void {
    if (value === 0) {
      this.buffer.push(0);
      return;
    }
    while (value > 0) {
      let byte: number = value % 0x80;
      value = Math.floor(value / 0x80);
      if (value > 0) {
        byte += 0x80;
      }
      this.buffer.push(byte);
    }
  }

  /** 写 tag（field_number << 3 | wire_type） */
  writeTag(fieldNumber: number, wireType: number): void {
    this.writeVarint(fieldNumber * 8 + wireType);
  }

  /** 写 int32 field（proto3 默认值 0 不编码） */
  writeInt32(fieldNumber: number, value: number): void {
    if (value === 0) {
      return;
    }
    this.writeTag(fieldNumber, 0);
    this.writeVarint(value);
  }

  /** 写 string field（空字符串不编码） */
  writeString(fieldNumber: number, value: string): void {
    if (value.length === 0) {
      return;
    }
    this.writeTag(fieldNumber, 2);
    const encoder = new util.TextEncoder();
    const bytes: Uint8Array = encoder.encodeInto(value);
    this.writeVarint(bytes.length);
    for (let i = 0; i < bytes.length; i++) {
      this.buffer.push(bytes[i]);
    }
  }

  /** 写嵌套 message field */
  writeMessage(fieldNumber: number, messageBytes: Uint8Array): void {
    this.writeTag(fieldNumber, 2);
    this.writeVarint(messageBytes.length);
    for (let i = 0; i < messageBytes.length; i++) {
      this.buffer.push(messageBytes[i]);
    }
  }

  /** 获取编码结果 */
  finish(): Uint8Array {
    return new Uint8Array(this.buffer);
  }
}

/** protobuf 解码器 */
export class ProtoReader {
  private buffer: Uint8Array;
  pos: number = 0;

  constructor(buffer: Uint8Array) {
    this.buffer = buffer;
  }

  /** 读 varint（用乘法避免位运算 32 位限制） */
  readVarint(): number {
    let result: number = 0;
    let multiplier: number = 1;
    let byte: number;
    let iterCount: number = 0;
    do {
      // 边界检查：防止截断的 protobuf 导致 NaN 传播
      if (this.pos >= this.buffer.length) {
        throw new Error('Protobuf 解码越界：varint 不完整');
      }
      byte = this.buffer[this.pos++];
      result += (byte & 0x7f) * multiplier;
      multiplier *= 0x80;
      iterCount++;
      // 防御 varint 过长（64 位 varint 最多 10 字节，超过即数据损坏）
      if (iterCount > 10) {
        throw new Error('Protobuf 解码异常：varint 超过 10 字节');
      }
    } while ((byte & 0x80) !== 0);
    return result;
  }

  /** 读 tag */
  readTag(): ProtoTag {
    const tag = new ProtoTag();
    const value = this.readVarint();
    tag.fieldNumber = Math.floor(value / 8);
    tag.wireType = value % 8;
    return tag;
  }

  /** 读 string */
  readString(): string {
    const length = this.readVarint();
    // 边界检查：防止损坏的 length 导致越界
    if (length < 0 || this.pos + length > this.buffer.length) {
      throw new Error(`Protobuf 解码越界：string length=${length} pos=${this.pos} buffer=${this.buffer.length}`);
    }
    const bytes = this.buffer.subarray(this.pos, this.pos + length);
    this.pos += length;
    const decoder = util.TextDecoder.create('utf-8');
    return decoder.decodeWithStream(bytes);
  }

  /** 读嵌套 message（返回独立 reader） */
  readMessage(): ProtoReader {
    const length = this.readVarint();
    // 边界检查：防止损坏的 length 导致越界
    if (length < 0 || this.pos + length > this.buffer.length) {
      throw new Error(`Protobuf 解码越界：message length=${length} pos=${this.pos} buffer=${this.buffer.length}`);
    }
    const bytes = this.buffer.subarray(this.pos, this.pos + length);
    this.pos += length;
    return new ProtoReader(bytes);
  }

  /** 跳过未知字段 */
  skipField(wireType: number): void {
    if (wireType === 0) {
      // varint
      this.readVarint();
    } else if (wireType === 1) {
      // 64-bit fixed：边界检查防止截断 protobuf 导致 pos 越界
      if (this.pos + 8 > this.buffer.length) {
        throw new Error(`Protobuf 解码越界：64-bit fixed pos=${this.pos} buffer=${this.buffer.length}`);
      }
      this.pos += 8;
    } else if (wireType === 2) {
      // length-delimited
      const length = this.readVarint();
      if (this.pos + length > this.buffer.length) {
        throw new Error(`Protobuf 解码越界：length-delimited length=${length} pos=${this.pos} buffer=${this.buffer.length}`);
      }
      this.pos += length;
    } else if (wireType === 5) {
      // 32-bit fixed：边界检查防止截断 protobuf 导致 pos 越界
      if (this.pos + 4 > this.buffer.length) {
        throw new Error(`Protobuf 解码越界：32-bit fixed pos=${this.pos} buffer=${this.buffer.length}`);
      }
      this.pos += 4;
    }
  }

  /** 是否读到末尾 */
  isEnd(): boolean {
    return this.pos >= this.buffer.length;
  }
}
