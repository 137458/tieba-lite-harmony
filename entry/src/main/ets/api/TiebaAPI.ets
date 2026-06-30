import { TiebaHttpClient, LATEST_VERSION, STABLE_VERSION } from '../net/TiebaHttpClient';
import { ThreadInfo, PostInfo, PageData, ForumInfo, UserInfo, MediaInfo, ExactSearch } from '../model/ForumModels';
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
import { initZid } from './InitZid';
import { CryptoUtil } from '../utils/CryptoUtil';
import { AppStorageManager } from '../data/AppStorage';

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
  error_code?: string;
  error_msg?: string;
  user?: LoginUser;
  anti?: LoginAnti;
}

interface AgreeResponse {
  error_code?: string;
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
  error_code?: string;
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
  error_code?: string;
  error_msg?: string;
  user_info?: InitNicknameUserInfo;
}

/** initNickname 接口返回值 */
class InitNicknameResult {
  userName: string = '';
  nameShow: string = '';
  tiebaUid: number = 0;
}

/** /home/get/panel 响应顶层 */
interface UserPanelResponse {
  no?: string | number;
  error?: string;
  data?: object;
}

/** /home/get/panel data 字段结构 */
interface UserPanelData {
  portrait?: string;
  name?: string;
  show_nickname?: string;
  name_show?: string;
  sex?: string;
  tb_age?: string;
  post_num?: string | number;
  followed_count?: string | number;
  vipInfo?: object;
}

/** /c/c/user/follow 与 /c/c/user/unfollow 响应 */
interface FollowOpResponse {
  error_code?: string;
  error_msg?: string;
}

/** /c/u/follow/followList 响应顶层 */
interface FollowsResponse {
  error_code?: string;
  error_msg?: string;
  follow_list?: object[];
  pn?: string | number;
  total_follow_num?: string | number;
  has_more?: string | number;
}

/** /c/u/fans/page 响应顶层 */
interface FansResponse {
  error_code?: string;
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
  error_code?: string;
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

        // 检查错误码
        if (data.error_code !== undefined && data.error_code !== '0') {
          throw new Error(`Login failed [${data.error_code}]: ${data.error_msg || 'unknown error'}`);
        }

