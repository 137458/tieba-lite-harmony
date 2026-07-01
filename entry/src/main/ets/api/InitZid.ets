import { HttpClient } from '../net/HttpClient';
import { util } from '@kit.ArkTS';
import { CryptoUtil } from '../utils/CryptoUtil';
import { STABLE_VERSION } from '../net/TiebaHttpClient';

/**
 * init_z_id 流程：向 sofire.baidu.com 注册设备指纹，获取 z_id
 *
 * 对齐 aiotieba api/init_z_id/_api.py：
 *   1. 计算 xyus = MD5(android_id + uuid).hex().upper() + "|0"
 *   2. 计算 xyus_md5_str = MD5(xyus).hex() （小写）
 *   3. 构造 params = {"module_section": [{"zid": xyus}]}
 *   4. req_body = gzip(JSON, level=6)
 *   5. req_body_aes = AES_CBC_PKCS7_encrypt(req_body, aes_cbc_sec_key, IV=0)
 *   6. req_body_md5 = MD5(req_body).digest() （16 raw 字节）
 *   7. payload = req_body_aes + req_body_md5
 *   8. URL = /c/11/z/100/{app_key}/{ts}/{MD5(app_key+ts+sec_key).hex()}?skey={base64(rc4_42(xyus_md5_str, aes_cbc_sec_key))}
 *   9. POST，headers: x-device-id={xyus_md5_str}, User-Agent=x6/{app_key}/{STABLE_VERSION}/4.4.1.3
 *  10. 响应 JSON: { skey: base64, data: base64 }
 *  11. res_aes_sec_key = rc4_42(xyus_md5_str, base64decode(skey))
 *  12. decrypted = AES_CBC_NoPadding_decrypt(base64decode(data), res_aes_sec_key, IV=0)
 *  13. 移除末尾 16 字节 md5 → PKCS7 unpad → gunzip → JSON
 *  14. zid = res_json.token
 */

const SOFIRE_HOST: string = 'https://sofire.baidu.com';
const APP_KEY: string = '200033';
const SEC_KEY: string = 'ea737e4f435b53786043369d2e5ace4f';

/** sofire 响应 JSON 结构 */
interface SofireResponse {
  skey: string;
  data: string;
}

/** init_z_id 解密后的 JSON 结构 */
interface ZidTokenResponse {
  token: string;
}

/** init_z_id 请求 module_section 数组项 */
interface ZidModuleSection {
  zid: string;
}

/** init_z_id 请求 JSON 顶层结构 */
interface ZidRequestBody {
  module_section: ZidModuleSection[];
}

/**
 * 执行 init_z_id 流程，返回 z_id
 *
 * @param androidId 16 字符小写 hex
 * @param uuid 36 字符 UUID v4
 * @param aesCbcSecKey 16 字节 AES-CBC 密钥
 * @returns z_id 字符串
 */
