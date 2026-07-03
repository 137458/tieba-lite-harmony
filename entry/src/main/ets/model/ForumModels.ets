export class ForumInfo {
  id: number = 0;
  name: string = '';
  avatar: string = '';
  slogan: string = '';
  memberCount: number = 0;
  postCount: number = 0;
  isFollowed: boolean = false;
  levelId: number = 0;

  constructor(init?: Partial<ForumInfo>) {
    if (init) {
      this.copyFrom(init);
    }
  }

  private copyFrom(init: Partial<ForumInfo>): void {
    if (init.id !== undefined) this.id = init.id;
    if (init.name !== undefined) this.name = init.name;
    if (init.avatar !== undefined) this.avatar = init.avatar;
    if (init.slogan !== undefined) this.slogan = init.slogan;
    if (init.memberCount !== undefined) this.memberCount = init.memberCount;
    if (init.postCount !== undefined) this.postCount = init.postCount;
    if (init.isFollowed !== undefined) this.isFollowed = init.isFollowed;
    if (init.levelId !== undefined) this.levelId = init.levelId;
  }
}

@Observed
export class ThreadInfo {
  tid: number = 0;
  title: string = '';
  author: UserInfo = new UserInfo();
  content: string = '';
  createTime: number = 0;
  replyNum: number = 0;
  viewNum: number = 0;
  agreeNum: number = 0;
  disagreeNum: number = 0;
  isTop: boolean = false;
  isGood: boolean = false;
  isEssence: boolean = false;
  mediaList: MediaInfo[] = [];
  forumName: string = '';
  // 本地状态：当前用户是否已赞/已踩（服务端不返回，点击后本地维护）
  isAgreed: boolean = false;
  isDisagreed: boolean = false;
  // 热度值（仅热榜接口返回，ThreadInfo.proto field 182，用于热榜排名展示）
  hotNum: number = 0;

  constructor(init?: Partial<ThreadInfo>) {
    if (init) {
      this.copyFrom(init);
    }
  }

  private copyFrom(init: Partial<ThreadInfo>): void {
    if (init.tid !== undefined) this.tid = init.tid;
    if (init.title !== undefined) this.title = init.title;
    if (init.author !== undefined) this.author = init.author;
    if (init.content !== undefined) this.content = init.content;
    if (init.createTime !== undefined) this.createTime = init.createTime;
    if (init.replyNum !== undefined) this.replyNum = init.replyNum;
    if (init.viewNum !== undefined) this.viewNum = init.viewNum;
    if (init.agreeNum !== undefined) this.agreeNum = init.agreeNum;
    if (init.disagreeNum !== undefined) this.disagreeNum = init.disagreeNum;
    if (init.isTop !== undefined) this.isTop = init.isTop;
    if (init.isGood !== undefined) this.isGood = init.isGood;
    if (init.isEssence !== undefined) this.isEssence = init.isEssence;
    if (init.mediaList !== undefined) this.mediaList = init.mediaList;
    if (init.forumName !== undefined) this.forumName = init.forumName;
    if (init.isAgreed !== undefined) this.isAgreed = init.isAgreed;
    if (init.isDisagreed !== undefined) this.isDisagreed = init.isDisagreed;
    if (init.hotNum !== undefined) this.hotNum = init.hotNum;
  }
}

@Observed
export class PostInfo {
  pid: number = 0;
  tid: number = 0;
  author: UserInfo = new UserInfo();
  content: string = '';
  createTime: number = 0;
  floor: number = 0;
  agreeNum: number = 0;
  disagreeNum: number = 0;
  replyNum: number = 0;
  mediaList: MediaInfo[] = [];
  subPostList: SubPostInfo[] = [];
  // 本地状态：当前用户是否已赞/已踩（服务端不返回，点击后本地维护）
  isAgreed: boolean = false;
  isDisagreed: boolean = false;

  constructor(init?: Partial<PostInfo>) {
    if (init) {
      this.copyFrom(init);
    }
  }

  private copyFrom(init: Partial<PostInfo>): void {
    if (init.pid !== undefined) this.pid = init.pid;
    if (init.tid !== undefined) this.tid = init.tid;
    if (init.author !== undefined) this.author = init.author;
    if (init.content !== undefined) this.content = init.content;
    if (init.createTime !== undefined) this.createTime = init.createTime;
    if (init.floor !== undefined) this.floor = init.floor;
    if (init.agreeNum !== undefined) this.agreeNum = init.agreeNum;
    if (init.disagreeNum !== undefined) this.disagreeNum = init.disagreeNum;
    if (init.replyNum !== undefined) this.replyNum = init.replyNum;
    if (init.mediaList !== undefined) this.mediaList = init.mediaList;
    if (init.subPostList !== undefined) this.subPostList = init.subPostList;
    if (init.isAgreed !== undefined) this.isAgreed = init.isAgreed;
    if (init.isDisagreed !== undefined) this.isDisagreed = init.isDisagreed;
  }
}

