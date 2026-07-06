// 消息页 protobuf 编解码（ReplyMe 接口）
// 字段编号对齐 tbclient.protobuf-main/proto/ReplyMe/ReplyMeReqIdl.proto
// 与 aiotieba-master/src/aiotieba/api/get_replys/protobuf/ReplyMeResIdl.proto
//
// 权威参考：aiotieba-master/src/aiotieba/api/get_replys/_api.py
//   - CMD = 303007
//   - 端点 POST /c/u/feed/replyme?cmd=303007
//   - 请求 body: multipart/form-data, part name="data"（protobuf 序列化后的 ReplyMeReqIdl）
//   - common.BDUSS + common._client_version 必传
//   - pn 为 string 类型（对齐 proto 定义：string pn = 1）
//
// 响应字段映射（对齐 aiotieba Reply.from_proto）:
//   data.reply_list[].thread_id#1   → tid
//   data.reply_list[].post_id#2     → pid
//   data.reply_list[].time#3        → createTime
//   data.reply_list[].fname#5       → fname
//   data.reply_list[].content#6     → text
//   data.reply_list[].is_floor#7    → isComment（楼中楼）
//   data.reply_list[].quote_content#8 → 引用内容（暂未使用）
//   data.reply_list[].replyer#9     → 回复者 User
//   data.reply_list[].quote_pid#14  → ppid（被回复的楼层 pid）
//   data.reply_list[].quote_user#15 → 楼层用户 User
//   data.reply_list[].thread_author_user#25 → 楼主 User
//   data.page.current_page#1 / has_more#2 / has_prev#3 → 分页信息

import { ProtoWriter, ProtoReader } from './ProtoWire';
import { LATEST_VERSION } from '../net/TiebaHttpClient';

// ==================== ReplyMe 请求编码 ====================

/** ReplyMe 请求参数 */
export interface IReplyMeReqParams {
  /** 页码（pn，从 1 开始） */
  pn: number;
  /** 用户 BDUSS（必传） */
  bduss: string;
  /** 客户端版本号，默认 LATEST_VERSION */
  clientVersion?: string;
}

/**
 * 编码 CommonReq（field 编号对齐 CommonReq.proto）
 * 仅传必填字段：_client_type + _client_version + BDUSS
 * 其他字段（cuid/tbs 等）服务端不强制要求
 */
function encodeCommonReq(writer: ProtoWriter, params: IReplyMeReqParams): void {
  const version: string = params.clientVersion !== undefined ? params.clientVersion : LATEST_VERSION;
  writer.writeInt32(1, 2);                    // _client_type = 2
  writer.writeString(2, version);             // _client_version
  writer.writeString(10, params.bduss);       // BDUSS（必传）
}

/**
 * 编码 ReplyMeReqIdl.DataReq
 * 字段：pn#1（string）+ common#3（嵌套 CommonReq）
 */
function encodeDataReq(params: IReplyMeReqParams): Uint8Array {
  const writer = new ProtoWriter();
  // pn 为 string 类型（对齐 proto 定义），用 String(number) 显式转换
  writer.writeString(1, String(params.pn));

  // common（field 3，嵌套 message）
  const commonWriter = new ProtoWriter();
  encodeCommonReq(commonWriter, params);
  writer.writeMessage(3, commonWriter.finish());

  return writer.finish();
}

/** 编码 ReplyMeReqIdl 顶层（field 1 = data） */
export function encodeReplyMeReq(params: IReplyMeReqParams): Uint8Array {
  const writer = new ProtoWriter();
  const dataBytes = encodeDataReq(params);
  writer.writeMessage(1, dataBytes);  // data
  return writer.finish();
}

// ==================== ReplyMe 响应解码 ====================

/** 回复消息用户信息（简化版，只取展示需要的字段） */
export class ReplyUser {
  userId: number = 0;
  userName: string = '';
  nickName: string = '';
  portrait: string = '';

  /** 显示名称：优先 nickName，其次 userName，最后 userId */
  getDisplayName(): string {
    if (this.nickName.length > 0) {
      return this.nickName;
    }
    if (this.userName.length > 0) {
      return this.userName;
    }
    return String(this.userId);
  }
}

/** 单条回复消息 */
export class ReplyMessage {
  text: string = '';
  fname: string = '';
  tid: number = 0;
  ppid: number = 0;
  pid: number = 0;
  /** 回复者 */
  user: ReplyUser = new ReplyUser();
  /** 被回复楼层用户 */
  postUser: ReplyUser = new ReplyUser();
  /** 楼主 */
  threadUser: ReplyUser = new ReplyUser();
  /** 是否楼中楼 */
  isComment: boolean = false;
  /** 创建时间（10 位秒级时间戳） */
  createTime: number = 0;
}

/** 回复列表分页信息 */
export class ReplysPageInfo {
  currentPage: number = 0;
  hasMore: boolean = false;
  hasPrev: boolean = false;
}

/** 回复列表解析结果 */
export class ReplysResult {
  list: ReplyMessage[] = [];
  page: ReplysPageInfo = new ReplysPageInfo();
}

