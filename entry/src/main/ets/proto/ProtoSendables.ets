// protobuf 解码 @Sendable 中间类与子线程辅助解码函数（issue #201 Slice 2）
// 从 ProtoDecoderTasks.ets 拆分而来，原因：
//   ArkTS @Concurrent 函数只能使用 import 变量或局部变量，不能使用同文件定义的类和函数。
//   故将 @Sendable 类与子线程辅助解码函数独立到此文件，供 ProtoDecoderTasks.ets 中的
//   @Concurrent 函数 import 后调用。
//
// 设计要点（对齐 HarmonyOS-Cases 性能指导 + ArkTS @Sendable / @Concurrent 约束）：
// 1. @Sendable 类属性只能是 primitives / Sendable 类 / @arkts.collections 容器
//    - enum（ContentFragmentType / MediaType）用 number 代替
//    - 数组用 collections.Array<T>
//    - PostInfo.videoInfo: VideoInfo | null 用 hasVideoInfo 标志 + SendableVideoInfo 字段表示
// 2. author 关联在子线程完成（用 Map<uid, SendableUserInfo> 关联），rebuild 时直接复用
// 3. getAvatarUrl 是纯函数（AvatarUtil.ets 导出），子线程函数可 import 后调用

import { collections } from '@kit.ArkTS';
import { ProtoReader, ProtoTag } from './ProtoWire';
import { getAvatarUrl } from '../utils/AvatarUtil';

// enum 无法跨线程传递（@Concurrent 函数限制），用数字常量代替
// 对齐 ForumModels.ets MediaType enum
const MEDIA_TYPE_IMAGE: number = 0;
const MEDIA_TYPE_VIDEO: number = 1;
// 对齐 ForumModels.ets ContentFragmentType enum
const CONTENT_FRAGMENT_TEXT: number = 0;
const CONTENT_FRAGMENT_LINK: number = 1;
const CONTENT_FRAGMENT_EMOJI: number = 2;
const CONTENT_FRAGMENT_IMAGE: number = 3;
const CONTENT_FRAGMENT_AT: number = 4;
const CONTENT_FRAGMENT_VIDEO: number = 5;

// ==================== @Sendable 中间类 ====================
// 字段与 model/ForumModels.ets 业务对象一一对应，但去除 @ObservedV2/@Trace 装饰器，
// 改用 @Sendable 装饰器以支持跨线程共享堆传递。

/** Sendable UserInfo（对应 UserInfo 普通类） */
@Sendable
export class SendableUserInfo {
  uid: number = 0;
  name: string = '';
  nickname: string = '';
  avatar: string = '';
  portrait: string = '';
  level: number = 0;
  levelName: string = '';
  gender: number = 0;
  isBawu: boolean = false;
}

/** Sendable MediaInfo（对应 MediaInfo 普通类，type 用 number 代替 MediaType enum） */
@Sendable
export class SendableMediaInfo {
  type: number = 0;  // MediaType enum value
  url: string = '';
  thumbnail: string = '';
  width: number = 0;
  height: number = 0;
}

/** Sendable VideoInfo（对应 VideoInfo @ObservedV2 类） */
@Sendable
export class SendableVideoInfo {
  videoUrl: string = '';
  videoDuration: number = 0;
  videoWidth: number = 0;
  videoHeight: number = 0;
  thumbnailUrl: string = '';
  thumbnailWidth: number = 0;
  thumbnailHeight: number = 0;
}

/** Sendable ContentFragment（对应 ContentFragment @ObservedV2 类，type 用 number 代替 enum） */
@Sendable
export class SendableContentFragment {
  type: number = 0;  // ContentFragmentType enum value
  text: string = '';
  link: string = '';
  uid: number = 0;
  emojiDesc: string = '';
  videoUrl: string = '';
  coverUrl: string = '';
  videoWidth: number = 0;
  videoHeight: number = 0;
}

