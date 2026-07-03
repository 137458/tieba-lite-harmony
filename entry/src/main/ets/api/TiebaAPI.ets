import { TiebaHttpClient, LATEST_VERSION, STABLE_VERSION } from '../net/TiebaHttpClient';
import { ThreadInfo, PostInfo, PageData, ForumInfo, UserInfo, MediaInfo, ExactSearch, SelfFollowForum, UserLikeResult, HotThreadListResult } from '../model/ForumModels';
import {
  UserProfileInfo,
  FollowUserInfo,
  FollowsPageInfo,
  FansPageInfo,
  FollowsResult,
  FansResult
} from '../model/UserProfileModels';
import { encodeFrsPageReq, decodeFrsPageRes, IFrsPageReqParams, FrsPageResult } from '../proto/FrsPageProto';
import { encodePbPageReq, decodePbPageRes, IPbPageReqParams, PbPageResult } from '../proto/PbPageProto';
import { encodePersonalizedReq, decodePersonalizedRes, IPersonalizedReqParams } from '../proto/PersonalizedProto';
import { encodeUserLikeReq, decodeUserLikeRes, IUserLikeReqParams } from '../proto/UserLikeProto';
import { encodeHotThreadListReq, decodeHotThreadListRes, IHotThreadListReqParams } from '../proto/HotThreadListProto';
import { encodeProfileReq, decodeProfileRes, IProfileReqParams } from '../proto/ProfileProto';
import { initZid } from './InitZid';
import { CryptoUtil } from '../utils/CryptoUtil';
import { AppStorageManager } from '../data/AppStorage';
import { getAvatarUrl } from '../utils/AvatarUtil';

/** 通用错误信息结构 */
interface ErrorInfo {
  errno?: string;
  errmsg?: string;
}

/** 收藏数据项结构 */
interface CollectDataItem {
  tid: string;
  pid: string;
  status: number;
}

interface LoginUser {
  id?: number;
  name?: string;
  name_show?: string;
  portrait?: string;
}

interface LoginAnti {
  tbs?: string;
}

interface LoginResponse {
  // error_code 运行时可能为数字或字符串（JSON.parse 不保证类型），声明为联合类型
  error_code?: number | string;
  error_msg?: string;
  user?: LoginUser;
  anti?: LoginAnti;
}

interface AgreeResponse {
  // error_code 运行时可能为数字或字符串（JSON.parse 不保证类型），声明为联合类型
  error_code?: number | string;
  error_msg?: string;
}

/** /c/f/forum/forumGuide 响应（对齐 aiotieba get_self_follow_forums） */
interface FollowForumsResponse {
  // error_code 运行时可能为数字或字符串（JSON.parse 不保证类型），声明为联合类型
  error_code?: number | string;
  error_msg?: string;
  like_forum?: object[];
  like_forum_has_more?: number | string;
}

/** /c/f/post/threadstore 响应（对齐原 app ThreadStoreBean） */
interface ThreadStoreResponse {
  // error_code 运行时可能为数字或字符串（JSON.parse 不保证类型），声明为联合类型
  error_code?: number | string;
  error_msg?: string;
  error?: ErrorInfo;
  store_thread?: ThreadStoreItem[];
}

/** threadstore 中的帖子项 */
interface ThreadStoreItem {
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
interface ThreadStoreAuthor {
  lz_uid?: string;
  name?: string;
  name_show?: string;
  user_portrait?: string;
}

/** threadstore 媒体信息 */
interface ThreadStoreMedia {
  type?: string;
  small_Pic?: string;
  big_pic?: string;
  width?: number;
  height?: number;
}

/** 通用响应（对齐原 app CommonResponse，addstore/rmstore 用） */
interface CommonResponse {
  error_code?: number | string;
  error_msg?: string;
  error?: ErrorInfo;
}

/** /c/s/sync 响应 client 子对象 */
interface SyncClient {
  client_id?: string;
}

/** /c/s/sync 响应 wl_config 子对象 */
interface SyncWlConfig {
  sample_id?: string;
}

/** /c/s/sync 响应顶层 */
interface SyncResponse {
  // error_code 运行时可能为数字或字符串（JSON.parse 不保证类型），声明为联合类型
  error_code?: number | string;
  error_msg?: string;
  client?: SyncClient;
  wl_config?: SyncWlConfig;
}

/** sync 接口返回值 */
class SyncResult {
  clientId: string = '';
  sampleId: string = '';
}

/** /c/s/initNickname 响应 user_info 子对象 */
interface InitNicknameUserInfo {
  user_name?: string;
  name_show?: string;
  tieba_uid?: string | number;
}

/** /c/s/initNickname 响应顶层 */
interface InitNicknameResponse {
  // error_code 运行时可能为数字或字符串（JSON.parse 不保证类型），声明为联合类型
  error_code?: number | string;
  error_msg?: string;
  user_info?: InitNicknameUserInfo;
}

/** initNickname 接口返回值 */
class InitNicknameResult {
  userName: string = '';
  nameShow: string = '';
  tiebaUid: number = 0;
}

/** /c/c/user/follow 与 /c/c/user/unfollow 响应 */
interface FollowOpResponse {
  // error_code 运行时可能为数字或字符串（JSON.parse 不保证类型），声明为联合类型
  error_code?: number | string;
  error_msg?: string;
}

/** /c/u/follow/followList 响应顶层 */
interface FollowsResponse {
  // error_code 运行时可能为数字或字符串（JSON.parse 不保证类型），声明为联合类型
  error_code?: number | string;
  error_msg?: string;
  follow_list?: object[];
  pn?: string | number;
  total_follow_num?: string | number;
  has_more?: string | number;
}

/** /c/u/fans/page 响应顶层 */
interface FansResponse {
  // error_code 运行时可能为数字或字符串（JSON.parse 不保证类型），声明为联合类型
  error_code?: number | string;
  error_msg?: string;
  user_list?: object[];
  page?: object;
}

/** /c/u/fans/page 的 page 子对象 */
class FansPage {
  page_size?: string | number;
  current_page?: string | number;
  total_page?: string | number;
  total_count?: string | number;
  has_more?: string | number;
  has_prev?: string | number;
}

interface UserInfoInit {
  uid: number;
  name: string;
  nickname?: string;
  avatar: string;
}

interface ThreadInfoInit {
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

/** /c/s/searchpost 响应 author 子对象 */
interface SearchPostAuthor {
  name_show?: string;
}

/** /c/s/searchpost 响应 post_list 数组项 */
interface SearchPostItem {
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
interface SearchPostPage {
  current_page?: string | number;
  total_page?: string | number;
  has_more?: string | number;
}

/** /c/s/searchpost 响应顶层 */
interface SearchPostResponse {
  // error_code 运行时可能为数字或字符串（JSON.parse 不保证类型），声明为联合类型
  error_code?: number | string;
  error_msg?: string;
  post_list?: SearchPostItem[];
  page?: SearchPostPage;
}

export class TiebaAPI {
  private static client: TiebaHttpClient = TiebaHttpClient.getInstance();
  private static tbs: string = '';

