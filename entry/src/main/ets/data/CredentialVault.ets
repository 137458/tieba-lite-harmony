import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';

const DOMAIN: number = 0x0000;
const BDUSS_ALIAS: string = 'tieba_lite_bduss';
const STOKEN_ALIAS: string = 'tieba_lite_stoken';

export class CredentialVault {
  private static encoder: util.TextEncoder = new util.TextEncoder();
  private static decoder: util.TextDecoder = new util.TextDecoder();

  static async saveBduss(value: string): Promise<void> {
    await CredentialVault.save(BDUSS_ALIAS, value);
  }

  static async saveStoken(value: string): Promise<void> {
    await CredentialVault.save(STOKEN_ALIAS, value);
  }

  static async getBduss(): Promise<string> {
    return await CredentialVault.get(BDUSS_ALIAS);
  }

  static async getStoken(): Promise<string> {
    return await CredentialVault.get(STOKEN_ALIAS);
  }

  static async clear(): Promise<void> {
    try {
      await CredentialVault.remove(BDUSS_ALIAS);
      await CredentialVault.remove(STOKEN_ALIAS);
    } catch (err) {
      throw new Error(`Credential vault clear failed: ${(err as Error).message}`);
    }
  }

  private static async save(alias: string, value: string): Promise<void> {
    const query: asset.AssetMap = CredentialVault.createAliasMap(alias);
    try {
      await asset.remove(query);
    } catch (err) {
      // 删除不存在的旧凭据是正常路径，其他错误继续交给新增操作报告。
    }
    try {
      const attributes: asset.AssetMap = CredentialVault.createAliasMap(alias);
      attributes.set(asset.Tag.SECRET, CredentialVault.encoder.encodeInto(value));
      attributes.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
      await asset.add(attributes);
    } catch (err) {
      throw new Error(`Credential vault save failed for ${alias}: ${(err as Error).message}`);
    }
  }

  private static async get(alias: string): Promise<string> {
    const query: asset.AssetMap = CredentialVault.createAliasMap(alias);
    query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
    try {
      const assets: asset.AssetMap[] = await asset.query(query);
      if (assets.length === 0) {
        return '';
      }
      const secret: Uint8Array | undefined = assets[0].get(asset.Tag.SECRET) as Uint8Array | undefined;
      if (secret === undefined) {
        return '';
      }
      return CredentialVault.decoder.decodeToString(secret) ?? '';
    } catch (err) {
      // asset 子系统异常（安全服务未就绪、条目损坏、跨设备迁移失败等）与"未登录"
      // 在调用方看来同为空串，必须留 code 线索才能归因"升级后/重启后被登出"类问题。
      // 仅记录 alias 与错误码/消息，绝不记录凭证明文；返回值语义不变。
      const error = err as BusinessError;
      const code: number = (typeof error.code === 'number') ? error.code : -1;
      const msg: string = error.message && error.message.length > 0 ? error.message : 'unknown error';
      hilog.error(DOMAIN, 'testTag',
        'credential vault query failed for %{public}s: code=%{public}d, %{public}s', alias, code, msg);
      return '';
    }
  }

  private static async remove(alias: string): Promise<void> {
    const exists: boolean = await CredentialVault.has(alias);
    if (!exists) {
      return;
    }
    await asset.remove(CredentialVault.createAliasMap(alias));
  }

  private static async has(alias: string): Promise<boolean> {
    const query: asset.AssetMap = CredentialVault.createAliasMap(alias);
    query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
    const assets: asset.AssetMap[] = await asset.query(query);
    return assets.length > 0;
  }

  private static createAliasMap(alias: string): asset.AssetMap {
    const attributes: asset.AssetMap = new Map();
    attributes.set(asset.Tag.ALIAS, CredentialVault.encoder.encodeInto(alias));
    return attributes;
  }
}