/** Sendable ThreadInfo（对应 ThreadInfo @ObservedV2 类，含嵌套 author/mediaList/videoInfo） */
@Sendable
export class SendableThreadInfo {
  tid: number = 0;
  title: string = '';
  author: SendableUserInfo = new SendableUserInfo();
  content: string = '';
  createTime: number = 0;
  replyNum: number = 0;
  viewNum: number = 0;
  agreeNum: number = 0;
  disagreeNum: number = 0;
  isTop: boolean = false;
  isGood: boolean = false;
  isEssence: boolean = false;
  mediaList: collections.Array<SendableMediaInfo> = new collections.Array<SendableMediaInfo>();
  forumName: string = '';
  hotNum: number = 0;
  videoInfo: SendableVideoInfo = new SendableVideoInfo();
}

/** Sendable PostInfo（对应 PostInfo @ObservedV2 类）
 *  videoInfo 用 hasVideoInfo 标志 + videoInfo 字段表示原本的 VideoInfo | null */
@Sendable
export class SendablePostInfo {
  pid: number = 0;
  tid: number = 0;
  author: SendableUserInfo = new SendableUserInfo();
  content: string = '';
  fragments: collections.Array<SendableContentFragment> = new collections.Array<SendableContentFragment>();
  createTime: number = 0;
  floor: number = 0;
  agreeNum: number = 0;
  disagreeNum: number = 0;
  replyNum: number = 0;
  mediaList: collections.Array<SendableMediaInfo> = new collections.Array<SendableMediaInfo>();
  subPostList: collections.Array<SendableSubPostInfo> = new collections.Array<SendableSubPostInfo>();
  isAgreed: boolean = false;
  isDisagreed: boolean = false;
  isAgreeing: boolean = false;
  hasVideoInfo: boolean = false;
  videoInfo: SendableVideoInfo = new SendableVideoInfo();
}

/** Sendable SubPostInfo（对应 SubPostInfo @ObservedV2 类） */
@Sendable
export class SendableSubPostInfo {
  spid: number = 0;
  pid: number = 0;
  tid: number = 0;
  author: SendableUserInfo = new SendableUserInfo();
  content: string = '';
  fragments: collections.Array<SendableContentFragment> = new collections.Array<SendableContentFragment>();
  createTime: number = 0;
  agreeNum: number = 0;
  disagreeNum: number = 0;
  floor: number = 0;
  title: string = '';
  isAgreed: boolean = false;
  isDisagreed: boolean = false;
}

/** Sendable ForumInfo（对应 ForumInfo 普通类） */
@Sendable
export class SendableForumInfo {
  id: number = 0;
  name: string = '';
  avatar: string = '';
  slogan: string = '';
  memberCount: number = 0;
  postCount: number = 0;
  isFollowed: boolean = false;
}

/** Sendable 分页信息（对应 PageData<T>） */
@Sendable
export class SendablePageInfo {
  currentPage: number = 0;
  totalPage: number = 0;
  hasMore: boolean = false;
  hasPrev: boolean = false;
}

/** Sendable FrsPageResult（对应 FrsPageResult） */
@Sendable
export class SendableFrsPageResult {
  forum: SendableForumInfo = new SendableForumInfo();
  threadsList: collections.Array<SendableThreadInfo> = new collections.Array<SendableThreadInfo>();
  threadsPage: SendablePageInfo = new SendablePageInfo();
}

/** Sendable PbPageResult（对应 PbPageResult） */
@Sendable
export class SendablePbPageResult {
  postsList: collections.Array<SendablePostInfo> = new collections.Array<SendablePostInfo>();
  postsPage: SendablePageInfo = new SendablePageInfo();
  thread: SendableThreadInfo = new SendableThreadInfo();
  forumId: number = 0;
}

/** Sendable PbFloorResult（对应 PbFloorResult） */
@Sendable
export class SendablePbFloorResult {
  subPosts: collections.Array<SendableSubPostInfo> = new collections.Array<SendableSubPostInfo>();
  currentPage: number = 1;
  totalPages: number = 1;
  hasMore: boolean = false;
}

