import { HttpClient, ResponseData } from './HttpClient';
import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { CryptoUtil } from '../utils/CryptoUtil';

/** 读 API 版本号（protobuf POST 端点，如 getThreads/getPosts） */
export const STABLE_VERSION: string = '12.64.1.1';
/** 写 API 版本号（JSON POST 端点，如 login/agree） */
export const LATEST_VERSION: string = '22.5.1.0';
/** 签名 salt（对齐 aiotieba APP_SALT） */
const APP_SALT: string = 'tiebaclient!!!';
/** CUID 合法字符校验正则（模块级常量，避免每次 buildCookie 重新编译正则） */
const TOKEN_RE: RegExp = /^[A-Za-z0-9_-]+$/;

export class TiebaHttpClient {
  private static instance: TiebaHttpClient;
  private httpClient: HttpClient = HttpClient.getInstance();
  private baseUrl: string = 'https://tiebac.baidu.com';
  private webBaseUrl: string = 'https://tieba.baidu.com';
  // TextEncoder 实例复用：buildMultipartBody 每次发帖/上传图片都会调用，
  // 避免每次新建实例造成 GC 压力
  private static readonly textEncoder: util.TextEncoder = new util.TextEncoder();
  // 可变认证状态字段并发安全性说明：
  // ArkTS 单线程模型下 async 切换点仅在 await 处；setAuth/setCuid 为同步赋值，
  // buildCookie/buildHeaders 在 await 前同步读取字段并固化为 headers 局部变量，
  // 后续 await 期间即使 setAuth 修改字段也不影响已构建的请求。
  // 单例 + 简单字符串赋值场景竞态风险低，无需加锁或 Promise 队列串行化。
  private bduss: string = '';
  private stoken: string = '';
  private cuid: string = '';

  private constructor() {
  }

  static getInstance(): TiebaHttpClient {
    if (!TiebaHttpClient.instance) {
      TiebaHttpClient.instance = new TiebaHttpClient();
    }
    return TiebaHttpClient.instance;
  }

  setAuth(bduss: string, stoken: string = ''): void {
    this.bduss = bduss;
    this.stoken = stoken;
  }

  setCuid(cuid: string): void {
    this.cuid = cuid;
  }

  /**
   * 暴露当前 BDUSS 给 API 层
   * 用途：getFollows/getFans/agree 等接口需要在表单数据中带 BDUSS 字段（不仅是 Cookie）
   */
  getBduss(): string {
    return this.bduss;
  }

  /**
   * 暴露当前 cuid 给 API 层
   * 用途：agree 等接口需要在表单数据中带 cuid 字段
   */
  getCuid(): string {
    return this.cuid;
  }

  /**
   * 暴露当前 STOKEN 给 API 层
   * 用途：收藏接口（threadstore/addstore/rmstore）需要在表单数据中带 stoken 字段
   */
  getStoken(): string {
    return this.stoken;
  }

  /**
   * GET 请求（读 API，web 端点）
   * @param path 路径，如 /c/f/frs/page
   * @param params 查询参数
   * @param version 客户端版本号，用于拼接 User-Agent，默认 STABLE_VERSION
   */
  async get(
    path: string,
    params?: Record<string, string | number>,
    version: string = STABLE_VERSION
  ): Promise<ResponseData> {
    const url = this.buildUrl(this.webBaseUrl, path, params);
    const headers = this.buildHeaders(version);
    return this.httpClient.get(url, headers);
  }

  /**
   * web 端 GET 请求（用浏览器 UA）
   * 对齐 aiotieba pack_web_get_request：web 端点（如 /home/get/panel），
   * 用浏览器 UA 而非 bdtb for Android UA，否则服务端会返回 HTML 错误页而非 JSON
   * @param path 路径，如 /home/get/panel
   * @param params 查询参数
   */
  async getWeb(
    path: string,
    params?: Record<string, string | number>
  ): Promise<ResponseData> {
    const url = this.buildUrl(this.webBaseUrl, path, params);
    const headers: Record<string, string> = {
      'Accept': 'application/json',
      'Accept-Encoding': 'gzip',
      'Connection': 'Keep-Alive',
      'User-Agent': 'Mozilla/5.0 (Linux; Android 14; HarmonyOS) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
      'Cookie': this.buildCookie()
    };
    return this.httpClient.get(url, headers);
  }

  /**
   * POST 请求（写 API，app 端点）
   * 自动调用 CryptoUtil.generateSign 追加 sign 字段，调用方不再手动调 generateSign
   * 对齐 aiotieba pack_form_request 行为
   * @param path 路径，如 /c/s/login
   * @param data 表单参数（不含 sign，由本方法追加）
   * @param version 客户端版本号，用于拼接 User-Agent，默认 LATEST_VERSION
   * @param extraHeaders 额外 headers（如 client_user_token，收藏接口需要）
   */
  async post(
    path: string,
    data?: Record<string, string | number>,
    version: string = LATEST_VERSION,
    extraHeaders?: Record<string, string>
  ): Promise<ResponseData> {
    const url = this.baseUrl + path;
    const signedData: Record<string, string | number> = await this.signParams(data);
    const body = this.buildFormData(signedData);
    const headers: Record<string, string> = this.buildHeaders(version);
    if (extraHeaders) {
      const keys = Object.keys(extraHeaders);
      for (let i = 0; i < keys.length; i++) {
        const k = keys[i];
        headers[k] = extraHeaders[k];
      }
    }
    return this.httpClient.post(url, body, headers);
  }