export class SubPostInfo {
  spid: number = 0;
  pid: number = 0;
  author: UserInfo = new UserInfo();
  content: string = '';
  createTime: number = 0;
  agreeNum: number = 0;

  constructor(init?: Partial<SubPostInfo>) {
    if (init) {
      this.copyFrom(init);
    }
  }

  private copyFrom(init: Partial<SubPostInfo>): void {
    if (init.spid !== undefined) this.spid = init.spid;
    if (init.pid !== undefined) this.pid = init.pid;
    if (init.author !== undefined) this.author = init.author;
    if (init.content !== undefined) this.content = init.content;
    if (init.createTime !== undefined) this.createTime = init.createTime;
    if (init.agreeNum !== undefined) this.agreeNum = init.agreeNum;
  }
}

export class UserInfo {
  uid: number = 0;
  name: string = '';
  nickname: string = '';
  avatar: string = '';
  portrait: string = '';
  level: number = 0;
  levelName: string = '';
  gender: number = 0;
  isBawu: boolean = false;

  constructor(init?: Partial<UserInfo>) {
    if (init) {
      this.copyFrom(init);
    }
  }

  private copyFrom(init: Partial<UserInfo>): void {
    if (init.uid !== undefined) this.uid = init.uid;
    if (init.name !== undefined) this.name = init.name;
    if (init.nickname !== undefined) this.nickname = init.nickname;
    if (init.avatar !== undefined) this.avatar = init.avatar;
    if (init.portrait !== undefined) this.portrait = init.portrait;
    if (init.level !== undefined) this.level = init.level;
    if (init.levelName !== undefined) this.levelName = init.levelName;
    if (init.gender !== undefined) this.gender = init.gender;
    if (init.isBawu !== undefined) this.isBawu = init.isBawu;
  }
}

export class MediaInfo {
  type: MediaType = MediaType.IMAGE;
  url: string = '';
  thumbnail: string = '';
  width: number = 0;
  height: number = 0;

  constructor(init?: Partial<MediaInfo>) {
    if (init) {
      this.copyFrom(init);
    }
  }

  private copyFrom(init: Partial<MediaInfo>): void {
    if (init.type !== undefined) this.type = init.type;
    if (init.url !== undefined) this.url = init.url;
    if (init.thumbnail !== undefined) this.thumbnail = init.thumbnail;
    if (init.width !== undefined) this.width = init.width;
    if (init.height !== undefined) this.height = init.height;
  }
}

export enum MediaType {
  IMAGE = 0,
  VIDEO = 1,
  AUDIO = 2
}

/**
 * 吧内精确搜索结果项
 * 对齐 aiotieba api/search_exact/_classdef.py ExactSearch
 */
@Observed
export class ExactSearch {
  text: string = '';
  title: string = '';
  fname: string = '';
  tid: number = 0;
  pid: number = 0;
  showName: string = '';
  isComment: boolean = false;
  createTime: number = 0;

  constructor(init?: Partial<ExactSearch>) {
    if (init) {
      this.copyFrom(init);
    }
  }

  private copyFrom(init: Partial<ExactSearch>): void {
    if (init.text !== undefined) this.text = init.text;
    if (init.title !== undefined) this.title = init.title;
    if (init.fname !== undefined) this.fname = init.fname;
    if (init.tid !== undefined) this.tid = init.tid;
    if (init.pid !== undefined) this.pid = init.pid;
    if (init.showName !== undefined) this.showName = init.showName;
    if (init.isComment !== undefined) this.isComment = init.isComment;
    if (init.createTime !== undefined) this.createTime = init.createTime;
  }
}

export class PageData<T> {
  list: T[] = [];
  currentPage: number = 1;
  totalPage: number = 1;
  hasMore: boolean = false;

  constructor(init?: Partial<PageData<T>>) {
    if (init) {
      this.copyFrom(init);
    }
  }

  private copyFrom(init: Partial<PageData<T>>): void {
    if (init.list !== undefined) this.list = init.list;
    if (init.currentPage !== undefined) this.currentPage = init.currentPage;
    if (init.totalPage !== undefined) this.totalPage = init.totalPage;
    if (init.hasMore !== undefined) this.hasMore = init.hasMore;
  }
}

/**
 * 本账号关注的贴吧基本信息
 * 对齐 aiotieba get_self_follow_forums/_classdef.py:SelfFollowForum
 */
export class SelfFollowForum {
  fid: number = 0;
  fname: string = '';
  level: number = 0;
  isSigned: boolean = false;
  // 吧头像 URL（forumGuide 响应字段 avatar，issue #UI 重构新增）
  avatar: string = '';
  // 吧关注人数（forumGuide 响应字段 member_count，对齐 Android ForumGuideBean.LikeForum.memberCount）
  memberCount: number = 0;
  // 吧帖子总数（forumGuide 响应字段 thread_num，对齐 Android ForumGuideBean.LikeForum.threadNum）
  threadNum: number = 0;

