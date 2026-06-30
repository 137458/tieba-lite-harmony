// 极简 protobuf 编解码器（issue #6）
// 手写实现 varint / length-delimited wire format，无第三方依赖
// 字段编号对齐 tbclient.protobuf-main/proto/FrsPage 原定义
// int64 用 number 表示（贴吧 tid/uid 实际值 < 2^33，安全）

import { util } from '@kit.ArkTS';
import { ThreadInfo, UserInfo, MediaInfo, MediaType, PageData, ForumInfo } from '../model/ForumModels';

// ==================== ProtoWriter 编码器 ====================

class ProtoWriter {
  private buffer: number[] = [];

  /** 写 varint（支持 < 2^53 的正整数，用 Math 运算避免位运算 32 位限制） */
  private writeVarint(value: number): void {
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
  private writeTag(fieldNumber: number, wireType: number): void {
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

// ==================== ProtoReader 解码器 ====================

/** tag 信息 */
class ProtoTag {
  fieldNumber: number = 0;
  wireType: number = 0;
}

class ProtoReader {
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
    do {
      byte = this.buffer[this.pos++];
      result += (byte & 0x7f) * multiplier;
      multiplier *= 0x80;
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
    const bytes = this.buffer.subarray(this.pos, this.pos + length);
    this.pos += length;
    const decoder = util.TextDecoder.create('utf-8');
    return decoder.decodeWithStream(bytes);
  }

  /** 读嵌套 message（返回独立 reader） */
  readMessage(): ProtoReader {
    const length = this.readVarint();
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
      // 64-bit fixed
      this.pos += 8;
    } else if (wireType === 2) {
      // length-delimited
      const length = this.readVarint();
      this.pos += length;
    } else if (wireType === 5) {
      // 32-bit fixed
      this.pos += 4;
    }
  }

  /** 是否读到末尾 */
  isEnd(): boolean {
    return this.pos >= this.buffer.length;
  }
}

// ==================== FrsPage 请求编码 ====================

/** FrsPage 请求参数 */
export interface IFrsPageReqParams {
  kw: string;
  pn: number;
  rn: number;
  isGood: boolean;
  sortType: number;
  clientVersion: string;
  // 账号字段可选：getThreads 公开读 API 不需要 BDUSS/cuid/tbs（对齐 aiotieba get_threads.pack_proto）
  // 仅个性化读 API（如 get_posts with_comments）才传 BDUSS
  bduss?: string;
  cuid?: string;
  cuidGalaxy2?: string;
  tbs?: string;
}

/**
 * 编码 CommonReq（field 编号对齐 CommonReq.proto）
 * 对齐 aiotieba get_threads.pack_proto：仅传 _client_type + _client_version
 * 账号字段（BDUSS/cuid/tbs/cuid_galaxy2）可选传入，空字符串不编码（ProtoWriter.writeString 自动跳过）
 */
function encodeCommonReq(writer: ProtoWriter, params: IFrsPageReqParams): void {
  writer.writeInt32(1, 2);                     // _client_type = 2
  writer.writeString(2, params.clientVersion); // _client_version
  if (params.cuid !== undefined) {
    writer.writeString(7, params.cuid);          // cuid
  }
  if (params.bduss !== undefined) {
    writer.writeString(10, params.bduss);        // BDUSS
  }
  if (params.tbs !== undefined) {
    writer.writeString(11, params.tbs);          // tbs
  }
  if (params.cuidGalaxy2 !== undefined) {
    writer.writeString(32, params.cuidGalaxy2);  // cuid_galaxy2
  }
}

/** 编码 DataReq */
function encodeDataReq(params: IFrsPageReqParams): Uint8Array {
  const writer = new ProtoWriter();
  writer.writeString(1, params.kw);                        // kw
  writer.writeInt32(2, params.rn);                         // rn
  writer.writeInt32(3, params.rn + 5);                     // rn_need（对齐 aiotieba）
  writer.writeInt32(4, params.isGood ? 1 : 0);             // is_good
  writer.writeInt32(15, params.pn === 1 ? 0 : params.pn);  // pn（aiotieba: pn=1 时传 0）
  writer.writeInt32(47, params.sortType);                  // sort_type

  // common（field 39，嵌套 message）
  const commonWriter = new ProtoWriter();
  encodeCommonReq(commonWriter, params);
  writer.writeMessage(39, commonWriter.finish());

  return writer.finish();
}

/** 编码 FrsPageReqIdl 顶层 */
export function encodeFrsPageReq(params: IFrsPageReqParams): Uint8Array {
  const writer = new ProtoWriter();
  const dataBytes = encodeDataReq(params);
  writer.writeMessage(1, dataBytes);  // data
  return writer.finish();
}

// ==================== FrsPage 响应解码 ====================

/** FrsPage 解析结果 */
export class FrsPageResult {
  forum: ForumInfo = new ForumInfo();
  threads: PageData<ThreadInfo> = new PageData<ThreadInfo>();
}

/** 解析 User（field 编号对齐 User.proto） */
function decodeUser(reader: ProtoReader): UserInfo {
  const user = new UserInfo();
  while (!reader.isEnd()) {
    const tag = reader.readTag();
    switch (tag.fieldNumber) {
      case 2:   // id
        user.uid = reader.readVarint();
        break;
      case 3:   // name
        user.name = reader.readString();
        break;
      case 4:   // name_show
        user.nickname = reader.readString();
        break;
      case 5:   // portrait
        user.avatar = reader.readString();
        break;
      case 23:  // level_id
        user.level = reader.readVarint();
        break;
      case 25:  // is_bawu
        user.isBawu = reader.readVarint() !== 0;
        break;
      case 42:  // gender
        user.gender = reader.readVarint();
        break;
      default:
        reader.skipField(tag.wireType);
        break;
    }
  }
  return user;
}

/** 解析 Media（field 编号对齐 Media.proto） */
function decodeMedia(reader: ProtoReader): MediaInfo {
  const media = new MediaInfo();
  // URL 优先级：origin_pic > big_pic > src_pic > small_pic
  let smallPic: string = '';
  let bigPic: string = '';
  let srcPic: string = '';
  let originPic: string = '';

  while (!reader.isEnd()) {
    const tag = reader.readTag();
    switch (tag.fieldNumber) {
      case 1:   // type
        media.type = reader.readVarint() === 1 ? MediaType.VIDEO : MediaType.IMAGE;
        break;
      case 2:   // small_pic
        smallPic = reader.readString();
        break;
      case 3:   // big_pic
        bigPic = reader.readString();
        break;
      case 8:   // src_pic
        srcPic = reader.readString();
        break;
      case 10:  // width
        media.width = reader.readVarint();
        break;
      case 11:  // height
        media.height = reader.readVarint();
        break;
      case 15:  // origin_pic
        originPic = reader.readString();
        break;
      default:
        reader.skipField(tag.wireType);
        break;
    }
  }

  // 设置 URL：大图优先 origin > big > src > small
  if (originPic.length > 0) {
    media.url = originPic;
  } else if (bigPic.length > 0) {
    media.url = bigPic;
  } else if (srcPic.length > 0) {
    media.url = srcPic;
  } else {
    media.url = smallPic;
  }
  // 缩略图用 small_pic
  media.thumbnail = smallPic;
  return media;
}

/** 解析 ThreadInfo（field 编号对齐 ThreadInfo.proto） */
function decodeThread(reader: ProtoReader, users: Map<number, UserInfo>, forumName: string): ThreadInfo {
  const thread = new ThreadInfo();
  thread.forumName = forumName;
  let authorId: number = 0;

  while (!reader.isEnd()) {
    const tag = reader.readTag();
    switch (tag.fieldNumber) {
      case 2:   // tid
        thread.tid = reader.readVarint();
        break;
      case 3:   // title
        thread.title = reader.readString();
        break;
      case 4:   // reply_num
        thread.replyNum = reader.readVarint();
        break;
      case 5:   // view_num
        thread.viewNum = reader.readVarint();
        break;
      case 9:   // is_top
        thread.isTop = reader.readVarint() !== 0;
        break;
      case 10:  // is_good
        thread.isGood = reader.readVarint() !== 0;
        break;
      case 21: {  // _abstract（repeated，拼接 text 字段作为正文摘要）
        const absReader = reader.readMessage();
        while (!absReader.isEnd()) {
          const absTag = absReader.readTag();
          if (absTag.fieldNumber === 2) {  // text
            thread.content += absReader.readString();
          } else {
            absReader.skipField(absTag.wireType);
          }
        }
        break;
      }
      case 22: {  // media（repeated）
        const mediaReader = reader.readMessage();
        thread.mediaList.push(decodeMedia(mediaReader));
        break;
      }
      case 45:  // create_time
        thread.createTime = reader.readVarint();
        break;
      case 56:  // author_id
        authorId = reader.readVarint();
        break;
      default:
        reader.skipField(tag.wireType);
        break;
    }
  }

  // 从 user_list 中查找作者
  if (authorId > 0) {
    const user = users.get(authorId);
    if (user !== undefined) {
      thread.author = user;
    }
  }

  return thread;
}

/** 解析 FrsPageResIdl 顶层 */
export function decodeFrsPageRes(bytes: Uint8Array): FrsPageResult {
  const reader = new ProtoReader(bytes);
  const result = new FrsPageResult();

  while (!reader.isEnd()) {
    const tag = reader.readTag();
    if (tag.fieldNumber === 1) {
      // error
      const errReader = reader.readMessage();
      let errorNo: number = 0;
      let errorMsg: string = '';
      while (!errReader.isEnd()) {
        const errTag = errReader.readTag();
        if (errTag.fieldNumber === 1) {        // errorno
          errorNo = errReader.readVarint();
        } else if (errTag.fieldNumber === 2) { // errmsg
          errorMsg = errReader.readString();
        } else {
          errReader.skipField(errTag.wireType);
        }
      }
      if (errorNo !== 0) {
        throw new Error(`获取帖子列表失败 [${errorNo}]: ${errorMsg}`);
      }
    } else if (tag.fieldNumber === 2) {
      // data
      const dataReader = reader.readMessage();
      const users = new Map<number, UserInfo>();
      const threads: ThreadInfo[] = [];
      let forumName: string = '';

      while (!dataReader.isEnd()) {
        const dataTag = dataReader.readTag();
        if (dataTag.fieldNumber === 2) {
          // forum
          const forumReader = dataReader.readMessage();
          while (!forumReader.isEnd()) {
            const forumTag = forumReader.readTag();
            if (forumTag.fieldNumber === 1) {        // id
              result.forum.id = forumReader.readVarint();
            } else if (forumTag.fieldNumber === 2) { // name
              result.forum.name = forumReader.readString();
              forumName = result.forum.name;
            } else {
              forumReader.skipField(forumTag.wireType);
            }
          }
        } else if (dataTag.fieldNumber === 4) {
          // page
          const pageReader = dataReader.readMessage();
          while (!pageReader.isEnd()) {
            const pageTag = pageReader.readTag();
            if (pageTag.fieldNumber === 3) {         // current_page
              result.threads.currentPage = pageReader.readVarint();
            } else if (pageTag.fieldNumber === 5) {  // total_page
              result.threads.totalPage = pageReader.readVarint();
            } else if (pageTag.fieldNumber === 6) {  // has_more
              result.threads.hasMore = pageReader.readVarint() !== 0;
            } else {
              pageReader.skipField(pageTag.wireType);
            }
          }
        } else if (dataTag.fieldNumber === 7) {
          // thread_list（repeated）
          const threadReader = dataReader.readMessage();
          threads.push(decodeThread(threadReader, users, forumName));
        } else if (dataTag.fieldNumber === 17) {
          // user_list（repeated）
          const userReader = dataReader.readMessage();
          const user = decodeUser(userReader);
          users.set(user.uid, user);
        } else {
          dataReader.skipField(dataTag.wireType);
        }
      }

      result.threads.list = threads;
    } else {
      reader.skipField(tag.wireType);
    }
  }

  return result;
}