  static setAuth(bduss: string, stoken: string = ''): void {
    TiebaAPI.client.setAuth(bduss, stoken);
  }

  static setCuid(cuid: string): void {
    TiebaAPI.client.setCuid(cuid);
  }

  static getTbs(): string {
    return TiebaAPI.tbs;
  }

  /**
   * 完整 4 步登录流程
   * 对齐 aiotieba 客户端登录初始化序列：
   *   1. init_z_id → 设备指纹注册（sofire.baidu.com，失败不阻塞）
   *   2. login → 用户认证 + tbs
   *   3. sync → client_id + sample_id（失败不阻塞）
   *   4. get_selfinfo_initNickname → tieba_uid + name_show（失败不阻塞）
   *
   * 仅 step 2 失败会抛出错误，其他步骤失败仅记录警告。
   * 持久化字段：cuid、z_id、client_id、sample_id、tieba_uid
   *
   * @param bduss BDUSS cookie 值
   * @param stoken STOKEN cookie 值（可选）
   * @returns 用户信息（uid + name + nickname + avatar）
   */
  static async login(bduss: string, stoken: string = ''): Promise<UserInfo> {
    // ===== Step 0: 准备设备参数 =====
    TiebaAPI.setAuth(bduss, stoken);

    const androidId: string = await CryptoUtil.getOrCreateAndroidId();
    const uuid: string = await CryptoUtil.getOrCreateUuid();
    const aesCbcSecKey: Uint8Array = await CryptoUtil.getOrCreateAesCbcSecKey();
    const deviceId: string = await CryptoUtil.getOrCreateDeviceId();
    const cuid: string = await CryptoUtil.generateCuid(deviceId);
    TiebaAPI.setCuid(cuid);
    await AppStorageManager.getInstance().setString('cuid', cuid);

    // ===== Step 1: init_z_id =====
    // 失败不阻塞登录（设备指纹仅用于部分场景）
    try {
      const zId: string = await initZid(androidId, uuid, aesCbcSecKey);
      await AppStorageManager.getInstance().setString('z_id', zId);
    } catch (err) {
      console.warn(`[TiebaAPI.login] init_z_id failed: ${(err as Error).message}`);
    }

    // ===== Step 2: login（核心步骤，失败抛出） =====
    const userInfo: UserInfo = await TiebaAPI.doLogin(bduss);

    // ===== Step 3: sync =====
    // 失败不阻塞（client_id/sample_id 用于统计，缺失不影响浏览）
    try {
      const syncResult: SyncResult = await TiebaAPI.sync(bduss, cuid);
      await AppStorageManager.getInstance().setString('client_id', syncResult.clientId);
      await AppStorageManager.getInstance().setString('sample_id', syncResult.sampleId);
    } catch (err) {
      console.warn(`[TiebaAPI.login] sync failed: ${(err as Error).message}`);
    }

    // ===== Step 4: get_selfinfo_initNickname =====
    // 失败不阻塞（tieba_uid 用于部分个人主页接口）
    try {
      const initResult: InitNicknameResult = await TiebaAPI.initNickname(bduss);
      await AppStorageManager.getInstance().setString('tieba_uid', initResult.tiebaUid.toString());
    } catch (err) {
      console.warn(`[TiebaAPI.login] initNickname failed: ${(err as Error).message}`);
    }

    return userInfo;
  }

  /**
   * 实际执行 POST /c/s/login 的内部方法
   * 由 login() 在完成 init_z_id 后调用
   */
  private static async doLogin(bduss: string): Promise<UserInfo> {
    // 对齐 aiotieba login/_api.py：参数仅 _client_version + bdusstoken
    // sign 由 TiebaHttpClient.post 自动追加
    const params: Record<string, string | number> = {
      '_client_version': LATEST_VERSION,
      'bdusstoken': bduss
    };

    try {
      const response = await TiebaAPI.client.post('/c/s/login', params, LATEST_VERSION);

      if (typeof response.data === 'string') {
        const data: LoginResponse = JSON.parse(response.data) as LoginResponse;

        // 检查错误码（兼容 number 0 和 string '0' 两种正常返回）
        if (data.error_code !== undefined && data.error_code !== 0 && data.error_code !== '0') {
          throw new Error(`Login failed [${data.error_code}]: ${data.error_msg || 'unknown error'}`);
        }

        // 检查是否有用户数据（用 undefined 检查，避免 uid=0 误判）
        if (!data.user || data.user.id === undefined || data.user.id === null) {
          throw new Error('Login failed: invalid user data in response');
        }

        // 保存 tbs
        if (data.anti && data.anti.tbs) {
          TiebaAPI.tbs = data.anti.tbs;
        }

        const userInfoInit: UserInfoInit = {
          uid: Number(data.user.id || 0),
          name: data.user.name || '',
          nickname: data.user.name_show || '',
          avatar: data.user.portrait || ''
        };
        return new UserInfo(userInfoInit);
      }

      throw new Error('Invalid login response: not a string');
    } catch (err) {
      const error = err as Error;
      // HttpClient 抛出 "HTTP request failed: xxx"，匹配该前缀提供更友好的错误信息
      // err 可能是非 Error 对象（如字符串、BusinessError），.message 为 undefined 时兜底为空串
      const msg: string = error.message || '';
      if (msg.includes('HTTP request failed') || msg.includes('http') || msg.includes('network')) {
        throw new Error('网络请求失败，请检查网络连接');
      }
      throw error;
    }
  }

  /**
   * sync 接口：拿 client_id + sample_id
   * 对齐 aiotieba api/sync/_api.py
   * 端点：POST /c/s/sync
   * 参数：BDUSS + _client_version + cuid
   */
  private static async sync(bduss: string, cuid: string): Promise<SyncResult> {
    const params: Record<string, string | number> = {
      'BDUSS': bduss,
      '_client_version': LATEST_VERSION,
      'cuid': cuid
    };

    const response = await TiebaAPI.client.post('/c/s/sync', params, LATEST_VERSION);

    if (typeof response.data !== 'string') {
      throw new Error('sync 响应不是字符串');
    }

    let resJson: SyncResponse;
    try {
      resJson = JSON.parse(response.data) as SyncResponse;
    } catch (err) {
      throw new Error('sync 响应 JSON 解析失败: ' + (err as Error).message);
    }

    if (resJson.error_code !== undefined && resJson.error_code !== 0 && resJson.error_code !== '0') {
      throw new Error(`sync 失败 [${resJson.error_code}]: ${resJson.error_msg || ''}`);
    }

    if (!resJson.client || !resJson.client.client_id) {
      throw new Error('sync 响应缺少 client.client_id');
    }

    const result: SyncResult = new SyncResult();
    result.clientId = resJson.client.client_id;
    result.sampleId = (resJson.wl_config && resJson.wl_config.sample_id) ? resJson.wl_config.sample_id : '';
    return result;
  }

