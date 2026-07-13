// protobuf 解码 TaskPool 化（issue #201 Slice 2）
// 将 decodeFrsPageRes / decodePbPageRes / decodePbFloorRes 三个重量级解码函数迁移到 TaskPool 子线程，
// 避免主线程被 50-200ms 的 protobuf 解码阻塞导致 UI 卡顿。
//
// 设计要点（对齐 HarmonyOS-Cases 性能指导 + ArkTS @Sendable / @Concurrent 约束）：
// 1. @Concurrent 函数只能使用 import 变量或局部变量，不能使用同文件定义的类和函数
//    故 @Sendable 中间类与子线程辅助解码函数已拆分到 ProtoSendables.ets，本文件通过 import 引入
// 2. @Sendable 类属性只能是 primitives / Sendable 类 / @arkts.collections 容器（详见 ProtoSendables.ets）
// 3. @ObservedV2 业务对象不能直接跨线程传递，故子线程返回 @Sendable 中间对象，主线程 rebuild 为 @ObservedV2 实例
// 4. author 关联在子线程完成（用 Map<uid, SendableUserInfo> 关联），rebuild 时直接复用
// 5. getAvatarUrl 是纯函数（AvatarUtil.ets 导出），@Concurrent 函数可 import 后调用

import { taskpool } from '@kit.ArkTS';
import { ProtoReader, ProtoTag } from './ProtoWire';
import { getAvatarUrl } from '../utils/AvatarUtil';
import {
  PostInfo, ThreadInfo, SubPostInfo, ContentFragment, VideoInfo, UserInfo, MediaInfo, ForumInfo,
  PageData
} from '../model/ForumModels';
import { FrsPageResult } from './FrsPageProto';
import { PbPageResult } from './PbPageProto';
import { PbFloorResult } from './PbFloorProto';
import {
  SendableUserInfo, SendableMediaInfo, SendableVideoInfo, SendableContentFragment,
  SendableThreadInfo, SendablePostInfo, SendableSubPostInfo, SendableForumInfo,
  SendablePageInfo, SendableFrsPageResult, SendablePbPageResult, SendablePbFloorResult,
  SendableContentResult,
  decodeUserInline, decodeMediaInline, decodeVideoInfoInline, decodePostContentInline,
  decodeThreadInline, decodePostInline, decodeSubPostListInline
} from './ProtoSendables';

// ==================== @Concurrent 解码函数 ====================
// 三个 @Concurrent 函数内联所有解码逻辑，依赖的 @Sendable 类与辅助函数均从 ProtoSendables.ets import。
// 唯一外部依赖是 getAvatarUrl（从 AvatarUtil.ets import 的纯函数，由辅助函数调用）。

/**
 * TaskPool 解码 FrsPageRes（吧页主题列表）
 * 对齐 FrsPageProto.decodeFrsPageRes 字段编号与关联逻辑
 */
