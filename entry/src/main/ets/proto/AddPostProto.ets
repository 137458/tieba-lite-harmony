// AddPost 回帖 protobuf 编解码（issue #74）
// 字段编号对齐 aiotieba api/add_post/protobuf/AddPostReqIdl.proto + AddPostResIdl.proto
// 端点 POST /c/c/post/add?cmd=309731（multipart protobuf）
// 表情在 content 中以 #(表情名) 格式插入，对齐 TiebaLite EmoticonManager.kt
// 楼中楼回复时 content 前缀 "回复 #(reply, portrait, userName) :"（对齐 ReplyPage.kt:658）

import { ProtoWriter, ProtoReader } from './ProtoWire';
import { STABLE_VERSION } from '../net/TiebaHttpClient';

// ==================== AddPost 请求编码 ====================

/** AddPost 请求参数 */
export interface IAddPostReqParams {
  /** 回帖内容（含 #(表情名) 表情标记，楼中楼时已含"回复 #(reply, ...) :"前缀） */
  content: string;
  /** 主题帖 tid */
  tid: number;
  /** 贴吧 fid */
  fid: number;
  /** 贴吧名（kw） */
  forumName: string;
  /** 反 CSRF token（tbs） */
  tbs: string;
  /** BDUSS */
  bduss: string;
  /** STOKEN */
  stoken: string;
  /** 当前用户显示名（name_show） */
  nameShow: string;
  /** 设备标识 cuid */
  cuid: string;
  /** 当前时间戳（毫秒） */
  timestamp: number;
  // 楼中楼回复参数（可选，回复主题时不传）
  /** 引用的楼层 pid（楼中楼回复时传） */
  postId?: number;
  /** 子楼层 spid（楼中楼的楼中楼时传） */
  subPostId?: number;
  /** 被回复者 uid（楼中楼时传） */
  replyUid?: number;
}

/** AddPost 接口返回结果 */
export class AddPostResult {
  /** 新楼层/楼中楼 id（成功标志） */
  pid: number = 0;
  /** 主题帖 id（服务端回传） */
  tid: number = 0;
  /** 服务端提示消息 */
  msg: string = '';
  /** 是否需要验证码（true 时调用方应弹验证码） */
  needVcode: boolean = false;
}

/**
 * 编码 CommonReq（对齐 aiotieba CommonReq.proto + TiebaLite ProtobufRequest.kt buildCommonRequest）
 * 字段：_client_type=1 / _client_version=2 / cuid=7 / _timestamp=8 / BDUSS=10 / tbs=11 / net_type=12 / stoken=30
 */
function encodeCommonReq(writer: ProtoWriter, params: IAddPostReqParams): void {
  writer.writeInt32(1, 2);                          // _client_type = 2
  writer.writeString(2, STABLE_VERSION);            // _client_version
  if (params.cuid.length > 0) {
    writer.writeString(7, params.cuid);             // cuid
  }
  if (params.timestamp > 0) {
    // _timestamp（毫秒，约 1.7e12 < 2^53，可用 varint 编码）
    writer.writeTag(8, 0);
    writer.writeVarint(params.timestamp);
  }
  writer.writeString(10, params.bduss);             // BDUSS（必传）
  writer.writeString(11, params.tbs);               // tbs（必传，反 CSRF）
  writer.writeInt32(12, 1);                         // net_type = 1（WIFI）
  if (params.stoken.length > 0) {
    writer.writeString(30, params.stoken);          // stoken（必传，部分操作要求）
  }
}

/**
 * 编码 AddPostReqIdl 顶层
 * 字段编号对齐 AddPostRequestData.proto + aiotieba _api.py pack_proto
 *
 * DataReq 关键字段：
 *   common=1 / tbs=4 / anonymous=6 / can_no_forum=7 / is_feedback=8 / takephoto_num=9 /
 *   entrance_type=10 / vcode_tag=16 / new_vcode=18 / content=19 / reply_uid=20 /
 *   fid=26 / v_fid=28 / v_fname=29 / kw=30 / is_barrage=31 / barrage_time=32 /
 *   tid=45 / quote_id=46 / is_twzhibo_thread=47 / floor_num=48 / repostid=49 /
 *   sub_post_id=50 / is_ad=51 / is_addition=52 / is_giftpost=53 / post_from=55 /
 *   name_show=58 / is_pictxt=60
 */