  /**
   * get_selfinfo_initNickname 接口：拿 tieba_uid + name_show
   * 对齐 aiotieba api/get_selfinfo_initNickname/_api.py
   * 端点：POST /c/s/initNickname
   * 参数：BDUSS + _client_version
   */
  private static async initNickname(bduss: string): Promise<InitNicknameResult> {
    const params: Record<string, string | number> = {
      'BDUSS': bduss,
      '_client_version': LATEST_VERSION
    };

    const response = await TiebaAPI.client.post('/c/s/initNickname', params, LATEST_VERSION);

    if (typeof response.data !== 'string') {
      throw new Error('initNickname 响应不是字符串');
    }

    let resJson: InitNicknameResponse;
    try {
      resJson = JSON.parse(response.data) as InitNicknameResponse;
    } catch (err) {
      throw new Error('initNickname 响应 JSON 解析失败: ' + (err as Error).message);
    }

    if (resJson.error_code !== undefined && resJson.error_code !== 0 && resJson.error_code !== '0') {
      throw new Error(`initNickname 失败 [${resJson.error_code}]: ${resJson.error_msg || ''}`);
    }

    if (!resJson.user_info || !resJson.user_info.tieba_uid) {
      throw new Error('initNickname 响应缺少 user_info.tieba_uid');
    }

    const result: InitNicknameResult = new InitNicknameResult();
    result.userName = resJson.user_info.user_name || '';
    result.nameShow = resJson.user_info.name_show || '';
    result.tiebaUid = Number(resJson.user_info.tieba_uid);
    return result;
  }

  /**
   * 获取贴吧首页帖子列表
   * 对齐 aiotieba get_threads.request_http：
   *   - 端点 POST /c/f/frs/page?cmd=301001
   *   - 协议：multipart/form-data + protobuf body（FrsPageReqIdl）
   *   - 版本：STABLE_VERSION（12.64.1.1）
   *   - CommonReq 仅含 _client_type + _client_version（公开读 API 不传 BDUSS）
   *
   * @param forumName 贴吧名（kw）
   * @param page 页码（pn），从 1 开始；aiotieba 中 pn=1 时实际传 0，由 encodeFrsPageReq 处理
   * @param sortType 排序方式（对齐 aiotieba ThreadSortType）：
   *   1=CREATE 按发布时间 / 2=FOLLOW 关注的人 / 3=HOT 热门 / 6=REPLY 按回复时间
   * @param isGood true 获取精品区，false 获取普通区
   */
  static async getThreads(
    forumName: string,
    page: number = 1,
    sortType: number = 1,
    isGood: boolean = false
  ): Promise<PageData<ThreadInfo>> {
    // 构造 protobuf 请求参数（对齐 aiotieba get_threads.pack_proto）
    const reqParams: IFrsPageReqParams = {
      kw: forumName,
      pn: page,
      rn: 30,
      isGood: isGood,
      sortType: sortType,
      clientVersion: STABLE_VERSION
    };

    try {
      // 编码 protobuf 请求
      const protobufBytes: Uint8Array = encodeFrsPageReq(reqParams);
      // POST 到 /c/f/frs/page?cmd=301001
      const responseBytes: Uint8Array = await TiebaAPI.client.postProtobuf('/c/f/frs/page', protobufBytes, 301001);

      // 解析 protobuf 响应
      const result: FrsPageResult = decodeFrsPageRes(responseBytes);
      return result.threads;
    } catch (err) {
      // err 可能非 Error 对象（如 BusinessError），.message 为 undefined 时兜底为空串（issue #32）
      const msg: string = (err as Error).message || '';
      // decodeFrsPageRes 抛出的错误已含"获取帖子列表失败"前缀，避免重复包装
      if (msg.startsWith('获取帖子列表失败')) {
        throw new Error(msg);
      }
      throw new Error('获取帖子列表失败: ' + msg);
    }
  }

  /**
   * 获取个性推荐帖子列表（主页用，issue #45）
   * 对齐 TiebaLite-4.0-dev PersonalizedRepository.personalizedFlow：
   *   - 端点 POST /c/f/excellent/personalized?cmd=309264
   *   - 协议：multipart/form-data + protobuf body（PersonalizedRequest）
   *   - 版本：STABLE_VERSION（12.64.1.1）
   *   - load_type：page=1 时传 1（刷新），page>1 时传 2（加载更多）
   *   - page_thread_count：原版默认 11
   *   - 响应 thread_list 复用 FrsPageProto.decodeThread 解码（author 从 field 18 内嵌获取）
   *
   * @param page 页码（pn），从 1 开始
   * @param rn 每页帖子数，默认 11（对齐原版 page_thread_count）
   * @returns PageData<ThreadInfo>，hasMore 根据返回数量判断（< rn 视为末页）
   */
  static async getPersonalized(page: number = 1, rn: number = 11): Promise<PageData<ThreadInfo>> {
    const loadType: number = page === 1 ? 1 : 2;  // 1=刷新 2=加载更多
    const reqParams: IPersonalizedReqParams = {
      loadType: loadType,
      pn: page,
      pageThreadCount: rn
    };

    try {
      const protobufBytes: Uint8Array = encodePersonalizedReq(reqParams);
      const responseBytes: Uint8Array = await TiebaAPI.client.postProtobuf(
        '/c/f/excellent/personalized', protobufBytes, 309264
      );
      const result = decodePersonalizedRes(responseBytes);

      const pageData: PageData<ThreadInfo> = new PageData<ThreadInfo>();
      pageData.list = result.threads;
      pageData.currentPage = page;
      // personalized 响应无 page 字段，用返回数量判断 hasMore
      pageData.hasMore = result.threads.length >= rn;
      return pageData;
    } catch (err) {
      // err 可能非 Error 对象（如 BusinessError），.message 为 undefined 时兜底为空串（issue #32）
      const msg: string = (err as Error).message || '';
      if (msg.startsWith('获取个性推荐失败')) {
        throw new Error(msg);
      }
      throw new Error('获取个性推荐失败: ' + msg);
    }
  }

