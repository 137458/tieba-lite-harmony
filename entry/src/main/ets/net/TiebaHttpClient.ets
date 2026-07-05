import { HttpClient, ResponseData } from './HttpClient';
import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { CryptoUtil } from '../utils/CryptoUtil';

/** 读 API 版本号（protobuf POST 端点，如 getThreads/getPosts）
 * 对齐 Android ClientVersion.TIEBA_V12 = "12.52.1.0"，实测 12.64.1.1 服务端兼容
 */
export const STABLE_VERSION: string = '12.64.1.1';
/** 写 API 版本号（JSON POST 端点，如 login/agree/addStore）
 * 对齐 Android RetrofitTiebaApi.kt L181/L217 OFFICIAL_TIEBA_API 硬编码 "12.41.7.1"
 * 之前用 '22.5.1.0' 是贴吧客户端序列里不存在的版本号，会被服务端风控
 */
export const LATEST_VERSION: string = '12.41.7.1';
/** 签名 salt（对齐 aiotieba APP_SALT） */
const APP_SALT: string = 'tiebaclient!!!';
/** CUID 合法字符校验正则（CUID 格式为 md5Hex|Vbase32，含 | 分隔符） */
const TOKEN_RE: RegExp = /^[A-Za-z0-9_|-]+$/;

/** #74 multipart/form-data 文本字段 */
export interface MultipartTextField {
  /** 字段名（如 "alt"、"chunkNo"） */
  name: string;
  /** 字段值（字符串形式，如 "json"、"1"） */
  value: string;
}

/** #74 multipart/form-data 文件字段 */
export interface MultipartFileField {
  /** 字段名（对齐 Android ImageUploader：固定 "chunk"） */
  name: string;
  /** 文件名（对齐 Android：固定 "file"） */
  filename: string;
  /** Content-Type（如 "image/jpeg"） */
  contentType: string;
  /** 二进制数据 */
  data: Uint8Array;
}

