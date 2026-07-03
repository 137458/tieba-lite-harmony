// PbPage protobuf 编解码（issue #7）
// 字段编号对齐 tbclient.protobuf-main/proto/PbPage 原定义
// wire format 编解码复用 ProtoWire.ets
// 用于 getPosts（帖子详情/回复列表），cmd=302001

import { PostInfo, UserInfo, PageData, ThreadInfo, MediaInfo } from '../model/ForumModels';
import { ProtoWriter, ProtoReader } from './ProtoWire';
import { getAvatarUrl } from '../utils/AvatarUtil';

// ==================== PbPage 请求编码 ====================

/** PbPage 请求参数 */
export interface IPbPageReqParams {
  tid: number;           // 主题帖 id（proto 字段名 kz）
  pn: number;            // 页码
  rn: number;            // 每页回复数
  sort: number;          // 排序方式（0=默认, 1=倒序, 2=正序）
  onlyAuthor: boolean;   // 只看楼主
  clientVersion: string;
  // 账号字段可选：with_comments=true 时需要 BDUSS
  bduss?: string;
  // 修复 350004：补全 CommonReq 必需字段（对齐 Android V12 ProtobufRequest.kt buildCommonRequest）
  cuid?: string;         // field 7：设备标识（Android V12 必传）
  timestamp?: number;    // field 8：当前时间戳（毫秒，Android V12 必传）
  netType?: number;      // field 12：网络类型（1=WIFI, Android V12 必传）
}

/**
 * 编码 CommonReq（field 编号对齐 CommonReq.proto）
 * 修复 350004：补全 Android V12 必传字段（cuid/timestamp/net_type）
 * 之前仅传 _client_type + _client_version + BDUSS，服务端对 Android UA 请求做严格字段校验导致 350004
 */
function encodeCommonReq(writer: ProtoWriter, params: IPbPageReqParams): void {
  writer.writeInt32(1, 2);                     // _client_type = 2
  writer.writeString(2, params.clientVersion); // _client_version
  if (params.cuid !== undefined && params.cuid.length > 0) {
    writer.writeString(7, params.cuid);        // cuid（Android V12 必传）
  }
  if (params.timestamp !== undefined && params.timestamp > 0) {
    // _timestamp（毫秒，Android V12 必传）
    // timestamp 约 1.7e12 < 2^53，可用 varint 编码（int64 在 JS number 精度内）
    writer.writeTag(8, 0);
    writer.writeVarint(params.timestamp);
  }
  if (params.bduss !== undefined && params.bduss.length > 0) {
    writer.writeString(10, params.bduss);      // BDUSS（Android V12 总是设）
  }
  if (params.netType !== undefined && params.netType > 0) {
    writer.writeInt32(12, params.netType);     // net_type（1=WIFI，Android V12 必传）
  }
}

/** 编码 DataReq（field 编号对齐 PbPageReqIdl.proto） */
function encodeDataReq(params: IPbPageReqParams): Uint8Array {
  const writer = new ProtoWriter();
  writer.writeInt32(4, params.tid);                          // kz = tid
  writer.writeInt32(5, params.onlyAuthor ? 1 : 0);           // lz = only_thread_author
  writer.writeInt32(6, params.sort);                         // r = sort
  // rn：对齐 aiotieba（rn > 1 时原样传，否则传 2）
  writer.writeInt32(13, params.rn > 1 ? params.rn : 2);      // rn
  writer.writeInt32(18, params.pn);                          // pn

  // common（field 25，嵌套 message）
  const commonWriter = new ProtoWriter();
  encodeCommonReq(commonWriter, params);
  writer.writeMessage(25, commonWriter.finish());

  return writer.finish();
}

/** 编码 PbPageReqIdl 顶层 */
export function encodePbPageReq(params: IPbPageReqParams): Uint8Array {
  const writer = new ProtoWriter();
  const dataBytes = encodeDataReq(params);
  writer.writeMessage(1, dataBytes);  // data
  return writer.finish();
}

