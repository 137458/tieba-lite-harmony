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

export class TiebaHttpClient {
  private static instance: TiebaHttpClient;
  private httpClient: HttpClient = HttpClient.getInstance();
  private baseUrl: string = 'https://tiebac.baidu.com';
  private webBaseUrl: string = 'https://tieba.baidu.com';
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
   * POST 请求（写 API，app 端点）
   * 自动调用 CryptoUtil.generateSign 追加 sign 字段，调用方不再手动调 generateSign
   * 对齐 aiotieba pack_form_request 行为
   * @param path 路径，如 /c/s/login
   * @param data 表单参数（不含 sign，由本方法追加）
   * @param version 客户端版本号，用于拼接 User-Agent，默认 LATEST_VERSION
   */
  async post(
    path: string,
    data?: Record<string, string | number>,
    version: string = LATEST_VERSION
  ): Promise<ResponseData> {
    const url = this.baseUrl + path;
    const signedData: Record<string, string | number> = await this.signParams(data);
    const body = this.buildFormData(signedData);
    const headers = this.buildHeaders(version);
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
    const headers: Record<string, string> = {
      'Content-Type': `multipart/form-data; boundary=${boundary}`,
      'User-Agent': `bdtb for Android ${STABLE_VERSION}`,
      'x_bd_data_type': 'protobuf',
      'Accept-Encoding': 'gzip',
      'Connection': 'keep-alive',
      'Cookie': this.buildCookie()
    };

    const response = await this.httpClient.post(url, body, headers);

    if (response.statusCode !== 200) {
      throw new Error(`Request failed with status ${response.statusCode}`);
    }

    if (response.data instanceof ArrayBuffer) {
      return new Uint8Array(response.data);
    }

    if (typeof response.data === 'string') {
      // string 响应说明服务端返回了非 protobuf 数据（如错误 JSON / HTML 风控页）
      throw new Error(`Unexpected string response: ${response.data}`);
    }

    throw new Error('Unexpected response data type');
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
    const encoder = new util.TextEncoder();
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
   * 构建 Cookie 字符串：未登录时返回 'ka=open'，登录后返回 'BDUSS=...;STOKEN=...;ka=open'
   */
  private buildCookie(): string {
    let cookie: string = 'ka=open';
    if (this.bduss.length > 0) {
      cookie = `BDUSS=${this.bduss}`;
      if (this.stoken.length > 0) {
        cookie += `;STOKEN=${this.stoken}`;
      }
      cookie += ';ka=open';
    }
    return cookie;
  }
}
