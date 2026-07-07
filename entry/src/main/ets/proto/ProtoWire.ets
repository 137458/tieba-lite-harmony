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
  // TextEncoder 实例复用：writeString 是高频调用，避免每次新建实例造成 GC 压力
  private static readonly encoder: util.TextEncoder = new util.TextEncoder();

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

  /** 写 int32 field（proto3 默认值 0 不编码）
   *  负值按 proto3 标准符号扩展到 64 位，编码为 10 字节 varint，
   *  避免直接 writeVarint 导致负值静默丢失
   */
  writeInt32(fieldNumber: number, value: number): void {
    if (value === 0) {
      return;
    }
    this.writeTag(fieldNumber, 0);
    if (value < 0) {
      // proto3 标准：int32 负值符号扩展到 64 位（高 32 位全 1），编码为 10 字节 varint
      // low32 = value + 2^32，将负值转换为无符号 32 位表示
      const low32: number = value + 0x100000000;
      // byte0-3：编码 low32 的 bit0-27
      this.buffer.push((low32 & 0x7F) | 0x80);
      this.buffer.push(((low32 >>> 7) & 0x7F) | 0x80);
      this.buffer.push(((low32 >>> 14) & 0x7F) | 0x80);
      this.buffer.push(((low32 >>> 21) & 0x7F) | 0x80);
      // byte4：低 4 位来自 low32 的 bit28-31，高 3 位来自符号扩展（全 1）
      this.buffer.push(((low32 >>> 28) & 0x0F) | 0x70 | 0x80);
      // byte5-8：符号扩展的 bit35-62（全 1）
      this.buffer.push(0xFF);
      this.buffer.push(0xFF);
      this.buffer.push(0xFF);
      this.buffer.push(0xFF);
      // byte9：符号扩展的 bit63 = 1，无后续字节
      this.buffer.push(0x01);
    } else {
      this.writeVarint(value);
    }
  }

  /** 写 string field（空字符串不编码） */
  writeString(fieldNumber: number, value: string): void {
    if (value.length === 0) {
      return;
    }
    this.writeTag(fieldNumber, 2);
    const bytes: Uint8Array = ProtoWriter.encoder.encodeInto(value);
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
  // #87 P1：TextDecoder 实例复用（对齐 ProtoWriter.encoder 静态复用模式）
  // readString 是高频调用（解码帖子列表/回复内容时每条 string field 都触发），
  // 每次新建 TextDecoder 会造成 GC 压力
  private static readonly decoder: util.TextDecoder = util.TextDecoder.create('utf-8');

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
    // #87 P1：复用静态 decoder 实例，避免高频调用时频繁创建对象
    const result = ProtoReader.decoder.decodeWithStream(bytes);
    // [DBG-Wire] #108 调试：验证假设——decodeWithStream 对空 bytes 返回 undefined 而非 ''
    // 这会导致 readString 返回 undefined，后续 .length/.indexOf 抛 NPE
    if (result === undefined || result === null) {
      console.warn(`[DBG-Wire] readString: decodeWithStream returned ${typeof result}, length=${length}, returning ''`);
      return '';
    }
    return result;
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
