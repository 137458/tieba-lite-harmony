// PbPage protobuf 编解码（issue #7）
// 字段编号对齐 tbclient.protobuf-main/proto/PbPage 原定义
// wire format 编解码复用 ProtoWire.ets
// 用于 getPosts（帖子详情/回复列表），cmd=302001

import { PostInfo, UserInfo, PageData, ThreadInfo, MediaInfo, ContentFragment, ContentFragmentType, VideoInfo } from '../model/ForumModels';
import { ProtoWriter, ProtoReader } from './ProtoWire';
import { getAvatarUrl } from '../utils/AvatarUtil';

// ==================== PbPage 请求编码 ====================

/** PbPage 请求参数 */
export interface IPbPageReqParams {
  tid: number;           // 主题帖 id（proto 字段名 kz）
  pn: number;            // 页码
  rn: number;            // 每页回复数
  sort: number;          // 排序方式（0=正序ASC, 1=倒序DESC, 2=热门HOT，对齐 Android ThreadSortType）
  onlyAuthor: boolean;   // 只看楼主
  clientVersion: string;
  // 账号字段可选：with_comments=true 时需要 BDUSS
  bduss?: string;
  // 修复 350004：补全 CommonReq 必需字段（对齐 Android V12 ProtobufRequest.kt buildCommonRequest）
  cuid?: string;         // field 7：设备标识（Android V12 必传）
  timestamp?: number;    // field 8：当前时间戳（毫秒，Android V12 必传）
  netType?: number;      // field 12：网络类型（1=WIFI, Android V12 必传）
  // #72 加载上一页：back 标记 + pid 锚点（对齐 Android PbPageRequestData.proto field 2/3）
  // back=true 时服务端返回上一页数据，pid 作为定位锚点（当前列表首条 post id）
  back?: boolean;        // field 3：是否向前翻页
  lastPostId?: number;   // field 2：锚点 post id（当前列表首条 pid）
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
  // #72 加载上一页：back 标记（field 3）+ pid 锚点（field 2）
  // 对齐 Android PbPageRequestData.proto：back=true 时服务端返回上一页数据
  if (params.back) {
    writer.writeInt32(3, 1);                                  // back = 1（向前翻页标记）
  }
  if (params.lastPostId !== undefined && params.lastPostId > 0) {
    writer.writeInt32(2, params.lastPostId);                  // pid（锚点 post id）
  }
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
  /** #74 贴吧 id（来自 forum.id，回帖 API 必传字段） */
  forumId: number = 0;
}

/**
 * #101 decodePostContent 解码结果（消除副作用，纯函数化）
 * 旧实现通过 mediaList 入参 push 数据违反纯函数原则，改为返回本 class 实例
 */
export class PostContentDecodeResult {
  fragments: ContentFragment[] = [];
  mediaList: MediaInfo[] = [];
}

/** 解析 User（field 编号对齐 User.proto，与 FrsPageProto.decodeUser 一致）
 * #73 楼中楼作者解析复用此函数：SubPostList.author 与 Post.author 同为 User */
