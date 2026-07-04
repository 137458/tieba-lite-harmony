// Profile 用户主页 protobuf 编解码（issue #63 切片1）
// 字段编号对齐 TiebaLite-4.0-dev/app/src/main/protos/Profile/ProfileRequestData.proto
// 以及 tbclient.protobuf-main/proto/Profile/ + aiotieba get_uinfo_profile 实现
// wire format 编解码复用 ProtoWire.ets
//
// 权威参考：aiotieba-master/src/aiotieba/api/profile/get_uinfo_profile/_api.py
//   - CMD = 303012
//   - 端点 POST /c/u/user/profile?cmd=303012&format=protobuf
//   - 请求 body: multipart/form-data, part name="data"
//   - common._client_version = LATEST_VERSION, common._client_type = 2
//   - need_post_count = 1, page = 1
//   - uid 或 friend_uid_portrait 二选一
//
// 响应字段映射（对齐 aiotieba UserInfo_pf.from_proto）:
//   data.user.id#2           → uid
//   data.user.name#3         → userName
//   data.user.nameShow#4     → nickName（aiotieba nick_name_new）
//   data.user.portrait#5     → portrait（去掉末尾 ?xxx 13 字符）
//   data.user.fans_num#30   → fanNum
//   data.user.concern_num#31 → followNum（对齐 aiotieba UserInfo_pf.follow_num）
//   data.user.sex#32        → gender（aiotieba 用 sex 非 gender）
//   data.user.intro#34      → sign
//   data.user.has_concerned#35 → isFollowing
//   data.user.post_num#37   → postNum
//   data.user.tb_age#38     → age（string 转 float）
//   data.user.new_tshow_icon#65 → isVip（repeated，非空即 VIP）
//   data.user.tieba_uid#120  → tiebaUid（string 转 number）
//   data.user_agree_info.total_agree_num#14→#1 → agreeNum

import { UserProfileInfo } from '../model/UserProfileModels';
import { ProtoWriter, ProtoReader } from './ProtoWire';
import { LATEST_VERSION } from '../net/TiebaHttpClient';

// ==================== Profile 请求编码 ====================

/** Profile 请求参数（uid 与 portrait 二选一，对齐 aiotieba pack_proto） */
export interface IProfileReqParams {
  /** 用户 uid（>0 时走 uid 字段，< = 0 时走 portrait 字段） */
  uid: number;
  /** portrait 头像标识（uid <= 0 时使用） */
  portrait: string;
}

/**
 * 编码 CommonRequest（field 编号对齐 CommonReq.proto）
 * 对齐 aiotieba get_uinfo_profile.pack_proto：_client_type + _client_version
 * 注意：profile API 用 LATEST_VERSION（22.5.1.0），非 STABLE_VERSION
 */
function encodeCommonReq(writer: ProtoWriter): void {
  writer.writeInt32(1, 2);                       // _client_type = 2
  writer.writeString(2, LATEST_VERSION);        // _client_version（对齐 aiotieba）
}

/**
 * 编码 ProfileRequestData（对齐 TiebaLite-4.0-dev ProfileRequestData.proto）
 * 字段：common#9 + need_post_count#2 + page#15 + (uid#1 或 friend_uid_portrait#16)
 */
function encodeDataReq(params: IProfileReqParams): Uint8Array {
  const writer = new ProtoWriter();

  // need_post_count（field 2）= 1（对齐 aiotieba）
  writer.writeInt32(2, 1);

  // page（field 15）= 1（对齐 aiotieba）
  writer.writeInt32(15, 1);

  // common（field 9，嵌套 CommonRequest message）
  const commonWriter = new ProtoWriter();
  encodeCommonReq(commonWriter);
  writer.writeMessage(9, commonWriter.finish());

  // uid（field 1）或 friend_uid_portrait（field 16）二选一（对齐 aiotieba）
  if (params.uid > 0) {
    writer.writeInt32(1, params.uid);  // 注意：proto 定义为 int64，但 uid < 2^53 安全
  } else if (params.portrait.length > 0) {
    writer.writeString(16, params.portrait);
  }

  return writer.finish();
}

/** 编码 ProfileRequest 顶层（field 1 = data） */
export function encodeProfileReq(params: IProfileReqParams): Uint8Array {
  const writer = new ProtoWriter();
  const dataBytes = encodeDataReq(params);
  writer.writeMessage(1, dataBytes);  // data
  return writer.finish();
}

// ==================== Profile 响应解码 ====================

/**
 * 去掉 portrait 末尾的 ?xxx 13 字符后缀（对齐 aiotieba UserInfo_pf.from_proto）
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
 * 解析 UserAgreeInfo（field 编号对齐 UserAgreeInfo.proto）
 * 结构：total_agree_num#1 + normal_agree_num#2 + user_agree_num#3 + ...
 */
