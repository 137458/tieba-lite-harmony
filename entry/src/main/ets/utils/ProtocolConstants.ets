// 贴吧客户端公开协议常量集中地（M27：对齐 aiotieba，问题定性是维护性而非泄密）
// 盐值/密钥形常量集中审计点；版本常量调整历史（'22.5.1.0' 曾因服务端风控被迫更换）见各注释。
// 放置说明：选 utils 而非条目首选 proto/——proto↔net 已存在包级依赖边（11 个 proto 文件
// 引 net 层版本常量），常量模块再被 net 引用会形成 net↔proto 包级环；utils 为最低层合法方向。

// ==================== 签名盐值 ====================

/** 签名 salt（对齐 aiotieba APP_SALT），TiebaHttpClient/TiebaAPI 签名共用 */
export const APP_SALT: string = 'tiebaclient!!!';

// ==================== 版本号 ====================

/** 读 API 版本号（protobuf POST 端点，如 getThreads/getPosts）
 * 对齐 Android ClientVersion.TIEBA_V12 = "12.52.1.0"，实测 12.64.1.1 服务端兼容
 */
export const STABLE_VERSION: string = '12.64.1.1';
/** 写 API 版本号（JSON POST 端点，如 login/agree/addStore）
 * 对齐 Android RetrofitTiebaApi.kt L181/L217 OFFICIAL_TIEBA_API 硬编码 "12.41.7.1"
 * 之前用 '22.5.1.0' 是贴吧客户端序列里不存在的版本号，会被服务端风控
 */
export const LATEST_VERSION: string = '12.41.7.1';

// ==================== API 域名 ====================

/** JSON 写接口域名（post / postMultipart 用）
 * 对齐 Android RetrofitTiebaApi.kt L179 OFFICIAL_TIEBA_API: "http://c.tieba.baidu.com/"
 * HTTPS 升级：HarmonyOS 默认强制 HTTPS，c.tieba.baidu.com 服务端支持 HTTPS
 */
export const APP_BASE_URL: string = 'https://c.tieba.baidu.com';
/** protobuf 端点域名（postProtobuf 用）
 * 对齐 Android RetrofitTiebaApi.kt L229 OFFICIAL_PROTOBUF_TIEBA_API: "https://tiebac.baidu.com/"
 */
export const PROTO_BASE_URL: string = 'https://tiebac.baidu.com';
/** web 端点域名（getWeb / postWeb 用，浏览器 UA；对齐 aiotieba http.py web cookie jar） */
export const WEB_BASE_URL: string = 'https://tieba.baidu.com';

// ==================== sofire 设备指纹注册（init_z_id）====================

/** sofire 设备指纹注册域名 */
export const SOFIRE_HOST: string = 'https://sofire.baidu.com';
/** sofire 应用 key（贴吧客户端公开协议常量，对齐 aiotieba） */
export const SOFIRE_APP_KEY: string = '200033';
/** sofire 应用 sec_key（贴吧客户端公开协议常量，对齐 aiotieba） */
export const SOFIRE_SEC_KEY: string = 'ea737e4f435b53786043369d2e5ace4f';