export function decodeUser(reader: ProtoReader): UserInfo {
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
 * #71 解析 Post 的 content 碎片（field 编号对齐 PbContent.proto）
 * 返回 PostContentDecodeResult，包含 ContentFragment[]（富文本渲染）+ MediaInfo[]（图片块渲染）
 * #101 消除副作用：旧实现通过 mediaList 入参 push 数据，改为返回结果对象（纯函数化）
 * 对齐 aiotieba get_posts/_classdef.py Contents_p.from_proto + 各 Frag*_p.from_proto
 *
 * 字段编号映射（aiotieba 权威）：
 * - field 1: type（碎片类型枚举）
 * - field 2: text（TEXT正文 / LINK标题 / EMOJI的id / AT的昵称）
 * - field 3: link（LINK的URL / VIDEO的src）
 * - field 4: src（VIDEO封面，本阶段未用）
 * - field 5: bsize（图片尺寸 "width,height"）
 * - field 8: cdn_src（小图CDN）
 * - field 9: big_cdn_src（大图CDN）
 * - field 11: c（EMOJI描述）
 * - field 15: uid（AT的用户ID）
 * - field 25: origin_src（原图链接）
 *
 * #73 楼中楼内容复用此函数：SubPostList.content 与 Post.content 同为 repeated PbContent
 */
export function decodePostContent(reader: ProtoReader): PostContentDecodeResult {
  const result: PostContentDecodeResult = new PostContentDecodeResult();
  // proto3 默认值 0 = 纯文本（对齐 aiotieba _classdef.py: _type in [0,9,18,27,40] 为纯文本）
  // 命名 fragmentType：明确表示"这个碎片的内容类型"（非"当前处理类型"）
  let fragmentType: number = 0;
  // 通用字段（按 type 语义复用）
  let textValue: string = '';     // field 2
  let linkValue: string = '';     // field 3（LINK URL）
  let emojiDesc: string = '';     // field 11（EMOJI 描述）
  let uidValue: number = 0;       // field 15（AT 用户ID）
  // 图片碎片字段（type=3/20 时有效，对齐 FragImage_p.from_proto）
  let cdnSrc: string = '';        // field 8 — 小图 CDN 链接
  let bigCdnSrc: string = '';     // field 9 — 大图 CDN 链接
  let originSrc: string = '';     // field 25 — 原图链接
  let bsize: string = '';         // field 5 — "width,height" 显示尺寸（图片专用）
  // #151 视频碎片字段（type=5 时有效，对齐 PbContent.proto + aiotieba FragVideo_p.from_proto）
  let srcValue: string = '';      // field 4 — src（视频封面URL）
  let videoWidth: number = 0;     // field 18 — 视频宽度（uint32，视频专用，非 bsize）
  let videoHeight: number = 0;    // field 19 — 视频高度（uint32，视频专用，非 bsize）

  while (!reader.isEnd()) {
    const tag = reader.readTag();
    if (tag.fieldNumber === 1) {
      // type（0=纯文本, 1=链接, 2/11=表情, 3/20=图片, 4=@, 5=视频, 9=电话号, 10=语音, 18=话题, 27=百科, 40=梗百科）
      fragmentType = reader.readVarint();
    } else if (tag.fieldNumber === 2) {
      // text —— 通用字段，语义随 type 变化（TEXT正文 / LINK标题 / EMOJI的id / AT的昵称 / VIDEO的webUrl）
      textValue = reader.readString();
    } else if (tag.fieldNumber === 3) {
      // link —— LINK的URL / VIDEO的视频URL（对齐 FragLink_p + PbContent type5）
      linkValue = reader.readString();
    } else if (tag.fieldNumber === 4) {
      // src —— VIDEO的封面URL（对齐 PbContent.proto type5: src = 封面图）
      srcValue = reader.readString();
    } else if (tag.fieldNumber === 5) {
      // bsize —— 图片/视频显示尺寸 "width,height"
      bsize = reader.readString();
    } else if (tag.fieldNumber === 8) {
      // cdn_src —— 小图 CDN 链接
      cdnSrc = reader.readString();
    } else if (tag.fieldNumber === 9) {
      // big_cdn_src —— 大图 CDN 链接
      bigCdnSrc = reader.readString();
    } else if (tag.fieldNumber === 11) {
      // c —— EMOJI 描述（对齐 FragEmoji_p: desc = data_proto.c）
      emojiDesc = reader.readString();
    } else if (tag.fieldNumber === 15) {
      // uid —— AT 用户ID（对齐 FragAt_p: user_id = data_proto.uid）
      uidValue = reader.readVarint();
    } else if (tag.fieldNumber === 18) {
      // width —— 视频宽度（对齐 PbContent.proto field 18 + aiotieba FragVideo_p: width = data_proto.width）
      videoWidth = reader.readVarint();
    } else if (tag.fieldNumber === 19) {
      // height —— 视频高度（对齐 PbContent.proto field 19 + aiotieba FragVideo_p: height = data_proto.height）
      videoHeight = reader.readVarint();
    } else if (tag.fieldNumber === 25) {
      // origin_src —— 原图链接
      originSrc = reader.readString();
    } else {
      reader.skipField(tag.wireType);
    }
  }

  // 按 fragmentType 分发构建 fragment（对齐 aiotieba Contents_p._frags 调度逻辑）
  if (fragmentType === 0 || fragmentType === 9 || fragmentType === 18
      || fragmentType === 27 || fragmentType === 40) {
    // FragText_p: 纯文本/电话号/话题/百科/梗百科
    if (textValue.length > 0) {
      const frag: ContentFragment = new ContentFragment();
      frag.type = ContentFragmentType.TEXT;
      frag.text = textValue;
      result.fragments.push(frag);
    }
  } else if (fragmentType === 1) {
    // FragLink_p: 链接（text=标题, link=URL）
    const frag: ContentFragment = new ContentFragment();
    frag.type = ContentFragmentType.LINK;
    frag.text = textValue;
    frag.link = linkValue;
    result.fragments.push(frag);
  } else if (fragmentType === 2 || fragmentType === 11) {
    // FragEmoji_p: 表情（text=表情id, emojiDesc=描述）
    // 防御：text 为空时跳过（避免 ImageSpan 加载 .../client/.png 无效 URL）
    if (textValue.length > 0) {
      const frag: ContentFragment = new ContentFragment();
      frag.type = ContentFragmentType.EMOJI;
      frag.text = textValue;
      frag.emojiDesc = emojiDesc;
      result.fragments.push(frag);
    }
  } else if (fragmentType === 4) {
    // FragAt_p: @用户（text=昵称, uid=用户ID）
    // 防御：text 为空时跳过（避免 Span('') 渲染空白可点击区域）
    if (textValue.length > 0) {
      const frag: ContentFragment = new ContentFragment();
      frag.type = ContentFragmentType.AT;
      frag.text = textValue;
      frag.uid = uidValue;
      result.fragments.push(frag);
    }
  } else if (fragmentType === 3 || fragmentType === 20) {
    // FragImage_p: 图片碎片（填充 mediaList，不创建 fragment，保留独立图片块渲染）
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
        // #101 P2 NaN 防护：Number('abc') 返回 NaN，NaN || 0 虽然得到 0 但语义模糊
        // 显式 Number.isNaN 检查，避免 NaN 传播到下游（NaN <= 0 返回 false 是经典陷阱）
        const w: number = Number(parts[0]);
        const h: number = Number(parts[1]);
        media.width = Number.isNaN(w) ? 0 : w;
        media.height = Number.isNaN(h) ? 0 : h;
      }
    }
    // 仅当有有效 URL 时才加入列表
    if (media.url.length > 0) {
      result.mediaList.push(media);
    }
  } else if (fragmentType === 5) {
    // #151 FragVideo: 视频碎片（对齐 PbContent.proto type5 + Extensions.kt 转换逻辑）
    // 有内嵌视频（src 封面非空）时创建 VIDEO fragment；否则降级为链接文本
    if (srcValue.length > 0 && linkValue.length > 0) {
      const frag: ContentFragment = new ContentFragment();
      frag.type = ContentFragmentType.VIDEO;
      frag.text = textValue;       // webUrl（视频网页链接，备用）
      frag.videoUrl = linkValue;   // 视频 URL（field 3=link）
      frag.coverUrl = srcValue;    // 封面 URL（field 4=src）
      // 视频宽高用 field 18/19（uint32），非 bsize（图片专用字符串）
      frag.videoWidth = videoWidth;
      frag.videoHeight = videoHeight;
      result.fragments.push(frag);
    } else if (textValue.length > 0) {
      // 无内嵌视频：降级为 LINK fragment（对齐 Extensions.kt: 降级为可点击链接文本）
      const frag: ContentFragment = new ContentFragment();
      frag.type = ContentFragmentType.LINK;
      frag.text = textValue;
      frag.link = textValue;
      result.fragments.push(frag);
    }
  }
  // 其他 type（10语音/35/36/37贴吧plus等）暂未实现，跳过

  return result;
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
        // #101 decodePostContent 返回 PostContentDecodeResult（fragments + mediaList），纯函数无副作用
        const contentResult: PostContentDecodeResult = decodePostContent(contentReader);
        for (let i = 0; i < contentResult.fragments.length; i++) {
          post.fragments.push(contentResult.fragments[i]);
          // 拼接可读文本到 contentText（向后兼容，content 字段保留纯文本展示/复制/搜索）
          // TEXT/LINK/AT 的 text 是可读文本；EMOJI 的 text 是 id 非可读，不拼入
          if (contentResult.fragments[i].type === ContentFragmentType.TEXT
              || contentResult.fragments[i].type === ContentFragmentType.LINK
              || contentResult.fragments[i].type === ContentFragmentType.AT) {
            contentText += contentResult.fragments[i].text;
          }
        }
        for (let i = 0; i < contentResult.mediaList.length; i++) {
          post.mediaList.push(contentResult.mediaList[i]);
        }
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
      case 29: {  // #151 video_info（VideoInfo，对齐 Post.proto field 29）
        const videoReader = reader.readMessage();
        post.videoInfo = decodeVideoInfo(videoReader);
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
 * #151 解析 VideoInfo（field 编号对齐 VideoInfo.proto）
 * 用于 Post field 29 / ThreadInfo field 79
 * 字段映射：2=videoUrl, 3=videoDuration, 4=videoWidth, 5=videoHeight,
 *           6=thumbnailUrl, 7=thumbnailWidth, 8=thumbnailHeight
 * field 1(videoMD5) / 11(mediaSubtitle) 暂不使用，跳过
 */
function decodeVideoInfo(reader: ProtoReader): VideoInfo {
  const info: VideoInfo = new VideoInfo();
  while (!reader.isEnd()) {
    const tag = reader.readTag();
    if (tag.fieldNumber === 2) {
      info.videoUrl = reader.readString();
    } else if (tag.fieldNumber === 3) {
      info.videoDuration = reader.readVarint();
    } else if (tag.fieldNumber === 4) {
      info.videoWidth = reader.readVarint();
    } else if (tag.fieldNumber === 5) {
      info.videoHeight = reader.readVarint();
    } else if (tag.fieldNumber === 6) {
      info.thumbnailUrl = reader.readString();
    } else if (tag.fieldNumber === 7) {
      info.thumbnailWidth = reader.readVarint();
    } else if (tag.fieldNumber === 8) {
      info.thumbnailHeight = reader.readVarint();
    } else {
      reader.skipField(tag.wireType);
    }
  }
  return info;
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
      let forumIdValue: number = 0;  // #74 forum.id（回帖 API 必传字段）

      // 第一遍：收集 forum/page/user_list/thread，post_list 只存 raw bytes
      while (!dataReader.isEnd()) {
        const dataTag = dataReader.readTag();
        if (dataTag.fieldNumber === 2) {
          // forum（SimpleForum）：id=1, name=2
          const forumReader = dataReader.readMessage();
          while (!forumReader.isEnd()) {
            const forumTag = forumReader.readTag();
            if (forumTag.fieldNumber === 1) {        // id
              forumIdValue = forumReader.readVarint();
            } else if (forumTag.fieldNumber === 2) { // name
              forumName = forumReader.readString();
            } else {
              forumReader.skipField(forumTag.wireType);
            }
          }
        } else if (dataTag.fieldNumber === 3) {
          // page（Page）：current_page=3, total_page=5, has_more=6, has_prev=7
          const pageReader = dataReader.readMessage();
          while (!pageReader.isEnd()) {
            const pageTag = pageReader.readTag();
            if (pageTag.fieldNumber === 3) {         // current_page
              result.posts.currentPage = pageReader.readVarint();
            } else if (pageTag.fieldNumber === 5) {  // total_page
              result.posts.totalPage = pageReader.readVarint();
            } else if (pageTag.fieldNumber === 6) {  // has_more
              result.posts.hasMore = pageReader.readVarint() !== 0;
            } else if (pageTag.fieldNumber === 7) {  // has_prev（#72 加载上一页）
              result.posts.hasPrev = pageReader.readVarint() !== 0;
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
      // #74 补全 forumId（回帖 API 必传字段，来自 forum.id）
      result.forumId = forumIdValue;
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