  /**
   * 获取关注吧动态流（userLikeFlow）
   * 对齐原 app OfficialProtobufTiebaApi.userLikeFlow + ConcernViewModel
   *   - 端点 POST /c/f/concern/userlike?cmd=309474（multipart protobuf）
   *   - 版本：STABLE_VERSION（12.64.1.1）
   *   - loadType: 1=下拉刷新（pageTag=""） 2=加载更多（pageTag=上次响应的游标）
   *   - lastRequestUnix: 持久化在 AppStorage，刷新后用响应的 requestUnix 更新
   *   - threadInfo 解码复用 FrsPageProto.decodeThread（author 从 field 18 内嵌获取）
   *   - 仅 recommendType==1 的 ConcernData 渲染（对齐原 app ConcernPage.kt:97）
   *
   * @param pageTag 页面游标（刷新传空字符串，加载更多传上次响应的 pageTag）
   * @param loadType 加载类型：1=刷新 2=加载更多
   * @returns UserLikeResult（threadList + pageTag + hasMore + requestUnix）
   */
  static async getUserLikeFlow(pageTag: string, loadType: number): Promise<UserLikeResult> {
    // 对齐原 app ConcernViewModel.kt:61：持久化 lastRequestUnix，刷新后用响应的 requestUnix 更新
    const storage: AppStorageManager = AppStorageManager.getInstance();
    await storage.ensureReady();
    const lastRequestUnix: number = await storage.getNumber('userLikeLastRequestUnix', 0);

    const reqParams: IUserLikeReqParams = {
      pageTag: pageTag,
      lastRequestUnix: lastRequestUnix,
      loadType: loadType
    };

    try {
      const protobufBytes: Uint8Array = encodeUserLikeReq(reqParams);
      const responseBytes: Uint8Array = await TiebaAPI.client.postProtobuf(
        '/c/f/concern/userlike', protobufBytes, 309474
      );
      const result: UserLikeResult = decodeUserLikeRes(responseBytes);

      // 刷新成功后持久化 requestUnix（对齐原 app，下次刷新只返回新动态）
      if (loadType === 1 && result.requestUnix > 0) {
        await storage.setNumber('userLikeLastRequestUnix', result.requestUnix);
      }
      return result;
    } catch (err) {
      const msg: string = (err as Error).message || '';
      if (msg.startsWith('获取动态失败')) {
        throw new Error(msg);
      }
      throw new Error('获取动态失败: ' + msg);
    }
  }

  /**
   * 获取热榜帖子列表（Phase B Issue #67）
   * 对齐原 app OfficialProtobufTiebaApi.hotThreadListFlow + HotViewModel：
   *   - 端点 POST /c/f/forum/hotThreadList?cmd=309661
   *   - 协议：multipart/form-data + protobuf body（HotThreadListReqIdl）
   *   - 版本：STABLE_VERSION（12.64.1.1）
   *   - 请求参数：common（公共头）+ tab_id（固定 "1"）+ tab_code（默认 "all"）
   *   - 响应：topic_list（话题榜）+ thread_info（帖子列表）+ hot_thread_tab_info（子 Tab）
   *   - 无分页：一次拉全量，切换子 Tab 仅传不同 tab_code 重新拉取
   *
   * @param tabCode Tab 编码，默认 "all"（全部）；切换子 Tab 时传该 Tab 的 tab_code
   * @returns HotThreadListResult（topicList + threadList + tabList）
   */
  static async getHotThreadList(tabCode: string = 'all'): Promise<HotThreadListResult> {
    const reqParams: IHotThreadListReqParams = {
      tabCode: tabCode
    };

    try {
      const protobufBytes: Uint8Array = encodeHotThreadListReq(reqParams);
      const responseBytes: Uint8Array = await TiebaAPI.client.postProtobuf(
        '/c/f/forum/hotThreadList', protobufBytes, 309661
      );
      return decodeHotThreadListRes(responseBytes);
    } catch (err) {
      // err 可能非 Error 对象，.message 为 undefined 时兜底为空串
      const msg: string = (err as Error).message || '';
      if (msg.startsWith('获取热榜失败')) {
        throw new Error(msg);
      }
      throw new Error('获取热榜失败: ' + msg);
    }
  }

  /**
   * 获取帖子详情/回复列表
   * 对齐 aiotieba get_posts.request_http：
   *   - 端点 POST /c/f/pb/page?cmd=302001
   *   - 协议：multipart/form-data + protobuf body（PbPageReqIdl）
   *   - 版本：STABLE_VERSION（12.64.1.1）
   *   - CommonReq 仅含 _client_type + _client_version（公开读 API 不传 BDUSS）
   *
   * 返回 PbPageResult（含 posts 分页数据 + thread 主题帖信息如标题），
   * 调用方（ThreadViewModel）负责提取 posts 和 threadTitle
   *
   * @param threadId 主题帖 id（kz）
   * @param page 页码（pn），从 1 开始
   * @param onlyAuthor true 只看楼主（lz=1）
   */
  static async getPosts(
    threadId: number,
    page: number = 1,
    onlyAuthor: boolean = false
  ): Promise<PbPageResult> {
    // 构造 protobuf 请求参数（对齐 aiotieba get_posts.pack_proto）
    const reqParams: IPbPageReqParams = {
      tid: threadId,
      pn: page,
      rn: 30,
      sort: 0,
      onlyAuthor: onlyAuthor,
      clientVersion: STABLE_VERSION
    };

    try {
      // 编码 protobuf 请求
      const protobufBytes: Uint8Array = encodePbPageReq(reqParams);

      // POST 到 /c/f/pb/page?cmd=302001
      const responseBytes: Uint8Array = await TiebaAPI.client.postProtobuf('/c/f/pb/page', protobufBytes, 302001);

      // 解析 protobuf 响应（含 posts + thread，调用方按需取用）
      return decodePbPageRes(responseBytes);
    } catch (err) {
      // err 可能非 Error 对象（如 BusinessError），.message 为 undefined 时兜底为空串（issue #32）
      const msg: string = (err as Error).message || '';
      // decodePbPageRes 抛出的错误已含"获取回复列表失败"前缀，避免重复包装
      if (msg.startsWith('获取回复列表失败')) {
        throw new Error(msg);
      }
      throw new Error('获取回复列表失败: ' + msg);
    }
  }

