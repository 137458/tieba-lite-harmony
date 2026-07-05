export class ForumInfo {
  id: number = 0;
  name: string = '';
  avatar: string = '';
  slogan: string = '';
  memberCount: number = 0;
  postCount: number = 0;
  isFollowed: boolean = false;

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

/**
 * #71 富文本碎片类型枚举（对齐 aiotieba Contents_p._type 映射）
 * 值为映射后的标准类型（原始 proto type 已合并到统一枚举）：
 * - 原始 0/9/18/27/40 → TEXT
 * - 原始 1 → LINK
 * - 原始 2/11 → EMOJI
 * - 原始 3/20 → IMAGE（保留枚举，但阶段一图片仍走 mediaList 独立块渲染）
 * - 原始 4 → AT
 */
export enum ContentFragmentType {
  TEXT = 0,
  LINK = 1,
  EMOJI = 2,
  IMAGE = 3,
  AT = 4,
}

/**
 * #71 富文本碎片（对齐 aiotieba FragText_p / FragLink_p / FragEmoji_p / FragAt_p）
 * 字段语义随 type 变化（对齐 aiotieba 字段编号映射）：
 * - TEXT: text = 正文文本（field 2）
 * - LINK: text = 链接标题（field 2）, link = 链接URL（field 3）
 * - EMOJI: text = 表情id（field 2）, emojiDesc = 表情描述（field 11）
 * - AT: text = 被@用户昵称（field 2）, uid = 用户ID（field 15）
 *
 * @Observed 装饰：当前 fragments 解析后只读，但为未来局部刷新场景预留
 * （如点击 @ 后变色，需配合 @ObjectLink 拆分子组件）
 */
@Observed
export class ContentFragment {
  type: ContentFragmentType = ContentFragmentType.TEXT;
  text: string = '';
  link: string = '';          // 仅 LINK
  uid: number = 0;            // 仅 AT
  emojiDesc: string = '';     // 仅 EMOJI

  constructor(init?: Partial<ContentFragment>) {
    if (init) {
      this.copyFrom(init);
    }
  }

  private copyFrom(init: Partial<ContentFragment>): void {
    if (init.type !== undefined) this.type = init.type;
    if (init.text !== undefined) this.text = init.text;
    if (init.link !== undefined) this.link = init.link;
    if (init.uid !== undefined) this.uid = init.uid;
    if (init.emojiDesc !== undefined) this.emojiDesc = init.emojiDesc;
  }
}

@Observed
export class PostInfo {
  pid: number = 0;
  tid: number = 0;
  author: UserInfo = new UserInfo();
  content: string = '';
  // #71 富文本碎片列表（渲染层用 Text+Span+ImageSpan 替代纯 content 字符串）
  fragments: ContentFragment[] = [];
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
  // 防抖锁：点赞/点踩请求进行中时禁用按钮，避免连点导致赞数错乱（3280003/3280004）
  isAgreeing: boolean = false;

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
    if (init.fragments !== undefined) this.fragments = init.fragments;
    if (init.createTime !== undefined) this.createTime = init.createTime;
    if (init.floor !== undefined) this.floor = init.floor;
    if (init.agreeNum !== undefined) this.agreeNum = init.agreeNum;
    if (init.disagreeNum !== undefined) this.disagreeNum = init.disagreeNum;
    if (init.replyNum !== undefined) this.replyNum = init.replyNum;
    if (init.mediaList !== undefined) this.mediaList = init.mediaList;
    if (init.subPostList !== undefined) this.subPostList = init.subPostList;
    if (init.isAgreed !== undefined) this.isAgreed = init.isAgreed;
    if (init.isDisagreed !== undefined) this.isDisagreed = init.isDisagreed;
    // #93 补全 isAgreeing 字段：之前 copyFrom 缺失此字段，
    // 若通过 new PostInfo(init) 重建对象（如某个 appendData 路径），
    // 新对象 isAgreeing 会被默认置为 false，可能卡锁或丢状态
    if (init.isAgreeing !== undefined) this.isAgreeing = init.isAgreeing;
  }
}

@Observed
export class SubPostInfo {
  /** 楼中楼 id（即 SubPostList.id，对齐 Android SubPostItemData.id） */
  spid: number = 0;
  /** 所在楼层 pid（PostInfo.pid） */
  pid: number = 0;
  /** 主题帖 tid（PostInfo.tid） */
  tid: number = 0;
  author: UserInfo = new UserInfo();
  content: string = '';
  /** #71 富文本碎片列表（复用 PostInfo.fragments 渲染方案） */
  fragments: ContentFragment[] = [];
  createTime: number = 0;
  agreeNum: number = 0;
  disagreeNum: number = 0;
  /** 楼层号（SubPostList.floor，对齐 Android 字段） */
  floor: number = 0;
  /** 标题（SubPostList.title，通常为空） */
  title: string = '';
  // 本地状态：当前用户是否已赞/已踩（服务端不返回，点击后本地维护）
  isAgreed: boolean = false;
  isDisagreed: boolean = false;

  constructor(init?: Partial<SubPostInfo>) {
    if (init) {
      this.copyFrom(init);
    }
  }

  private copyFrom(init: Partial<SubPostInfo>): void {
    if (init.spid !== undefined) this.spid = init.spid;
    if (init.pid !== undefined) this.pid = init.pid;
    if (init.tid !== undefined) this.tid = init.tid;
    if (init.author !== undefined) this.author = init.author;
    if (init.content !== undefined) this.content = init.content;
    if (init.fragments !== undefined) this.fragments = init.fragments;
    if (init.createTime !== undefined) this.createTime = init.createTime;
    if (init.agreeNum !== undefined) this.agreeNum = init.agreeNum;
    if (init.disagreeNum !== undefined) this.disagreeNum = init.disagreeNum;
    if (init.floor !== undefined) this.floor = init.floor;
    if (init.title !== undefined) this.title = init.title;
    if (init.isAgreed !== undefined) this.isAgreed = init.isAgreed;
    if (init.isDisagreed !== undefined) this.isDisagreed = init.isDisagreed;
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

/**
 * 贴吧搜索结果
 * 对齐 TiebaLite SearchForumBean：exactMatch 精确匹配 + fuzzyMatch 模糊匹配列表
 * 端点：GET /mo/q/search/forum?word=xxx（web 端点）
 * 用 hasExactMatch 标志位避免 nullable 字段（ArkTS 谨慎用联合类型）
 */
@Observed
export class SearchForumResult {
  hasExactMatch: boolean = false;
  exactMatch: ForumInfo = new ForumInfo();
  fuzzyMatch: ForumInfo[] = [];
}

export class PageData<T> {
  list: T[] = [];
  currentPage: number = 1;
  totalPage: number = 1;
  hasMore: boolean = false;
  // #72 是否有上一页（Page.has_prev field 7），用于"加载上一页"按钮显示
  hasPrev: boolean = false;

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
    if (init.hasPrev !== undefined) this.hasPrev = init.hasPrev;
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
