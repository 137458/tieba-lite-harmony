// TiebaAPI 响应模型与参数契约（H01 自 TiebaAPI.ets 纯迁移）
// JSON 响应 interface 为 wire 契约（error_code 运行时可能是数字或字符串）；
// class 为解析结果模型。TiebaAPI.ets 对本文件 re-export，既有引用方 import 路径不变。
import { MediaInfo, UserInfo } from '../model/ForumModels';

/** 通用错误信息结构 */
export interface ErrorInfo {
  errno?: string;
  errmsg?: string;
}

/** 收藏数据项结构 */
export interface CollectDataItem {
  tid: string;
  pid: string;
  status: number;
}

export interface LoginUser {
  id?: number;
  name?: string;
  name_show?: string;
  portrait?: string;
}

export interface LoginAnti {
  tbs?: string;
}

export interface LoginResponse {
  // error_code 运行时可能为数字或字符串（JSON.parse 不保证类型），声明为联合类型
  error_code?: number | string;
  error_msg?: string;
  user?: LoginUser;
  anti?: LoginAnti;
}

export interface AgreeResponse {
  // error_code 运行时可能为数字或字符串（JSON.parse 不保证类型），声明为联合类型
  error_code?: number | string;
  error_msg?: string;
}

/** /c/f/forum/forumGuide 响应（对齐 aiotieba get_self_follow_forums） */
export interface FollowForumsResponse {
  // error_code 运行时可能为数字或字符串（JSON.parse 不保证类型），声明为联合类型
  error_code?: number | string;
  error_msg?: string;
  like_forum?: object[];
  like_forum_has_more?: number | string;
}

export interface ForumListResponse {
  error_code?: number | string;
  error_msg?: string;
  level?: number | string;
  msign_step_num?: number | string;
}

export interface MultiSignInfo {
  forum_id?: number | string;
  signed?: number | string;
}

export interface MultiSignResponse {
  error_code?: number | string;
  error_msg?: string;
  info?: MultiSignInfo[];
}

export class SignAllForumsResult {
  totalCount: number = 0;
  signedCount: number = 0;
  failedCount: number = 0;
  signedFids: number[] = [];
}

/** /c/f/post/threadstore 响应（对齐原 app ThreadStoreBean） */
export interface ThreadStoreResponse {
  // error_code 运行时可能为数字或字符串（JSON.parse 不保证类型），声明为联合类型
  error_code?: number | string;
  error_msg?: string;
  error?: ErrorInfo;
  store_thread?: ThreadStoreItem[];
}

/** threadstore 中的帖子项 */
export interface ThreadStoreItem {
  thread_id?: string;
  title?: string;
  forum_name?: string;
  author?: ThreadStoreAuthor;
  media?: ThreadStoreMedia[];
  is_deleted?: string;
  last_time?: string;
  count?: string;
}

/** threadstore 作者信息 */
export interface ThreadStoreAuthor {
  lz_uid?: string;
  name?: string;
  name_show?: string;
  user_portrait?: string;
}

/** threadstore 媒体信息 */
export interface ThreadStoreMedia {
  type?: string;
  small_Pic?: string;
  big_pic?: string;
  width?: number;
  height?: number;
}

/** 通用响应（对齐原 app CommonResponse，addstore/rmstore 用） */
export interface CommonResponse {
  error_code?: number | string;
  error_msg?: string;
  error?: ErrorInfo;
}

/** /c/s/sync 响应 client 子对象 */
export interface SyncClient {
  client_id?: string;
}

/** /c/s/sync 响应 wl_config 子对象 */
export interface SyncWlConfig {
  sample_id?: string;
}

/** /c/s/sync 响应顶层 */
export interface SyncResponse {
  // error_code 运行时可能为数字或字符串（JSON.parse 不保证类型），声明为联合类型
  error_code?: number | string;
  error_msg?: string;
  client?: SyncClient;
  wl_config?: SyncWlConfig;
}

/** sync 接口返回值 */
export class SyncResult {
  clientId: string = '';
  sampleId: string = '';
}

/** /c/s/initNickname 响应 user_info 子对象 */
export interface InitNicknameUserInfo {
  user_name?: string;
  name_show?: string;
  tieba_uid?: string | number;
}

/** /c/s/initNickname 响应顶层 */
export interface InitNicknameResponse {
  // error_code 运行时可能为数字或字符串（JSON.parse 不保证类型），声明为联合类型
  error_code?: number | string;
  error_msg?: string;
  user_info?: InitNicknameUserInfo;
}

/** initNickname 接口返回值 */
export class InitNicknameResult {
  userName: string = '';
  nameShow: string = '';
  tiebaUid: number = 0;
}

/** /c/c/user/follow 与 /c/c/user/unfollow 响应 */
export interface FollowOpResponse {
  // error_code 运行时可能为数字或字符串（JSON.parse 不保证类型），声明为联合类型
  error_code?: number | string;
  error_msg?: string;
}

