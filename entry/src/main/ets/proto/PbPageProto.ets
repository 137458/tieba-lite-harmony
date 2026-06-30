// PbPage protobuf 编解码（issue #7）
// 字段编号对齐 tbclient.protobuf-main/proto/PbPage 原定义
// wire format 编解码复用 ProtoWire.ets
// 用于 getPosts（帖子详情/回复列表），cmd=302001

import { PostInfo, UserInfo, PageData, ThreadInfo } from '../model/ForumModels';
import { ProtoWriter, ProtoReader } from './ProtoWire';

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
}

/**
 * 编码 CommonReq（field 编号对齐 CommonReq.proto）
 * 对齐 aiotieba get_posts.pack_proto：仅传 _client_type + _client_version
 * with_comments 时才传 BDUSS
 */
function encodeCommonReq(writer: ProtoWriter, params: IPbPageReqParams): void {
  writer.writeInt32(1, 2);                     // _client_type = 2
  writer.writeString(2, params.clientVersion); // _client_version
  if (params.bduss !== undefined) {
    writer.writeString(10, params.bduss);      // BDUSS
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

/**
 * 解析 Post 的 content 碎片（field 编号对齐 Abstract.proto / PbContent）
 * 只提取 type=0（纯文本）的 text 字段，拼接成正文
 * 注：单个 PbContent 内字段顺序为 type(1) → text(2)，需先读 type 再判断是否拼接 text
 */
function decodePostContent(reader: ProtoReader): string {
  let text: string = '';
  let currentType: number = -1;  // -1 表示尚未读到 type 字段
  while (!reader.isEnd()) {
    const tag = reader.readTag();
    if (tag.fieldNumber === 1) {
      // type（0=纯文本, 2/11=表情, 4=@, 1=链接, 9电话号, 10@IP...）
      currentType = reader.readVarint();
    } else if (tag.fieldNumber === 2) {
      // text —— 仅 type=0 纯文本碎片才拼接（对齐 aiotieba FragText_pt）
      const textValue: string = reader.readString();
      if (currentType === 0) {
        text += textValue;
      }
    } else {
      reader.skipField(tag.wireType);
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
        contentText += decodePostContent(contentReader);
        break;
      }
      case 13:  // sub_post_number（楼中楼数 = replyNum）
        post.replyNum = reader.readVarint();
        break;
      case 19:  // author_id
        authorId = reader.readVarint();
        break;
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

      // 第一遍：收集 forum/page/user_list/thread，post_list 只存 raw bytes
      while (!dataReader.isEnd()) {
        const dataTag = dataReader.readTag();
        if (dataTag.fieldNumber === 2) {
          // forum（SimpleForum）：id=1, name=2
          const forumReader = dataReader.readMessage();
          while (!forumReader.isEnd()) {
            const forumTag = forumReader.readTag();
            if (forumTag.fieldNumber === 1) {        // id
              // forum id（暂不存储，PostInfo 无此字段）
              forumReader.readVarint();
            } else if (forumTag.fieldNumber === 2) { // name
              // forum name（暂不存储）
              forumReader.readString();
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
          // thread（ThreadInfo）—— 提取 tid 和 title
          const threadReader = dataReader.readMessage();
          while (!threadReader.isEnd()) {
            const threadTag = threadReader.readTag();
            if (threadTag.fieldNumber === 2) {       // tid（ThreadInfo.id）
              threadTid = threadReader.readVarint();
              result.thread.tid = threadTid;
            } else if (threadTag.fieldNumber === 3) { // title
              result.thread.title = threadReader.readString();
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