  /**
   * web 端 form POST 请求（不对齐 app sign，用 webBaseUrl）
   * 对齐 aiotieba pack_web_form_request：web 端点（如 /c/f/forum/forumGuide），
   * body 为 application/x-www-form-urlencoded，不自动追加 sign
   * @param path 路径，如 /c/f/forum/forumGuide
   * @param data 表单参数
   * @param extraHeaders 额外 headers（如 Subapp-Type: hybrid）
   */
  async postWeb(
    path: string,
    data?: Record<string, string | number>,
    extraHeaders?: Record<string, string>
  ): Promise<ResponseData> {
    const url = this.webBaseUrl + path;
    const body = this.buildFormData(data);
    const headers: Record<string, string> = this.buildHeaders(STABLE_VERSION);
    // web 端点（如 /c/f/forum/forumGuide）按 aiotieba web cookie jar 必须带 BDUSS + STOKEN 鉴权，
    // 覆盖 buildHeaders 中默认的 buildCookie（无 BDUSS，对齐 Android V12 protobuf 端点修复 350004）
    headers['Cookie'] = this.buildWebCookie();
    if (extraHeaders) {
      const keys = Object.keys(extraHeaders);
      for (let i = 0; i < keys.length; i++) {
        const k = keys[i];
        headers[k] = extraHeaders[k];
      }
    }
    return this.httpClient.post(url, body, headers);
  }

  /**
   * protobuf POST 请求（读 API，app 端点）
   * 对齐 aiotieba HttpCore.pack_proto_request：
   *   - body 用 multipart/form-data 格式，boundary 固定 "-*_r1999"
   *   - part name="data" filename="file"
   *   - headers 含 x_bd_data_type: protobuf
   *   - cmd 通过 URL query 传递（?cmd=301001）
   * @param path 路径，如 /c/f/frs/page（不含 query）
   * @param protobufData protobuf 序列化后的二进制数据（Uint8Array）
   * @param cmd 命令字，如 301001（拼接到 URL query）
   */
  async postProtobuf(
    path: string,
    protobufData: Uint8Array,
    cmd: number
  ): Promise<Uint8Array> {
    // URL 加 cmd query（对齐 aiotieba request_http: query_string=f"cmd={CMD}"）
    const url = this.baseUrl + path + `?cmd=${cmd}`;
    const boundary: string = '-*_r1999';

    // 构造 multipart/form-data body
    const body: ArrayBuffer = this.buildMultipartBody(boundary, protobufData);

    // headers 对齐 aiotieba app_proto_headers
    // 修复 350004：CUID 必须在 headers 中（对齐 Android 原版，Android 在 header/Cookie/CommonReq 4 处都传 CUID）
    const headers: Record<string, string> = {
      'Content-Type': `multipart/form-data; boundary=${boundary}`,
      'User-Agent': `bdtb for Android ${STABLE_VERSION}`,
      'x_bd_data_type': 'protobuf',
      'Accept-Encoding': 'gzip',
      'Connection': 'keep-alive',
      'Cookie': this.buildCookie()
    };
    if (this.cuid.length > 0) {
      headers['cuid'] = this.cuid;
    }

    // 用 postBinary 强制 expectDataType=ARRAY_BUFFER，避免 HarmonyOS 把二进制响应误判成 JSON
    const response = await this.httpClient.postBinary(url, body, headers);

    if (response.statusCode !== 200) {
      throw new Error(`Request failed with status ${response.statusCode}`);
    }

    if (response.data instanceof ArrayBuffer) {
      return new Uint8Array(response.data);
    }

    // expectDataType=ARRAY_BUFFER 时 data 必为 ArrayBuffer，否则属于异常
    throw new Error(`Unexpected response data type: ${typeof response.data}`);
  }

