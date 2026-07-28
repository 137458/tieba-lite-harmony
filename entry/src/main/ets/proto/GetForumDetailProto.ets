// GetForumDetail 吧详情 protobuf 编解码（完整版吧内页面切片）
// 字段编号对齐 aiotieba api/get_forum_detail/protobuf/*.proto：
//   - GetForumDetailReqIdl: data=1
//   - DataReq: forum_id=1(int64) / common=2(CommonReq)
//   - GetForumDetailResIdl: error=1 / data=2
//   - DataRes: forum_info=1(RecommendForumInfo) / election_tab=8(ManagerElectionTab)
//   - RecommendForumInfo: avatar=1 / forum_id=2 / forum_name=3 / member_count=5 /
//                          thread_count=6 / slogan=7 / lv1_name=18 / avatar_origin=20
// 端点 POST /c/f/forum/getforumdetail?cmd=303021（multipart protobuf）
// 鉴权：CommonReq.BDUSS (field 10) 必传，_client_version (field 2) 必传

import { ForumDetailInfo } from '../model/ForumModels';
import { ProtoWriter, ProtoReader } from './ProtoWire';
import { STABLE_VERSION } from '../net/TiebaHttpClient';

// ==================== GetForumDetail 请求编码 ====================

/** GetForumDetail 请求参数 */
export interface IGetForumDetailReqParams {
  /** 吧 id（forum_id，int64） */
  forumId: number;
  /** BDUSS（鉴权必传） */
  bduss: string;
}

/**
 * 编码 CommonReq（field 编号对齐 CommonReq.proto）
 * 对齐 aiotieba get_forum_detail/_api.py:pack_proto：
 *   - common._client_version = LATEST_VERSION
 *   - common.BDUSS = account.BDUSS
 * HarmonyOS 端用 STABLE_VERSION 以复用 postProtobuf 协议头，实测服务端兼容
 */
function encodeCommonReq(writer: ProtoWriter, params: IGetForumDetailReqParams): void {
  // _client_version（field 2，string）
  writer.writeString(2, STABLE_VERSION);
  // BDUSS（field 10，string）
  writer.writeString(10, params.bduss);
}

/**
 * 编码 GetForumDetailReqIdl 顶层
 * 字段编号对齐 GetForumDetailReqIdl.proto DataReq:
 *   forum_id=1(int64) / common=2(CommonReq)
 */
export function encodeGetForumDetailReq(params: IGetForumDetailReqParams): Uint8Array {
  const writer = new ProtoWriter();

  // 先编码 data 内部
  const dataWriter = new ProtoWriter();
  // forum_id（field 1，int64 = wire type 0 varint）
  if (params.forumId > 0) {
    dataWriter.writeTag(1, 0);
    dataWriter.writeVarint(params.forumId);
  }
  // common（field 2，嵌套 message）
  const commonWriter = new ProtoWriter();
  encodeCommonReq(commonWriter, params);
  dataWriter.writeMessage(2, commonWriter.finish());

  // 顶层 data（field 1）
  writer.writeMessage(1, dataWriter.finish());
  return writer.finish();
}

// ==================== GetForumDetail 响应解码 ====================

/** GetForumDetail 接口返回结果 */
export class GetForumDetailResult {
  /** 吧详情信息（forum_info 解码结果） */
  forumInfo: ForumDetailInfo = new ForumDetailInfo();
}

/**
 * 解析 RecommendForumInfo（field 编号对齐 GetForumDetailResIdl.DataRes.RecommendForumInfo）
 * 字段：avatar=1 / forum_id=2(uint64) / forum_name=3 / member_count=5(uint32) /
 *      thread_count=6(uint32) / slogan=7 / lv1_name=18 / avatar_origin=20
 * 完整版吧内页面切片仅提取 avatar/forum_id/forum_name/member_count/thread_count/slogan，
 * 其他字段（is_like/content/forum_type/lv1_name/avatar_origin 等）暂不使用
 */
function decodeRecommendForumInfo(reader: ProtoReader): ForumDetailInfo {
  const info = new ForumDetailInfo();
  while (!reader.isEnd()) {
    const tag = reader.readTag();
    switch (tag.fieldNumber) {
      case 1:   // avatar（string，吧头像）
        info.avatar = reader.readString();
        break;
      case 2:   // forum_id（uint64）
        info.forumId = reader.readVarint();
        break;
      case 3:   // forum_name（string）
        info.forumName = reader.readString();
        break;
      case 5:   // member_count（uint32）
        info.memberCount = reader.readVarint();
        break;
      case 6:   // thread_count（uint32）
        info.threadCount = reader.readVarint();
        break;
      case 7:   // slogan（string）
        info.slogan = reader.readString();
        break;
      default:
        // is_like=4 / content=8 / forum_type=9 / authen=10 / recom_reason=11 /
        // is_brand_forum=12 / hot_text=13 / abtest_tag=14 / source=15 / extra=16 /
        // is_private_forum=17 / lv1_name=18 / lv2_name=19 / avatar_origin=20 等
        // 完整版吧内页面切片暂不使用，跳过
        reader.skipField(tag.wireType);
        break;
    }
  }
  return info;
}

/**
 * 解析 GetForumDetailResIdl 顶层
 * 结构：error (field 1) + data (field 2)
 * data 内：forum_info (field 1, RecommendForumInfo) / election_tab (field 8, ManagerElectionTab)
 */
export function decodeGetForumDetailRes(bytes: Uint8Array): GetForumDetailResult {
  const reader = new ProtoReader(bytes);
  const result = new GetForumDetailResult();

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
        throw new Error(`获取吧详情失败 [${errorNo}]: ${errorMsg}`);
      }
    } else if (tag.fieldNumber === 2) {
      // data
      const dataReader = reader.readMessage();
      while (!dataReader.isEnd()) {
        const dataTag = dataReader.readTag();
        if (dataTag.fieldNumber === 1) {
          // forum_info（RecommendForumInfo）
          const forumReader = dataReader.readMessage();
          result.forumInfo = decodeRecommendForumInfo(forumReader);
        } else {
          // election_tab=8 / thread_list=2 / is_bawu_show=4 / bz_apply_info=5 等
          // 完整版吧内页面切片暂不使用，跳过
          dataReader.skipField(dataTag.wireType);
        }
      }
    } else {
      reader.skipField(tag.wireType);
    }
  }

  return result;
}