// ==================== PbPage 响应解码 ====================

/** PbPage 解析结果 */
export class PbPageResult {
  posts: PageData<PostInfo> = new PageData<PostInfo>();
  thread: ThreadInfo = new ThreadInfo();  // 主题帖信息（标题等）
}

/** 解析 User（field 编号对齐 User.proto，与 FrsPageProto.decodeUser 一致） */
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
      case 5: {  // portrait（短标识符如 "tb.0.xxx"，需拼接完整 URL）
        const portrait: string = reader.readString();
        // 保存原始 portrait 标识符，用于用户主页 API 查询
        user.portrait = portrait;
        // 对齐 aiotieba client.py:1221：小头像 55x55（AvatarUtil 内部已处理清洗+空值）
        user.avatar = getAvatarUrl(portrait, 's');
        break;
      }
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

/**
 * 解析 Post 的 content 碎片（field 编号对齐 PbContent.proto）
 * 提取 type=0/9/18/27/40 的 text 字段拼接成正文；
 * 提取 type=3/20 的图片碎片字段（cdn_src/big_cdn_src/origin_src）填充 mediaList
 * 对齐 aiotieba get_posts/_classdef.py Contents_p.from_proto + FragImage_p.from_proto
 */
function decodePostContent(reader: ProtoReader, mediaList: MediaInfo[]): string {
  let text: string = '';
  // proto3 默认值 0 = 纯文本（对齐 aiotieba _classdef.py:155-157: _type in [0,9,18,27,40] 为纯文本）
  let currentType: number = 0;
  // 图片碎片字段（type=3/20 时有效，对齐 FragImage_p.from_proto）
  let cdnSrc: string = '';        // field 8 — 小图 CDN 链接
  let bigCdnSrc: string = '';     // field 9 — 大图 CDN 链接
  let originSrc: string = '';     // field 25 — 原图链接
  let bsize: string = '';         // field 5 — "width,height" 显示尺寸

  while (!reader.isEnd()) {
    const tag = reader.readTag();
    if (tag.fieldNumber === 1) {
      // type（0=纯文本, 2/11=表情, 3/20=图片, 4=@, 1=链接, 9电话号, 10语音, 5视频...）
      currentType = reader.readVarint();
    } else if (tag.fieldNumber === 2) {
      // text —— 仅纯文本类碎片（type=0/9/18/27/40）才拼接（对齐 aiotieba FragText_pt）
      const textValue: string = reader.readString();
      if (currentType === 0 || currentType === 9 || currentType === 18
          || currentType === 27 || currentType === 40) {
        text += textValue;
      }
    } else if (tag.fieldNumber === 5) {
      // bsize —— 图片显示尺寸 "width,height"
      bsize = reader.readString();
    } else if (tag.fieldNumber === 8) {
      // cdn_src —— 小图 CDN 链接
      cdnSrc = reader.readString();
    } else if (tag.fieldNumber === 9) {
      // big_cdn_src —— 大图 CDN 链接
      bigCdnSrc = reader.readString();
    } else if (tag.fieldNumber === 25) {
      // origin_src —— 原图链接
      originSrc = reader.readString();
    } else {
      reader.skipField(tag.wireType);
    }
  }

  // type=3/20 为图片碎片（对齐 aiotieba Contents_p._frags: _type in [3, 20]）
  if (currentType === 3 || currentType === 20) {
    const media: MediaInfo = new MediaInfo();
    // URL 优先级：origin > big_cdn > cdn（对齐 FragImage_p）
    if (originSrc.length > 0) {
      media.url = originSrc;
    } else if (bigCdnSrc.length > 0) {
      media.url = bigCdnSrc;
    } else {
      media.url = cdnSrc;
    }
    // 缩略图用小图 cdn_src
    media.thumbnail = cdnSrc;
    // 解析 bsize "width,height"
    if (bsize.length > 0) {
      const parts: string[] = bsize.split(',');
      if (parts.length >= 2) {
        media.width = Number(parts[0]) || 0;
        media.height = Number(parts[1]) || 0;
      }
    }
    // 仅当有有效 URL 时才加入列表
    if (media.url.length > 0) {
      mediaList.push(media);
    }
  }

  return text;
}

