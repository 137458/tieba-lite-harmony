import { webview } from '@kit.ArkWeb';
import { AppStorageManager } from './AppStorage';
import { CredentialVault } from './CredentialVault';

const LEGACY_CREDENTIAL_KEYS: string[] = ['bduss', 'stoken'];
const SESSION_CACHE_KEYS: string[] = [
  'tbs', 'cuid', 'baiduid', 'z_id', 'client_id', 'sample_id', 'tieba_uid',
  'uid', 'name', 'avatar', 'nickname'
];

export class AuthSessionManager {
  static async migrateLegacyCredentials(): Promise<string> {
    const storage: AppStorageManager = AppStorageManager.getInstance();
    const vaultBduss: string = await CredentialVault.getBduss();
    const vaultStoken: string = await CredentialVault.getStoken();
    const legacyBduss: string = await storage.getString('bduss', '');
    const legacyStoken: string = await storage.getString('stoken', '');

    if (legacyBduss.length > 0) {
      if (vaultBduss.length === 0) {
        await CredentialVault.saveBduss(legacyBduss);
      }
      await storage.remove('bduss');
    }
    if (legacyStoken.length > 0) {
      if (vaultStoken.length === 0) {
        await CredentialVault.saveStoken(legacyStoken);
      }
      await storage.remove('stoken');
    }

    if (vaultBduss.length > 0) {
      return vaultBduss;
    }
    return legacyBduss;
  }

  static async logout(): Promise<void> {
    const storage: AppStorageManager = AppStorageManager.getInstance();
    await storage.ensureReady();
    await AuthSessionManager.removeKeys(storage, LEGACY_CREDENTIAL_KEYS);
    webview.WebCookieManager.clearAllCookiesSync();
    await CredentialVault.clear();
    await AuthSessionManager.removeKeys(storage, SESSION_CACHE_KEYS);
  }

  private static async removeKeys(storage: AppStorageManager, keys: string[]): Promise<void> {
    for (let i: number = 0; i < keys.length; i++) {
      await storage.remove(keys[i]);
    }
  }
}