        // 检查是否有用户数据
        if (!data.user || !data.user.id) {
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
      // 如果是网络错误，提供更详细的信息
      if (error.message.includes('Network')) {
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

    if (resJson.error_code !== undefined && resJson.error_code !== '0') {
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

    if (resJson.error_code !== undefined && resJson.error_code !== '0') {
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
      const msg = (err as Error).message;
      // decodeFrsPageRes 抛出的错误已含"获取帖子列表失败"前缀，避免重复包装
      if (msg.startsWith('获取帖子列表失败')) {
        throw new Error(msg);
      }
      throw new Error('获取帖子列表失败: ' + msg);
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
   * @param threadId 主题帖 id（kz）
   * @param page 页码（pn），从 1 开始
   * @param onlyAuthor true 只看楼主（lz=1）
   */
  static async getPosts(
    threadId: number,
    page: number = 1,
    onlyAuthor: boolean = false
  ): Promise<PageData<PostInfo>> {
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

      // 解析 protobuf 响应
      const result: PbPageResult = decodePbPageRes(responseBytes);
      return result.posts;
    } catch (err) {
      const msg = (err as Error).message;
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
   * @param fname 吧名（kw，可为空字符串表示全吧搜索）
   * @param keyword 关键词（word）
   * @param page 页码（pn），从 1 开始
   * @param pageSize 每页数量（rn），默认 30
   * @param searchType 搜索类型（sm）：0=ALL / 1=TIME / 2=RELATION
   * @param onlyThread true 只搜主题帖，false 含楼中楼回复
   */
  static async searchExact(
    fname: string,
    keyword: string,
    page: number = 1,
    pageSize: number = 30,
    searchType: SearchType = SearchType.ALL,
    onlyThread: boolean = true
  ): Promise<PageData<ExactSearch>> {
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

    if (resJson.error_code !== undefined && resJson.error_code !== '0') {
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
      pageData.currentPage = Number(resJson.page.current_page || 1);
      pageData.totalPage = Number(resJson.page.total_page || 1);
      pageData.hasMore = Number(resJson.page.has_more || 0) === 1;
    } else {
      pageData.hasMore = false;
    }
    return pageData;
  }

  /**
   * 通过 portrait 获取用户主页资料
   * 对应 aiotieba get_uinfo_panel.request(http_core, name_or_portrait)
   * 端点：GET /home/get/panel，参数 id=portrait 或 un=userName
   *
   * @param portrait 用户头像标识（如 "tb.0.xxx"），非空时走 id 参数
   * @param userName 用户名（fallback，portrait 为空时走 un 参数）
   * @param uid 旧版 user_id，panel API 不返回此字段，由调用方传入回填到结果中
   */
  static async getUserProfile(
    portrait: string,
    userName: string = '',
    uid: number = 0
  ): Promise<UserProfileInfo> {
    const params: Record<string, string | number> = {};
    if (portrait.length > 0) {
      params['id'] = portrait;
    } else if (userName.length > 0) {
      params['un'] = userName;
    } else {
      throw new Error('portrait 和 userName 不能同时为空');
    }

    const response = await TiebaAPI.client.get('/home/get/panel', params);

    if (typeof response.data !== 'string') {
      throw new Error('Invalid user profile response: not a string');
    }

    let resJson: UserPanelResponse;
    try {
      resJson = JSON.parse(response.data) as UserPanelResponse;
    } catch (err) {
      throw new Error('解析用户资料失败: ' + (err as Error).message);
    }

    // 检查错误码（panel API 用 no/error 字段，非 0 表示失败）
    const noValue = resJson.no;
    if (noValue !== undefined && noValue !== 0 && noValue !== '0') {
      const errMsg = resJson.error || 'unknown error';
      throw new Error(`获取用户资料失败 [${noValue}]: ${errMsg}`);
    }

    if (!resJson.data) {
      throw new Error('用户资料响应缺少 data 字段');
    }

    const dataObj = resJson.data as UserPanelData;
    // ArkTS 严格模式禁止对象字面量传给 Partial<T>，改为逐字段赋值
    const profile: UserProfileInfo = new UserProfileInfo();
    profile.uid = uid;
    profile.portrait = TiebaAPI.safeGetString(dataObj, 'portrait');
    profile.userName = TiebaAPI.safeGetString(dataObj, 'name');
    profile.nickName = TiebaAPI.safeGetString(dataObj, 'show_nickname');
    profile.nickNameOld = TiebaAPI.safeGetString(dataObj, 'name_show');
    profile.gender = TiebaAPI.parseGender(dataObj.sex);
    profile.age = TiebaAPI.parseAge(dataObj.tb_age);
    profile.postNum = TiebaAPI.parseTbNum(dataObj.post_num);
    profile.fanNum = TiebaAPI.parseTbNum(dataObj.followed_count);
    profile.isVip = TiebaAPI.parseVip(dataObj.vipInfo);
    return profile;
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

    if (resJson.error_code !== undefined && resJson.error_code !== '0') {
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

    if (resJson.error_code !== undefined && resJson.error_code !== '0') {
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

    const params: Record<string, string | number> = {
      'BDUSS': TiebaAPI.getBduss(),
      '_client_version': LATEST_VERSION,
      'agree_type': isDisagree ? 5 : 2,
      'cuid': TiebaAPI.client.getCuid(),
      'obj_type': objType,
      'op_type': isUndo ? 1 : 0,
      'post_id': pid,
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

    if (resJson.error_code !== undefined && resJson.error_code !== '0') {
      throw new Error(`点赞操作失败 [${resJson.error_code}]`);
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

    if (resJson.error_code !== undefined && resJson.error_code !== '0') {
      throw new Error(`操作失败 [${resJson.error_code}]: ${resJson.error_msg || ''}`);
    }
  }

  /** 从 HttpClient 取出当前 BDUSS（供表单字段使用，Cookie 由 HttpClient 自动注入） */
  private static getBduss(): string {
    return TiebaAPI.client.getBduss();
  }

  /**
   * 解析性别字段
   * 对应 aiotieba _classdef.py 中 sex 字段的转换逻辑
   * @returns 0=未知 1=男 2=女
   */
  private static parseGender(sex: string | undefined): number {
    if (sex === 'male') return 1;
    if (sex === 'female') return 2;
    return 0;
  }

  /**
   * 解析吧龄字段
   * 对应 aiotieba _classdef.py 中 tb_age 字段，"-" 表示未设置
   */
  private static parseAge(tbAge: string | undefined): number {
    if (!tbAge || tbAge === '-') return 0;
    const age = Number(tbAge);
    if (isNaN(age)) return 0;
    return age;
  }

  /**
   * 解析贴吧数字字段
   * 对应 aiotieba _classdef.py 中 _tbnum2int 函数
   * 服务端可能返回 "1.2万" 或数字，统一转为整数
   */
  private static parseTbNum(value: string | number | undefined): number {
    if (value === undefined || value === null) return 0;
    if (typeof value === 'number') return value;
    if (value.length === 0) return 0;
    if (value.endsWith('万')) {
      const wan = Number(value.substring(0, value.length - 1));
      if (isNaN(wan)) return 0;
      return Math.floor(wan * 10000);
    }
    const num = Number(value);
    if (isNaN(num)) return 0;
    return num;
  }

  /**
   * 解析 vipInfo 字段
   * 对应 aiotieba _classdef.py 中 v_status == 3 判定为超级会员
   */
  private static parseVip(vipInfo: object | undefined): boolean {
    if (!vipInfo || typeof vipInfo !== 'object') return false;
    const record = vipInfo as Record<string, object>;
    const status = record['v_status'];
    if (status === undefined || status === null) return false;
    return Number(status) === 3;
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

  private static parseThreadsResponse(data: object): PageData<ThreadInfo> {
    const pageData = new PageData<ThreadInfo>();

    if (data && typeof data === 'object') {
      const obj = data as Record<string, object>;

      // 检查 error_code：非 0 表示服务端错误（如签名错误、参数错误、风控）
      // 对齐 aiotieba parse_body 的 `if code := int(res_json["error_code"])` 检查
      const errorCode = TiebaAPI.safeGetString(obj, 'error_code');
      if (errorCode.length > 0 && errorCode !== '0') {
        const errorMsg = TiebaAPI.safeGetString(obj, 'error_msg');
        throw new Error(`获取帖子列表失败 [${errorCode}]: ${errorMsg}`);
      }

      if (obj['page']) {
        const pageInfo = obj['page'] as Record<string, number>;
        pageData.currentPage = pageInfo['current_page'] !== undefined ? pageInfo['current_page'] : 1;
        pageData.totalPage = pageInfo['total_page'] !== undefined ? pageInfo['total_page'] : 1;
        pageData.hasMore = pageData.currentPage < pageData.totalPage;
      }

      if (obj['thread_list']) {
        const threads = obj['thread_list'] as object[];
        pageData.list = threads.map((thread: object) => {
          const t = thread as Record<string, object>;
          const authorObj = t['author'];
          const authorInit: UserInfoInit = {
            uid: TiebaAPI.safeGetNumber(authorObj, 'id'),
            name: TiebaAPI.safeGetString(authorObj, 'name'),
            avatar: TiebaAPI.safeGetString(authorObj, 'portrait')
          };
          // 媒体列表解析：服务端 thread.media 为对象数组，含 big_pic/src_pic/pic 等字段
          const mediaList = TiebaAPI.parseMediaList(t['media']);
          const threadInfoInit: ThreadInfoInit = {
            tid: Number(t['tid'] || 0),
            title: String(t['title'] || ''),
            content: String(t['abstract'] || ''),
            replyNum: Number(t['reply_num'] || 0),
            viewNum: Number(t['view_num'] || 0),
            isTop: Number(t['is_top']) === 1,
            isGood: Number(t['is_good']) === 1,
            author: new UserInfo(authorInit),
            createTime: TiebaAPI.safeGetNumber(t, 'create_time'),
            forumName: TiebaAPI.safeGetString(t, 'forum_name'),
            mediaList: mediaList
          };
          return new ThreadInfo(threadInfoInit);
        });
      }
    }

    return pageData;
  }


  /**
   * 解析媒体列表
   * 对应 protobuf ThreadInfo.media / PostInfo.media 字段
   * 服务端字段：每个 media 对象含 big_pic/src_pic/pic（图片地址）及宽高信息
   * 转换为 MediaInfo[]，url 优先取 big_pic，其次 src_pic，最后 pic
   */
  private static parseMediaList(rawMedia: object | undefined): MediaInfo[] {
    if (!rawMedia || typeof rawMedia !== 'object') {
      return [];
    }
    const arr = rawMedia as object[];
    const result: MediaInfo[] = [];
    for (let i = 0; i < arr.length; i++) {
      const item = arr[i] as Record<string, object>;
      const bigPic = TiebaAPI.safeGetString(item, 'big_pic');
      const srcPic = TiebaAPI.safeGetString(item, 'src_pic');
      const pic = TiebaAPI.safeGetString(item, 'pic');
      const url = bigPic.length > 0 ? bigPic : (srcPic.length > 0 ? srcPic : pic);
      const mediaInfo: MediaInfo = new MediaInfo();
      mediaInfo.url = url;
      mediaInfo.thumbnail = pic;
      mediaInfo.width = TiebaAPI.safeGetNumber(item, 'width');
      mediaInfo.height = TiebaAPI.safeGetNumber(item, 'height');
      result.push(mediaInfo);
    }
    return result;
  }
}
