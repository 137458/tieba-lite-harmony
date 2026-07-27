// 应用更新检查工具（GitHub Releases API）
// 数据源：api.github.com/repos/137458/tieba-lite-harmony/releases/latest
// 返回 Release 的 tag_name（版本号）和 body（更新公告）
// 速率限制：未认证 60 次/小时/IP（启动检查 + 手动检查足够）
// 网络环境：api.github.com 在大陆可能不稳定，请求失败静默处理（启动检查）/提示用户（手动检查）

import { HttpClient, HttpError } from '../net/HttpClient';
import { http } from '@kit.NetworkKit';
import { bundleManager } from '@kit.AbilityKit';
import { AppStorageManager } from '../data/AppStorage';

// GitHub Releases API 地址（获取最新 Release）
const GITHUB_RELEASES_API: string = 'https://api.github.com/repos/137458/tieba-lite-harmony/releases/latest';
// GitHub Release 页面地址（用于"前往查看"按钮跳转浏览器）
const GITHUB_RELEASE_PAGE: string = 'https://github.com/137458/tieba-lite-harmony/releases/latest';
// 请求超时（ms）：GitHub API 在大陆可能慢，给 15s
const REQUEST_TIMEOUT_MS: number = 15000;
// 已读更新公告的版本号持久化 key（记录用户已读 Release 的 tag_name）
const READ_UPDATE_VERSION_KEY: string = 'readUpdateVersion';

/**
 * GitHub Release 信息（仅提取需要的字段）
 */
export class ReleaseInfo {
  /** Release tag（如 "v1.0.0" 或 "1.0.0"） */
  tag_name: string = '';
  /** Release body（Markdown 格式的更新公告） */
  body: string = '';
  /** Release HTML 页面地址 */
  html_url: string = '';
  /** Release 名称（如 "v1.0.0 - 重大更新"） */
  name: string = '';
  /** Release 发布时间（ISO 8601 格式字符串） */
  published_at: string = '';
}

/**
 * 版本比较结果
 */
export class VersionCompareResult {
  /** 当前应用版本号 */
  currentVersion: string = '';
  /** 最新 Release 版本号 */
  latestVersion: string = '';
  /** 是否有新版本 */
  hasUpdate: boolean = false;
  /** Release 信息 */
  releaseInfo: ReleaseInfo | null = null;
}

