// UserPost 用户主页发帖历史 protobuf 编解码（issue #75）
// 字段编号对齐 aiotieba api/get_user_contents/protobuf/UserPostReqIdl.proto + UserPostResIdl.proto
// 响应 PostInfoList 字段编号对齐 aiotieba api/_protobuf/PostInfoList.proto
// 端点 POST /c/u/feed/userpost?cmd=303002（multipart protobuf）
// 注意：aiotieba 在 get_posts/_api.py 中 USER_POSTS_VERSION="8"（非 LATEST_VERSION），
// 但 HarmonyOS 端统一用 STABLE_VERSION（12.64.1.1）以复用 postProtobuf，实测服务端兼容

import { ThreadInfo, UserInfo, MediaInfo, MediaType } from '../model/ForumModels';
import { ProtoWriter, ProtoReader } from './ProtoWire';
import { STABLE_VERSION } from '../net/TiebaHttpClient';

// ==================== UserPost 请求编码 ====================

/** UserPost 请求参数 */
export interface IUserPostReqParams {
  /** 用户 uid（int64，贴吧 user_id） */
  uid: number;
  /** 页码（pn），从 1 开始 */
  pn: number;
  /** 每页条数（rn），默认 20，最大 74 */
  rn: number;
}

/** UserPost 接口返回结果 */
export class UserPostResult {
  /** 帖子列表（每个 PostInfoList 转为一条 ThreadInfo 卡片） */
  threadList: ThreadInfo[] = [];
  /** 是否有更多数据：服务端无 has_more 字段，用 `post_list.length < rn` 判断 */
  hasMore: boolean = false;
}

/**
 * 编码 CommonReq（对齐 aiotieba get_posts/_api.py:18-20）
 * 仅传 BDUSS + _client_version（USER_POSTS_VERSION="8" 在 aiotieba 中，
 * 但 HarmonyOS 用 STABLE_VERSION 以复用 postProtobuf 协议头）
 */
function encodeCommonReq(writer: ProtoWriter, bduss: string): void {
  // CommonReq.BDUSS (field 10, string) - 对齐 aiotieba req_proto.data.common.BDUSS = account.BDUSS
  writer.writeString(10, bduss);
  // CommonReq._client_version (field 2, string)
  writer.writeString(2, STABLE_VERSION);
}

/**
 * 编码 UserPostReqIdl 顶层
 * 字段编号对齐 UserPostReqIdl.proto DataReq:
 *   uid=1(int64) / rn=2(uint32) / is_thread=4 / need_content=5 / pn=26(uint32) / is_view_card=33 / common=27
 */
export function encodeUserPostReq(params: IUserPostReqParams, bduss: string): Uint8Array {
  const writer = new ProtoWriter();

  // 先编码 data 内部
  const dataWriter = new ProtoWriter();
  // common（field 27）
  const commonWriter = new ProtoWriter();
  encodeCommonReq(commonWriter, bduss);
  dataWriter.writeMessage(27, commonWriter.finish());
  // uid（field 1，int64 = wire type 0 varint）
  if (params.uid > 0) {
    dataWriter.writeTag(1, 0);
    dataWriter.writeVarint(params.uid);
  }
  // need_content（field 5，固定 1，对齐 aiotieba pack_proto）
  dataWriter.writeInt32(5, 1);
  // is_thread（field 4，固定 1，对齐 aiotieba get_threads/_api.py:21）
  // is_thread=1 拉取主题帖列表（UserThreads），不设默认 0 返回回复列表（UserPostss）
  // Android UserPostPage 默认 isThread=true 也走此分支
  dataWriter.writeInt32(4, 1);
  // pn（field 26，uint32）
  dataWriter.writeInt32(26, params.pn);
  // rn（field 2，uint32）
  dataWriter.writeInt32(2, params.rn);

  // 顶层 data（field 1）
  writer.writeMessage(1, dataWriter.finish());
  return writer.finish();
}

// ==================== UserPost 响应解码 ====================

/**
 * 解析 PostInfoList 内的 PostInfoContent.PostContent（Abstract）
 * 字段：type=1 / text=2 / link=3 / during_time=6 / voice_md5=7
 * 返回拼接后的文本（type 0/4 纯文本 + type 1 链接标题）
 */
function decodePostContentText(reader: ProtoReader): string {
  let text: string = '';
  while (!reader.isEnd()) {
    const tag = reader.readTag();
    if (tag.fieldNumber === 2) {  // text
      text += reader.readString();
    } else {
      reader.skipField(tag.wireType);
    }
  }
  return text;
}

/**
 * 解析 PostInfoContent（field 编号对齐 PostInfoList.proto PostInfoContent）
 * 字段：post_content=1(repeated Abstract) / create_time=2 / post_type=3 / post_id=4
 * 返回该回复的文本（post_content 中所有 Abstract 的 text 拼接）
 */
function decodePostInfoContent(reader: ProtoReader): string {
  let text: string = '';
  while (!reader.isEnd()) {
    const tag = reader.readTag();
    if (tag.fieldNumber === 1) {  // post_content（repeated Abstract）
      const absReader = reader.readMessage();
      text += decodePostContentText(absReader);
    } else {
      reader.skipField(tag.wireType);
    }
  }
  return text;
}