  /**
   * 吧内精确搜索（search_exact）
   * 对齐 aiotieba api/search_exact/_api.py：
   *   - 端点 POST /c/s/searchpost（旧实现 GET /c/f/search/page 已弃用）
   *   - 7 个参数：_client_version、kw、only_thread、pn、rn、sm、word
   *   - 版本：LATEST_VERSION（22.5.1.0，写 API）
   *   - sign 由 TiebaHttpClient.post 自动追加
   *
   * @param options 搜索参数对象（ISearchExactParams）
   */
  static async searchExact(options: ISearchExactParams): Promise<PageData<ExactSearch>> {
    const fname: string = options.fname;
    const keyword: string = options.keyword;
    const page: number = options.page;
    const pageSize: number = options.pageSize;
    const searchType: SearchType = options.searchType;
    const onlyThread: boolean = options.onlyThread;
    const params: Record<string, string | number> = {
      '_client_version': LATEST_VERSION,
      'kw': fname,
      'only_thread': onlyThread ? 1 : 0,
      'pn': page,
      'rn': pageSize,
      'sm': searchType,
      'word': keyword
    };

    const response = await TiebaAPI.client.post('/c/s/searchpost', params, LATEST_VERSION);

    if (typeof response.data !== 'string') {
      throw new Error('Invalid search response: not a string');
    }

    let resJson: SearchPostResponse;
    try {
      resJson = JSON.parse(response.data) as SearchPostResponse;
    } catch (err) {
      throw new Error('解析搜索结果失败: ' + (err as Error).message);
    }

    if (resJson.error_code !== undefined && resJson.error_code !== 0 && resJson.error_code !== '0') {
      throw new Error(`搜索失败 [${resJson.error_code}]: ${resJson.error_msg || ''}`);
    }

    const rawList: SearchPostItem[] = resJson.post_list || [];
    const list: ExactSearch[] = rawList.map((raw: SearchPostItem) => {
      const item: ExactSearch = new ExactSearch();
      item.text = raw.content || '';
      item.title = raw.title || '';
      item.fname = raw.fname || '';
      item.tid = Number(raw.tid || 0);
      item.pid = Number(raw.pid || 0);
      item.showName = (raw.author && raw.author.name_show) ? raw.author.name_show : '';
      item.isComment = Number(raw.is_floor || 0) === 1;
      item.createTime = Number(raw.time || 0);
      return item;
    });

    const pageData: PageData<ExactSearch> = new PageData<ExactSearch>();
    pageData.list = list;
    if (resJson.page) {
      // 用 undefined 检查替代 || 1，避免 current_page=0（合法值，第一页）被误替换
      pageData.currentPage = resJson.page.current_page !== undefined
        ? Number(resJson.page.current_page) : 1;
      pageData.totalPage = resJson.page.total_page !== undefined
        ? Number(resJson.page.total_page) : 1;
      pageData.hasMore = Number(resJson.page.has_more || 0) === 1;
    } else {
      pageData.hasMore = false;
    }
    return pageData;
  }

  /**
   * 获取用户主页资料
   * 对应 aiotieba get_uinfo_profile，端点 POST /c/u/user/profile?cmd=303012（protobuf）
   * 替代旧的 /home/get/panel HTML 端点（issue #64 切片2）
   *
   * @param portrait 用户头像标识（如 "tb.0.xxx"），uid <= 0 时使用
   * @param userName 保留签名兼容性，protobuf 路径下不再使用
   * @param uid 用户 uid，>0 时优先用 uid 查询
   */
  static async getUserProfile(
    portrait: string,
    userName: string = '',
    uid: number = 0
  ): Promise<UserProfileInfo> {
    // uid > 0 时用 uid 查询，否则用 portrait 查询（对齐 aiotieba pack_proto）
    if (uid <= 0 && portrait.length === 0) {
      throw new Error('portrait 和 uid 不能同时为空');
    }

    const params: IProfileReqParams = {
      uid: uid,
      portrait: portrait
    };
    const bytes: Uint8Array = encodeProfileReq(params);
    const resBytes: Uint8Array = await TiebaAPI.client.postProtobuf('/c/u/user/profile', bytes, 303012);
    return decodeProfileRes(resBytes);
  }

  /**
   * 获取用户关注列表
   * 对应 aiotieba get_follows.request(http_core, user_id, pn)
   * 端点：POST /c/u/follow/followList
   * 参数：BDUSS（由 HttpClient 注入 Cookie）、pn、uid
   */
  static async getFollows(userId: number, page: number = 1): Promise<FollowsResult> {
    const params: Record<string, string | number> = {
      'BDUSS': TiebaAPI.getBduss(),
      '_client_version': '12.64.1.1',
      'pn': page,
      'uid': userId
    };

    const response = await TiebaAPI.client.post('/c/u/follow/followList', params, LATEST_VERSION);

    if (typeof response.data !== 'string') {
      throw new Error('Invalid follows response: not a string');
    }

    let resJson: FollowsResponse;
    try {
      resJson = JSON.parse(response.data) as FollowsResponse;
    } catch (err) {
      throw new Error('解析关注列表失败: ' + (err as Error).message);
    }

    if (resJson.error_code !== undefined && resJson.error_code !== 0 && resJson.error_code !== '0') {
      throw new Error(`获取关注列表失败 [${resJson.error_code}]: ${resJson.error_msg || ''}`);
    }

    const followList = resJson.follow_list || [];
    const list: FollowUserInfo[] = followList.map((rawItem: object) => {
      const followUser: FollowUserInfo = new FollowUserInfo();
      followUser.userId = TiebaAPI.safeGetNumber(rawItem, 'id');
      followUser.portrait = TiebaAPI.safeGetString(rawItem, 'portrait');
      followUser.userName = TiebaAPI.safeGetString(rawItem, 'name');
      followUser.nickName = TiebaAPI.safeGetString(rawItem, 'name_show');
      return followUser;
    });

    const followsPage: FollowsPageInfo = new FollowsPageInfo();
    followsPage.currentPage = TiebaAPI.safeGetNumber(resJson, 'pn');
    followsPage.totalCount = TiebaAPI.safeGetNumber(resJson, 'total_follow_num');
    followsPage.hasMore = TiebaAPI.safeGetNumber(resJson, 'has_more') === 1;

    const followsResult: FollowsResult = new FollowsResult();
    followsResult.list = list;
    followsResult.pageInfo = followsPage;
    return followsResult;
  }