@Concurrent
export function decodeFrsPageResTask(bytes: Uint8Array): SendableFrsPageResult {
  const reader: ProtoReader = new ProtoReader(bytes);
  const result: SendableFrsPageResult = new SendableFrsPageResult();

  while (!reader.isEnd()) {
    const tag: ProtoTag = reader.readTag();
    if (tag.fieldNumber === 1) {
      // error
      const errReader: ProtoReader = reader.readMessage();
      let errorNo: number = 0;
      let errorMsg: string = '';
      while (!errReader.isEnd()) {
        const errTag: ProtoTag = errReader.readTag();
        if (errTag.fieldNumber === 1) {
          errorNo = errReader.readVarint();
        } else if (errTag.fieldNumber === 2) {
          errorMsg = errReader.readString();
        } else {
          errReader.skipField(errTag.wireType);
        }
      }
      if (errorNo !== 0) {
        throw new Error(`获取帖子列表失败 [${errorNo}]: ${errorMsg}`);
      }
    } else if (tag.fieldNumber === 2) {
      // data
      const dataReader: ProtoReader = reader.readMessage();
      const users: Map<number, SendableUserInfo> = new Map<number, SendableUserInfo>();
      const rawThreads: ProtoReader[] = [];
      let forumName: string = '';

      while (!dataReader.isEnd()) {
        const dataTag: ProtoTag = dataReader.readTag();
        if (dataTag.fieldNumber === 2) {
          // forum
          const forumReader: ProtoReader = dataReader.readMessage();
          while (!forumReader.isEnd()) {
            const forumTag: ProtoTag = forumReader.readTag();
            if (forumTag.fieldNumber === 1) {
              result.forum.id = forumReader.readVarint();
            } else if (forumTag.fieldNumber === 2) {
              result.forum.name = forumReader.readString();
              forumName = result.forum.name;
            } else {
              forumReader.skipField(forumTag.wireType);
            }
          }
        } else if (dataTag.fieldNumber === 4) {
          // page
          const pageReader: ProtoReader = dataReader.readMessage();
          while (!pageReader.isEnd()) {
            const pageTag: ProtoTag = pageReader.readTag();
            if (pageTag.fieldNumber === 3) {
              result.threadsPage.currentPage = pageReader.readVarint();
            } else if (pageTag.fieldNumber === 5) {
              result.threadsPage.totalPage = pageReader.readVarint();
            } else if (pageTag.fieldNumber === 6) {
              result.threadsPage.hasMore = pageReader.readVarint() !== 0;
            } else {
              pageReader.skipField(pageTag.wireType);
            }
          }
        } else if (dataTag.fieldNumber === 7) {
          // thread_list（repeated）—— 先存 raw bytes，第二遍再解码
          rawThreads.push(dataReader.readMessage());
        } else if (dataTag.fieldNumber === 17) {
          // user_list（repeated）
          const userReader: ProtoReader = dataReader.readMessage();
          const user: SendableUserInfo = decodeUserInline(userReader);
          users.set(user.uid, user);
        } else {
          dataReader.skipField(dataTag.wireType);
        }
      }

      // 第二遍：解析 threads（此时 users map 已全部填充）
      for (let i = 0; i < rawThreads.length; i++) {
        result.threadsList.push(decodeThreadInline(rawThreads[i], users, forumName));
      }
    } else {
      reader.skipField(tag.wireType);
    }
  }

  return result;
}

/**
 * TaskPool 解码 PbPageRes（帖子详情/回复列表）
 * 对齐 PbPageProto.decodePbPageRes 字段编号与关联逻辑
 */