/** /c/u/follow/followList 响应顶层 */
export interface FollowsResponse {
  // error_code 运行时可能为数字或字符串（JSON.parse 不保证类型），声明为联合类型
  error_code?: number | string;
  error_msg?: string;
  follow_list?: object[];
  pn?: string | number;
  total_follow_num?: string | number;
  has_more?: string | number;
}

/** /c/u/fans/page 响应顶层 */
export interface FansResponse {
  // error_code 运行时可能为数字或字符串（JSON.parse 不保证类型），声明为联合类型
  error_code?: number | string;
  error_msg?: string;
  user_list?: object[];
  page?: object;
}

/** /c/u/fans/page 的 page 子对象 */
export class FansPage {
  page_size?: string | number;
  current_page?: string | number;
  total_page?: string | number;
  total_count?: string | number;
  has_more?: string | number;
  has_prev?: string | number;
}

export interface UserInfoInit {
  uid: number;
  name: string;
  nickname?: string;
  avatar: string;
}

export interface ThreadInfoInit {
  tid: number;
  title: string;
  content: string;
  replyNum: number;
  viewNum: number;
  isTop: boolean;
  isGood: boolean;
  author: UserInfo;
  createTime: number;
  forumName: string;
  mediaList: MediaInfo[];
}

/** 搜索类型枚举（对齐 aiotieba SearchType） */
export enum SearchType {
  /** 搜索全部 */
  ALL = 0,
  /** 按时间倒序 */
  TIME = 1,
  /** 按相关性排序 */
  RELATION = 2
}

/** searchExact 的参数对象（issue #29：options 对象传参，避免 6 参数位置传错） */
export interface ISearchExactParams {
  /** 吧名（kw，可为空字符串表示全吧搜索） */
  fname: string;
  /** 关键词（word） */
  keyword: string;
  /** 页码（pn），从 1 开始 */
  page: number;
  /** 每页数量（rn），默认 30 */
  pageSize: number;
  /** 搜索类型（sm）：0=ALL / 1=TIME / 2=RELATION */
  searchType: SearchType;
  /** true 只搜主题帖，false 含楼中楼回复 */
  onlyThread: boolean;
}

/** addPost 回帖参数（issue #95 切片 3，8 参 → options 对象） */
export interface IAddPostParams {
  /** 回帖内容（content） */
  content: string;
  /** 帖子 ID（tid） */
  tid: number;
  /** 吧 ID（fid） */
  fid: number;
  /** 吧名（forumName） */
  forumName: string;
  /** 显示名称（nameShow） */
  nameShow: string;
  /** 楼中楼回复目标 postId（可选，>0 表示楼中楼回复） */
  postId?: number;
  /** 楼中楼回复目标 subPostId（可选） */
  subPostId?: number;
  /** 楼中楼回复目标用户 UID（可选） */
  replyUid?: number;
}

/** addThread 发新帖参数（Phase 4，z_id/name_show/tbs/stoken 等由 addThread 内部获取） */
export interface IAddThreadParams {
  /** 帖子标题（可为空，空标题时 is_ntitle=0） */
  title: string;
  /** 帖子正文（可含 #(表情名) 与 #(pic,...) 图片标记） */
  content: string;
  /** 吧 ID（fid） */
  forumId: number;
  /** 吧名（kw） */
  forumName: string;
}

/** /c/c/thread/add 响应（标准 c/c JSON：error_code + error_msg） */
export interface AddThreadResponse {
  error_code?: number | string;
  error_msg?: string;
}

/** getPosts 获取帖子回复参数（issue #95 切片 3，6 参 → options 对象，back/lastPostId 拆至 getPrevPosts） */
export interface IGetPostsParams {
  /** 帖子 ID（threadId） */
  threadId: number;
  /** 页码（pn），从 1 开始 */
  page: number;
  /** true 只看楼主 */
  onlyAuthor: boolean;
  /** 排序：0=正序 / 1=倒序 / 2=热门 */
  sort: number;
}

/** getTopicDetail 话题详情参数（issue #95 切片 3，6 参 → options 对象） */
export interface IGetTopicDetailParams {
  /** 话题 ID（topic_id） */
  topicId: string;
  /** 话题名称（topic_name） */
  topicName: string;
  /** 页码（page），从 1 开始 */
  page: number;
  /** 每页数量（page_size），默认 10 */
  pageSize: number;
  /** 偏移量（offset），加载更多时 = (currentPage-1) * pageSize */
  offset: number;
  /** 上一页最后一项 feedId（lastId），首页空字符串 */
  lastId: string;
}

/** /c/s/searchpost 响应 author 子对象 */
export interface SearchPostAuthor {
  name_show?: string;
}

/** /c/s/searchpost 响应 post_list 数组项 */
export interface SearchPostItem {
  content?: string;
  title?: string;
  fname?: string;
  tid?: string | number;
  pid?: string | number;
  author?: SearchPostAuthor;
  is_floor?: string | number;
  time?: string | number;
}

/** /c/s/searchpost 响应 page 子对象 */
export interface SearchPostPage {
  current_page?: string | number;
  total_page?: string | number;
  has_more?: string | number;
}