export class UpdateChecker {
  /**
   * 获取当前应用版本号（versionName）
   * 失败时返回空字符串
   */
  static getCurrentVersion(): string {
    try {
      const bundleInfo: bundleManager.BundleInfo = bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT
      );
      return bundleInfo.versionName;
    } catch (err) {
      console.error(`[UpdateChecker] getCurrentVersion failed: ${(err as Error).message}`);
      return '';
    }
  }

  /**
   * 获取最新 Release 信息
   * 调用 GitHub Releases API，失败时抛 HttpError
   */
  static async fetchLatestRelease(): Promise<ReleaseInfo> {
    const client: HttpClient = HttpClient.getInstance();
    const headers: Record<string, string> = {
      'Accept': 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
      'User-Agent': 'TiebaLite-Harmony/UpdateChecker'
    };
    const response = await client.request({
      url: GITHUB_RELEASES_API,
      method: http.RequestMethod.GET,
      headers: headers,
      timeout: REQUEST_TIMEOUT_MS,
      expectDataType: http.HttpDataType.STRING
    });
    if (response.statusCode !== 200) {
      throw new HttpError(response.statusCode, `GitHub API returned ${response.statusCode}`);
    }
    const data: string = response.data as string;
    const json: Record<string, Object> = JSON.parse(data) as Record<string, Object>;
    const info: ReleaseInfo = new ReleaseInfo();
    info.tag_name = (json['tag_name'] as string) || '';
    info.body = (json['body'] as string) || '';
    info.html_url = (json['html_url'] as string) || GITHUB_RELEASE_PAGE;
    info.name = (json['name'] as string) || '';
    info.published_at = (json['published_at'] as string) || '';
    return info;
  }

  /**
   * 比较版本号（语义化版本，如 "1.0.0" 或 "v1.0.0"）
   * 去掉前缀 "v" 后按 "." 分段比较数字大小
   * @returns 正数表示 latest > current（有更新），0 表示相等，负数表示 latest < current
   */
  static compareVersions(current: string, latest: string): number {
    const normalize = (v: string): string => {
      let s: string = v.trim();
      if (s.startsWith('v') || s.startsWith('V')) {
        s = s.substring(1);
      }
      return s;
    };
    const cur: string = normalize(current);
    const lat: string = normalize(latest);
    const curParts: string[] = cur.split('.');
    const latParts: string[] = lat.split('.');
    const maxLen: number = Math.max(curParts.length, latParts.length);
    for (let i = 0; i < maxLen; i++) {
      const curNum: number = i < curParts.length ? parseInt(curParts[i], 10) || 0 : 0;
      const latNum: number = i < latParts.length ? parseInt(latParts[i], 10) || 0 : 0;
      if (latNum !== curNum) {
        return latNum - curNum;
      }
    }
    return 0;
  }

  /**
   * 检查更新（综合调用：获取当前版本 + 拉取最新 Release + 比较）
   * 失败时抛异常，调用方自行处理（启动检查静默 / 手动检查提示）
   */
  static async checkUpdate(): Promise<VersionCompareResult> {
    const currentVersion: string = UpdateChecker.getCurrentVersion();
    if (currentVersion.length === 0) {
      throw new Error('无法获取当前应用版本号');
    }
    const releaseInfo: ReleaseInfo = await UpdateChecker.fetchLatestRelease();
    const result: VersionCompareResult = new VersionCompareResult();
    result.currentVersion = currentVersion;
    result.latestVersion = releaseInfo.tag_name;
    result.releaseInfo = releaseInfo;
    result.hasUpdate = UpdateChecker.compareVersions(currentVersion, releaseInfo.tag_name) > 0;
    return result;
  }

  /**
   * 获取已读更新公告的版本号（持久化）
   * 用于判断本次启动是否需要弹窗显示更新公告
   */
  static async getReadUpdateVersion(): Promise<string> {
    try {
      await AppStorageManager.getInstance().ensureReady();
      return await AppStorageManager.getInstance().getString(READ_UPDATE_VERSION_KEY, '');
    } catch (err) {
      console.error(`[UpdateChecker] getReadUpdateVersion failed: ${(err as Error).message}`);
      return '';
    }
  }

  /**
   * 标记某版本号的更新公告为已读（持久化）
   * 用户关闭更新公告弹窗后调用，避免下次启动重复弹窗
   */
  static async setReadUpdateVersion(version: string): Promise<void> {
    try {
      await AppStorageManager.getInstance().ensureReady();
      await AppStorageManager.getInstance().setString(READ_UPDATE_VERSION_KEY, version);
    } catch (err) {
      console.error(`[UpdateChecker] setReadUpdateVersion failed: ${(err as Error).message}`);
    }
  }

  /**
   * 判断是否需要显示更新公告弹窗
   * 条件：当前版本号与已读版本号不同（应用更新后首次启动）
   * @returns 需要显示返回 true，否则 false
   */
  static async shouldShowUpdateNotice(): Promise<boolean> {
    const currentVersion: string = UpdateChecker.getCurrentVersion();
    if (currentVersion.length === 0) {
      return false;
    }
    const readVersion: string = await UpdateChecker.getReadUpdateVersion();
    // 已读版本与当前版本不同，说明应用刚更新，需要显示公告
    return readVersion !== currentVersion;
  }

  /**
   * 标记当前版本更新公告为已读
   * 应用启动后显示更新公告，用户关闭后调用
   */
  static async markCurrentVersionRead(): Promise<void> {
    const currentVersion: string = UpdateChecker.getCurrentVersion();
    if (currentVersion.length > 0) {
      await UpdateChecker.setReadUpdateVersion(currentVersion);
    }
  }
}