export async function initZid(
  androidId: string,
  uuid: string,
  aesCbcSecKey: Uint8Array
): Promise<string> {
  // step 1: xyus = MD5(android_id + uuid).hex().upper() + "|0"
  const xyusRaw: string = androidId + uuid;
  const xyusMd5Upper: string = (await CryptoUtil.md5(xyusRaw)).toUpperCase();
  const xyus: string = `${xyusMd5Upper}|0`;

  // step 2: xyus_md5_str = MD5(xyus).hex() （小写）
  const xyusMd5Str: string = await CryptoUtil.md5(xyus);

  // step 3: 当前时间戳（秒）
  const ts: string = Math.floor(Date.now() / 1000).toString();

  // step 4: 构造请求 JSON
  // 对齐 aiotieba pack_json：separators=(',', ':') 无空格
  const zidSection: ZidModuleSection = { zid: xyus };
  const reqBodyObj: ZidRequestBody = { module_section: [zidSection] };
  const reqJson: string = JSON.stringify(reqBodyObj);

  // step 5: gzip 压缩（level=6, mtime=0）
  const encoder: util.TextEncoder = new util.TextEncoder();
  const reqBody: Uint8Array = await CryptoUtil.gzipCompress(encoder.encodeInto(reqJson));

  // step 6: AES-CBC-PKCS7 加密
  const reqBodyAes: Uint8Array = await CryptoUtil.aesCbcEncrypt(reqBody, aesCbcSecKey);

  // step 7: MD5 摘要（16 raw 字节）
  const reqBodyMd5: Uint8Array = await CryptoUtil.md5Bytes(reqBody);

  // step 8: payload = req_body_aes + req_body_md5
  const payload: Uint8Array = new Uint8Array(reqBodyAes.length + reqBodyMd5.length);
  payload.set(reqBodyAes, 0);
  payload.set(reqBodyMd5, reqBodyAes.length);

  // step 9: 构造 URL
  // path_combine_md5 = MD5(app_key + ts + sec_key).hex()
  const pathCombine: string = APP_KEY + ts + SEC_KEY;
  const pathCombineMd5: string = await CryptoUtil.md5(pathCombine);

  // skey = base64(rc4_42(xyus_md5_str, aes_cbc_sec_key))
  const skeyEncrypted: Uint8Array = CryptoUtil.rc442(xyusMd5Str, aesCbcSecKey);
  const skeyB64: string = CryptoUtil.bytesToBase64(skeyEncrypted);

  const url: string = `${SOFIRE_HOST}/c/11/z/100/${APP_KEY}/${ts}/${pathCombineMd5}?skey=${encodeURIComponent(skeyB64)}`;

  // step 10: POST 请求
  const headers: Record<string, string> = {
    'Content-Type': 'application/x-www-form-urlencoded',
    'x-device-id': xyusMd5Str,
    'User-Agent': `x6/${APP_KEY}/${STABLE_VERSION}/4.4.1.3`,
    'x-plu-ver': 'x6/4.4.1.3'
  };

  const httpClient: HttpClient = HttpClient.getInstance();
  const response = await httpClient.post(url, payload.buffer, headers);

  if (response.statusCode !== 200) {
    throw new Error(`init_z_id 失败：HTTP ${response.statusCode}`);
  }

  if (typeof response.data !== 'string') {
    throw new Error('init_z_id 失败：响应不是字符串');
  }

  // step 11: 解析响应 JSON
  let resJson: SofireResponse;
  try {
    resJson = JSON.parse(response.data) as SofireResponse;
  } catch (err) {
    throw new Error('init_z_id 失败：响应 JSON 解析失败 - ' + (err as Error).message);
  }

  if (!resJson.skey || !resJson.data) {
    throw new Error('init_z_id 失败：响应缺少 skey 或 data 字段');
  }

  // step 12-17: 解密链统一 try-catch（AES/gzip/PKCS7/JSON 任一步抛错转友好信息）
  // 之前 AES 解密/gzip 解压/PKCS7 unpad 失败会抛底层错误（如 "Invalid PKCS7 padding length"），
  // 用户无法理解，统一转为 "init_z_id 失败：解密链异常" 便于诊断
  let decrypted: Uint8Array;
  let finalJson: ZidTokenResponse;
  try {
    // step 12: 派生响应 AES 密钥
    const resQuerySkey: Uint8Array = CryptoUtil.base64ToBytes(resJson.skey);
    const resAesSecKey: Uint8Array = CryptoUtil.rc442(xyusMd5Str, resQuerySkey);

    // step 13: AES-CBC-NoPadding 解密
    const resData: Uint8Array = CryptoUtil.base64ToBytes(resJson.data);
    decrypted = await CryptoUtil.aesCbcDecryptRaw(resData, resAesSecKey);

    // step 14: 移除末尾 16 字节 md5
    if (decrypted.length < 16) {
      throw new Error('init_z_id 失败：解密数据过短');
    }
    const withoutMd5: Uint8Array = decrypted.subarray(0, decrypted.length - 16);

    // step 15: PKCS7 unpad
    const unpadded: Uint8Array = CryptoUtil.pkcs7Unpad(withoutMd5);

    // step 16: gunzip
    const decompressed: Uint8Array = await CryptoUtil.gzipDecompress(unpadded);

    // step 17: 解析最终 JSON，提取 token
    const decoder: util.TextDecoder = new util.TextDecoder();
    const finalJsonStr: string = decoder.decodeWithStream(decompressed);
    finalJson = JSON.parse(finalJsonStr) as ZidTokenResponse;
  } catch (err) {
    // 解密链异常（AES/gzip/PKCS7/JSON 任意环节失败），转友好错误信息
    throw new Error(`init_z_id 失败：解密链异常 - ${(err as Error).message}`);
  }

  if (!finalJson.token) {
    throw new Error('init_z_id 失败：响应缺少 token 字段');
  }

  return finalJson.token;
}
