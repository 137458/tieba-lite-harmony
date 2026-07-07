// AppLinking 工具类（issue #109 A1 AppLinking）
// 提供 want.uri 解析 + 预留 AppLinking generateLink 接口
//
// 支持的 URI 格式（对齐 Android 原版 3 种 scheme）：
// 1. tblite://thread/{tid}              — 自定义 scheme，贴吧 Lite 内部跳转
// 2. com.baidu.tieba://unidispatch?...  — 百度官方 scheme（query 参数携带 tid）
// 3. https://tieba.baidu.com/p/{tid}    — 标准 web URL
//    http://tieba.baidu.com/p/{tid}     — 同上（http 协议）
//
// 解析优先级：
// 1. path 末尾数字（/p/123456 → 123456，/thread/123456 → 123456）
// 2. query 参数 tid / thread / threadId
// 3. 失败返回 null
//
// AGC AppLinking generateLink 预留：当前 AGC 未开通 AppLinking 服务，
// 调用 generateLink 会抛出友好错误，调用方应降级使用 https URL 分享。

import { url } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0000;
const TAG: string = 'AppLinkingUtil';

/** AppLinking 解析结果 */
export interface AppLinkingParseResult {
  /** 帖子 ID（解析失败为 0） */
  threadId: number;
  /** 是否只看楼主（query 参数 see_lz=1 时 true） */
  seeLz: boolean;
}

/**
 * 解析 want.uri 提取帖子 ID 和只看楼主标志
 * @param uri want.uri 字符串
 * @returns 解析结果，失败时 threadId=0
 */
export function parseAppLinkingUri(uri: string): AppLinkingParseResult {
  const empty: AppLinkingParseResult = { threadId: 0, seeLz: false };
  if (!uri || uri.length === 0) {
    return empty;
  }

  try {
    const urlObj: url.URL = url.URL.parseURL(uri);
    const pathname: string = urlObj.pathname;
    const params: url.URLSearchParams = urlObj.params;

    // 优先级 1：path 末尾数字
    // /p/123456 → 123456，/thread/123456 → 123456
    const tid: number = extractTidFromPath(pathname);
    if (tid > 0) {
      const seeLz: boolean = readSeeLzFromParams(params);
      hilog.info(DOMAIN, TAG, 'Parsed from path: tid=%{public}d, seeLz=%{public}s, uri=%{public}s',
        tid, String(seeLz), uri);
      return { threadId: tid, seeLz };
    }

    // 优先级 2：query 参数 tid / thread / threadId
    const queryTid: number = readTidFromParams(params);
    if (queryTid > 0) {
      const seeLz: boolean = readSeeLzFromParams(params);
      hilog.info(DOMAIN, TAG, 'Parsed from query: tid=%{public}d, seeLz=%{public}s, uri=%{public}s',
        queryTid, String(seeLz), uri);
      return { threadId: queryTid, seeLz };
    }

    hilog.warn(DOMAIN, TAG, 'Failed to parse tid from uri: %{public}s', uri);
    return empty;
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'parseAppLinkingUri exception: %{public}s, uri=%{public}s',
      JSON.stringify(err), uri);
    return empty;
  }
}

/**
 * 从 path 提取帖子 ID
 * 匹配模式：/p/{数字} 或 /thread/{数字} 或末尾 /{数字}
 * @returns tid，失败返回 0
 */
function extractTidFromPath(pathname: string): number {
  if (!pathname || pathname.length === 0) {
    return 0;
  }

  // 标准贴吧帖子 URL：/p/{tid}
  // 内部 tblite scheme：/thread/{tid}
  // 通用：末尾 /{数字}
  const segments: string[] = pathname.split('/').filter((s: string) => s.length > 0);
  if (segments.length === 0) {
    return 0;
  }

  const last: string = segments[segments.length - 1];
  const tid: number = Number(last);
  if (!Number.isNaN(tid) && tid > 0 && Number.isInteger(tid)) {
    return tid;
  }
  return 0;
}

/**
 * 从 query 参数读取 tid（支持 tid / thread / threadId 三种 key）
 * @returns tid，失败返回 0
 */
function readTidFromParams(params: url.URLSearchParams): number {
  if (!params) {
    return 0;
  }
  const keys: string[] = ['tid', 'thread', 'threadId'];
  for (let i: number = 0; i < keys.length; i++) {
    const value: string | null = params.get(keys[i]);
    if (value !== null && value.length > 0) {
      const tid: number = Number(value);
      if (!Number.isNaN(tid) && tid > 0 && Number.isInteger(tid)) {
        return tid;
      }
    }
  }
  return 0;
}

/**
 * 从 query 参数读取 see_lz 标志
 * see_lz=1 → true，其他 → false
 */
function readSeeLzFromParams(params: url.URLSearchParams): boolean {
  if (!params) {
    return false;
  }
  const value: string | null = params.get('see_lz');
  return value === '1' || value === 'true';
}

/**
 * 预留：调用 AGC AppLinking generateLink 生成长链接/短链接
 *
 * 当前 AGC 未开通 AppLinking 服务，调用会抛出错误。
 * 调用方应捕获并降级使用 https://tieba.baidu.com/p/{tid} 直接分享。
 *
 * @param threadId 帖子 ID
 * @param threadTitle 帖子标题（用于社交分享预览）
 * @returns AppLinking URL，AGC 未开通时抛出 Error
 */
export function generateAppLinkingUrl(threadId: number, threadTitle: string): string {
  // AGC 未开通 AppLinking 服务，直接抛错让调用方降级
  // 后续开通 AGC 后，此处替换为：
  //   import { appLinking } from '@kit.PurchaseKit';
  //   const link: appLinking.AppLinking = await appLinking.generateLink({...});
  //   return link.uri;
  throw new Error('AGC AppLinking service not configured. Please enable AppLinking in AGC Console and configure domain.');
}

/**
 * 构造标准 https 帖子 URL（用于分享）
 * @param threadId 帖子 ID
 * @param seeLz 是否只看楼主
 * @returns https://tieba.baidu.com/p/{tid}[?see_lz=1]
 */
export function buildThreadShareUrl(threadId: number, seeLz: boolean = false): string {
  if (seeLz) {
    return `https://tieba.baidu.com/p/${threadId}?see_lz=1`;
  }
  return `https://tieba.baidu.com/p/${threadId}`;
}