/** 解析 Post（field 编号对齐 Post.proto） */
function decodePost(reader: ProtoReader, users: Map<number, UserInfo>, threadTid: number): PostInfo {
  const post = new PostInfo();
  post.tid = threadTid;
  let authorId: number = 0;
  let contentText: string = '';

  while (!reader.isEnd()) {
    const tag = reader.readTag();
    switch (tag.fieldNumber) {
      case 1:   // id（pid）
        post.pid = reader.readVarint();
        break;
      case 3:   // floor
        post.floor = reader.readVarint();
        break;
      case 4:   // time（create_time）
        post.createTime = reader.readVarint();
        break;
      case 5: {  // content（repeated PbContent）
        const contentReader = reader.readMessage();
        contentText += decodePostContent(contentReader, post.mediaList);
        break;
      }
      case 13:  // sub_post_number（楼中楼数 = replyNum）
        post.replyNum = reader.readVarint();
        break;
      case 19:  // author_id
        authorId = reader.readVarint();
        break;
      case 37: {  // agree（AgreeInfo: agree_num=1, disagree_num=4）
        const agreeReader = reader.readMessage();
        while (!agreeReader.isEnd()) {
          const agreeTag = agreeReader.readTag();
          if (agreeTag.fieldNumber === 1) {        // agree_num
            post.agreeNum = agreeReader.readVarint();
          } else if (agreeTag.fieldNumber === 4) { // disagree_num
            post.disagreeNum = agreeReader.readVarint();
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

  post.content = contentText;

  // 从 user_list 中查找作者
  if (authorId > 0) {
    const user = users.get(authorId);
    if (user !== undefined) {
      post.author = user;
    }
  }

  return post;
}

/**
 * 解析 PbPageResIdl 顶层
 * 对齐 aiotieba get_posts.parse_body + Posts.from_proto
 * 关联逻辑：先收集 user_list，再解析 post_list（避免字段顺序问题）
 */
export function decodePbPageRes(bytes: Uint8Array): PbPageResult {
  const reader = new ProtoReader(bytes);
  const result = new PbPageResult();

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
        throw new Error(`获取回复列表失败 [${errorNo}]: ${errorMsg}`);
      }
    } else if (tag.fieldNumber === 2) {
      // data
      const dataReader = reader.readMessage();
      const users = new Map<number, UserInfo>();
      const rawPosts: ProtoReader[] = [];  // 先收集 post_list raw bytes
      let threadTid: number = 0;
      let threadAuthorId: number = 0;
      let forumName: string = '';

      // 第一遍：收集 forum/page/user_list/thread，post_list 只存 raw bytes
      while (!dataReader.isEnd()) {
        const dataTag = dataReader.readTag();
        if (dataTag.fieldNumber === 2) {
          // forum（SimpleForum）：id=1, name=2
          const forumReader = dataReader.readMessage();
          while (!forumReader.isEnd()) {
            const forumTag = forumReader.readTag();
            if (forumTag.fieldNumber === 1) {        // id
              forumReader.readVarint();
            } else if (forumTag.fieldNumber === 2) { // name
              forumName = forumReader.readString();
            } else {
              forumReader.skipField(forumTag.wireType);
            }
          }
        } else if (dataTag.fieldNumber === 3) {
          // page（Page）：current_page=3, total_page=5, has_more=6
          const pageReader = dataReader.readMessage();
          while (!pageReader.isEnd()) {
            const pageTag = pageReader.readTag();
            if (pageTag.fieldNumber === 3) {         // current_page
              result.posts.currentPage = pageReader.readVarint();
            } else if (pageTag.fieldNumber === 5) {  // total_page
              result.posts.totalPage = pageReader.readVarint();
            } else if (pageTag.fieldNumber === 6) {  // has_more
              result.posts.hasMore = pageReader.readVarint() !== 0;
            } else {
              pageReader.skipField(pageTag.wireType);
            }
          }
        } else if (dataTag.fieldNumber === 6) {
          // post_list（repeated）—— 先存 raw bytes，第二遍再解码
          rawPosts.push(dataReader.readMessage());
        } else if (dataTag.fieldNumber === 8) {
          // thread（ThreadInfo）—— 提取 tid、title、reply_num、view_num、create_time、forum_name、author_id、agree
          // 字段编号对齐 tbclient.protobuf-main/Post/Thread.proto：
          //   tid=2, title=3, reply_num=4, view_num=5, create_time=45, forum_name=28, author_id=56, agree=126（AgreeInfo）
          const threadReader = dataReader.readMessage();
          while (!threadReader.isEnd()) {
            const threadTag = threadReader.readTag();
            if (threadTag.fieldNumber === 2) {       // tid（ThreadInfo.id）
              threadTid = threadReader.readVarint();
              result.thread.tid = threadTid;
            } else if (threadTag.fieldNumber === 3) { // title
              result.thread.title = threadReader.readString();
            } else if (threadTag.fieldNumber === 4) { // reply_num（总回复数）
              result.thread.replyNum = threadReader.readVarint();
            } else if (threadTag.fieldNumber === 5) { // view_num（浏览数）
              result.thread.viewNum = threadReader.readVarint();
            } else if (threadTag.fieldNumber === 28) { // forum_name（吧名，优先于 forum 字段）
              result.thread.forumName = threadReader.readString();
            } else if (threadTag.fieldNumber === 45) { // create_time（创建时间戳，秒）
              result.thread.createTime = threadReader.readVarint();
            } else if (threadTag.fieldNumber === 56) { // author_id（作者 uid）
              threadAuthorId = threadReader.readVarint();
            } else if (threadTag.fieldNumber === 126) { // agree（AgreeInfo，#69 主题帖点赞）
              const agreeReader = threadReader.readMessage();
              while (!agreeReader.isEnd()) {
                const agreeTag = agreeReader.readTag();
                if (agreeTag.fieldNumber === 1) {        // agree_num
                  result.thread.agreeNum = agreeReader.readVarint();
                } else if (agreeTag.fieldNumber === 4) { // disagree_num
                  result.thread.disagreeNum = agreeReader.readVarint();
                } else {
                  agreeReader.skipField(agreeTag.wireType);
                }
              }
            } else {
              threadReader.skipField(threadTag.wireType);
            }
          }
        } else if (dataTag.fieldNumber === 13) {
          // user_list（repeated）
          const userReader = dataReader.readMessage();
          const user = decodeUser(userReader);
          users.set(user.uid, user);
        } else {
          dataReader.skipField(dataTag.wireType);
        }
      }

      // 第一遍结束后：补全 thread.forumName（若 thread 内嵌吧名缺失则用 forum 字段）
      if (result.thread.forumName.length === 0 && forumName.length > 0) {
        result.thread.forumName = forumName;
      }
      // 补全 thread.author（从 user_list 查找作者信息）
      if (threadAuthorId > 0) {
        const author = users.get(threadAuthorId);
        if (author !== undefined) {
          result.thread.author = author;
        }
      }

      // 第二遍：解析 posts（此时 users map 已全部填充，author 关联可靠）
      const posts: PostInfo[] = [];
      for (let i = 0; i < rawPosts.length; i++) {
        posts.push(decodePost(rawPosts[i], users, threadTid));
      }
      result.posts.list = posts;
    } else {
      reader.skipField(tag.wireType);
    }
  }

  return result;
}
