import { HttpClient, HttpError } from '../net/HttpClient';
import { http } from '@kit.NetworkKit';
import { bundleManager } from '@kit.AbilityKit';
import { AppStorageManager } from '../data/AppStorage';

const GITHUB_RELEASES_API: string = 'https://api.github.com/repos/137458/tieba-lite-harmony/releases/latest';
const GITHUB_RELEASES_LIST_API: string = 'https://api.github.com/repos/137458/tieba-lite-harmony/releases?per_page=20';
const GITHUB_RELEASES_TAG_API: string = 'https://api.github.com/repos/137458/tieba-lite-harmony/releases/tags/';
const GITHUB_RELEASE_PAGE: string = 'https://github.com/137458/tieba-lite-harmony/releases/latest';
const REQUEST_TIMEOUT_MS: number = 15000;
const READ_UPDATE_VERSION_KEY: string = 'readUpdateVersion';

export class ReleaseInfo {
  tag_name: string = '';
  body: string = '';
  html_url: string = '';
  name: string = '';
  published_at: string = '';
  draft: boolean = false;
  prerelease: boolean = false;
}

export class VersionCompareResult {
  currentVersion: string = '';
  latestVersion: string = '';
  hasUpdate: boolean = false;
  releaseInfo: ReleaseInfo | null = null;
}

export class UpdateChecker {
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

  private static createReleaseInfo(data: string): ReleaseInfo {
    const json: Record<string, Object> = JSON.parse(data) as Record<string, Object>;
    const info: ReleaseInfo = new ReleaseInfo();
    info.tag_name = (json['tag_name'] as string) || '';
    info.body = (json['body'] as string) || '';
    info.html_url = (json['html_url'] as string) || GITHUB_RELEASE_PAGE;
    info.name = (json['name'] as string) || '';
    info.published_at = (json['published_at'] as string) || '';
    info.draft = (json['draft'] as boolean) || false;
    info.prerelease = (json['prerelease'] as boolean) || false;
    return info;
  }

  private static async fetchRelease(url: string): Promise<ReleaseInfo> {
    const client: HttpClient = HttpClient.getInstance();
    const headers: Record<string, string> = {
      'Accept': 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
      'User-Agent': 'TiebaLite-Harmony/UpdateChecker'
    };
    const response = await client.request({
      url: url,
      method: http.RequestMethod.GET,
      headers: headers,
      timeout: REQUEST_TIMEOUT_MS,
      expectDataType: http.HttpDataType.STRING
    });
    if (response.statusCode !== 200) {
      throw new HttpError(response.statusCode, `GitHub API returned ${response.statusCode}`);
    }
    return UpdateChecker.createReleaseInfo(response.data as string);
  }

  static async fetchLatestRelease(): Promise<ReleaseInfo> {
    return UpdateChecker.fetchRelease(GITHUB_RELEASES_API);
  }

  static selectLatestRelease(releases: ReleaseInfo[], includePrerelease: boolean): ReleaseInfo | null {
    let selected: ReleaseInfo | null = null;
    for (let i = 0; i < releases.length; i++) {
      const release: ReleaseInfo = releases[i];
      if (release.draft || (!includePrerelease && release.prerelease) || release.tag_name.length === 0) {
        continue;
      }
      if (selected === null || UpdateChecker.compareVersions(selected.tag_name, release.tag_name) > 0) {
        selected = release;
      }
    }
    return selected;
  }

  static async fetchLatestAvailableRelease(includePrerelease: boolean): Promise<ReleaseInfo> {
    if (!includePrerelease) {
      return UpdateChecker.fetchLatestRelease();
    }
    const client: HttpClient = HttpClient.getInstance();
    const response = await client.request({
      url: GITHUB_RELEASES_LIST_API,
      method: http.RequestMethod.GET,
      headers: {
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        'User-Agent': 'TiebaLite-Harmony/UpdateChecker'
      },
      timeout: REQUEST_TIMEOUT_MS,
      expectDataType: http.HttpDataType.STRING
    });
    if (response.statusCode !== 200) {
      throw new HttpError(response.statusCode, `GitHub API returned ${response.statusCode}`);
    }
    const rawList: Object[] = JSON.parse(response.data as string) as Object[];
    const releases: ReleaseInfo[] = [];
    for (let i = 0; i < rawList.length; i++) {
      releases.push(UpdateChecker.createReleaseInfo(JSON.stringify(rawList[i])));
    }
    const selected: ReleaseInfo | null = UpdateChecker.selectLatestRelease(releases, true);
    if (selected === null) {
      throw new Error('没有可用 Release');
    }
    return selected;
  }

  static async fetchReleaseByVersion(version: string): Promise<ReleaseInfo> {
    const normalizedVersion: string = UpdateChecker.normalizeVersion(version);
    if (normalizedVersion.length === 0) {
      throw new Error('版本号为空');
    }
    const tag: string = `v${normalizedVersion}`;
    return UpdateChecker.fetchRelease(GITHUB_RELEASES_TAG_API + encodeURIComponent(tag));
  }