/**
 * 去掉 portrait 末尾的 ?xxx 13 字符后缀（对齐 aiotieba UserInfo_reply.from_proto）
 * aiotieba: if "?" in portrait: portrait = portrait[:-13]
 */
function stripPortraitSuffix(portrait: string): string {
  const qIndex: number = portrait.indexOf('?');
  if (qIndex >= 0 && portrait.length - qIndex === 13) {
    return portrait.substring(0, qIndex);
  }
  return portrait;
}

/**
 * 解析 User 消息（field 编号对齐 User.proto 简化版）
 * 提取展示需要的字段：id#1 + portrait#2 + name#3 + name_show#4
 * 注意：实际 User.proto 字段编号较复杂，这里只取展示必需字段
 */
function decodeUser(reader: ProtoReader): ReplyUser {
  const user: ReplyUser = new ReplyUser();
  while (!reader.isEnd()) {
    const tag = reader.readTag();
    switch (tag.fieldNumber) {
      case 1:   // id（user_id）
        user.userId = reader.readVarint();
        break;
      case 2:   // portrait
        user.portrait = stripPortraitSuffix(reader.readString());
        break;
      case 3:   // name（user_name）
        user.userName = reader.readString();
        break;
      case 4:   // name_show（nick_name_new）
        user.nickName = reader.readString();
        break;
      default:
        reader.skipField(tag.wireType);
        break;
    }
  }
  return user;
}

/**
 * 解析单条 ReplyList 消息
 * 字段编号对齐 ReplyMeResIdl.proto 中的 ReplyList message
 */
function decodeReplyMessage(reader: ProtoReader): ReplyMessage {
  const msg: ReplyMessage = new ReplyMessage();
  while (!reader.isEnd()) {
    const tag = reader.readTag();
    switch (tag.fieldNumber) {
      case 1:   // thread_id（uint64）
        msg.tid = reader.readVarint();
        break;
      case 2:   // post_id（uint64）
        msg.pid = reader.readVarint();
        break;
      case 3:   // time（uint32）
        msg.createTime = reader.readVarint();
        break;
      case 5:   // fname
        msg.fname = reader.readString();
        break;
      case 6:   // content
        msg.text = reader.readString();
        break;
      case 7:   // is_floor
        msg.isComment = reader.readVarint() !== 0;
        break;
      case 9:   // replyer（User，回复者）
        msg.user = decodeUser(reader.readMessage());
        break;
      case 14:  // quote_pid（uint64）
        msg.ppid = reader.readVarint();
        break;
      case 15:  // quote_user（User，被回复楼层用户）
        msg.postUser = decodeUser(reader.readMessage());
        break;
      case 25:  // thread_author_user（User，楼主）
        msg.threadUser = decodeUser(reader.readMessage());
        break;
      default:
        reader.skipField(tag.wireType);
        break;
    }
  }
  return msg;
}

/**
 * 解析 Page message（对齐 Page.proto 简化版）
 * 字段：current_page#1 + has_more#2 + has_prev#3
 */
function decodeReplysPage(reader: ProtoReader): ReplysPageInfo {
  const page: ReplysPageInfo = new ReplysPageInfo();
  while (!reader.isEnd()) {
    const tag = reader.readTag();
    switch (tag.fieldNumber) {
      case 1:   // current_page
        page.currentPage = reader.readVarint();
        break;
      case 2:   // has_more
        page.hasMore = reader.readVarint() !== 0;
        break;
      case 3:   // has_prev
        page.hasPrev = reader.readVarint() !== 0;
        break;
      default:
        reader.skipField(tag.wireType);
        break;
    }
  }
  return page;
}

/**
 * 解析 ReplyMeResIdl 顶层
 * 结构：error#1 + data#2
 * data 内：page#1 + reply_list#2（repeated ReplyList）
 */
export function decodeReplyMeRes(bytes: Uint8Array): ReplysResult {
  const reader = new ProtoReader(bytes);
  const result: ReplysResult = new ReplysResult();

  try {
    while (!reader.isEnd()) {
      const tag = reader.readTag();
      if (tag.fieldNumber === 1) {
        // error message
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
          throw new Error(`获取回复列表失败 [${errorNo}]: ${errorMsg}`);
        }
      } else if (tag.fieldNumber === 2) {
        // data message
        const dataReader = reader.readMessage();
        while (!dataReader.isEnd()) {
          const dataTag = dataReader.readTag();
          if (dataTag.fieldNumber === 1) {
            // page
            result.page = decodeReplysPage(dataReader.readMessage());
          } else if (dataTag.fieldNumber === 2) {
            // reply_list（repeated message）
            result.list.push(decodeReplyMessage(dataReader.readMessage()));
          } else {
            dataReader.skipField(dataTag.wireType);
          }
        }
      } else {
        reader.skipField(tag.wireType);
      }
    }
    return result;
  } catch (err) {
    throw err instanceof Error ? err : new Error(String(err));
  }
}