/** Sendable ContentResult（decodePostContentInline 的返回值包装，避免匿名对象类型） */
@Sendable
export class SendableContentResult {
  fragments: collections.Array<SendableContentFragment> = new collections.Array<SendableContentFragment>();
  mediaList: collections.Array<SendableMediaInfo> = new collections.Array<SendableMediaInfo>();
}

// ==================== 子线程辅助解码函数 ====================
// 这些函数在 TaskPool 子线程被 @Concurrent 函数调用（通过 import 引入）。
// 都是纯函数（仅依赖参数 + import 的 Sendable 类 / getAvatarUrl），不引用任何外部闭包变量。

/** 解析 User message（对齐 FrsPageProto/PbPageProto.decodeUser） */
export function decodeUserInline(reader: ProtoReader): SendableUserInfo {
  const user: SendableUserInfo = new SendableUserInfo();
  while (!reader.isEnd()) {
    const tag: ProtoTag = reader.readTag();
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
      case 5: {  // portrait
        const portrait: string = reader.readString();
        user.portrait = portrait;
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

/** 解析 Media message（对齐 FrsPageProto.decodeMedia） */
export function decodeMediaInline(reader: ProtoReader): SendableMediaInfo {
  const media: SendableMediaInfo = new SendableMediaInfo();
  let smallPic: string = '';
  let bigPic: string = '';
  let srcPic: string = '';
  let originPic: string = '';

  while (!reader.isEnd()) {
    const tag: ProtoTag = reader.readTag();
    switch (tag.fieldNumber) {
      case 1:   // type
        media.type = reader.readVarint() === 1 ? MEDIA_TYPE_VIDEO : MEDIA_TYPE_IMAGE;
        break;
      case 2:   // small_pic
        smallPic = reader.readString();
        break;
      case 3:   // big_pic
        bigPic = reader.readString();
        break;
      case 8:   // src_pic
        srcPic = reader.readString();
        break;
      case 10:  // width
        media.width = reader.readVarint();
        break;
      case 11:  // height
        media.height = reader.readVarint();
        break;
      case 15:  // origin_pic
        originPic = reader.readString();
        break;
      default:
        reader.skipField(tag.wireType);
        break;
    }
  }

  if (originPic.length > 0) {
    media.url = originPic;
  } else if (bigPic.length > 0) {
    media.url = bigPic;
  } else if (srcPic.length > 0) {
    media.url = srcPic;
  } else {
    media.url = smallPic;
  }
  media.thumbnail = smallPic;
  return media;
}

/** 解析 VideoInfo message（对齐 FrsPageProto/PbPageProto.decodeVideoInfo） */
export function decodeVideoInfoInline(reader: ProtoReader): SendableVideoInfo {
  const info: SendableVideoInfo = new SendableVideoInfo();
  while (!reader.isEnd()) {
    const tag: ProtoTag = reader.readTag();
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

/** 解析 Post content 碎片（对齐 PbPageProto.decodePostContent）
 *  返回 fragments + mediaList（两个 collections.Array） */
export function decodePostContentInline(reader: ProtoReader): SendableContentResult {
  const fragments: collections.Array<SendableContentFragment> = new collections.Array<SendableContentFragment>();
  const mediaList: collections.Array<SendableMediaInfo> = new collections.Array<SendableMediaInfo>();

  let fragmentType: number = 0;
  let textValue: string = '';
  let linkValue: string = '';
  let emojiDesc: string = '';
  let uidValue: number = 0;
  let cdnSrc: string = '';
  let bigCdnSrc: string = '';
  let originSrc: string = '';
  let bsize: string = '';
  let srcValue: string = '';
  let videoWidth: number = 0;
  let videoHeight: number = 0;

  while (!reader.isEnd()) {
    const tag: ProtoTag = reader.readTag();
    if (tag.fieldNumber === 1) {
      fragmentType = reader.readVarint();
    } else if (tag.fieldNumber === 2) {
      textValue = reader.readString();
    } else if (tag.fieldNumber === 3) {
      linkValue = reader.readString();
    } else if (tag.fieldNumber === 4) {
      srcValue = reader.readString();
    } else if (tag.fieldNumber === 5) {
      bsize = reader.readString();
    } else if (tag.fieldNumber === 8) {
      cdnSrc = reader.readString();
    } else if (tag.fieldNumber === 9) {
      bigCdnSrc = reader.readString();
    } else if (tag.fieldNumber === 11) {
      emojiDesc = reader.readString();
    } else if (tag.fieldNumber === 15) {
      uidValue = reader.readVarint();
    } else if (tag.fieldNumber === 18) {
      videoWidth = reader.readVarint();
    } else if (tag.fieldNumber === 19) {
      videoHeight = reader.readVarint();
    } else if (tag.fieldNumber === 25) {
      originSrc = reader.readString();
    } else {
      reader.skipField(tag.wireType);
    }
  }

  // 按 fragmentType 分发构建 fragment
  if (fragmentType === 0 || fragmentType === 9 || fragmentType === 18
      || fragmentType === 27 || fragmentType === 40) {
    // FragText_p
    if (textValue.length > 0) {
      const frag: SendableContentFragment = new SendableContentFragment();
      frag.type = CONTENT_FRAGMENT_TEXT;
      frag.text = textValue;
      fragments.push(frag);
    }
  } else if (fragmentType === 1) {
    // FragLink_p
    const frag: SendableContentFragment = new SendableContentFragment();
    frag.type = CONTENT_FRAGMENT_LINK;
    frag.text = textValue;
    frag.link = linkValue;
    fragments.push(frag);
  } else if (fragmentType === 2 || fragmentType === 11) {
    // FragEmoji_p
    if (textValue.length > 0) {
      const frag: SendableContentFragment = new SendableContentFragment();
      frag.type = CONTENT_FRAGMENT_EMOJI;
      frag.text = textValue;
      frag.emojiDesc = emojiDesc;
      fragments.push(frag);
    }
  } else if (fragmentType === 4) {
    // FragAt_p
    if (textValue.length > 0) {
      const frag: SendableContentFragment = new SendableContentFragment();
      frag.type = CONTENT_FRAGMENT_AT;
      frag.text = textValue;
      frag.uid = uidValue;
      fragments.push(frag);
    }
  } else if (fragmentType === 3 || fragmentType === 20) {
    // FragImage_p
    const media: SendableMediaInfo = new SendableMediaInfo();
    if (originSrc.length > 0) {
      media.url = originSrc;
    } else if (bigCdnSrc.length > 0) {
      media.url = bigCdnSrc;
    } else {
      media.url = cdnSrc;
    }
    media.thumbnail = cdnSrc;
    if (bsize.length > 0) {
      const parts: string[] = bsize.split(',');
      if (parts.length >= 2) {
        const w: number = Number(parts[0]);
        const h: number = Number(parts[1]);
        media.width = Number.isNaN(w) ? 0 : w;
        media.height = Number.isNaN(h) ? 0 : h;
      }
    }
    if (media.url.length > 0) {
      mediaList.push(media);
    }
  } else if (fragmentType === 5) {
    // FragVideo
    if (srcValue.length > 0 && linkValue.length > 0) {
      const frag: SendableContentFragment = new SendableContentFragment();
      frag.type = CONTENT_FRAGMENT_VIDEO;
      frag.text = textValue;
      frag.videoUrl = linkValue;
      frag.coverUrl = srcValue;
      frag.videoWidth = videoWidth;
      frag.videoHeight = videoHeight;
      fragments.push(frag);
    } else if (textValue.length > 0) {
      const frag: SendableContentFragment = new SendableContentFragment();
      frag.type = CONTENT_FRAGMENT_LINK;
      frag.text = textValue;
      frag.link = textValue;
      fragments.push(frag);
    }
  }

  const result: SendableContentResult = new SendableContentResult();
  result.fragments = fragments;
  result.mediaList = mediaList;
  return result;
}

/** 解析 Thread message（对齐 FrsPageProto.decodeThread） */
export function decodeThreadInline(reader: ProtoReader, users: Map<number, SendableUserInfo>, forumName: string): SendableThreadInfo {
  const thread: SendableThreadInfo = new SendableThreadInfo();
  thread.forumName = forumName;
  let authorId: number = 0;

  while (!reader.isEnd()) {
    const tag: ProtoTag = reader.readTag();
    switch (tag.fieldNumber) {
      case 1:   // id
        thread.tid = reader.readVarint();
        break;
      case 2:   // threadId
        thread.tid = reader.readVarint();
        break;
      case 3:   // title
        thread.title = reader.readString();
        break;
      case 4:   // reply_num
        thread.replyNum = reader.readVarint();
        break;
      case 5:   // view_num
        thread.viewNum = reader.readVarint();
        break;
      case 9:   // is_top
        thread.isTop = reader.readVarint() !== 0;
        break;
      case 10:  // is_good
        thread.isGood = reader.readVarint() !== 0;
        break;
      case 18: {  // author（内嵌 User）
        const authorReader: ProtoReader = reader.readMessage();
        thread.author = decodeUserInline(authorReader);
        break;
      }
      case 21: {  // _abstract（repeated）
        const absReader: ProtoReader = reader.readMessage();
        while (!absReader.isEnd()) {
          const absTag: ProtoTag = absReader.readTag();
          if (absTag.fieldNumber === 2) {
            thread.content += absReader.readString();
          } else {
            absReader.skipField(absTag.wireType);
          }
        }
        break;
      }
      case 22: {  // media（repeated）
        const mediaReader: ProtoReader = reader.readMessage();
        thread.mediaList.push(decodeMediaInline(mediaReader));
        break;
      }
      case 28:  // forum_name
        thread.forumName = reader.readString();
        break;
      case 45:  // create_time
        thread.createTime = reader.readVarint();
        break;
      case 56:  // author_id
        authorId = reader.readVarint();
        break;
      case 126: {  // agree
        const agreeReader: ProtoReader = reader.readMessage();
        while (!agreeReader.isEnd()) {
          const agreeTag: ProtoTag = agreeReader.readTag();
          if (agreeTag.fieldNumber === 1) {
            thread.agreeNum = agreeReader.readVarint();
          } else if (agreeTag.fieldNumber === 4) {
            thread.disagreeNum = agreeReader.readVarint();
          } else {
            agreeReader.skipField(agreeTag.wireType);
          }
        }
        break;
      }
      case 182:  // hot_num
        thread.hotNum = reader.readVarint();
        break;
      case 79: {  // video_info
        const videoReader: ProtoReader = reader.readMessage();
        thread.videoInfo = decodeVideoInfoInline(videoReader);
        break;
      }
      default:
        reader.skipField(tag.wireType);
        break;
    }
  }

  // user_list 关联优先于内嵌 author
  if (authorId > 0) {
    const user: SendableUserInfo | undefined = users.get(authorId);
    if (user !== undefined) {
      thread.author = user;
    }
  }

  return thread;
}

/** 解析 Post message（对齐 PbPageProto.decodePost） */
export function decodePostInline(reader: ProtoReader, users: Map<number, SendableUserInfo>, threadTid: number): SendablePostInfo {
  const post: SendablePostInfo = new SendablePostInfo();
  post.tid = threadTid;
  let authorId: number = 0;
  let contentText: string = '';

  while (!reader.isEnd()) {
    const tag: ProtoTag = reader.readTag();
    switch (tag.fieldNumber) {
      case 1:   // id（pid）
        post.pid = reader.readVarint();
        break;
      case 3:   // floor
        post.floor = reader.readVarint();
        break;
      case 4:   // time
        post.createTime = reader.readVarint();
        break;
      case 5: {  // content（repeated PbContent）
        const contentReader: ProtoReader = reader.readMessage();
        const contentResult = decodePostContentInline(contentReader);
        for (let i = 0; i < contentResult.fragments.length; i++) {
          post.fragments.push(contentResult.fragments[i]);
          if (contentResult.fragments[i].type === CONTENT_FRAGMENT_TEXT
              || contentResult.fragments[i].type === CONTENT_FRAGMENT_LINK
              || contentResult.fragments[i].type === CONTENT_FRAGMENT_AT) {
            contentText += contentResult.fragments[i].text;
          }
        }
        for (let i = 0; i < contentResult.mediaList.length; i++) {
          post.mediaList.push(contentResult.mediaList[i]);
        }
        break;
      }
      case 13:  // sub_post_number
        post.replyNum = reader.readVarint();
        break;
      case 19:  // author_id
        authorId = reader.readVarint();
        break;
      case 29: {  // video_info
        const videoReader: ProtoReader = reader.readMessage();
        post.hasVideoInfo = true;
        post.videoInfo = decodeVideoInfoInline(videoReader);
        break;
      }
      case 37: {  // agree
        const agreeReader: ProtoReader = reader.readMessage();
        while (!agreeReader.isEnd()) {
          const agreeTag: ProtoTag = agreeReader.readTag();
          if (agreeTag.fieldNumber === 1) {
            post.agreeNum = agreeReader.readVarint();
          } else if (agreeTag.fieldNumber === 4) {
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

  if (authorId > 0) {
    const user: SendableUserInfo | undefined = users.get(authorId);
    if (user !== undefined) {
      post.author = user;
    }
  }

  return post;
}

/** 解析 SubPostList message（对齐 PbFloorProto.decodeSubPostList） */
export function decodeSubPostListInline(reader: ProtoReader, tid: number, pid: number): SendableSubPostInfo {
  const subPost: SendableSubPostInfo = new SendableSubPostInfo();
  subPost.tid = tid;
  subPost.pid = pid;
  let authorId: number = 0;

  while (!reader.isEnd()) {
    const tag: ProtoTag = reader.readTag();
    switch (tag.fieldNumber) {
      case 1:   // id（spid）
        subPost.spid = reader.readVarint();
        break;
      case 2: {  // content（repeated PbContent）
        const contentReader: ProtoReader = reader.readMessage();
        const contentResult = decodePostContentInline(contentReader);
        for (let i = 0; i < contentResult.fragments.length; i++) {
          subPost.fragments.push(contentResult.fragments[i]);
        }
        break;
      }
      case 3:   // time
        subPost.createTime = reader.readVarint();
        break;
      case 4:   // author_id
        authorId = reader.readVarint();
        break;
      case 5:   // title
        subPost.title = reader.readString();
        break;
      case 6:   // floor
        subPost.floor = reader.readVarint();
        break;
      case 7: {  // author（User message）
        const authorReader: ProtoReader = reader.readMessage();
        subPost.author = decodeUserInline(authorReader);
        break;
      }
      case 9: {  // agree
        const agreeReader: ProtoReader = reader.readMessage();
        while (!agreeReader.isEnd()) {
          const agreeTag: ProtoTag = agreeReader.readTag();
          if (agreeTag.fieldNumber === 1) {
            subPost.agreeNum = agreeReader.readVarint();
          } else if (agreeTag.fieldNumber === 4) {
            subPost.disagreeNum = agreeReader.readVarint();
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

  // 拼接 content 文本
  const contentParts: string[] = [];
  for (let i = 0; i < subPost.fragments.length; i++) {
    const frag: SendableContentFragment = subPost.fragments[i];
    if (frag.type === CONTENT_FRAGMENT_TEXT
        || frag.type === CONTENT_FRAGMENT_LINK
        || frag.type === CONTENT_FRAGMENT_AT) {
      contentParts.push(frag.text);
    }
  }
  subPost.content = contentParts.join('');

  if (subPost.author.uid === 0 && authorId > 0) {
    subPost.author.uid = authorId;
  }
  return subPost;
}