  /**
   * 获取用户粉丝列表
   * 对应 aiotieba get_fans.request(http_core, user_id, pn)
   * 端点：POST /c/u/fans/page
   * 参数：BDUSS、pn、uid
   * 注意：分页信息在 page 子对象内，与 getFollows 顶层分页不同
   */
  static async getFans(userId: number, page: number = 1): Promise<FansResult> {
    const params: Record<string, string | number> = {
      'BDUSS': TiebaAPI.getBduss(),
      '_client_version': '12.64.1.1',
      'pn': page,
      'uid': userId
    };

    const response = await TiebaAPI.client.post('/c/u/fans/page', params, LATEST_VERSION);

    if (typeof response.data !== 'string') {
      throw new Error('Invalid fans response: not a string');
    }

    let resJson: FansResponse;
    try {
      resJson = JSON.parse(response.data) as FansResponse;
    } catch (err) {
      throw new Error('解析粉丝列表失败: ' + (err as Error).message);
    }

    if (resJson.error_code !== undefined && resJson.error_code !== 0 && resJson.error_code !== '0') {
      throw new Error(`获取粉丝列表失败 [${resJson.error_code}]: ${resJson.error_msg || ''}`);
    }

    const userList = resJson.user_list || [];
    const list: FollowUserInfo[] = userList.map((rawItem: object) => {
      const fanUser: FollowUserInfo = new FollowUserInfo();
      fanUser.userId = TiebaAPI.safeGetNumber(rawItem, 'id');
      fanUser.portrait = TiebaAPI.safeGetString(rawItem, 'portrait');
      fanUser.userName = TiebaAPI.safeGetString(rawItem, 'name');
      fanUser.nickName = TiebaAPI.safeGetString(rawItem, 'name_show');
      return fanUser;
    });

    const pageObj: FansPage = resJson.page ? (resJson.page as FansPage) : new FansPage();
    const fansPage: FansPageInfo = new FansPageInfo();
    fansPage.pageSize = TiebaAPI.safeGetNumber(pageObj, 'page_size');
    fansPage.currentPage = TiebaAPI.safeGetNumber(pageObj, 'current_page');
    fansPage.totalPage = TiebaAPI.safeGetNumber(pageObj, 'total_page');
    fansPage.totalCount = TiebaAPI.safeGetNumber(pageObj, 'total_count');
    fansPage.hasMore = TiebaAPI.safeGetNumber(pageObj, 'has_more') === 1;

    const fansResult: FansResult = new FansResult();
    fansResult.list = list;
    fansResult.pageInfo = fansPage;
    return fansResult;
  }

  /**
   * 关注用户
   * 对应 aiotieba follow_user.request(http_core, portrait)
   * 端点：POST /c/c/user/follow
   * 参数：BDUSS、portrait、tbs
   * 注意：参数是 portrait，不是 user_id
   */
  static async followUser(portrait: string): Promise<void> {
    await TiebaAPI.followOpRequest('/c/c/user/follow', portrait);
  }

  /**
   * 取消关注用户
   * 对应 aiotieba unfollow_user.request(http_core, portrait)
   * 端点：POST /c/c/user/unfollow
   * 参数：BDUSS、portrait、tbs
   */
  static async unfollowUser(portrait: string): Promise<void> {
    await TiebaAPI.followOpRequest('/c/c/user/unfollow', portrait);
  }

  /**
   * 点赞（agree_type=2, op_type=0）
   * 对齐 aiotieba api/agree/_api.py：POST /c/c/agree/opAgree
   *
   * @param tid 主题帖 id
   * @param pid 回复 id；为 0 表示对主题帖点赞（obj_type=3）
   * @param isComment true 表示楼中楼（obj_type=2），false 表示普通回复（obj_type=1）
   */
  static async agree(tid: number, pid: number = 0, isComment: boolean = false): Promise<void> {
    await TiebaAPI.doAgree(tid, pid, isComment, false, false);
  }

  /**
   * 撤销点赞（agree_type=2, op_type=1）
   */
  static async unagree(tid: number, pid: number = 0, isComment: boolean = false): Promise<void> {
    await TiebaAPI.doAgree(tid, pid, isComment, false, true);
  }

  /**
   * 点踩（agree_type=5, op_type=0）
   */
  static async disagree(tid: number, pid: number = 0, isComment: boolean = false): Promise<void> {
    await TiebaAPI.doAgree(tid, pid, isComment, true, false);
  }

  /**
   * 撤销点踩（agree_type=5, op_type=1）
   */
  static async undisagree(tid: number, pid: number = 0, isComment: boolean = false): Promise<void> {
    await TiebaAPI.doAgree(tid, pid, isComment, true, true);
  }

  /**
   * agree 操作统一内部实现
   * 对齐 aiotieba api/agree/_api.py：
   *   - 端点 POST /c/c/agree/opAgree
   *   - 9 个参数：BDUSS、_client_version、agree_type、cuid、obj_type、op_type、post_id、tbs、thread_id
   *   - obj_type：pid>0 时 1=回复 / 2=楼中楼；pid=0 时 3=主题帖
   *   - agree_type：2=点赞 / 5=点踩
   *   - op_type：0=执行 / 1=撤销
   *   - sign 由 TiebaHttpClient.post 自动追加
   */
  private static async doAgree(
    tid: number, pid: number, isComment: boolean, isDisagree: boolean, isUndo: boolean
  ): Promise<void> {
    // 计算 obj_type
    let objType: number;
    if (pid > 0) {
      objType = isComment ? 2 : 1;
    } else {
      objType = 3;
    }

    const tbs: string = TiebaAPI.getTbs();
    if (tbs.length === 0) {
      throw new Error('tbs 未初始化，请先登录');
    }

    const bduss: string = TiebaAPI.getBduss();
    if (bduss.length === 0) {
      throw new Error('BDUSS 未设置，请先登录');
    }

    const cuid: string = TiebaAPI.client.getCuid();
    if (cuid.length === 0) {
      throw new Error('cuid 未设置，请先登录');
    }

    // 对齐 Android 原版 MiniTiebaApi.agree/disagree：opAgree 必传 stoken
    // 缺少 stoken 时服务器拒绝取消点赞（返回"你已经点过赞了"）
    const stoken: string = TiebaAPI.client.getStoken();

    const params: Record<string, string | number> = {
      'BDUSS': bduss,
      '_client_version': LATEST_VERSION,
      'agree_type': isDisagree ? 5 : 2,
      'cuid': cuid,
      'obj_type': objType,
      'op_type': isUndo ? 1 : 0,
      'post_id': pid,
      'stoken': stoken,
      'tbs': tbs,
      'thread_id': tid
    };

    const response = await TiebaAPI.client.post('/c/c/agree/opAgree', params, LATEST_VERSION);

    if (typeof response.data !== 'string') {
      throw new Error('Invalid agree response: not a string');
    }

    let resJson: AgreeResponse;
    try {
      resJson = JSON.parse(response.data) as AgreeResponse;
    } catch (err) {
      throw new Error('解析点赞响应失败: ' + (err as Error).message);
    }

    if (resJson.error_code !== undefined && resJson.error_code !== 0 && resJson.error_code !== '0') {
      // 补充 error_msg，对齐 sync/initNickname/searchExact 的错误处理
      throw new Error(`点赞操作失败 [${resJson.error_code}]: ${resJson.error_msg || ''}`);
    }
  }