/**
 * 解析 PostInfoList 顶层（field 编号对齐 PostInfoList.proto）
 * 字段：forum_id=1 / thread_id=2 / post_id=3 / create_time=5 / forum_name=6 / title=7 /
 *      content=8(repeated PostInfoContent) / user_name=10 / media=16 / reply_num=17 /
 *      user_id=18 / user_portrait=19 / name_show=35 / share_num=39 / agree=40 / first_post_content=49
 *
 * 简化策略：每个 PostInfoList 转为一条 ThreadInfo 卡片
 *   - tid = thread_id, title = title, forumName = forum_name
 *   - content = 第一个 content 的 post_content 文本拼接（用户在该帖中的第一条回复）
 *   - createTime = create_time, replyNum = reply_num, agreeNum = agree.agree_num
 *   - author = UserInfo(user_id, user_name, user_portrait, name_show)
 */
function decodePostInfoList(reader: ProtoReader): ThreadInfo {
  const thread = new ThreadInfo();
  const author = new UserInfo();
  let firstContentText: string = '';

  while (!reader.isEnd()) {
    const tag = reader.readTag();
    switch (tag.fieldNumber) {
      case 2:   // thread_id（uint64）
        thread.tid = reader.readVarint();
        break;
      case 5:   // create_time（uint32）
        thread.createTime = reader.readVarint();
        break;
      case 6:   // forum_name（string）
        thread.forumName = reader.readString();
        break;
      case 7:   // title（string）
        thread.title = reader.readString();
        break;
      case 8: {  // content（repeated PostInfoContent）- 取第一个非空的作为正文摘要
        const contentReader = reader.readMessage();
        const text: string = decodePostInfoContent(contentReader);
        if (firstContentText.length === 0 && text.length > 0) {
          firstContentText = text;
        }
        break;
      }
      case 10:  // user_name（string）
        author.name = reader.readString();
        break;
      case 16: {  // media（repeated Media）- 简化：仅取图片 URL
        const mediaReader = reader.readMessage();
        const media = decodeMedia(mediaReader);
        if (media.url.length > 0) {
          thread.mediaList.push(media);
        }
        break;
      }
      case 17:  // reply_num（uint32）
        thread.replyNum = reader.readVarint();
        break;
      case 18:  // user_id（int64）
        author.uid = reader.readVarint();
        break;
      case 19:  // user_portrait（string）
        author.portrait = reader.readString();
        break;
      case 35:  // name_show（string，对齐 UserInfo_u.nick_name_new）
        author.nickname = reader.readString();
        break;
      case 40: {  // agree（Agree message: agree_num=1, disagree_num=4）
        const agreeReader = reader.readMessage();
        while (!agreeReader.isEnd()) {
          const agreeTag = agreeReader.readTag();
          if (agreeTag.fieldNumber === 1) {
            thread.agreeNum = agreeReader.readVarint();
          } else {
            agreeReader.skipField(agreeTag.wireType);
          }
        }
        break;
      }
      default:
        reader.skipField(tag.wireType);
        break;
    }
  }

  // 正文：优先用第一条回复文本，否则用标题 fallback
  thread.content = firstContentText.length > 0 ? firstContentText : thread.title;
  thread.author = author;
  return thread;
}

/**
 * 解析 Media message（简化版，对齐 Media.proto 关键字段）
 * 字段：type=1 / origin_pic=3 / big_pic=4 / small_pic=5 / width=6 / height=7
 */
function decodeMedia(reader: ProtoReader): MediaInfo {
  const media = new MediaInfo();
  let mediaType: number = 0;
  while (!reader.isEnd()) {
    const tag = reader.readTag();
    switch (tag.fieldNumber) {
      case 1:  // type
        mediaType = reader.readVarint();
        if (mediaType === 5) {
          media.type = MediaType.VIDEO;
        } else {
          media.type = MediaType.IMAGE;
        }
        break;
      case 3:  // origin_pic
        media.url = reader.readString();
        break;
      case 4:  // big_pic
        if (media.url.length === 0) {
          media.url = reader.readString();
        } else {
          reader.skipField(tag.wireType);
        }
        break;
      case 5:  // small_pic
        media.thumbnail = reader.readString();
        break;
      default:
        reader.skipField(tag.wireType);
        break;
    }
  }
  return media;
}

/**
 * 解析 UserPostResIdl 顶层
 * 结构：error (field 1) + data (field 2)
 * data 内：post_list (field 1, repeated PostInfoList)
 * 服务端无 has_more 字段，客户端用 `post_list.length < rn` 判断末页
 */
export function decodeUserPostRes(bytes: Uint8Array, rn: number): UserPostResult {
  const reader = new ProtoReader(bytes);
  const result = new UserPostResult();

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
        throw new Error(`获取用户发帖失败 [${errorNo}]: ${errorMsg}`);
      }
    } else if (tag.fieldNumber === 2) {
      // data
      const dataReader = reader.readMessage();
      while (!dataReader.isEnd()) {
        const dataTag = dataReader.readTag();
        if (dataTag.fieldNumber === 1) {
          // post_list（repeated PostInfoList）
          const postReader = dataReader.readMessage();
          const thread = decodePostInfoList(postReader);
          if (thread.tid > 0) {
            result.threadList.push(thread);
          }
        } else {
          dataReader.skipField(dataTag.wireType);
        }
      }
    } else {
      reader.skipField(tag.wireType);
    }
  }

  // 末页判断：返回条数 < 请求 rn 视为末页（对齐 aiotieba 无 has_more 字段的判断方式）
  result.hasMore = result.threadList.length >= rn && result.threadList.length > 0;
  return result;
}
