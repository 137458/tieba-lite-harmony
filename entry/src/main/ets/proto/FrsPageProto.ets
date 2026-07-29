// FrsPage protobuf 编解码（issue #6）
// 字段编号对齐 tbclient.protobuf-main/proto/FrsPage 原定义
// wire format 编解码复用 ProtoWire.ets

import { ThreadInfo, UserInfo, MediaInfo, MediaType, PageData, ForumInfo, VideoInfo, FrsTabInfo, SortButton, TabMenu, NavTabInfo } from '../model/ForumModels';
import { ProtoWriter, ProtoReader } from './ProtoWire';
import { getAvatarUrl } from '../utils/AvatarUtil';

// ==================== FrsPage 请求编码 ====================

/** FrsPage 请求参数 */
export interface IFrsPageReqParams {
  kw: string;
  pn: number;
  rn: number;
  isGood: boolean;
  sortType: number;
  clientVersion: string;
  // 账号字段可选：getThreads 公开读 API 不需要 BDUSS/cuid/tbs（对齐 aiotieba get_threads.pack_proto）
  // 仅个性化读 API（如 get_posts with_comments）才传 BDUSS
  bduss?: string;
  cuid?: string;
  cuidGalaxy2?: string;
  tbs?: string;
}

/**
 * 编码 CommonReq（field 编号对齐 CommonReq.proto）
 * 对齐 aiotieba get_threads.pack_proto：仅传 _client_type + _client_version
 * 账号字段（BDUSS/cuid/tbs/cuid_galaxy2）可选传入，空字符串不编码（ProtoWriter.writeString 自动跳过）
 */
function encodeCommonReq(writer: ProtoWriter, params: IFrsPageReqParams): void {
  writer.writeInt32(1, 2);                     // _client_type = 2
  writer.writeString(2, params.clientVersion); // _client_version
  if (params.cuid !== undefined) {
    writer.writeString(7, params.cuid);          // cuid
  }
  if (params.bduss !== undefined) {
    writer.writeString(10, params.bduss);        // BDUSS
  }
  if (params.tbs !== undefined) {
    writer.writeString(11, params.tbs);          // tbs
  }
  if (params.cuidGalaxy2 !== undefined) {
    writer.writeString(32, params.cuidGalaxy2);  // cuid_galaxy2
  }
}

/** 编码 DataReq */
function encodeDataReq(params: IFrsPageReqParams): Uint8Array {
  const writer = new ProtoWriter();
  writer.writeString(1, params.kw);                        // kw
  writer.writeInt32(2, params.rn);                         // rn
  writer.writeInt32(3, params.rn + 5);                     // rn_need（对齐 aiotieba）
  writer.writeInt32(4, params.isGood ? 1 : 0);             // is_good
  writer.writeInt32(15, params.pn === 1 ? 0 : params.pn);  // pn（aiotieba: pn=1 时传 0）
  writer.writeInt32(47, params.sortType);                  // sort_type

  // common（field 39，嵌套 message）
  const commonWriter = new ProtoWriter();
  encodeCommonReq(commonWriter, params);
  writer.writeMessage(39, commonWriter.finish());

  return writer.finish();
}

/** 编码 FrsPageReqIdl 顶层 */
export function encodeFrsPageReq(params: IFrsPageReqParams): Uint8Array {
  const writer = new ProtoWriter();
  const dataBytes = encodeDataReq(params);
  writer.writeMessage(1, dataBytes);  // data
  return writer.finish();
}

// ==================== FrsPage 响应解码 ====================

/** FrsPage 解析结果 */
export class FrsPageResult {
  forum: ForumInfo = new ForumInfo();
  threads: PageData<ThreadInfo> = new PageData<ThreadInfo>();
  // 完整版吧内页面切片：NavTabInfo（FrsPageResponseData field 37）
  navTabInfo: NavTabInfo = new NavTabInfo();
}

/** 解析 User（field 编号对齐 User.proto），export 供 PersonalizedProto 复用 */
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