@Concurrent
export function decodePbPageResTask(bytes: Uint8Array): SendablePbPageResult {
  const reader: ProtoReader = new ProtoReader(bytes);
  const result: SendablePbPageResult = new SendablePbPageResult();

  while (!reader.isEnd()) {
    const tag: ProtoTag = reader.readTag();
    if (tag.fieldNumber === 1) {
      // error
      const errReader: ProtoReader = reader.readMessage();
      let errorNo: number = 0;
      let errorMsg: string = '';
      while (!errReader.isEnd()) {
        const errTag: ProtoTag = errReader.readTag();
        if (errTag.fieldNumber === 1) {
          errorNo = errReader.readVarint();
        } else if (errTag.fieldNumber === 2) {
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
      const dataReader: ProtoReader = reader.readMessage();
      const users: Map<number, SendableUserInfo> = new Map<number, SendableUserInfo>();
      const rawPosts: ProtoReader[] = [];
      let threadTid: number = 0;
      let threadAuthorId: number = 0;
      let forumName: string = '';
      let forumIdValue: number = 0;

      while (!dataReader.isEnd()) {
        const dataTag: ProtoTag = dataReader.readTag();
        if (dataTag.fieldNumber === 2) {
          // forum（SimpleForum）：id=1, name=2
          const forumReader: ProtoReader = dataReader.readMessage();
          while (!forumReader.isEnd()) {
            const forumTag: ProtoTag = forumReader.readTag();
            if (forumTag.fieldNumber === 1) {
              forumIdValue = forumReader.readVarint();
            } else if (forumTag.fieldNumber === 2) {
              forumName = forumReader.readString();
            } else {
              forumReader.skipField(forumTag.wireType);
            }
          }
        } else if (dataTag.fieldNumber === 3) {
          // page（Page）：current_page=3, total_page=5, has_more=6, has_prev=7
          const pageReader: ProtoReader = dataReader.readMessage();
          while (!pageReader.isEnd()) {
            const pageTag: ProtoTag = pageReader.readTag();
            if (pageTag.fieldNumber === 3) {
              result.postsPage.currentPage = pageReader.readVarint();
            } else if (pageTag.fieldNumber === 5) {
              result.postsPage.totalPage = pageReader.readVarint();
            } else if (pageTag.fieldNumber === 6) {
              result.postsPage.hasMore = pageReader.readVarint() !== 0;
            } else if (pageTag.fieldNumber === 7) {
              result.postsPage.hasPrev = pageReader.readVarint() !== 0;
            } else {
              pageReader.skipField(pageTag.wireType);
            }
          }
        } else if (dataTag.fieldNumber === 6) {
          // post_list（repeated）—— 先存 raw bytes，第二遍再解码
          rawPosts.push(dataReader.readMessage());
        } else if (dataTag.fieldNumber === 8) {
          // thread（ThreadInfo）—— 提取 tid、title、reply_num、view_num、create_time、forum_name、author_id、agree
          const threadReader: ProtoReader = dataReader.readMessage();
          while (!threadReader.isEnd()) {
            const threadTag: ProtoTag = threadReader.readTag();
            if (threadTag.fieldNumber === 2) {
              threadTid = threadReader.readVarint();
              result.thread.tid = threadTid;
            } else if (threadTag.fieldNumber === 3) {
              result.thread.title = threadReader.readString();
            } else if (threadTag.fieldNumber === 4) {
              result.thread.replyNum = threadReader.readVarint();
            } else if (threadTag.fieldNumber === 5) {
              result.thread.viewNum = threadReader.readVarint();
            } else if (threadTag.fieldNumber === 28) {
              result.thread.forumName = threadReader.readString();
            } else if (threadTag.fieldNumber === 45) {
              result.thread.createTime = threadReader.readVarint();
            } else if (threadTag.fieldNumber === 56) {
              threadAuthorId = threadReader.readVarint();
            } else if (threadTag.fieldNumber === 126) {
              // agree（AgreeInfo）
              const agreeReader: ProtoReader = threadReader.readMessage();
              while (!agreeReader.isEnd()) {
                const agreeTag: ProtoTag = agreeReader.readTag();
                if (agreeTag.fieldNumber === 1) {
                  result.thread.agreeNum = agreeReader.readVarint();
                } else if (agreeTag.fieldNumber === 4) {
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
          const userReader: ProtoReader = dataReader.readMessage();
          const user: SendableUserInfo = decodeUserInline(userReader);
          users.set(user.uid, user);
        } else {
          dataReader.skipField(dataTag.wireType);
        }
      }

      // 补全 thread.forumName（若 thread 内嵌吧名缺失则用 forum 字段）
      if (result.thread.forumName.length === 0 && forumName.length > 0) {
        result.thread.forumName = forumName;
      }
      // 补全 forumId
      result.forumId = forumIdValue;
      // 补全 thread.author
      if (threadAuthorId > 0) {
        const author: SendableUserInfo | undefined = users.get(threadAuthorId);
        if (author !== undefined) {
          result.thread.author = author;
        }
      }

      // 第二遍：解析 posts
      for (let i = 0; i < rawPosts.length; i++) {
        result.postsList.push(decodePostInline(rawPosts[i], users, threadTid));
      }
    } else {
      reader.skipField(tag.wireType);
    }
  }

  return result;
}

/**
 * TaskPool 解码 PbFloorRes（楼中楼列表）
 * 对齐 PbFloorProto.decodePbFloorRes 字段编号与关联逻辑
 */
@Concurrent
export function decodePbFloorResTask(bytes: Uint8Array, tid: number, pid: number): SendablePbFloorResult {
  const reader: ProtoReader = new ProtoReader(bytes);
  const result: SendablePbFloorResult = new SendablePbFloorResult();

  while (!reader.isEnd()) {
    const tag: ProtoTag = reader.readTag();
    if (tag.fieldNumber === 1) {
      // error
      const errReader: ProtoReader = reader.readMessage();
      let errorNo: number = 0;
      let errorMsg: string = '';
      while (!errReader.isEnd()) {
        const errTag: ProtoTag = errReader.readTag();
        if (errTag.fieldNumber === 1) {
          errorNo = errReader.readVarint();
        } else if (errTag.fieldNumber === 2) {
          errorMsg = errReader.readString();
        } else {
          errReader.skipField(errTag.wireType);
        }
      }
      if (errorNo !== 0) {
        throw new Error(`获取楼中楼失败 [${errorNo}]: ${errorMsg}`);
      }
    } else if (tag.fieldNumber === 2) {
      // data
      const dataReader: ProtoReader = reader.readMessage();
      while (!dataReader.isEnd()) {
        const dataTag: ProtoTag = dataReader.readTag();
        if (dataTag.fieldNumber === 1) {
          // page
          const pageReader: ProtoReader = dataReader.readMessage();
          while (!pageReader.isEnd()) {
            const pageTag: ProtoTag = pageReader.readTag();
            if (pageTag.fieldNumber === 3) {
              result.currentPage = pageReader.readVarint();
            } else if (pageTag.fieldNumber === 5) {
              result.totalPages = pageReader.readVarint();
            } else {
              pageReader.skipField(pageTag.wireType);
            }
          }
          result.hasMore = result.currentPage < result.totalPages;
        } else if (dataTag.fieldNumber === 4) {
          // subpost_list（repeated SubPostList）
          const subReader: ProtoReader = dataReader.readMessage();
          const subPost: SendableSubPostInfo = decodeSubPostListInline(subReader, tid, pid);
          if (subPost.spid > 0) {
            result.subPosts.push(subPost);
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

// ==================== 主线程 rebuild 函数 ====================
// 将 @Sendable 中间对象重建为 @ObservedV2 业务对象（@ObservedV2 不能跨线程传递，需在主线程重建）
// 这些函数不是 @Concurrent 函数，可以使用同文件定义的函数（互相调用）。

/** rebuild UserInfo */
function rebuildUserInfo(s: SendableUserInfo): UserInfo {
  const u: UserInfo = new UserInfo();
  u.uid = s.uid;
  u.name = s.name;
  u.nickname = s.nickname;
  u.avatar = s.avatar;
  u.portrait = s.portrait;
  u.level = s.level;
  u.levelName = s.levelName;
  u.gender = s.gender;
  u.isBawu = s.isBawu;
  return u;
}

/** rebuild MediaInfo */
function rebuildMediaInfo(s: SendableMediaInfo): MediaInfo {
  const m: MediaInfo = new MediaInfo();
  m.type = s.type;
  m.url = s.url;
  m.thumbnail = s.thumbnail;
  m.width = s.width;
  m.height = s.height;
  return m;
}

/** rebuild VideoInfo */
function rebuildVideoInfo(s: SendableVideoInfo): VideoInfo {
  const v: VideoInfo = new VideoInfo();
  v.videoUrl = s.videoUrl;
  v.videoDuration = s.videoDuration;
  v.videoWidth = s.videoWidth;
  v.videoHeight = s.videoHeight;
  v.thumbnailUrl = s.thumbnailUrl;
  v.thumbnailWidth = s.thumbnailWidth;
  v.thumbnailHeight = s.thumbnailHeight;
  return v;
}

/** rebuild ContentFragment */
function rebuildContentFragment(s: SendableContentFragment): ContentFragment {
  const f: ContentFragment = new ContentFragment();
  f.type = s.type;
  f.text = s.text;
  f.link = s.link;
  f.uid = s.uid;
  f.emojiDesc = s.emojiDesc;
  f.videoUrl = s.videoUrl;
  f.coverUrl = s.coverUrl;
  f.videoWidth = s.videoWidth;
  f.videoHeight = s.videoHeight;
  return f;
}

/** rebuild ThreadInfo */
function rebuildThreadInfo(s: SendableThreadInfo): ThreadInfo {
  const t: ThreadInfo = new ThreadInfo();
  t.tid = s.tid;
  t.title = s.title;
  t.author = rebuildUserInfo(s.author);
  t.content = s.content;
  t.createTime = s.createTime;
  t.replyNum = s.replyNum;
  t.viewNum = s.viewNum;
  t.agreeNum = s.agreeNum;
  t.disagreeNum = s.disagreeNum;
  t.isTop = s.isTop;
  t.isGood = s.isGood;
  t.isEssence = s.isEssence;
  for (let i = 0; i < s.mediaList.length; i++) {
    t.mediaList.push(rebuildMediaInfo(s.mediaList[i]));
  }
  t.forumName = s.forumName;
  t.hotNum = s.hotNum;
  t.videoInfo = rebuildVideoInfo(s.videoInfo);
  return t;
}

/** rebuild PostInfo */
function rebuildPostInfo(s: SendablePostInfo): PostInfo {
  const p: PostInfo = new PostInfo();
  p.pid = s.pid;
  p.tid = s.tid;
  p.author = rebuildUserInfo(s.author);
  p.content = s.content;
  for (let i = 0; i < s.fragments.length; i++) {
    p.fragments.push(rebuildContentFragment(s.fragments[i]));
  }
  p.createTime = s.createTime;
  p.floor = s.floor;
  p.agreeNum = s.agreeNum;
  p.disagreeNum = s.disagreeNum;
  p.replyNum = s.replyNum;
  for (let i = 0; i < s.mediaList.length; i++) {
    p.mediaList.push(rebuildMediaInfo(s.mediaList[i]));
  }
  // subPostList 在 PbPage 解码中未填充（楼中楼走 PbFloor 独立接口），保留空数组
  p.isAgreed = s.isAgreed;
  p.isDisagreed = s.isDisagreed;
  p.isAgreeing = s.isAgreeing;
  p.videoInfo = s.hasVideoInfo ? rebuildVideoInfo(s.videoInfo) : null;
  return p;
}

/** rebuild SubPostInfo */
function rebuildSubPostInfo(s: SendableSubPostInfo): SubPostInfo {
  const sp: SubPostInfo = new SubPostInfo();
  sp.spid = s.spid;
  sp.pid = s.pid;
  sp.tid = s.tid;
  sp.author = rebuildUserInfo(s.author);
  sp.content = s.content;
  for (let i = 0; i < s.fragments.length; i++) {
    sp.fragments.push(rebuildContentFragment(s.fragments[i]));
  }
  sp.createTime = s.createTime;
  sp.agreeNum = s.agreeNum;
  sp.disagreeNum = s.disagreeNum;
  sp.floor = s.floor;
  sp.title = s.title;
  sp.isAgreed = s.isAgreed;
  sp.isDisagreed = s.isDisagreed;
  return sp;
}

/** rebuild ForumInfo */
function rebuildForumInfo(s: SendableForumInfo): ForumInfo {
  const f: ForumInfo = new ForumInfo();
  f.id = s.id;
  f.name = s.name;
  f.avatar = s.avatar;
  f.slogan = s.slogan;
  f.memberCount = s.memberCount;
  f.postCount = s.postCount;
  f.isFollowed = s.isFollowed;
  return f;
}

// ==================== 对外暴露的 TaskPool 调用包装 ====================

/** 在 TaskPool 子线程解码 FrsPageRes，主线程 rebuild 为 FrsPageResult */
export async function decodeFrsPageResAsync(bytes: Uint8Array): Promise<FrsPageResult> {
  const sendable: SendableFrsPageResult = await taskpool.execute(decodeFrsPageResTask, bytes) as SendableFrsPageResult;
  const result: FrsPageResult = new FrsPageResult();
  result.forum = rebuildForumInfo(sendable.forum);
  result.threads.currentPage = sendable.threadsPage.currentPage;
  result.threads.totalPage = sendable.threadsPage.totalPage;
  result.threads.hasMore = sendable.threadsPage.hasMore;
  const threads: ThreadInfo[] = [];
  for (let i = 0; i < sendable.threadsList.length; i++) {
    threads.push(rebuildThreadInfo(sendable.threadsList[i]));
  }
  result.threads.list = threads;
  return result;
}

/** 在 TaskPool 子线程解码 PbPageRes，主线程 rebuild 为 PbPageResult */
export async function decodePbPageResAsync(bytes: Uint8Array): Promise<PbPageResult> {
  const sendable: SendablePbPageResult = await taskpool.execute(decodePbPageResTask, bytes) as SendablePbPageResult;
  const result: PbPageResult = new PbPageResult();
  result.forumId = sendable.forumId;
  result.thread = rebuildThreadInfo(sendable.thread);
  result.posts.currentPage = sendable.postsPage.currentPage;
  result.posts.totalPage = sendable.postsPage.totalPage;
  result.posts.hasMore = sendable.postsPage.hasMore;
  result.posts.hasPrev = sendable.postsPage.hasPrev;
  const posts: PostInfo[] = [];
  for (let i = 0; i < sendable.postsList.length; i++) {
    posts.push(rebuildPostInfo(sendable.postsList[i]));
  }
  result.posts.list = posts;
  return result;
}

/** 在 TaskPool 子线程解码 PbFloorRes，主线程 rebuild 为 PbFloorResult */
export async function decodePbFloorResAsync(bytes: Uint8Array, tid: number, pid: number): Promise<PbFloorResult> {
  const sendable: SendablePbFloorResult = await taskpool.execute(decodePbFloorResTask, bytes, tid, pid) as SendablePbFloorResult;
  const result: PbFloorResult = new PbFloorResult();
  result.currentPage = sendable.currentPage;
  result.totalPages = sendable.totalPages;
  result.hasMore = sendable.hasMore;
  for (let i = 0; i < sendable.subPosts.length; i++) {
    result.subPosts.push(rebuildSubPostInfo(sendable.subPosts[i]));
  }
  return result;
}