export function encodeAddPostReq(params: IAddPostReqParams): Uint8Array {
  const writer = new ProtoWriter();

  // 先编码 data 内部
  const dataWriter = new ProtoWriter();

  // common（field 1）
  const commonWriter = new ProtoWriter();
  encodeCommonReq(commonWriter, params);
  dataWriter.writeMessage(1, commonWriter.finish());

  // tbs（field 4，对齐 TiebaLite 双写 common.tbs + DataReq.tbs）
  dataWriter.writeString(4, params.tbs);

  // 固定参数（对齐 aiotieba _api.py:30-77 默认值）
  dataWriter.writeString(6, '1');                   // anonymous = "1"（匿名）
  dataWriter.writeString(7, '0');                   // can_no_forum = "0"
  dataWriter.writeString(8, '0');                   // is_feedback = "0"
  dataWriter.writeString(9, '0');                   // takephoto_num = "0"
  dataWriter.writeString(10, '0');                  // entrance_type = "0"
  dataWriter.writeString(16, '12');                 // vcode_tag = "12"
  dataWriter.writeString(18, '1');                  // new_vcode = "1"

  // content（field 19，核心字段）
  dataWriter.writeString(19, params.content);

  // reply_uid（field 20，楼中楼时传被回复者 uid）
  if (params.replyUid !== undefined && params.replyUid > 0) {
    dataWriter.writeString(20, params.replyUid.toString());
  }

  // fid（field 26，贴吧 id）
  if (params.fid > 0) {
    dataWriter.writeString(26, params.fid.toString());
  }

  // v_fid / v_fname（field 28/29，仅回复主题时填空串，对齐 TiebaLite addPostFlow）
  if (params.postId === undefined || params.postId <= 0) {
    dataWriter.writeString(28, '');
    dataWriter.writeString(29, '');
  }

  // kw（field 30，贴吧名）
  dataWriter.writeString(30, params.forumName);

  // is_barrage（field 31）/ barrage_time（field 32）
  dataWriter.writeString(31, '0');
  if (params.postId === undefined || params.postId <= 0) {
    dataWriter.writeString(32, '0');
  }

  // tid（field 45，主题帖 id）
  dataWriter.writeString(45, params.tid.toString());

  // quote_id（field 46，楼中楼回复时传被回复楼层 pid）
  if (params.postId !== undefined && params.postId > 0) {
    dataWriter.writeString(46, params.postId.toString());
  }

  // is_twzhibo_thread（field 47）
  dataWriter.writeString(47, '0');

  // floor_num（field 48）
  dataWriter.writeString(48, '0');

  // repostid（field 49，楼中楼时与 quote_id 相同）
  if (params.postId !== undefined && params.postId > 0) {
    dataWriter.writeString(49, params.postId.toString());
  }

  // sub_post_id（field 50，楼中楼的楼中楼时传 spid）
  if (params.subPostId !== undefined && params.subPostId > 0) {
    dataWriter.writeString(50, params.subPostId.toString());
  }

  // 固定标记位
  dataWriter.writeString(51, '0');                  // is_ad = "0"
  dataWriter.writeString(52, '0');                  // is_addition = "0"
  dataWriter.writeString(53, '0');                  // is_giftpost = "0"

  // post_from（field 55，对齐 aiotieba "3"）
  dataWriter.writeString(55, '3');

  // name_show（field 58，当前用户显示名）
  dataWriter.writeString(58, params.nameShow);

  // is_pictxt（field 60，纯文本回帖为 "0"）
  dataWriter.writeString(60, '0');

  // 顶层 data（field 1）
  writer.writeMessage(1, dataWriter.finish());
  return writer.finish();
}

// ==================== AddPost 响应解码 ====================

/**
 * 解析 AddPostResIdl 顶层
 * 结构：error (field 1) + data (field 2)
 * data 内：tid=2 / pid=3 / msg=5 / info=14(PostAntiInfo, 含 need_vcode=1)
 */
export function decodeAddPostRes(bytes: Uint8Array): AddPostResult {
  const reader = new ProtoReader(bytes);
  const result = new AddPostResult();

  while (!reader.isEnd()) {
    const tag = reader.readTag();
    if (tag.fieldNumber === 1) {
      // error
      const errReader = reader.readMessage();
      let errorNo: number = 0;
      let errorMsg: string = '';
      while (!errReader.isEnd()) {
        const errTag = errReader.readTag();
        if (errTag.fieldNumber === 1) {             // errorno
          errorNo = errReader.readVarint();
        } else if (errTag.fieldNumber === 2) {      // errmsg
          errorMsg = errReader.readString();
        } else {
          errReader.skipField(errTag.wireType);
        }
      }
      if (errorNo !== 0) {
        throw new Error(`回帖失败 [${errorNo}]: ${errorMsg}`);
      }
    } else if (tag.fieldNumber === 2) {
      // data
      const dataReader = reader.readMessage();
      while (!dataReader.isEnd()) {
        const dataTag = dataReader.readTag();
        if (dataTag.fieldNumber === 2) {            // tid
          const tidStr: string = dataReader.readString();
          const tidNum: number = Number(tidStr);
          result.tid = isNaN(tidNum) ? 0 : tidNum;
        } else if (dataTag.fieldNumber === 3) {     // pid
          const pidStr: string = dataReader.readString();
          const pidNum: number = Number(pidStr);
          result.pid = isNaN(pidNum) ? 0 : pidNum;
        } else if (dataTag.fieldNumber === 5) {     // msg
          result.msg = dataReader.readString();
        } else if (dataTag.fieldNumber === 14) {    // info (PostAntiInfo)
          const infoReader = dataReader.readMessage();
          while (!infoReader.isEnd()) {
            const infoTag = infoReader.readTag();
            if (infoTag.fieldNumber === 1) {        // need_vcode
              const vcodeFlag: number = infoReader.readVarint();
              result.needVcode = vcodeFlag !== 0;
            } else {
              infoReader.skipField(infoTag.wireType);
            }
          }
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