  constructor(init?: Partial<SelfFollowForum>) {
    if (init) {
      this.copyFrom(init);
    }
  }

  private copyFrom(init: Partial<SelfFollowForum>): void {
    if (init.fid !== undefined) this.fid = init.fid;
    if (init.fname !== undefined) this.fname = init.fname;
    if (init.level !== undefined) this.level = init.level;
    if (init.isSigned !== undefined) this.isSigned = init.isSigned;
    if (init.avatar !== undefined) this.avatar = init.avatar;
    if (init.memberCount !== undefined) this.memberCount = init.memberCount;
    if (init.threadNum !== undefined) this.threadNum = init.threadNum;
  }
}

/**
 * 本账号关注贴吧列表分页结果
 * 对齐 aiotieba get_self_follow_forums/_classdef.py:SelfFollowForums
 */
export class SelfFollowForums {
  list: SelfFollowForum[] = [];
  hasMore: boolean = false;

  constructor(init?: Partial<SelfFollowForums>) {
    if (init) {
      this.copyFrom(init);
    }
  }

  private copyFrom(init: Partial<SelfFollowForums>): void {
    if (init.list !== undefined) this.list = init.list;
    if (init.hasMore !== undefined) this.hasMore = init.hasMore;
  }
}

/**
 * userLikeFlow 动态页响应结果（issue #50 切片3）
 * 对齐原 app UserLikeResponseData：threadInfo + pageTag + hasMore + requestUnix
 */
export class UserLikeResult {
  threadList: ThreadInfo[] = [];
  pageTag: string = '';
  hasMore: boolean = false;
  requestUnix: number = 0;

  constructor(init?: Partial<UserLikeResult>) {
    if (init) {
      this.copyFrom(init);
    }
  }

  private copyFrom(init: Partial<UserLikeResult>): void {
    if (init.threadList !== undefined) this.threadList = init.threadList;
    if (init.pageTag !== undefined) this.pageTag = init.pageTag;
    if (init.hasMore !== undefined) this.hasMore = init.hasMore;
    if (init.requestUnix !== undefined) this.requestUnix = init.requestUnix;
  }
}

/**
 * 热榜话题榜条目（Phase B Issue #67）
 * 对齐 RecomTopicList.proto（不含 rank 字段，排名用列表 index 推导）
 */
@Observed
export class HotTopicInfo {
  topicId: number = 0;
  topicName: string = '';
  discussNum: number = 0;
  topicDesc: string = '';
  topicPic: string = '';
  // 标签位掩码（field 5），原 app 用 tag==1 标"热"、tag==2 标"新"
  tag: number = 0;

  constructor(init?: Partial<HotTopicInfo>) {
    if (init) {
      this.copyFrom(init);
    }
  }

  private copyFrom(init: Partial<HotTopicInfo>): void {
    if (init.topicId !== undefined) this.topicId = init.topicId;
    if (init.topicName !== undefined) this.topicName = init.topicName;
    if (init.discussNum !== undefined) this.discussNum = init.discussNum;
    if (init.topicDesc !== undefined) this.topicDesc = init.topicDesc;
    if (init.topicPic !== undefined) this.topicPic = init.topicPic;
    if (init.tag !== undefined) this.tag = init.tag;
  }
}

/**
 * 热榜子 Tab 信息（Phase B Issue #67）
 * 对齐 FrsTabInfo.proto：tab_id=field1 / tab_name=field3 / tab_code=field8
 */
export class HotTabInfo {
  tabId: number = 0;
  tabName: string = '';
  tabCode: string = '';

  constructor(init?: Partial<HotTabInfo>) {
    if (init) {
      this.copyFrom(init);
    }
  }

  private copyFrom(init: Partial<HotTabInfo>): void {
    if (init.tabId !== undefined) this.tabId = init.tabId;
    if (init.tabName !== undefined) this.tabName = init.tabName;
    if (init.tabCode !== undefined) this.tabCode = init.tabCode;
  }
}

/**
 * 热榜响应结果（Phase B Issue #67）
 * 对齐 HotThreadListResIdl：topic_list + thread_info + hot_thread_tab_info
 * 无分页字段，一次拉全量；切换子 Tab 仅更新 threadList
 */
export class HotThreadListResult {
  topicList: HotTopicInfo[] = [];
  threadList: ThreadInfo[] = [];
  tabList: HotTabInfo[] = [];

  constructor(init?: Partial<HotThreadListResult>) {
    if (init) {
      this.copyFrom(init);
    }
  }

  private copyFrom(init: Partial<HotThreadListResult>): void {
    if (init.topicList !== undefined) this.topicList = init.topicList;
    if (init.threadList !== undefined) this.threadList = init.threadList;
    if (init.tabList !== undefined) this.tabList = init.tabList;
  }
}
