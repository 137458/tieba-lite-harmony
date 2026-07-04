/**
 * 话题详情数据模型
 * 对齐 Android TopicDetailBean.kt（web JSON 响应，非 protobuf）
 * 端点：GET /mo/q/newtopic/topicDetail
 */

/** 话题信息 */
export class TopicInfo {
  topicId: string = '';
  topicName: string = '';
  topicDesc: string = '';
  discussNum: number = 0;
  topicImage: string = '';
  shareTitle: string = '';
  sharePic: string = '';
  isVideoTopic: number = 0;
  idxNum: number = 0;
}

/** 相关帖子中的媒体信息 */
export class TopicMediaInfo {
  type: string = '';
  width: string = '';
  height: string = '';
  smallPic: string = '';
  bigPic: string = '';
  waterPic: string = '';
  isLongPic: number = 0;
  bSize: string = '';
}

/** 相关帖子作者 */
export class TopicThreadAuthor {
  name: string = '';
  id: number = 0;
  showNickName: string = '';
  nameShow: string = '';
  portrait: string = '';
}

/** 相关帖子（对齐 ThreadBean，简化字段） */
export class TopicThread {
  feedId: number = 0;
  tid: number = 0;
  title: string = '';
  forumId: number = 0;
  forumName: string = '';
  createTime: number = 0;
  abstractText: string = '';
  agreeNum: number = 0;
  replyNum: number = 0;
  shareNum: number = 0;
  userId: number = 0;
  firstPostId: number = 0;
  userAgree: number = 0;
  avatar: string = '';
  media: TopicMediaInfo[] = [];
  mediaNumPic: number = 0;
  author: TopicThreadAuthor = new TopicThreadAuthor();
}

/** 相关贴吧 */
export class RelateForum {
  forumId: number = 0;
  forumName: string = '';
  avatar: string = '';
  desc: string = '';
  memberNum: number = 0;
  threadNum: number = 0;
  postNum: number = 0;
}

/** 话题详情请求结果 */
export class TopicDetailResult {
  hasMore: boolean = false;
  currentPage: number = 1;
  topicInfo: TopicInfo = new TopicInfo();
  relateForum: RelateForum[] = [];
  relateThread: TopicThread[] = [];
}

/** 话题详情响应 JSON（顶层） */
export interface TopicDetailResponse {
  no: number | string;
  error: string;
  data: TopicDetailData;
}

/** 话题详情响应 data 字段 */
export interface TopicDetailData {
  topic_info: TopicInfoRaw;
  relate_forum: RelateForumRaw[];
  relate_thread: RelateThreadRaw;
  has_more: boolean;
  wreq: WreqRaw;
}

interface TopicInfoRaw {
  topic_id: string;
  topic_name: string;
  topic_desc: string;
  discuss_num: number;
  topic_image: string;
  share_title: string;
  share_pic: string;
  is_video_topic: number;
  idx_num: number;
}

interface RelateForumRaw {
  forum_id: number;
  forum_name: string;
  avatar: string;
  desc: string;
  member_num: number;
  thread_num: number;
  post_num: number;
}

interface RelateThreadRaw {
  thread_list: TopicThreadRaw[];
}

interface TopicThreadRaw {
  feed_id: number;
  thread_info: ThreadInfoRaw;
  user_agree: number;
}

interface ThreadInfoRaw {
  id: number;
  feed_id: number;
  avatar: string;
  title: string;
  tid: number;
  forum_id: number;
  forum_name: string;
  create_time: number;
  abstract: string;
  media: TopicMediaRaw[];
  media_num: MediaNumRaw;
  agree_num: number;
  reply_num: number;
  share_num: number;
  user_id: number;
  first_post_id: number;
  user_agree: number;
  author: AuthorRaw;
}

interface TopicMediaRaw {
  type: string;
  width: string;
  height: string;
  small_pic: string;
  big_pic: string;
  water_pic: string;
  is_long_pic: number;
  bsize: string;
}

interface MediaNumRaw {
  pic: number;
}

interface AuthorRaw {
  name: string;
  id: number;
  show_nickname: string;
  name_show: string;
  portrait: string;
}

interface WreqRaw {
  pn: number;
  rn: number;
}
