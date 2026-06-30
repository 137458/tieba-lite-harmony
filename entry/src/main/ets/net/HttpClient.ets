import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';

export interface RequestConfig {
  url: string;
  method: http.RequestMethod;
  headers?: Record<string, string>;
  body?: string | ArrayBuffer;
  timeout?: number;
}

export interface ResponseData {
  statusCode: number;
  headers: Record<string, string>;
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
      connectTimeout: config.timeout || this.defaultTimeout
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
      throw new Error(`HTTP request failed: ${error.message}`);
    } finally {
      httpRequest.destroy();
    }
  }

  async get(url: string, headers?: Record<string, string>): Promise<ResponseData> {
    return this.request({
      url: url,
      method: http.RequestMethod.GET,
      headers: headers
    });
  }

  async post(url: string, body?: string | ArrayBuffer, headers?: Record<string, string>): Promise<ResponseData> {
    return this.request({
      url: url,
      method: http.RequestMethod.POST,
      body: body,
      headers: headers
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
