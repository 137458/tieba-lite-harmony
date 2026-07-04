// UserLike 动态页 protobuf 编解码（issue #50 切片3）
// 字段编号对齐 TiebaLite-4.0-dev/app/src/main/protos/UserLike/UserLike.proto
// wire format 编解码复用 ProtoWire.ets，thread 解码复用 FrsPageProto.decodeThread
// aiotieba 无此 API 实现，对照原版 Android TiebaLite-4.0-dev 手写

import { ThreadInfo, UserInfo, UserLikeResult } from '../model/ForumModels';
import { ProtoWriter, ProtoReader } from './ProtoWire';
import { decodeThread } from './FrsPageProto';
import { STABLE_VERSION } from '../net/TiebaHttpClient';

// ==================== UserLike 请求编码 ====================

/** UserLike 请求参数 */
export interface IUserLikeReqParams {
  /** 页面游标（刷新时传空字符串，加载更多时传上次响应的 pageTag） */
  pageTag: string;
  /** 上次请求的 Unix 时间戳（首次传 0，刷新后由响应更新并持久化） */
  lastRequestUnix: number;
  /** 加载类型：1=下拉刷新 2=加载更多（对齐原版 load_type） */
  loadType: number;
  /** BDUSS（认证凭证，V11 必传） */
  bduss: string;
  /** cuid（设备标识，V11 必传） */
  cuid: string;
  /** _timestamp（毫秒，V11 必传） */
  timestamp: number;
  /** net_type（1=WIFI，V11 必传） */
  netType: number;
  /** stoken（可选，部分操作要求） */
  stoken: string;
}

/**
 * 编码 CommonRequest（field 编号对齐 CommonRequest.proto）
 * 补全 BDUSS/cuid/timestamp/net_type 字段（对齐 AddPostProto.ets 修复模式 + TiebaLite V11 路径）
 * 之前仅传 _client_type + _client_version 导致服务端严格校验失败（关注页无法加载根因）
 */
function encodeCommonReq(writer: ProtoWriter, params: IUserLikeReqParams): void {
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
    writer.writeString(10, params.bduss);     // BDUSS（V11 必传）
  }
  writer.writeInt32(12, params.netType);      // net_type（V11 必传，1=WIFI）
  if (params.stoken.length > 0) {
    writer.writeString(30, params.stoken);    // stoken
  }
}

/**
 * 编码 UserLikeRequest 顶层（field 1 = data）
 * lastRequestUnix 是 uint64，ProtoWriter 无 writeUInt64 方法，
 * 这里用 writeTag(field 3, wire type 0) + writeVarint 手动编码
 */
export function encodeUserLikeReq(params: IUserLikeReqParams): Uint8Array {
  const writer = new ProtoWriter();

  // 先编码 data 内部内容
  const dataWriter = new ProtoWriter();
  // common（field 1）
  const commonWriter = new ProtoWriter();
  encodeCommonReq(commonWriter, params);
  dataWriter.writeMessage(1, commonWriter.finish());
  // pageTag（field 2）
  dataWriter.writeString(2, params.pageTag);
  // lastRequestUnix（field 3，uint64 = wire type 0 varint）
  if (params.lastRequestUnix > 0) {
    dataWriter.writeTag(3, 0);
    dataWriter.writeVarint(params.lastRequestUnix);
  }
  // followType（field 4）：1=关注的人的动态（对齐原 app 行为）
  // followType=0 返回关注吧动态但 recommendType!=1 会被过滤，导致 0 条
  dataWriter.writeInt32(4, 1);
  // loadType（field 5）：1=刷新 2=加载更多
  dataWriter.writeInt32(5, params.loadType);

  // 顶层 data（field 1）
  writer.writeMessage(1, dataWriter.finish());
  return writer.finish();
}

// ==================== UserLike 响应解码 ====================

/**
 * 解析 ConcernData（field 编号对齐 UserLike.proto）
 * threadList (field 1) + recommendType (field 3)
 * recommendType==1 时为正常动态，其他值跳过（对齐原 app ConcernViewModel 渲染逻辑）
 */
function decodeConcernData(reader: ProtoReader, users: Map<number, UserInfo>): ThreadInfo | null {
  let thread: ThreadInfo | null = null;
  let recommendType: number = 0;

  while (!reader.isEnd()) {
    const tag = reader.readTag();
    switch (tag.fieldNumber) {
      case 1: {  // threadList（ThreadInfo）
        const threadReader = reader.readMessage();
        thread = decodeThread(threadReader, users, '');
        break;
      }
      case 3:  // recommendType
        recommendType = reader.readVarint();
        break;
      default:
        reader.skipField(tag.wireType);
        break;
    }
  }

  // 仅 recommendType==1 时为正常动态，对齐原 app ConcernPage.kt:97 的渲染过滤逻辑
  if (thread === null) {
    return null;
  }
  if (recommendType !== 1) {
    return null;
  }
  return thread;
}

/**
 * 解析 UserLikeResponse 顶层
 * 结构：error (field 1) + data (field 2)
 * data 内：threadInfo (field 1, repeated ConcernData) + pageTag (field 2) + hasMore (field 4) + requestUnix (field 10)
 */
export function decodeUserLikeRes(bytes: Uint8Array): UserLikeResult {
  const reader = new ProtoReader(bytes);
  const result = new UserLikeResult();
  // UserLike 响应无 user_list，传空 map，author 由 decodeThread 的 field 18 内嵌解析
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
        throw new Error(`获取动态失败 [${errorNo}]: ${errorMsg}`);
      }
    } else if (tag.fieldNumber === 2) {
      // data
      const dataReader = reader.readMessage();
      while (!dataReader.isEnd()) {
        const dataTag = dataReader.readTag();
        if (dataTag.fieldNumber === 1) {
          // threadInfo（repeated ConcernData）
          const concernReader = dataReader.readMessage();
          const thread = decodeConcernData(concernReader, emptyUsers);
          if (thread !== null) {
            result.threadList.push(thread);
          }
        } else if (dataTag.fieldNumber === 2) {
          // pageTag
          result.pageTag = dataReader.readString();
        } else if (dataTag.fieldNumber === 4) {
          // hasMore
          result.hasMore = dataReader.readVarint() !== 0;
        } else if (dataTag.fieldNumber === 10) {
          // requestUnix
          result.requestUnix = dataReader.readVarint();
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