function decodeUserAgreeInfo(reader: ProtoReader): number {
  let totalAgreeNum: number = 0;
  while (!reader.isEnd()) {
    const tag = reader.readTag();
    if (tag.fieldNumber === 1) {  // total_agree_num
      totalAgreeNum = reader.readVarint();
    } else {
      reader.skipField(tag.wireType);
    }
  }
  return totalAgreeNum;
}

/**
 * 解析 Profile 响应中的 User（field 编号对齐 User.proto）
 * 提取用户主页展示所需的字段，填充到 UserProfileInfo
 */
function decodeProfileUser(reader: ProtoReader): UserProfileInfo {
  const profile: UserProfileInfo = new UserProfileInfo();
  // new_tshow_icon(#65) 是 repeated，记录出现次数，>0 即 VIP
  let tshowIconCount: number = 0;

  while (!reader.isEnd()) {
    const tag = reader.readTag();
    switch (tag.fieldNumber) {
      case 2:   // id
        profile.uid = reader.readVarint();
        break;
      case 3:   // name
        profile.userName = reader.readString();
        break;
      case 4:   // nameShow（显示名，对齐 aiotieba nick_name_new）
        profile.nickName = reader.readString();
        profile.nickNameOld = profile.nickName;
        break;
      case 5: { // portrait（去掉末尾 ?xxx 后缀）
        const rawPortrait: string = reader.readString();
        profile.portrait = stripPortraitSuffix(rawPortrait);
        break;
      }
      case 30:  // fans_num
        profile.fanNum = reader.readVarint();
        break;
      case 31:  // concern_num（关注数，对齐 aiotieba UserInfo_pf.follow_num）
        profile.followNum = reader.readVarint();
        break;
      case 32:  // sex（aiotieba 用 sex 字段，非 gender#42）
        profile.gender = reader.readVarint();
        break;
      case 34:  // intro（个性签名）
        profile.sign = reader.readString();
        break;
      case 35:  // has_concerned
        profile.isFollowing = reader.readVarint() !== 0;
        break;
      case 37:  // post_num
        profile.postNum = reader.readVarint();
        break;
      case 38: { // tb_age（string 类型，需转 number）
        const ageStr: string = reader.readString();
        const parsed: number = parseFloat(ageStr);
        profile.age = isNaN(parsed) ? 0 : parsed;
        break;
      }
      case 65:  // new_tshow_icon（repeated TshowInfo，出现即读取并计数）
        reader.readMessage();
        tshowIconCount++;
        break;
      case 120: { // tieba_uid（string 类型，需转 number）
        const tiebaUidStr: string = reader.readString();
        const parsedUid: number = parseInt(tiebaUidStr, 10);
        profile.tiebaUid = isNaN(parsedUid) ? 0 : parsedUid;
        break;
      }
      default:
        reader.skipField(tag.wireType);
        break;
    }
  }

  // new_tshow_icon 出现 >= 1 次即为超级会员（对齐 aiotieba bool(user_proto.new_tshow_icon)）
  profile.isVip = tshowIconCount > 0;
  return profile;
}

/**
 * 解析 ProfileResIdl 顶层
 * 结构：error (field 1) + data (field 2)
 * data 内：user (field 1, User) + user_agree_info (field 14, UserAgreeInfo)
 */
export function decodeProfileRes(bytes: Uint8Array): UserProfileInfo {
  const reader = new ProtoReader(bytes);
  // 初始化默认 profile（若响应缺少 data 则返回空对象）
  let profile: UserProfileInfo = new UserProfileInfo();
  // agreeNum 临时保存，避免 user_agree_info(#14) 先于 user(#1) 出现时被覆盖丢失
  let agreeNum: number = 0;

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
        throw new Error(`获取用户资料失败 [${errorNo}]: ${errorMsg}`);
      }
    } else if (tag.fieldNumber === 2) {
      // data（ProfileResponseData）
      const dataReader = reader.readMessage();
      while (!dataReader.isEnd()) {
        const dataTag = dataReader.readTag();
        if (dataTag.fieldNumber === 1) {
          // user（User proto）
          const userReader = dataReader.readMessage();
          profile = decodeProfileUser(userReader);
        } else if (dataTag.fieldNumber === 14) {
          // user_agree_info（UserAgreeInfo，total_agree_num）
          const agreeReader = dataReader.readMessage();
          agreeNum = decodeUserAgreeInfo(agreeReader);
        } else {
          dataReader.skipField(dataTag.wireType);
        }
      }
    } else {
      reader.skipField(tag.wireType);
    }
  }
  // 最后赋值 agreeNum，避免 user_agree_info 先于 user 出现时丢失
  profile.agreeNum = agreeNum;
  return profile;
}
