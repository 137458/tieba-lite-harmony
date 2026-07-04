import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';

/**
 * HTTP 请求错误类
 * 保留 BusinessError 的 code 字段，调用方可根据 code 区分错误类型
 * （如超时、网络断开、SSL 错误等），避免丢失上下文
 */
export class HttpError extends Error {
  code: number;

  constructor(code: number, message: string) {
    super(message);
    this.name = 'HttpError';
    this.code = code;
  }
}

export interface RequestConfig {
  url: string;
  method: http.RequestMethod;
  headers?: Record<string, string>;
  body?: string | ArrayBuffer;
  timeout?: number;
  /**
   * 预期响应数据类型。
   * - STRING：响应体作为字符串返回（默认，调用方自行 JSON.parse）
   * - ARRAY_BUFFER：响应体作为 ArrayBuffer 返回（protobuf/二进制场景）
   * 不设置时由 HarmonyOS 自动推断（JSON 响应会被解析成 object，导致 typeof 判断失效）
   */
  expectDataType?: http.HttpDataType;
}

export interface ResponseData {
  statusCode: number;
  // HarmonyOS http.HttpResponse.header 返回 Object 类型，
  // 无法直接赋值给 Record<string, string>（无索引签名）。
  // 使用 object（小写）类型兼容 API 返回值；当前无调用方读取此字段。
  headers: object;
  data: string | object | ArrayBuffer;
}

export class HttpClient {
  private static instance: HttpClient;
  private defaultTimeout: number = 30000;
  private defaultHeaders: Record<string, string> = {
    'Content-Type': 'application/x-www-form-urlencoded',
    'User-Agent': 'Mozilla/5.0 (Linux; Android 14; HarmonyOS; Phone) AppleWebKit/537.36'
  };

  private constructor() {
  }

  static getInstance(): HttpClient {
    if (!HttpClient.instance) {
      HttpClient.instance = new HttpClient();
    }
    return HttpClient.instance;
  }

  async request(config: RequestConfig): Promise<ResponseData> {
    const httpRequest = http.createHttp();

    const options: http.HttpRequestOptions = {
      method: config.method,
      header: this.mergeHeaders(config.headers),
      readTimeout: config.timeout || this.defaultTimeout,
      connectTimeout: config.timeout || this.defaultTimeout,
      expectDataType: config.expectDataType
    };

    if (config.body) {
      options.extraData = config.body;
    }

    try {
      const response = await httpRequest.request(config.url, options);

      return {
        statusCode: response.responseCode,
        headers: response.header,
        data: response.result
      };
    } catch (err) {
      const error = err as BusinessError;
      // 保留 BusinessError 的 code 字段，调用方可据此区分错误类型
      throw new HttpError(error.code, `HTTP request failed: ${error.message}`);
    } finally {
      httpRequest.destroy();
    }
  }

  async get(url: string, headers?: Record<string, string>): Promise<ResponseData> {
    return this.request({
      url: url,
      method: http.RequestMethod.GET,
      headers: headers,
      expectDataType: http.HttpDataType.STRING
    });
  }

  async post(url: string, body?: string | ArrayBuffer, headers?: Record<string, string>): Promise<ResponseData> {
    return this.request({
      url: url,
      method: http.RequestMethod.POST,
      body: body,
      headers: headers,
      expectDataType: http.HttpDataType.STRING
    });
  }

  /**
   * POST 二进制响应（protobuf/图片等场景）
   * 强制 expectDataType=ARRAY_BUFFER，避免 JSON 自动解析导致类型丢失
   */
  async postBinary(url: string, body: ArrayBuffer, headers: Record<string, string>): Promise<ResponseData> {
    return this.request({
      url: url,
      method: http.RequestMethod.POST,
      body: body,
      headers: headers,
      expectDataType: http.HttpDataType.ARRAY_BUFFER
    });
  }

  private mergeHeaders(customHeaders?: Record<string, string>): Record<string, string> {
    if (!customHeaders) {
      return this.defaultHeaders;
    }

    const merged: Record<string, string> = {};
    for (const key of Object.keys(this.defaultHeaders)) {
      merged[key] = this.defaultHeaders[key];
    }
    for (const key of Object.keys(customHeaders)) {
      merged[key] = customHeaders[key];
    }
    return merged;
  }
}
