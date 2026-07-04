/**
 * 用户主页相关数据模型
 *
 * 设计依据：aiotieba-master 的 get_uinfo_panel / get_follows / get_fans API 实现
 * 字段与 aiotieba UserInfo_panel / Follow / Fan 对齐
 *
 * 与 ForumModels.ets 中 UserInfo 区分：
 * - UserInfo 用于帖子/回复的作者摘要（仅 uid/name/avatar）
 * - UserProfileInfo 用于用户主页展示（含发帖数/粉丝数/吧龄等完整字段）
 * 遵循 aiotieba AGENTS.md "避免为多场景共用超大类" 原则
 */

/**
 * 用户主页完整信息（对应 aiotieba UserInfo_panel）
 *
 * 用 @Observed 装饰：在 @State 持有该类实例时，内部字段变化（如 isFollowing 切换）
 * 能触发 UI 刷新。否则需重新赋值整个对象才能刷新。
 */
@Observed
export class UserProfileInfo {
  uid: number = 0;             // 旧版 user_id（panel API 不返回，由调用方传入）
  portrait: string = '';       // portrait 头像标识，同时作为 panel API 的 id 参数
  userName: string = '';       // 用户名 name
  nickName: string = '';       // 新版昵称 show_nickname（protobuf 路径取 nameShow#4）
  nickNameOld: string = '';    // 旧版昵称 name_show
  gender: number = 0;          // 性别：0=未知 1=男 2=女
  age: number = 0;             // 吧龄（年）
  postNum: number = 0;         // 发帖数 post_num
  fanNum: number = 0;          // 粉丝数 fans_num#30
  followNum: number = 0;       // 关注数 concern_num#31（对齐 aiotieba UserInfo_pf.follow_num）
  isVip: boolean = false;      // 是否超级会员
  isFollowing: boolean = false; // 当前登录用户是否已关注 TA
  sign: string = '';           // 个性签名 intro（protobuf cmd=303012 路径新增）
  tiebaUid: number = 0;        // 贴吧 uid（tieba_uid#120，string 转 number）
  agreeNum: number = 0;        // 获赞数（来自 data.user_agree_info.total_agree_num）

  constructor(init?: Partial<UserProfileInfo>) {
    if (init) {
      this.copyFrom(init);
    }
  }

  private copyFrom(init: Partial<UserProfileInfo>): void {
    if (init.uid !== undefined) this.uid = init.uid;
    if (init.portrait !== undefined) this.portrait = init.portrait;
    if (init.userName !== undefined) this.userName = init.userName;
    if (init.nickName !== undefined) this.nickName = init.nickName;
    if (init.nickNameOld !== undefined) this.nickNameOld = init.nickNameOld;
    if (init.gender !== undefined) this.gender = init.gender;
    if (init.age !== undefined) this.age = init.age;
    if (init.postNum !== undefined) this.postNum = init.postNum;
    if (init.fanNum !== undefined) this.fanNum = init.fanNum;
    if (init.followNum !== undefined) this.followNum = init.followNum;
    if (init.isVip !== undefined) this.isVip = init.isVip;
    if (init.isFollowing !== undefined) this.isFollowing = init.isFollowing;
    if (init.sign !== undefined) this.sign = init.sign;
    if (init.tiebaUid !== undefined) this.tiebaUid = init.tiebaUid;
    if (init.agreeNum !== undefined) this.agreeNum = init.agreeNum;
  }
}

/** 关注/粉丝列表中的用户项（对应 aiotieba Follow / Fan） */
export class FollowUserInfo {
  userId: number = 0;          // 用户 id
  portrait: string = '';       // portrait 头像标识
  userName: string = '';       // 用户名 name
  nickName: string = '';       // 新版昵称 name_show

  constructor(init?: Partial<FollowUserInfo>) {
    if (init) {
      this.copyFrom(init);
    }
  }

  private copyFrom(init: Partial<FollowUserInfo>): void {
    if (init.userId !== undefined) this.userId = init.userId;
    if (init.portrait !== undefined) this.portrait = init.portrait;
    if (init.userName !== undefined) this.userName = init.userName;
    if (init.nickName !== undefined) this.nickName = init.nickName;
  }
}

/** 关注列表分页信息（对应 aiotieba Page_follow，分页字段在响应顶层） */
export class FollowsPageInfo {
  currentPage: number = 1;
  totalCount: number = 0;
  hasMore: boolean = false;

  constructor(init?: Partial<FollowsPageInfo>) {
    if (init) {
      this.copyFrom(init);
    }
  }

  private copyFrom(init: Partial<FollowsPageInfo>): void {
    if (init.currentPage !== undefined) this.currentPage = init.currentPage;
    if (init.totalCount !== undefined) this.totalCount = init.totalCount;
    if (init.hasMore !== undefined) this.hasMore = init.hasMore;
  }
}

/** 粉丝列表分页信息（对应 aiotieba Page_fan，分页字段在 page 子对象内） */
export class FansPageInfo {
  pageSize: number = 0;
  currentPage: number = 1;
  totalPage: number = 1;
  totalCount: number = 0;
  hasMore: boolean = false;

  constructor(init?: Partial<FansPageInfo>) {
    if (init) {
      this.copyFrom(init);
    }
  }

  private copyFrom(init: Partial<FansPageInfo>): void {
    if (init.pageSize !== undefined) this.pageSize = init.pageSize;
    if (init.currentPage !== undefined) this.currentPage = init.currentPage;
    if (init.totalPage !== undefined) this.totalPage = init.totalPage;
    if (init.totalCount !== undefined) this.totalCount = init.totalCount;
    if (init.hasMore !== undefined) this.hasMore = init.hasMore;
  }
}

/** getFollows 调用结果：用户列表 + 分页信息 */
export class FollowsResult {
  list: FollowUserInfo[] = [];
  pageInfo: FollowsPageInfo = new FollowsPageInfo();

  constructor(init?: Partial<FollowsResult>) {
    if (init) {
      this.copyFrom(init);
    }
  }

  private copyFrom(init: Partial<FollowsResult>): void {
    if (init.list !== undefined) this.list = init.list;
    if (init.pageInfo !== undefined) this.pageInfo = init.pageInfo;
  }
}

/** getFans 调用结果：用户列表 + 分页信息 */
export class FansResult {
  list: FollowUserInfo[] = [];
  pageInfo: FansPageInfo = new FansPageInfo();

  constructor(init?: Partial<FansResult>) {
    if (init) {
      this.copyFrom(init);
    }
  }

  private copyFrom(init: Partial<FansResult>): void {
    if (init.list !== undefined) this.list = init.list;
    if (init.pageInfo !== undefined) this.pageInfo = init.pageInfo;
  }
}
