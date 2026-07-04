// Personalized 个性推荐 protobuf 编解码（issue #44）
// 字段编号对齐 TiebaLite-4.0-dev/app/src/main/protos/Personalized.proto
// wire format 编解码复用 ProtoWire.ets，thread 解码复用 FrsPageProto.decodeThread
// aiotieba 无此 API 实现，对照原版 Android TiebaLite-4.0-dev 手写

import { ThreadInfo, UserInfo } from '../model/ForumModels';
import { ProtoWriter, ProtoReader } from './ProtoWire';
import { decodeThread } from './FrsPageProto';
import { STABLE_VERSION } from '../net/TiebaHttpClient';

// ==================== Personalized 请求编码 ====================

/** Personalized 请求参数 */
export interface IPersonalizedReqParams {
  /** 加载类型：1=下拉刷新 2=加载更多（对齐原版 load_type） */
  loadType: number;
  /** 页码（pn） */
  pn: number;
  /** 每页帖子数量（page_thread_count），原版默认 11 */
  pageThreadCount: number;
  /** BDUSS（认证凭证，V12 必传） */
  bduss: string;
  /** cuid（设备标识，V12 必传） */
  cuid: string;
  /** _timestamp（毫秒，V12 必传） */
  timestamp: number;
  /** net_type（1=WIFI，V12 必传） */
  netType: number;
  /** stoken（可选，部分操作要求） */
  stoken: string;
}

/**
 * 编码 CommonRequest（field 编号对齐 CommonRequest.proto）
 * 补全 BDUSS/cuid/timestamp/net_type 字段（对齐 AddPostProto.ets 修复模式 + TiebaLite V12 路径）
 * 之前仅传 _client_type + _client_version 导致服务端严格校验失败（推荐页无法加载根因）
 */
function encodeCommonReq(writer: ProtoWriter, params: IPersonalizedReqParams): void {
  writer.writeInt32(1, 2);                    // _client_type = 2
  writer.writeString(2, STABLE_VERSION);      // _client_version
  if (params.cuid.length > 0) {
    writer.writeString(7, params.cuid);       // cuid
  }
  if (params.timestamp > 0) {
    // _timestamp（毫秒，约 1.7e12 < 2^53，可用 varint 编码）
    writer.writeTag(8, 0);
    writer.writeVarint(params.timestamp);
  }
  if (params.bduss.length > 0) {
    writer.writeString(10, params.bduss);     // BDUSS（V12 必传）
  }
  writer.writeInt32(12, params.netType);      // net_type（V12 必传，1=WIFI）
  if (params.stoken.length > 0) {
    writer.writeString(30, params.stoken);    // stoken
  }
}

/** 编码 PersonalizedRequestData */
function encodeDataReq(params: IPersonalizedReqParams): Uint8Array {
  const writer = new ProtoWriter();
  // common（field 1，嵌套 CommonRequest message）
  const commonWriter = new ProtoWriter();
  encodeCommonReq(commonWriter, params);
  writer.writeMessage(1, commonWriter.finish());

  // load_type（field 4）：1=刷新 2=加载更多
  writer.writeInt32(4, params.loadType);
  // page_thread_count（field 5）：每页帖子数
  writer.writeInt32(5, params.pageThreadCount);
  // pn（field 6）：页码
  writer.writeInt32(6, params.pn);
  // q_type（field 11）：原版传 1
  writer.writeInt32(11, 1);
  // need_forumlist（field 22）：0
  writer.writeInt32(22, 0);
  // new_net_type（field 23）：1
  writer.writeInt32(23, 1);
  // new_install（field 27）：0
  writer.writeInt32(27, 0);
  // request_times（field 28）：0
  writer.writeInt32(28, 0);

  return writer.finish();
}

/** 编码 PersonalizedRequest 顶层（field 1 = data） */
export function encodePersonalizedReq(params: IPersonalizedReqParams): Uint8Array {
  const writer = new ProtoWriter();
  const dataBytes = encodeDataReq(params);
  writer.writeMessage(1, dataBytes);  // data
  return writer.finish();
}

// ==================== Personalized 响应解码 ====================

/** Personalized 解析结果（hasMore 由调用方根据返回是否为空决定） */
export class PersonalizedResult {
  threads: ThreadInfo[] = [];
}

/**
 * 解析 PersonalizedResponse 顶层
 * 结构：error (field 1) + data (field 2)
 * data 内：thread_list (field 2, repeated ThreadInfo) + thread_personalized (field 7)
 * thread_list 解码复用 FrsPageProto.decodeThread（传空 users map，author 从 field 18 内嵌获取）
 */
export function decodePersonalizedRes(bytes: Uint8Array): PersonalizedResult {
  const reader = new ProtoReader(bytes);
  const result = new PersonalizedResult();
  // personalized 响应无 user_list，传空 map，author 由 decodeThread 的 field 18 内嵌解析
  const emptyUsers = new Map<number, UserInfo>();

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
        throw new Error(`获取个性推荐失败 [${errorNo}]: ${errorMsg}`);
      }
    } else if (tag.fieldNumber === 2) {
      // data
      const dataReader = reader.readMessage();
      while (!dataReader.isEnd()) {
        const dataTag = dataReader.readTag();
        if (dataTag.fieldNumber === 2) {
          // thread_list（repeated ThreadInfo），复用 FrsPageProto.decodeThread
          const threadReader = dataReader.readMessage();
          const thread = decodeThread(threadReader, emptyUsers, '');
          result.threads.push(thread);
        } else {
          dataReader.skipField(dataTag.wireType);
        }
      }
    } else {
      reader.skipField(tag.wireType);
    }
  }
  return result;
}
