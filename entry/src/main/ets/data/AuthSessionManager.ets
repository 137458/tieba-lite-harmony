import { webview } from '@kit.ArkWeb';
import { AppStorageManager } from './AppStorage';
import { CredentialVault } from './CredentialVault';

const LEGACY_CREDENTIAL_KEYS: string[] = ['bduss', 'stoken'];
const CREDENTIAL_STORAGE_MIGRATION_KEY: string = 'credentialNonPersistentMigrated';
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
    let effectiveBduss: string = vaultBduss;
    let effectiveStoken: string = vaultStoken;

    if (legacyBduss.length > 0) {
      if (vaultBduss.length === 0) {
        await CredentialVault.saveBduss(legacyBduss);
        effectiveBduss = legacyBduss;
      }
      await storage.remove('bduss');
    }
    if (legacyStoken.length > 0) {
      if (vaultStoken.length === 0) {
        await CredentialVault.saveStoken(legacyStoken);
        effectiveStoken = legacyStoken;
      }
      await storage.remove('stoken');
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
    await storage.remove(CREDENTIAL_STORAGE_MIGRATION_KEY);
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