  static compareVersions(current: string, latest: string): number {
    const currentVersion: string = UpdateChecker.normalizeVersion(current);
    const latestVersion: string = UpdateChecker.normalizeVersion(latest);
    const currentSplitIndex: number = currentVersion.indexOf('-');
    const latestSplitIndex: number = latestVersion.indexOf('-');
    const currentBase: string = currentSplitIndex >= 0 ? currentVersion.substring(0, currentSplitIndex) : currentVersion;
    const latestBase: string = latestSplitIndex >= 0 ? latestVersion.substring(0, latestSplitIndex) : latestVersion;
    const baseResult: number = UpdateChecker.compareVersionParts(currentBase, latestBase);
    if (baseResult !== 0) {
      return baseResult;
    }

    const currentPreRelease: string = currentSplitIndex >= 0 ? currentVersion.substring(currentSplitIndex + 1) : '';
    const latestPreRelease: string = latestSplitIndex >= 0 ? latestVersion.substring(latestSplitIndex + 1) : '';
    if (currentPreRelease.length === 0 && latestPreRelease.length === 0) {
      return 0;
    }
    if (currentPreRelease.length === 0) {
      return -1;
    }
    if (latestPreRelease.length === 0) {
      return 1;
    }
    return UpdateChecker.comparePreReleaseParts(currentPreRelease, latestPreRelease);
  }

  private static normalizeVersion(version: string): string {
    let normalized: string = version.trim();
    if (normalized.startsWith('v') || normalized.startsWith('V')) {
      normalized = normalized.substring(1);
    }
    return normalized;
  }

  private static compareVersionParts(current: string, latest: string): number {
    const currentParts: string[] = current.split('.');
    const latestParts: string[] = latest.split('.');
    const maxLength: number = Math.max(currentParts.length, latestParts.length);
    for (let i = 0; i < maxLength; i++) {
      const currentPart: string = i < currentParts.length ? currentParts[i] : '0';
      const latestPart: string = i < latestParts.length ? latestParts[i] : '0';
      const currentNumber: number = /^\d+$/.test(currentPart) ? Number(currentPart) : 0;
      const latestNumber: number = /^\d+$/.test(latestPart) ? Number(latestPart) : 0;
      if (latestNumber !== currentNumber) {
        return latestNumber - currentNumber;
      }
    }
    return 0;
  }

  private static comparePreReleaseParts(current: string, latest: string): number {
    const currentParts: string[] = current.split('.');
    const latestParts: string[] = latest.split('.');
    const maxLength: number = Math.max(currentParts.length, latestParts.length);
    for (let i = 0; i < maxLength; i++) {
      if (i >= currentParts.length) {
        return 1;
      }
      if (i >= latestParts.length) {
        return -1;
      }
      const currentPart: string = currentParts[i];
      const latestPart: string = latestParts[i];
      const currentIsNumber: boolean = /^\d+$/.test(currentPart);
      const latestIsNumber: boolean = /^\d+$/.test(latestPart);
      if (currentIsNumber && latestIsNumber) {
        const currentNumber: number = Number(currentPart);
        const latestNumber: number = Number(latestPart);
        if (latestNumber !== currentNumber) {
          return latestNumber - currentNumber;
        }
      } else if (currentIsNumber !== latestIsNumber) {
        return latestIsNumber ? -1 : 1;
      } else if (currentPart !== latestPart) {
        return latestPart > currentPart ? 1 : -1;
      }
    }
    return 0;
  }

  static async checkUpdate(): Promise<VersionCompareResult> {
    const currentVersion: string = UpdateChecker.getCurrentVersion();
    if (currentVersion.length === 0) {
      throw new Error('无法获取当前应用版本号');
    }
    await AppStorageManager.getInstance().ensureReady();
    const includePrerelease: boolean = await AppStorageManager.getInstance().getBoolean('receivePrereleaseUpdates', false);
    const releaseInfo: ReleaseInfo = await UpdateChecker.fetchLatestAvailableRelease(includePrerelease);
    const result: VersionCompareResult = new VersionCompareResult();
    result.currentVersion = currentVersion;
    result.latestVersion = releaseInfo.tag_name;
    result.releaseInfo = releaseInfo;
    result.hasUpdate = UpdateChecker.compareVersions(currentVersion, releaseInfo.tag_name) > 0;
    return result;
  }

  static async getReadUpdateVersion(): Promise<string> {
    try {
      await AppStorageManager.getInstance().ensureReady();
      return await AppStorageManager.getInstance().getString(READ_UPDATE_VERSION_KEY, '');
    } catch (err) {
      console.error(`[UpdateChecker] getReadUpdateVersion failed: ${(err as Error).message}`);
      return '';
    }
  }

  static async setReadUpdateVersion(version: string): Promise<void> {
    try {
      await AppStorageManager.getInstance().ensureReady();
      await AppStorageManager.getInstance().setString(READ_UPDATE_VERSION_KEY, version);
    } catch (err) {
      console.error(`[UpdateChecker] setReadUpdateVersion failed: ${(err as Error).message}`);
    }
  }

  static async shouldShowUpdateNotice(): Promise<boolean> {
    const currentVersion: string = UpdateChecker.getCurrentVersion();
    if (currentVersion.length === 0) {
      return false;
    }
    const readVersion: string = await UpdateChecker.getReadUpdateVersion();
    return readVersion !== currentVersion;
  }

  static async markCurrentVersionRead(): Promise<void> {
    const currentVersion: string = UpdateChecker.getCurrentVersion();
    if (currentVersion.length > 0) {
      await UpdateChecker.setReadUpdateVersion(currentVersion);
    }
  }
}
