import { HttpClient, ResponseData } from './HttpClient';
import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';

export class TiebaHttpClient {
  private static instance: TiebaHttpClient;
  private httpClient: HttpClient = HttpClient.getInstance();
  private baseUrl: string = 'https://tiebac.baidu.com';
  private webBaseUrl: string = 'https://tieba.baidu.com';
  private bduss: string = '';
  private stoken: string = '';
  private cuid: string = '';
  private commonHeaders: Record<string, string> = {
    'Content-Type': 'application/x-www-form-urlencoded',
    'Accept': 'application/json',
    'Accept-Encoding': 'gzip',
    'Connection': 'Keep-Alive',
    'User-Agent': 'bdtb for Android 12.64.1.1',
    'Cookie': 'ka=open'
  };

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
   * 用途：getFollows/getFans 等接口需要在表单数据中带 BDUSS 字段（不仅是 Cookie）
   */
  getBduss(): string {
    return this.bduss;
  }

  async get(path: string, params?: Record<string, string | number>): Promise<ResponseData> {
    const url = this.buildUrl(this.webBaseUrl, path, params);
    const headers = this.buildHeaders();
    return this.httpClient.get(url, headers);
  }

  async post(path: string, data?: Record<string, string | number>): Promise<ResponseData> {
    const url = this.baseUrl + path;
    const body = this.buildFormData(data);
    const headers = this.buildHeaders();
    return this.httpClient.post(url, body, headers);
  }

  async postProtobuf(
    path: string,
    protobufData: ArrayBuffer,
    cmd: number,
    dataType: number = 1
  ): Promise<ArrayBuffer> {
    const url = this.baseUrl + path;

    const headers: Record<string, string> = {
      'Content-Type': 'application/x-protobuf',
      'Accept': 'application/x-protobuf',
      'Accept-Encoding': 'gzip',
      'User-Agent': 'bdtb for Android 12.64.1.1',
      'Cookie': this.buildCookie(),
      'X-Bd-Client-Type': '1',
      'X-Bd-Cuid': this.cuid || '',
      'X-Bd-Data-Type': dataType.toString(),
      'X-Bd-Command': cmd.toString()
    };

    const response = await this.httpClient.post(url, protobufData, headers);

    if (response.statusCode !== 200) {
      throw new Error(`Request failed with status ${response.statusCode}`);
    }

    if (response.data instanceof ArrayBuffer) {
      return response.data;
    }

    if (typeof response.data === 'string') {
      return this.stringToArrayBuffer(response.data);
    }

    throw new Error('Unexpected response data type');
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
    for (const key of Object.keys(params)) {
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

  private buildHeaders(): Record<string, string> {
    const headers: Record<string, string> = {};
    for (const key of Object.keys(this.commonHeaders)) {
      headers[key] = this.commonHeaders[key];
    }

    headers['Cookie'] = this.buildCookie();
    return headers;
  }

  /**
   * 构建 Cookie 字符串：未登录时返回 'ka=open'，登录后返回 'BDUSS=...;STOKEN=...;ka=open'
   * 抽取自原 postProtobuf 与 buildHeaders 两处重复逻辑
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

  private stringToArrayBuffer(str: string): ArrayBuffer {
    const encoder = new util.TextEncoder();
    return encoder.encodeInto(str).buffer;
  }
}