  /**
   * 关注/取消关注共用请求逻辑
   * 对应 aiotieba follow_user / unfollow_user 的 request 实现
   * 端点：POST /c/c/user/{follow|unfollow}
   * 参数：BDUSS、portrait、tbs
   * 响应：error_code 为 '0' 表示成功，否则抛出带错误码的异常
   */
  private static async followOpRequest(url: string, portrait: string): Promise<void> {
    if (portrait.length === 0) {
      throw new Error('portrait 不能为空');
    }

    const tbs = TiebaAPI.getTbs();
    if (tbs.length === 0) {
      throw new Error('tbs 未初始化，请先登录');
    }

    const params: Record<string, string | number> = {
      'BDUSS': TiebaAPI.getBduss(),
      'portrait': portrait,
      'tbs': tbs
    };

    const response = await TiebaAPI.client.post(url, params, LATEST_VERSION);

    if (typeof response.data !== 'string') {
      throw new Error('Invalid follow operation response: not a string');
    }

    let resJson: FollowOpResponse;
    try {
      resJson = JSON.parse(response.data) as FollowOpResponse;
    } catch (err) {
      throw new Error('解析关注操作响应失败: ' + (err as Error).message);
    }

    if (resJson.error_code !== undefined && resJson.error_code !== 0 && resJson.error_code !== '0') {
      throw new Error(`操作失败 [${resJson.error_code}]: ${resJson.error_msg || ''}`);
    }
  }

  /**
   * 获取本账号关注的贴吧列表
   * 对齐 aiotieba get_self_follow_forums.request：
   *   - 端点 POST /c/f/forum/forumGuide（web 端）
   *   - 协议：application/x-www-form-urlencoded
   *   - header: Subapp-Type: hybrid
   *   - 参数：tbs、sort_type=3、call_from=3、page_no、res_num
   *   - 响应：error_code/error_msg/like_forum[]/like_forum_has_more
   *
   * @param page 页码（page_no），从 1 开始
   * @param rn 每页数量（res_num），默认 20
   */
  static async getFollowForums(page: number = 1, rn: number = 20): Promise<PageData<SelfFollowForum>> {
    const tbs: string = TiebaAPI.getTbs();
    if (tbs.length === 0) {
      throw new Error('tbs 未初始化，请先登录');
    }

    const params: Record<string, string | number> = {
      'tbs': tbs,
      'sort_type': 3,
      'call_from': 3,
      'page_no': page,
      'res_num': rn
    };
    const extraHeaders: Record<string, string> = {
      'Subapp-Type': 'hybrid'
    };

    const response = await TiebaAPI.client.postWeb('/c/f/forum/forumGuide', params, extraHeaders);

    if (typeof response.data !== 'string') {
      throw new Error('Invalid follow forums response: not a string');
    }

    let resJson: FollowForumsResponse;
    try {
      resJson = JSON.parse(response.data) as FollowForumsResponse;
    } catch (err) {
      throw new Error('解析关注吧列表失败: ' + (err as Error).message);
    }

    // 错误码检查（error_code 非 0/'0' 视为失败，兼容字符串与数字两种返回）
    const errorCode = resJson.error_code;
    if (errorCode !== undefined && errorCode !== 0 && errorCode !== '0') {
      throw new Error(`获取关注吧列表失败 [${errorCode}]: ${resJson.error_msg || ''}`);
    }

    const rawList = resJson.like_forum || [];
    const list: SelfFollowForum[] = rawList.map((rawItem: object) => {
      const forum: SelfFollowForum = new SelfFollowForum();
      forum.fid = TiebaAPI.safeGetNumber(rawItem, 'forum_id');
      forum.fname = TiebaAPI.safeGetString(rawItem, 'forum_name');
      forum.level = TiebaAPI.safeGetNumber(rawItem, 'level_id');
      forum.isSigned = TiebaAPI.safeGetNumber(rawItem, 'is_sign') === 1;
      forum.avatar = TiebaAPI.safeGetString(rawItem, 'avatar');
      return forum;
    });

    const pageData: PageData<SelfFollowForum> = new PageData();
    pageData.list = list;
    pageData.currentPage = page;
    pageData.hasMore = TiebaAPI.safeGetNumber(resJson, 'like_forum_has_more') === 1;
    return pageData;
  }

  /**
   * 获取收藏帖子列表
   * 对齐原 app OfficialTiebaApi.threadStoreFlow（page 从 0 开始）
   * 端点 POST /c/f/post/threadstore（app 签名端点）
   * 参数：rn、offset、user_id、stoken、_client_version
   * header: client_user_token
   * 分页用 offset（偏移量 = rn * page），page 从 0 开始（对齐 Android ThreadStoreViewModel）
   */
  static async getThreadStore(page: number = 0, rn: number = 20): Promise<PageData<ThreadInfo>> {
    const stoken: string = TiebaAPI.client.getStoken();
    const uid: string = await AppStorageManager.getInstance().getString('uid', '');
    if (stoken.length === 0) {
      throw new Error('stoken 未初始化，请先登录');
    }
    if (uid.length === 0) {
      throw new Error('uid 未获取，请先登录');
    }
    // page 从 0 开始（对齐 Android），offset = rn * page
    const offset: number = rn * page;
    const params: Record<string, string | number> = {
      'rn': rn,
      'offset': offset,
      'user_id': uid,
      'stoken': stoken,
      '_client_version': LATEST_VERSION
    };
    const extraHeaders: Record<string, string> = {
      'client_user_token': uid
    };
    const response = await TiebaAPI.client.post('/c/f/post/threadstore', params, LATEST_VERSION, extraHeaders);

    if (typeof response.data !== 'string') {
      throw new Error('Invalid thread store response: not a string');
    }
    let resJson: ThreadStoreResponse;
    try {
      resJson = JSON.parse(response.data) as ThreadStoreResponse;
    } catch (err) {
      throw new Error('解析收藏列表失败: ' + (err as Error).message);
    }
    // 错误码检查（error_code 非 0/'0' 视为失败，兼容字符串与数字两种返回）
    const errorCode = resJson.error_code;
    if (errorCode !== undefined && errorCode !== 0 && errorCode !== '0') {
      const errMsg = resJson.error_msg
        || (resJson.error ? resJson.error.errmsg : '')
        || 'unknown error';
      throw new Error(`获取收藏列表失败 [${errorCode}]: ${errMsg}`);
    }

    const rawList = resJson.store_thread || [];
    const list: ThreadInfo[] = [];
    for (let i = 0; i < rawList.length; i++) {
      const rawItem: ThreadStoreItem = rawList[i];
      const thread: ThreadInfo = new ThreadInfo();
      thread.tid = Number(rawItem.thread_id) || 0;
      thread.title = rawItem.title || '';
      thread.forumName = rawItem.forum_name || '';
      thread.replyNum = Number(rawItem.count) || 0;
      // 已删除帖子标题加标记
      if (rawItem.is_deleted === '1') {
        thread.title = '[已删除] ' + thread.title;
      }
      // 作者
      if (rawItem.author) {
        thread.author.uid = Number(rawItem.author.lz_uid) || 0;
        thread.author.name = rawItem.author.name || '';
        thread.author.nickname = rawItem.author.name_show || '';
        thread.author.portrait = rawItem.author.user_portrait || '';
        thread.author.avatar = getAvatarUrl(thread.author.portrait, 's');
      }
      // 媒体（URL 优先级：big_pic > small_Pic）
      if (rawItem.media) {
        for (let j = 0; j < rawItem.media.length; j++) {
          const m: ThreadStoreMedia = rawItem.media[j];
          const media: MediaInfo = new MediaInfo();
          const bigPic: string = m.big_pic || '';
          const smallPic: string = m.small_Pic || '';
          if (bigPic.length > 0) {
            media.url = bigPic;
          } else if (smallPic.length > 0) {
            media.url = smallPic;
          }
          media.thumbnail = smallPic;
          media.width = m.width || 0;
          media.height = m.height || 0;
          if (media.url.length > 0) {
            thread.mediaList.push(media);
          }
        }
      }
      list.push(thread);
    }

    const pageData: PageData<ThreadInfo> = new PageData();
    pageData.list = list;
    // 返回 1-based currentPage 对齐 BaseViewModel 约定（loadData 用 result.currentPage+1 推进）
    // 内部 offset 仍按 0-based page 计算（对齐 Android），仅返回值转为 1-based
    pageData.currentPage = page + 1;
    // threadstore 无 total/has_more 字段，按返回数量推断是否还有更多
    pageData.hasMore = list.length >= rn;
    return pageData;
  }