  /**
   * 构造 multipart/form-data body（对齐 aiohttp.MultipartWriter 输出格式）
   * 结构：
   *   --{boundary}\r\n
   *   Content-Disposition: form-data; name="data"; filename="file"\r\n
   *   \r\n
   *   <protobuf bytes>\r\n
   *   --{boundary}--\r\n
   */
  private buildMultipartBody(boundary: string, protobufData: Uint8Array): ArrayBuffer {
    const encoder: util.TextEncoder = TiebaHttpClient.textEncoder;
    const parts: Uint8Array[] = [];

    // 开头 boundary 行
    parts.push(encoder.encodeInto(`--${boundary}\r\n`));
    // Content-Disposition 头
    parts.push(encoder.encodeInto('Content-Disposition: form-data; name="data"; filename="file"\r\n'));
    // 空行（头与 body 分隔）
    parts.push(encoder.encodeInto('\r\n'));
    // protobuf 二进制数据
    parts.push(protobufData);
    // 结尾 boundary 行
    parts.push(encoder.encodeInto(`\r\n--${boundary}--\r\n`));

    // 拼接所有部分
    let totalLength: number = 0;
    for (let i = 0; i < parts.length; i++) {
      totalLength += parts[i].length;
    }
    const result = new Uint8Array(totalLength);
    let offset: number = 0;
    for (let i = 0; i < parts.length; i++) {
      result.set(parts[i], offset);
      offset += parts[i].length;
    }
    return result.buffer;
  }

  /**
   * 为参数追加 sign 字段
   * 对齐 aiotieba helper/crypto/sign.py:sign
   * 算法：sorted(params by key) → key=val 拼接 → 末尾加 salt → MD5
   */
  private async signParams(data?: Record<string, string | number>): Promise<Record<string, string | number>> {
    const params: Record<string, string | number> = {};
    if (data) {
      const keys = Object.keys(data);
      for (let i = 0; i < keys.length; i++) {
        const k = keys[i];
        params[k] = data[k];
      }
    }
    const sign: string = await CryptoUtil.generateSign(params, APP_SALT);
    params['sign'] = sign;
    return params;
  }

  private buildUrl(base: string, path: string, params?: Record<string, string | number>): string {
    let url = base + path;
    if (params) {
      const query = this.buildQueryString(params);
      if (query.length > 0) {
        url += '?' + query;
      }
    }
    return url;
  }

  private buildQueryString(params: Record<string, string | number>): string {
    const pairs: string[] = [];
    const keys = Object.keys(params);
    for (let i = 0; i < keys.length; i++) {
      const key = keys[i];
      const value = params[key];
      if (value !== undefined && value !== null) {
        pairs.push(`${encodeURIComponent(key)}=${encodeURIComponent(String(value))}`);
      }
    }
    return pairs.join('&');
  }

  private buildFormData(data?: Record<string, string | number>): string {
    if (!data) {
      return '';
    }
    return this.buildQueryString(data);
  }

  /**
   * 构建 headers，动态拼接 User-Agent
   */
  private buildHeaders(version: string): Record<string, string> {
    const headers: Record<string, string> = {
      'Content-Type': 'application/x-www-form-urlencoded',
      'Accept': 'application/json',
      'Accept-Encoding': 'gzip',
      'Connection': 'Keep-Alive',
      'User-Agent': `bdtb for Android ${version}`,
      'Cookie': this.buildCookie()
    };
    return headers;
  }

  /**
   * 构建 Cookie 字符串（对齐 Android V12 RetrofitTiebaApi.getCookie()）
   * 修复 350004 根因：BDUSS 不放入 Cookie，仅通过 CommonReq field 10 传递
   * Android V12 Cookie 只有 ka:open; CUID:xxx; TBBRAND:xxx，刻意不含 BDUSS/STOKEN
   * 之前 HarmonyOS 同时在 Cookie + CommonReq 传 BDUSS，服务端两条校验路径产生时序竞态
   */
  private buildCookie(): string {
    // 未登录或登录态均以 ka=open 开头（对齐 Android V12）
    let cookie: string = 'ka=open';
    // CUID 追加到 Cookie（无论登录态，对齐 Android 原版）
    if (this.cuid.length > 0 && TOKEN_RE.test(this.cuid)) {
      cookie += `;CUID=${this.cuid}`;
    } else if (this.cuid.length > 0) {
      console.warn('[TiebaHttpClient] CUID 格式非法，Cookie 中已跳过');
    }
    return cookie;
  }

  /**
   * 构建 web 端点专用 Cookie（对齐 aiotieba http.py:82-89 web cookie jar）
   * web 端 form POST（如 /c/f/forum/forumGuide）靠 BDUSS + STOKEN Cookie 鉴权，
   * 不像 protobuf 端点用 CommonReq field 10 传 BDUSS。
   * 此 Cookie 仅 postWeb 使用，postProtobuf/post 仍用 buildCookie（不含 BDUSS，保住 350004 修复）
   */
  private buildWebCookie(): string {
    let cookie: string = 'ka=open';
    if (this.cuid.length > 0 && TOKEN_RE.test(this.cuid)) {
      cookie += `;CUID=${this.cuid}`;
    }
    // BDUSS 域：baidu.com（对齐 aiotieba http.py:84）
    if (this.bduss.length > 0) {
      cookie += `;BDUSS=${this.bduss}`;
    }
    // STOKEN 域：tieba.baidu.com（对齐 aiotieba http.py:88），web 端点鉴权需要
    if (this.stoken.length > 0) {
      cookie += `;STOKEN=${this.stoken}`;
    }
    return cookie;
  }
}