/** /c/s/searchpost 响应顶层 */
export interface SearchPostResponse {
  // error_code 运行时可能为数字或字符串（JSON.parse 不保证类型），声明为联合类型
  error_code?: number | string;
  error_msg?: string;
  post_list?: SearchPostItem[];
  page?: SearchPostPage;
}

/** /mo/q/search/forum 响应 data 子对象
 *  对齐 TiebaLite SearchForumBean.DataBean
 *  注意：exactMatch/fuzzyMatch 是 camelCase（非 snake_case），
 *  服务端可能返回单个对象或数组（TiebaLite 用 ExactMatchAdapter/ForumFuzzyMatchAdapter 兼容），
 *  用 object 类型接收，运行时用 Array.isArray 判断
 */
export interface SearchForumDataRaw {
  has_more?: string | number;
  pn?: string | number;
  fuzzyMatch?: object;
  exactMatch?: object;
}

/** /mo/q/search/forum 响应顶层
 *  对齐 TiebaLite SearchForumBean：
 *  - 错误码字段名是 no（不是 error_code）
 *  - 错误消息字段名是 error（不是 error_msg）
 *  - 数据封装在 data 对象中
 */
export interface SearchForumResponse {
  no?: number | string;
  error?: string;
  data?: SearchForumDataRaw;
}

// ==================== 消息（@我的）相关类型 ====================

/** /c/u/feed/atme 响应（对齐 aiotieba get_ats） */
export interface AtsResponse {
  // error_code 运行时可能为数字或字符串（JSON.parse 不保证类型），声明为联合类型
  error_code?: number | string;
  error_msg?: string;
  at_list?: AtsRawItem[];
  page?: AtsPageRaw;
}

/** at_list 数组项原始结构 */
export interface AtsRawItem {
  content?: string;
  fname?: string;
  thread_id?: string | number;
  post_id?: string | number;
  replyer?: AtsRawUser;
  is_floor?: string | number;
  is_first_post?: string | number;
  time?: string | number;
}

/** at_list[].replyer 原始用户结构 */
export interface AtsRawUser {
  id?: string | number;
  portrait?: string;
  name?: string;
  name_show?: string;
}

/** page 原始结构 */
export interface AtsPageRaw {
  current_page?: string | number;
  has_more?: string | number;
  has_prev?: string | number;
}

/** @我的消息用户信息 */
export class AtUser {
  userId: number = 0;
  userName: string = '';
  nickName: string = '';
  portrait: string = '';

  /** 显示名称：优先 nickName，其次 userName，最后 userId */
  getDisplayName(): string {
    if (this.nickName.length > 0) {
      return this.nickName;
    }
    if (this.userName.length > 0) {
      return this.userName;
    }
    return String(this.userId);
  }
}

/**
 * 用户在吧内的等级信息（getUserForumLevelInfo 接口返回）
 * 对齐 aiotieba get_user_forum_info/_classdef.py:UserForumInfo
 * 用于吧内页面显示等级经验值进度条（curScore/levelupScore/levelName）
 */
export class UserForumLevelInfo {
  /** 当前等级 */
  level: number = 0;
  /** 等级名称（如"吧主"） */
  levelName: string = '';
  /** 当前经验值 */
  curScore: number = 0;
  /** 升级所需经验值 */
  levelupScore: number = 0;
  /** 是否已关注该吧 */
  isFollow: boolean = false;
  /** 连续签到天数 */
  signDays: number = 0;
}

/** 单条@我的消息 */
export class AtMessage {
  text: string = '';
  fname: string = '';
  tid: number = 0;
  pid: number = 0;
  /** @我的 用户 */
  user: AtUser = new AtUser();
  /** 是否楼中楼 */
  isComment: boolean = false;
  /** 是否主题帖 */
  isThread: boolean = false;
  /** 创建时间（10 位秒级时间戳） */
  createTime: number = 0;
}

/** @我的列表分页信息 */
export class AtsPageInfo {
  currentPage: number = 0;
  hasMore: boolean = false;
  hasPrev: boolean = false;
}

/** @我的列表解析结果 */
export class AtsResult {
  list: AtMessage[] = [];
  page: AtsPageInfo = new AtsPageInfo();
}

// ==================== 消息计数（/c/s/msg）相关类型 ====================

/** /c/s/msg 响应 message 子对象（对齐 Android MsgBean.MessageBean） */
export interface MsgResponseMessage {
  /** 回复我的计数（数字字符串，"0" 表示无新消息） */
  replyme?: string;
  /** @我的计数（数字字符串） */
  atme?: string;
  /** 新粉丝数（数字字符串，当前未使用） */
  fans?: string;
}

/** /c/s/msg 响应顶层（对齐 Android MsgBean） */
export interface MsgResponse {
  // error_code 运行时可能为数字或字符串（JSON.parse 不保证类型），声明为联合类型
  error_code?: number | string;
  error_msg?: string;
  message?: MsgResponseMessage;
}

/** /c/s/msg 接口返回值（消息未读计数） */
export class MsgCountResult {
  /** 回复我的未读数 */
  replyMe: number = 0;
  /** @我的未读数 */
  atMe: number = 0;
  /** 新粉丝数（当前未使用，预留） */
  fans: number = 0;
}