/** 解析 Media（field 编号对齐 Media.proto） */
function decodeMedia(reader: ProtoReader): MediaInfo {
  const media = new MediaInfo();
  // URL 优先级：origin_pic > big_pic > src_pic > small_pic
  let smallPic: string = '';
  let bigPic: string = '';
  let srcPic: string = '';
  let originPic: string = '';

  while (!reader.isEnd()) {
    const tag = reader.readTag();
    switch (tag.fieldNumber) {
      case 1:   // type
        media.type = reader.readVarint() === 1 ? MediaType.VIDEO : MediaType.IMAGE;
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

  // 设置 URL：大图优先 origin > big > src > small
  if (originPic.length > 0) {
    media.url = originPic;
  } else if (bigPic.length > 0) {
    media.url = bigPic;
  } else if (srcPic.length > 0) {
    media.url = srcPic;
  } else {
    media.url = smallPic;
  }
  // 缩略图用 small_pic
  media.thumbnail = smallPic;
  return media;
}

/** 解析 VideoInfo（field 编号对齐 VideoInfo.proto，ThreadInfo field 79 / Post field 29）
 * 字段：field 2=video_url, field 3=video_duration, field 4=video_width,
 *       field 5=video_height, field 6=thumbnail_url, field 10=play_count
 */
export function decodeVideoInfo(reader: ProtoReader): VideoInfo {
  const info: VideoInfo = new VideoInfo();
  while (!reader.isEnd()) {
    const tag = reader.readTag();
    switch (tag.fieldNumber) {
      case 2:  // video_url
        info.videoUrl = reader.readString();
        break;
      case 3:  // video_duration
        info.videoDuration = reader.readVarint();
        break;
      case 4:  // video_width
        info.videoWidth = reader.readVarint();
        break;
      case 5:  // video_height
        info.videoHeight = reader.readVarint();
        break;
      case 6:  // thumbnail_url
        info.thumbnailUrl = reader.readString();
        break;
      default:
        reader.skipField(tag.wireType);
        break;
    }
  }
  return info;
}

// ==================== 完整版吧内页面切片：NavTabInfo / FrsTabInfo / SortButton / TabMenu 解码 ====================

/**
 * 解析 SortButton（field 编号对齐 SortButton.proto）
 * 字段：text=1(string) / source_id=2(int32)
 */
function decodeSortButton(reader: ProtoReader): SortButton {
  const button = new SortButton();
  while (!reader.isEnd()) {
    const tag = reader.readTag();
    switch (tag.fieldNumber) {
      case 1:   // text
        button.text = reader.readString();
        break;
      case 2:   // source_id
        button.sourceId = reader.readVarint();
        break;
      default:
        reader.skipField(tag.wireType);
        break;
    }
  }
  return button;
}

/**
 * 解析 TabMenu（field 编号对齐 TabMenu.proto）
 * 字段：class_id=1(int32) / class_name=2(string)
 */
function decodeTabMenu(reader: ProtoReader): TabMenu {
  const menu = new TabMenu();
  while (!reader.isEnd()) {
    const tag = reader.readTag();
    switch (tag.fieldNumber) {
      case 1:   // class_id
        menu.classId = reader.readVarint();
        break;
      case 2:   // class_name
        menu.className = reader.readString();
        break;
      default:
        reader.skipField(tag.wireType);
        break;
    }
  }
  return menu;
}

/**
 * 解析 FrsTabInfo（field 编号对齐 FrsTabInfo.proto）
 * 字段：tab_id=1 / tab_type=2 / tab_name=3 / tab_url=4 / tab_gid=5 /
 *      tab_title=6 / is_general_tab=7 / tab_code=8 / tab_version=9 /
 *      is_default=10 / sort_menu=19(repeated) / sub_tab_list=20(repeated)
 */
export function decodeFrsTabInfo(reader: ProtoReader): FrsTabInfo {
  const tab = new FrsTabInfo();
  while (!reader.isEnd()) {
    const tag = reader.readTag();
    switch (tag.fieldNumber) {
      case 1:   // tab_id
        tab.tabId = reader.readVarint();
        break;
      case 2:   // tab_type
        tab.tabType = reader.readVarint();
        break;
      case 3:   // tab_name
        tab.tabName = reader.readString();
        break;
      case 4:   // tab_url
        tab.tabUrl = reader.readString();
        break;
      case 5:   // tab_gid
        tab.tabGid = reader.readString();
        break;
      case 6:   // tab_title
        tab.tabTitle = reader.readString();
        break;
      case 7:   // is_general_tab
        tab.isGeneralTab = reader.readVarint();
        break;
      case 8:   // tab_code
        tab.tabCode = reader.readString();
        break;
      case 9:   // tab_version
        tab.tabVersion = reader.readVarint();
        break;
      case 10:  // is_default
        tab.isDefault = reader.readVarint();
        break;
      case 19: {  // sort_menu（repeated SortButton）
        const sortReader = reader.readMessage();
        tab.sortMenu.push(decodeSortButton(sortReader));
        break;
      }
      case 20: {  // sub_tab_list（repeated TabMenu）
        const subReader = reader.readMessage();
        tab.subTabList.push(decodeTabMenu(subReader));
        break;
      }
      default:
        // head_pics=12 / need_page=11 / exposure_monitor_url=13 等 暂不使用，跳过
        reader.skipField(tag.wireType);
        break;
    }
  }
  return tab;
}

/**
 * 解析 NavTabInfo（field 编号对齐 FrsPage/NavTabInfo.proto）
 * 字段：tab=1(repeated FrsTabInfo) / menu=2(repeated FrsTabInfo) / head=3(repeated FrsTabInfo)
 */
export function decodeNavTabInfo(reader: ProtoReader): NavTabInfo {
  const navTabInfo = new NavTabInfo();
  while (!reader.isEnd()) {
    const tag = reader.readTag();
    switch (tag.fieldNumber) {
      case 1: {  // tab
        const tabReader = reader.readMessage();
        navTabInfo.tabs.push(decodeFrsTabInfo(tabReader));
        break;
      }
      case 2: {  // menu
        const menuReader = reader.readMessage();
        navTabInfo.menus.push(decodeFrsTabInfo(menuReader));
        break;
      }
      case 3: {  // head
        const headReader = reader.readMessage();
        navTabInfo.heads.push(decodeFrsTabInfo(headReader));
        break;
      }
      default:
        reader.skipField(tag.wireType);
        break;
    }
  }
  return navTabInfo;
}

/** 解析 Thread（field 编号对齐 ThreadInfo.proto），export 供 PersonalizedProto 复用
 *  author 来源：field 18 内嵌 User（personalized 用）或 field 56 authorId + users map 关联（FrsPage 用）
 */
export function decodeThread(reader: ProtoReader, users: Map<number, UserInfo>, forumName: string): ThreadInfo {
  const thread = new ThreadInfo();
  thread.forumName = forumName;
  let authorId: number = 0;

  while (!reader.isEnd()) {
    const tag = reader.readTag();
    switch (tag.fieldNumber) {
      case 1:   // id（部分帖子仅设置 id 而非 threadId，作为 fallback 读取）
        thread.tid = reader.readVarint();
        break;
      case 2:   // threadId（优先级高于 id，存在时覆盖）
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
      case 18: {  // author（内嵌 User，personalized 无 user_list 时用此字段）
        const authorReader = reader.readMessage();
        thread.author = decodeUser(authorReader);
        break;
      }
      case 21: {  // _abstract（repeated，拼接 text 字段作为正文摘要）
        const absReader = reader.readMessage();
        while (!absReader.isEnd()) {
          const absTag = absReader.readTag();
          if (absTag.fieldNumber === 2) {  // text
            thread.content += absReader.readString();
          } else {
            absReader.skipField(absTag.wireType);
          }
        }
        break;
      }
      case 22: {  // media（repeated）
        const mediaReader = reader.readMessage();
        thread.mediaList.push(decodeMedia(mediaReader));
        break;
      }
      case 28:  // forum_name（personalized thread 自带吧名）
        thread.forumName = reader.readString();
        break;
      case 155: { // forum_info（推荐流内嵌吧信息）
        const forumReader = reader.readMessage();
        while (!forumReader.isEnd()) {
          const forumTag = forumReader.readTag();
          if (forumTag.fieldNumber === 1) {
            thread.forumInfo.id = forumReader.readVarint();
          } else if (forumTag.fieldNumber === 2) {
            thread.forumInfo.name = forumReader.readString();
          } else if (forumTag.fieldNumber === 4) {
            thread.forumInfo.avatar = forumReader.readString();
          } else if (forumTag.fieldNumber === 5) {
            thread.forumInfo.isFollowed = forumReader.readVarint() !== 0;
          } else {
            forumReader.skipField(forumTag.wireType);
          }
        }
        if (thread.forumInfo.name.length > 0) {
          thread.forumName = thread.forumInfo.name;
        }
        break;
      }
      case 45:  // create_time
        thread.createTime = reader.readVarint();
        break;
      case 56:  // author_id
        authorId = reader.readVarint();
        break;
      case 126: {  // agree（Agree: agree_num=1, disagree_num=4）
        const agreeReader = reader.readMessage();
        while (!agreeReader.isEnd()) {
          const agreeTag = agreeReader.readTag();
          if (agreeTag.fieldNumber === 1) {        // agree_num
            thread.agreeNum = agreeReader.readVarint();
          } else if (agreeTag.fieldNumber === 4) { // disagree_num
            thread.disagreeNum = agreeReader.readVarint();
          } else {
            agreeReader.skipField(agreeTag.wireType);
          }
        }
        break;
      }
      case 182:  // hot_num（热榜接口专用，ThreadInfo.proto field 182）
        thread.hotNum = reader.readVarint();
        break;
      case 79: {  // video_info（ThreadInfo.proto field 79，视频帖非空，列表层用于识别视频帖）
        const videoReader = reader.readMessage();
        thread.videoInfo = decodeVideoInfo(videoReader);
        break;
      }
      default:
        reader.skipField(tag.wireType);
        break;
    }
  }

  // user_list 关联优先于内嵌 author（FrsPage 的 user_list 更完整）
  if (authorId > 0) {
    const user = users.get(authorId);
    if (user !== undefined) {
      thread.author = user;
    }
  }

  return thread;
}

/** 解析 FrsPageResIdl 顶层 */
export function decodeFrsPageRes(bytes: Uint8Array): FrsPageResult {
  const reader = new ProtoReader(bytes);
  const result = new FrsPageResult();

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
        throw new Error(`获取帖子列表失败 [${errorNo}]: ${errorMsg}`);
      }
    } else if (tag.fieldNumber === 2) {
      // data
      const dataReader = reader.readMessage();
      const users = new Map<number, UserInfo>();
      const rawThreads: ProtoReader[] = [];  // 先收集 thread_list 的 raw bytes
      let forumName: string = '';

      // 第一遍：遍历 data，收集 forum/page/user_list，thread_list 只存 raw bytes
      // （protobuf 字段顺序不固定，thread_list 可能先于 user_list 出现，
      //   所以先存 raw bytes，等 user_list 全部解析后再解码 thread 以关联 author）
      while (!dataReader.isEnd()) {
        const dataTag = dataReader.readTag();
        if (dataTag.fieldNumber === 2) {
          // forum（对齐 FrsPage/ForumInfo.proto）
          const forumReader = dataReader.readMessage();
          while (!forumReader.isEnd()) {
            const forumTag = forumReader.readTag();
            switch (forumTag.fieldNumber) {
              case 1:   // id（int64）
                result.forum.id = forumReader.readVarint();
                break;
              case 2:   // name（string）
                result.forum.name = forumReader.readString();
                forumName = result.forum.name;
                break;
              case 3:   // first_class（string，吧一级分类）
                forumReader.readString();
                break;
              case 4:   // second_class（string，吧二级分类）
                forumReader.readString();
                break;
              case 9:   // member_num（int32 → memberCount）
                result.forum.memberCount = forumReader.readVarint();
                break;
              case 10:  // thread_num（int32 → postCount，对齐现有 ForumInfo 语义）
                result.forum.postCount = forumReader.readVarint();
                break;
              case 11:  // post_num（int32，吧累计发帖数，暂不使用）
                forumReader.readVarint();
                break;
              default:
                // 注意：FrsPage.ForumInfo（对齐 aiotieba FrsPageResIdl.proto）仅包含
                // id/name/first_class/second_class/member_num/thread_num/post_num/managers
                // user_level/level_name 在 get_forum_level 接口，cur_score/levelup_score 在
                // get_user_forum_info 接口（JSON），avatar/slogan 在 get_forum_detail 接口。
                // 完整版吧内页面通过 checkFollowingStatus 从 SelfFollowForum 同步关注列表数据。
                // 旧代码曾把 case 7/8/13/14/24/25 当作 forum 字段解析，但 proto 中不存在这些字段。
                forumReader.skipField(forumTag.wireType);
                break;
            }
          }
        } else if (dataTag.fieldNumber === 4) {
          // page
          const pageReader = dataReader.readMessage();
          while (!pageReader.isEnd()) {
            const pageTag = pageReader.readTag();
            if (pageTag.fieldNumber === 3) {         // current_page
              result.threads.currentPage = pageReader.readVarint();
            } else if (pageTag.fieldNumber === 5) {  // total_page
              result.threads.totalPage = pageReader.readVarint();
            } else if (pageTag.fieldNumber === 6) {  // has_more
              result.threads.hasMore = pageReader.readVarint() !== 0;
            } else {
              pageReader.skipField(pageTag.wireType);
            }
          }
        } else if (dataTag.fieldNumber === 7) {
          // thread_list（repeated）—— 先存 raw bytes，第二遍再解码
          rawThreads.push(dataReader.readMessage());
        } else if (dataTag.fieldNumber === 17) {
          // user_list（repeated）
          const userReader = dataReader.readMessage();
          const user = decodeUser(userReader);
          users.set(user.uid, user);
        } else if (dataTag.fieldNumber === 37) {
          // nav_tab_info（完整版吧内页面切片，FrsPageResponseData field 37）
          const navTabReader = dataReader.readMessage();
          result.navTabInfo = decodeNavTabInfo(navTabReader);
        } else {
          dataReader.skipField(dataTag.wireType);
        }
      }

      // 第二遍：解析 threads（此时 users map 已全部填充，author 关联可靠）
      const threads: ThreadInfo[] = [];
      for (let i = 0; i < rawThreads.length; i++) {
        threads.push(decodeThread(rawThreads[i], users, forumName));
      }

      result.threads.list = threads;
    } else {
      reader.skipField(tag.wireType);
    }
  }

  return result;
}