export class TiebaHttpClient {
  private static instance: TiebaHttpClient;
  private httpClient: HttpClient = HttpClient.getInstance();
  /** JSON 写接口域名（post / postMultipart 用）
   * 对齐 Android RetrofitTiebaApi.kt L179 OFFICIAL_TIEBA_API: "http://c.tieba.baidu.com/"
   * HTTPS 升级：HarmonyOS 默认强制 HTTPS，c.tieba.baidu.com 服务端支持 HTTPS
   */
  private appBaseUrl: string = 'https://c.tieba.baidu.com';
  /** protobuf 端点域名（postProtobuf 用）
   * 对齐 Android RetrofitTiebaApi.kt L229 OFFICIAL_PROTOBUF_TIEBA_API: "https://tiebac.baidu.com/"
   */
  private protoBaseUrl: string = 'https://tiebac.baidu.com';
  /** web 端点域名（getWeb / postWeb 用，浏览器 UA）
   * 对齐 aiotieba http.py web cookie jar
   */
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
    const url = this.appBaseUrl + path;
    // 注入公共参数（BDUSS/cuid/cuid_galaxy2/from/timestamp/_client_type/_client_version/model/net_type）
    // 对齐 Android CommonParamInterceptor + OFFICIAL_TIEBA_API 默认参数集
    // 必须在 signParams 之前调用，确保公共参数参与签名
    const enrichedData: Record<string, string | number> = this.injectCommonParams(data);
    const signedData: Record<string, string | number> = await this.signParams(enrichedData);
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
    const url = this.protoBaseUrl + path + `?cmd=${cmd}`;
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
      const rawBytes = new Uint8Array(response.data);
      // 检测 gzip 压缩：HarmonyOS HTTP 框架不会自动解压 ARRAY_BUFFER 响应
      // gzip magic number: 0x1f 0x8b
      if (rawBytes.length >= 2 && rawBytes[0] === 0x1f && rawBytes[1] === 0x8b) {
        return await CryptoUtil.gzipDecompress(rawBytes);
      }
      return rawBytes;
    }

    // expectDataType=ARRAY_BUFFER 时 data 必为 ArrayBuffer，否则属于异常
    throw new Error(`Unexpected response data type: ${typeof response.data}`);
  }

  /**
   * #74 multipart/form-data POST 请求（多 part，用于图片上传 /c/s/uploadPicture）
   * 对齐 Android OfficialTiebaApi.uploadPicture：
   *   - POST /c/s/uploadPicture（multipart/form-data）
   *   - 响应为 JSON 字符串（error_code/error_msg/picId/picInfo 等）
   *   - 鉴权：BDUSS/STOKEN 通过 Cookie + 表单字段双重传递（对齐 Android 拦截器）
   *   - 不自动追加 sign（Android uploadPicture 接口本身不做 sign 加签）
   * @param path 路径，如 /c/s/uploadPicture
   * @param textFields 文本字段数组（alt/chunkNo/forum_name/groupId/...）
   * @param fileField 文件字段（name="chunk", filename="file", contentType="image/jpeg"）
   * @param version 客户端版本号，默认 LATEST_VERSION
   */
  async postMultipart(
    path: string,
    textFields: MultipartTextField[],
    fileField: MultipartFileField,
    version: string = LATEST_VERSION
  ): Promise<ResponseData> {
    const url: string = this.appBaseUrl + path;
    // 固定 boundary（对齐 Android ProtobufRequest.kt:26 BOUNDARY = "--------7da3d81520810*"）
    const boundary: string = '--------7da3d81520810*';
    const body: ArrayBuffer = this.buildMultipartBodyMultiPart(boundary, textFields, fileField);
    const headers: Record<string, string> = {
      'Content-Type': `multipart/form-data; boundary=${boundary}`,
      'User-Agent': `bdtb for Android ${version}`,
      'Accept': 'application/json',
      'Accept-Encoding': 'gzip',
      'Connection': 'keep-alive',
      // uploadPicture 强制登录（对齐 Android @Headers("force_login: true")），
      // web 端点 Cookie 模式：BDUSS + STOKEN + CUID 全部带在 Cookie（对齐 Android 拦截器）
      'Cookie': this.buildWebCookie()
    };
    return this.httpClient.post(url, body, headers);
  }

  /**
   * 构造多 part multipart/form-data body（用于图片上传）
   * 结构（对齐 Android MyMultipartBody）：
   *   --{boundary}\r\n
   *   Content-Disposition: form-data; name="{name}"\r\n
   *   \r\n
   *   {value}\r\n
   *   ...（重复每个文本字段）
   *   --{boundary}\r\n
   *   Content-Disposition: form-data; name="{fileField.name}"; filename="{fileField.filename}"\r\n
   *   Content-Type: {fileField.contentType}\r\n
   *   \r\n
   *   <binary bytes>\r\n
   *   --{boundary}--\r\n
   */
  private buildMultipartBodyMultiPart(
    boundary: string,
    textFields: MultipartTextField[],
    fileField: MultipartFileField
  ): ArrayBuffer {
    const encoder: util.TextEncoder = TiebaHttpClient.textEncoder;
    const parts: Uint8Array[] = [];

    // 文本字段（按调用方传入顺序写入，对齐 Android addFormDataPart 调用顺序）
    for (let i = 0; i < textFields.length; i++) {
      const f: MultipartTextField = textFields[i];
      parts.push(encoder.encodeInto(`--${boundary}\r\n`));
      parts.push(encoder.encodeInto(`Content-Disposition: form-data; name="${f.name}"\r\n\r\n`));
      parts.push(encoder.encodeInto(`${f.value}\r\n`));
    }

    // 文件字段
    parts.push(encoder.encodeInto(`--${boundary}\r\n`));
    parts.push(encoder.encodeInto(
      `Content-Disposition: form-data; name="${fileField.name}"; filename="${fileField.filename}"\r\n`
    ));
    parts.push(encoder.encodeInto(`Content-Type: ${fileField.contentType}\r\n\r\n`));
    parts.push(fileField.data);
    parts.push(encoder.encodeInto(`\r\n`));

    // 结尾 boundary
    parts.push(encoder.encodeInto(`--${boundary}--\r\n`));

    // 拼接所有部分（沿用 buildMultipartBody 逻辑）
    let totalLength: number = 0;
    for (let i = 0; i < parts.length; i++) {
      totalLength += parts[i].length;
    }
    const result: Uint8Array = new Uint8Array(totalLength);
    let offset: number = 0;
    for (let i = 0; i < parts.length; i++) {
      result.set(parts[i], offset);
      offset += parts[i].length;
    }
    return result.buffer;
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

  /**
   * 注入公共表单参数（对齐 Android CommonParamInterceptor + OFFICIAL_TIEBA_API 默认参数集）
   *
   * 实现依据：Android RetrofitTiebaApi.kt L64-L73 defaultCommonParamInterceptor +
   * L191-L220 OFFICIAL_TIEBA_API 追加参数。HarmonyOS 端无法获取 IMEI/OAID/AID/
   * AndroidId/BaiduId/SampleId/ClientId 等 Android 特有设备标识，仅注入最小必填集。
   *
   * 注入字段（仅当 params 中未含同名参数时才注入，对齐 Android CommonParamInterceptor 去重逻辑）：
   *   - BDUSS（已登录时注入，对齐 Param.BDUSS）
   *   - cuid / cuid_galaxy2（同值，对齐 CuidUtils.getNewCuid()）
   *   - cuid_gid = ""（对齐 Android 空值）
   *   - from = "tieba"（对齐 Param.FROM）
   *   - timestamp（毫秒，对齐 Param.TIMESTAMP = System.currentTimeMillis()）
   *   - _client_type = "2"（对齐 Param.CLIENT_TYPE，2=Android）
   *   - _client_version = LATEST_VERSION（对齐 Param.CLIENT_VERSION）
   *   - model = "HarmonyOS"（对齐 Param.MODEL = Build.MODEL）
   *   - net_type = "1"（对齐 Param.NET_TYPE，1=WIFI）
   *
   * 必须在 signParams 之前调用，确保公共参数参与签名。
   * 收藏功能根因：之前 addStore/getThreadStore 的 form body 缺 BDUSS 字段，
   * 服务端从 form 读不到 BDUSS 返回 error_code=1 "用户未登录或登录失败"。
   *
   * @param data 调用方传入的原始参数（可能为 undefined）
   * @returns 注入公共参数后的新参数对象（不修改原 data）
   */
  private injectCommonParams(data?: Record<string, string | number>): Record<string, string | number> {
    const params: Record<string, string | number> = {};
    // 先复制调用方传入的参数（调用方传入的字段优先级高于公共参数，对齐 Android FormBody 去重逻辑）
    if (data) {
      const keys = Object.keys(data);
      for (let i = 0; i < keys.length; i++) {
        const k = keys[i];
        params[k] = data[k];
      }
    }
    // 注入公共参数（仅当 params 中未含同名参数时）
    // BDUSS（已登录时注入）
    if (this.bduss.length > 0 && !this.containsKey(params, 'BDUSS')) {
      params['BDUSS'] = this.bduss;
    }
    // cuid
    if (this.cuid.length > 0 && !this.containsKey(params, 'cuid')) {
      params['cuid'] = this.cuid;
    }
    // cuid_galaxy2 = cuid（对齐 Android CuidUtils.getNewCuid() 同值）
    if (this.cuid.length > 0 && !this.containsKey(params, 'cuid_galaxy2')) {
      params['cuid_galaxy2'] = this.cuid;
    }
    // cuid_gid = ""（对齐 Android 空值）
    if (!this.containsKey(params, 'cuid_gid')) {
      params['cuid_gid'] = '';
    }
    // from = "tieba"
    if (!this.containsKey(params, 'from')) {
      params['from'] = 'tieba';
    }
    // timestamp（毫秒，对齐 System.currentTimeMillis()）
    if (!this.containsKey(params, 'timestamp')) {
      params['timestamp'] = Date.now().toString();
    }
    // _client_type = "2"（2=Android）
    if (!this.containsKey(params, '_client_type')) {
      params['_client_type'] = '2';
    }
    // _client_version = LATEST_VERSION
    if (!this.containsKey(params, '_client_version')) {
      params['_client_version'] = LATEST_VERSION;
    }
    // model = "HarmonyOS"（HarmonyOS 设备统一标识）
    if (!this.containsKey(params, 'model')) {
      params['model'] = 'HarmonyOS';
    }
    // net_type = "1"（1=WIFI）
    if (!this.containsKey(params, 'net_type')) {
      params['net_type'] = '1';
    }
    return params;
  }

  /**
   * 判断 params 中是否包含指定 key
   * ArkTS 不支持 `in` 运算符，需手动遍历 keys（对齐 CommonParamInterceptor.containsEncodedName）
   */
  private containsKey(params: Record<string, string | number>, key: string): boolean {
    const keys = Object.keys(params);
    for (let i = 0; i < keys.length; i++) {
      if (keys[i] === key) {
        return true;
      }
    }
    return false;
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
   * 构建 headers，动态拼接 User-Agent + 注入公共 header
   *
   * 对齐 Android RetrofitTiebaApi.kt L180-L190 CommonHeaderInterceptor 参数：
   *   - User-Agent（L181）
   *   - cookie（L182，但 buildCookie 已处理）
   *   - cuid / cuid_galaxy2（L183-L184，同值）
   *   - cuid_gid = ""（L185）
   *   - c3_aid（L186，HarmonyOS 无 AID，跳过）
   *   - client_type = "2"（L187）
   *   - Charset = "UTF-8"（L188，注意首字母大写）
   *   - client_logid（L189，HarmonyOS 无 initTime，跳过）
   *
   * ifAbsent 语义说明：Android CommonHeaderInterceptor.intercept L15 只在原请求未设置同名 header 时才 addHeader。
   * HarmonyOS 端 post() 的 extraHeaders 在本方法之后应用（L172-L178），可覆盖此处设置的 header，
   * 与 Android @Headers 注解覆盖 interceptor 注入值的语义一致。
   *
   * 已知不对齐：Android addStore/rmstore/threadstore 通过 @Headers("drop_headers: Charset,client_type")
   * 丢弃这两个 header。HarmonyOS 未实现 drop_headers 机制，本方法会注入这两个 header。
   * 对收藏功能无影响（BDUSS 通过 form body 传递），drop_headers 精确对齐留待后续切片。
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
    // 公共 header 注入（对齐 Android CommonHeaderInterceptor L183-L188）
    if (this.cuid.length > 0) {
      headers['cuid'] = this.cuid;
      headers['cuid_galaxy2'] = this.cuid;
    }
    headers['cuid_gid'] = '';
    headers['client_type'] = '2';
    headers['Charset'] = 'UTF-8';
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
