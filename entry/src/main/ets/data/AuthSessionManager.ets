import { webview } from '@kit.ArkWeb';
import { TiebaAPI } from '../api/TiebaAPI';
import { AppStorageManager } from './AppStorage';
import { CredentialVault } from './CredentialVault';
import { connectLogin } from '../model/AppStorageV2Models';
import { StringPrefs, BooleanPrefs } from './PreferenceKeys';

const LEGACY_CREDENTIAL_KEYS: string[] = [StringPrefs.BDUSS.key, StringPrefs.STOKEN.key];
const CREDENTIAL_STORAGE_MIGRATION_KEY: string = BooleanPrefs.CREDENTIAL_NON_PERSISTENT_MIGRATED.key;
const SESSION_CACHE_KEYS: string[] = [
  StringPrefs.TBS.key, StringPrefs.CUID.key, StringPrefs.BAIDUID.key,
  StringPrefs.Z_ID.key, StringPrefs.CLIENT_ID.key, StringPrefs.SAMPLE_ID.key,
  StringPrefs.TIEBA_UID.key, StringPrefs.UID.key, StringPrefs.NAME.key,
  StringPrefs.AVATAR.key, StringPrefs.NICKNAME.key
];

export class AuthSessionManager {
  static async migrateLegacyCredentials(): Promise<string> {
    const storage: AppStorageManager = AppStorageManager.getInstance();
    const vaultBduss: string = await CredentialVault.getBduss();
    const vaultStoken: string = await CredentialVault.getStoken();
    const legacyBduss: string = await storage.getString(StringPrefs.BDUSS.key, '');
    const legacyStoken: string = await storage.getString(StringPrefs.STOKEN.key, '');
    let effectiveBduss: string = vaultBduss;
    let effectiveStoken: string = vaultStoken;

    if (legacyBduss.length > 0) {
      if (vaultBduss.length === 0) {
        await CredentialVault.saveBduss(legacyBduss);
        effectiveBduss = legacyBduss;
      }
      await storage.remove(StringPrefs.BDUSS.key);
    }
    if (legacyStoken.length > 0) {
      if (vaultStoken.length === 0) {
        await CredentialVault.saveStoken(legacyStoken);
        effectiveStoken = legacyStoken;
      }
      await storage.remove(StringPrefs.STOKEN.key);
    }

    const hasMigrated: boolean = await storage.getBoolean(CREDENTIAL_STORAGE_MIGRATION_KEY, false);
    if (!hasMigrated) {
      if (effectiveBduss.length > 0) {
        await CredentialVault.saveBduss(effectiveBduss);
      }
      if (effectiveStoken.length > 0) {
        await CredentialVault.saveStoken(effectiveStoken);
      }
      await storage.setBoolean(CREDENTIAL_STORAGE_MIGRATION_KEY, true);
    }
    return effectiveBduss;
  }

  static async logout(): Promise<void> {
    const storage: AppStorageManager = AppStorageManager.getInstance();
    await storage.ensureReady();
    await AuthSessionManager.removeKeys(storage, LEGACY_CREDENTIAL_KEYS);
    // H06：先清 vault 再删迁移标记——clear 中断（抛错）时标记保留，下次启动
    // migrateLegacyCredentials 会把 vault 残留凭证重新 save 并复位标记，
    // 避免原顺序（先删标记后清 vault）中断后呈现"凭证残留但标记已删"的半登出
    await CredentialVault.clear();
    await storage.remove(CREDENTIAL_STORAGE_MIGRATION_KEY);
    webview.WebCookieManager.clearAllCookiesSync();
    await AuthSessionManager.removeKeys(storage, SESSION_CACHE_KEYS);
  }

  /**
   * 登出编排（H06 收敛 SettingsPage/ProfilePage 的重复实现，行为以 ProfilePage 版本为准）
   * 序列：logout（vault 凭证/Cookie/会话缓存清理）→ 清网络层内存态凭证
   *       （setAuth + restoreTbs）→ 复位全局登录态（LoginState 置 false）
   * 路由跳转由调用方负责（SettingsPage→LoginPage / ProfilePage→参数目标页）；
   * 账号级偏好 littleTail 是否随登出清除属产品决策，本轮保持现状不清理
   */
  static async logoutAndReset(): Promise<void> {
    await AuthSessionManager.logout();
    TiebaAPI.setAuth('', '');
    TiebaAPI.restoreTbs('');
    const loginState = connectLogin();
    loginState.value = false;
  }

  private static async removeKeys(storage: AppStorageManager, keys: string[]): Promise<void> {
    for (let i: number = 0; i < keys.length; i++) {
      await storage.remove(keys[i]);
    }
  }
}