  /**
   * 添加收藏
   * 对齐原 app OfficialTiebaApi.addStoreFlow
   * 端点 POST /c/c/post/addstore
   * data 字段是 JSON 字符串：[{"tid":"<tid>","pid":"<pid>","status":1}]
   */
  static async addStore(tid: number, pid: number = 0): Promise<void> {
    // 对齐 Android 原版 NewTiebaApi.addStore：参数为 data + tbs（无 stoken）
    // 之前误传 stoken 导致服务器返回 300000 错误
    const tbs: string = TiebaAPI.getTbs();
    if (tbs.length === 0) {
      throw new Error('tbs 未初始化，请先登录');
    }
    // 构造 data JSON（NewCollectDataBean）
    const collectData: CollectDataItem[] = [{
      tid: tid.toString(),
      pid: pid.toString(),
      status: 1
    }];
    const dataJson: string = JSON.stringify(collectData);
    const params: Record<string, string | number> = {
      'data': dataJson,
      'tbs': tbs
    };
    const uid: string = await AppStorageManager.getInstance().getString('uid', '');
    const extraHeaders: Record<string, string> = {};
    if (uid.length > 0) {
      extraHeaders['client_user_token'] = uid;
    }
    const response = await TiebaAPI.client.post('/c/c/post/addstore', params, LATEST_VERSION,
      Object.keys(extraHeaders).length > 0 ? extraHeaders : undefined);

    if (typeof response.data !== 'string') {
      throw new Error('Invalid addstore response: not a string');
    }
    let resJson: CommonResponse;
    try {
      resJson = JSON.parse(response.data) as CommonResponse;
    } catch (err) {
      throw new Error('解析添加收藏响应失败: ' + (err as Error).message);
    }
    const code = resJson.error_code;
    if (code !== undefined && code !== 0 && code !== '0') {
      const msg = resJson.error_msg || '';
      throw new Error(`添加收藏失败 [${code}]: ${msg}`);
    }
  }

  /**
   * 取消收藏
   * 对齐原 app OfficialTiebaApi.removeStoreFlow
   * 端点 POST /c/c/post/rmstore
   * 参数：tid、fid(默认"null")、tbs、stoken、user_id
   */
  static async removeStore(tid: number): Promise<void> {
    const stoken: string = TiebaAPI.client.getStoken();
    const tbs: string = TiebaAPI.getTbs();
    const uid: string = await AppStorageManager.getInstance().getString('uid', '');
    if (stoken.length === 0) {
      throw new Error('stoken 未初始化，请先登录');
    }
    if (tbs.length === 0) {
      throw new Error('tbs 未初始化，请先登录');
    }
    const params: Record<string, string | number> = {
      'tid': tid.toString(),
      'fid': 'null',
      'tbs': tbs,
      'stoken': stoken,
      'user_id': uid
    };
    const extraHeaders: Record<string, string> = {};
    if (uid.length > 0) {
      extraHeaders['client_user_token'] = uid;
    }
    const response = await TiebaAPI.client.post('/c/c/post/rmstore', params, LATEST_VERSION,
      Object.keys(extraHeaders).length > 0 ? extraHeaders : undefined);

    if (typeof response.data !== 'string') {
      throw new Error('Invalid rmstore response: not a string');
    }
    let resJson: CommonResponse;
    try {
      resJson = JSON.parse(response.data) as CommonResponse;
    } catch (err) {
      throw new Error('解析取消收藏响应失败: ' + (err as Error).message);
    }
    const code = resJson.error_code;
    if (code !== undefined && code !== 0 && code !== '0') {
      const msg = resJson.error_msg || '';
      throw new Error(`取消收藏失败 [${code}]: ${msg}`);
    }
  }

  /** 从 HttpClient 取出当前 BDUSS（供表单字段使用，Cookie 由 HttpClient 自动注入） */
  private static getBduss(): string {
    return TiebaAPI.client.getBduss();
  }

  /**
   * 安全从对象中读取数字字段，对 null/undefined/非对象输入返回 0
   * 替代裸 `as Record<string, number>` 断言，避免 null 断言不报错导致脏数据
   */
  private static safeGetNumber(obj: object | undefined | null, key: string): number {
    if (!obj || typeof obj !== 'object') return 0;
    const record = obj as Record<string, object>;
    const val = record[key];
    if (val === undefined || val === null) return 0;
    return Number(val);
  }

  /**
   * 安全从对象中读取字符串字段，对 null/undefined/非对象输入返回空串
   */
  private static safeGetString(obj: object | undefined | null, key: string): string {
    if (!obj || typeof obj !== 'object') return '';
    const record = obj as Record<string, object>;
    const val = record[key];
    if (val === undefined || val === null) return '';
    return String(val);
  }

}
