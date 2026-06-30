import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect } from '@ohos/hypium';
import { CryptoUtil } from '../../../main/ets/utils/CryptoUtil';

/**
 * CryptoUtil 设备测试（需在设备/模拟器上运行）
 * 覆盖 generateSign / generateCuid / base64 / md5 等 cryptoFramework 依赖方法
 */
export default function cryptoUtilTest() {
  describe('CryptoUtilMd5', () => {
    beforeAll(() => {});
    beforeEach(() => {});
    afterEach(() => {});
    afterAll(() => {});

    it('md5_hello', 0, async () => {
      // MD5("hello") = 5d41402abc4b2a76b9719d911017c592
      const result: string = await CryptoUtil.md5('hello');
      expect(result).assertEqual('5d41402abc4b2a76b9719d911017c592');
    });

    it('md5_empty', 0, async () => {
      // MD5("") = d41d8cd98f00b204e9800998ecf8427e
      const result: string = await CryptoUtil.md5('');
      expect(result).assertEqual('d41d8cd98f00b204e9800998ecf8427e');
    });

    it('md5_test', 0, async () => {
      // MD5("test") = 098f6bcd4621d373cade4e832627b4f6
      const result: string = await CryptoUtil.md5('test');
      expect(result).assertEqual('098f6bcd4621d373cade4e832627b4f6');
    });
  });

  describe('CryptoUtilGenerateSign', () => {
    it('generateSign_emptyParams', 0, async () => {
      // 空参数 + 'test' secret → MD5('test') = 098f6bcd4621d373cade4e832627b4f6
      const params: Record<string, string> = {};
      const result: string = await CryptoUtil.generateSign(params, 'test');
      expect(result).assertEqual('098f6bcd4621d373cade4e832627b4f6');
    });

    it('generateSign_sortedParams', 0, async () => {
      // 验证参数按 key 排序：{b:'2', a:'1'} → 'a=1b=2' + secret
      const params: Record<string, string> = {
        'b': '2',
        'a': '1'
      };
      const result: string = await CryptoUtil.generateSign(params, '');
      // MD5('a=1b=2') = ?
      // 先验证长度 32（MD5 hex）
      expect(result.length).assertEqual(32);
      // 验证与直接 MD5('a=1b=2') 一致
      const expected: string = await CryptoUtil.md5('a=1b=2');
      expect(result).assertEqual(expected);
    });

    it('generateSign_noEmptyFilter', 0, async () => {
      // 验证空值参数也参与签名（对齐 aiotieba sign.py，无空值过滤）
      // params={'a':''} + secret='test' → MD5('a=test')
      const paramsWithEmpty: Record<string, string> = {
        'a': ''
      };
      const resultWithEmpty: string = await CryptoUtil.generateSign(paramsWithEmpty, 'test');
      const expected: string = await CryptoUtil.md5('a=test');
      expect(resultWithEmpty).assertEqual(expected);
    });

    it('generateSign_emptyValueDiffersFromNoKey', 0, async () => {
      // 验证 {a:''} + 'test' 与 {} + 'test' 产生不同签名
      // 前者 → MD5('a=test')，后者 → MD5('test')
      const paramsWithEmpty: Record<string, string> = {
        'a': ''
      };
      const paramsEmpty: Record<string, string> = {};
      const r1: string = await CryptoUtil.generateSign(paramsWithEmpty, 'test');
      const r2: string = await CryptoUtil.generateSign(paramsEmpty, 'test');
      expect(r1).assertNotEqual(r2);
    });
  });

  describe('CryptoUtilBase64', () => {
    it('base64Encode_hello', 0, () => {
      expect(CryptoUtil.base64Encode('hello')).assertEqual('aGVsbG8=');
    });

    it('base64Encode_empty', 0, () => {
      expect(CryptoUtil.base64Encode('')).assertEqual('');
    });

    it('base64Decode_hello', 0, () => {
      expect(CryptoUtil.base64Decode('aGVsbG8=')).assertEqual('hello');
    });

    it('base64_roundTrip_ascii', 0, () => {
      const original: string = 'Hello Tieba! Test 123';
      const encoded: string = CryptoUtil.base64Encode(original);
      const decoded: string = CryptoUtil.base64Decode(encoded);
      expect(decoded).assertEqual(original);
    });

    it('base64_roundTrip_unicode', 0, () => {
      // 验证 UTF-8 多字节字符的往返
      const original: string = '你好世界 tieba';
      const encoded: string = CryptoUtil.base64Encode(original);
      const decoded: string = CryptoUtil.base64Decode(encoded);
      expect(decoded).assertEqual(original);
    });

    it('base64Encode_knownVector', 0, () => {
      // "Man" → "TWFu"（Base64 标准测试向量）
      expect(CryptoUtil.base64Encode('Man')).assertEqual('TWFu');
    });

    it('base64Encode_noPadding_2bytes', 0, () => {
      // "He" → "SGU="（2 字节 → 4 字符，1 个填充）
      expect(CryptoUtil.base64Encode('He')).assertEqual('SGU=');
    });
  });

  describe('CryptoUtilBytesToHex', () => {
    it('bytesToHex_known', 0, () => {
      const input: Uint8Array = new Uint8Array([0x5d, 0x41, 0x40, 0x2a]);
      expect(CryptoUtil.bytesToHex(input)).assertEqual('5d41402a');
    });

    it('bytesToHex_leadingZero', 0, () => {
      // 验证前导零填充：0x0a → "0a" 而非 "a"
      const input: Uint8Array = new Uint8Array([0x0a, 0xff]);
      expect(CryptoUtil.bytesToHex(input)).assertEqual('0aff');
    });

    it('bytesToHex_empty', 0, () => {
      const input: Uint8Array = new Uint8Array(0);
      expect(CryptoUtil.bytesToHex(input)).assertEqual('');
    });
  });

  describe('CryptoUtilGenerateCuid', () => {
    it('generateCuid_length42', 0, async () => {
      const cuid: string = await CryptoUtil.generateCuid('abcdef0123456789abcdef0123456789');
      expect(cuid.length).assertEqual(42);
    });

    it('generateCuid_format', 0, async () => {
      const cuid: string = await CryptoUtil.generateCuid('abcdef0123456789abcdef0123456789');
      // 格式：32 大写 hex + "|V" + 8 base32 字符
      const separatorIdx: number = cuid.indexOf('|V');
      expect(separatorIdx).assertEqual(32);
      expect(cuid.length).assertEqual(42);

      const md5Part: string = cuid.substring(0, 32);
      const base32Part: string = cuid.substring(34);

      // 验证前 32 字符是大写 hex
      for (let i: number = 0; i < md5Part.length; i++) {
        const c: string = md5Part.charAt(i);
        const isHex: boolean = (c >= '0' && c <= '9') || (c >= 'A' && c <= 'F');
        expect(isHex).assertTrue();
      }

      // 验证后 8 字符是 Base32 字符（A-Z, 2-7）
      expect(base32Part.length).assertEqual(8);
      for (let i: number = 0; i < base32Part.length; i++) {
        const c: string = base32Part.charAt(i);
        const isBase32: boolean = (c >= 'A' && c <= 'Z') || (c >= '2' && c <= '7');
        expect(isBase32).assertTrue();
      }
    });

    it('generateCuid_deterministic', 0, async () => {
      const androidId: string = 'abcdef0123456789abcdef0123456789';
      const cuid1: string = await CryptoUtil.generateCuid(androidId);
      const cuid2: string = await CryptoUtil.generateCuid(androidId);
      expect(cuid1).assertEqual(cuid2);
    });

    it('generateCuid_differentInputs', 0, async () => {
      const cuid1: string = await CryptoUtil.generateCuid('abcdef0123456789abcdef0123456789');
      const cuid2: string = await CryptoUtil.generateCuid('9876543210fedcba9876543210fedcba');
      expect(cuid1).assertNotEqual(cuid2);
    });

    it('generateCuid_md5PartMatches', 0, async () => {
      // 验证前 32 字符 = MD5("com.baidu" + androidId).uppercase()
      const androidId: string = 'abcdef0123456789abcdef0123456789';
      const cuid: string = await CryptoUtil.generateCuid(androidId);
      const expectedMd5: string = (await CryptoUtil.md5(`com.baidu${androidId}`)).toUpperCase();
      expect(cuid.substring(0, 32)).assertEqual(expectedMd5);
    });
  });

  describe('CryptoUtilGenerateZid', () => {
    it('generateZid_format', 0, () => {
      const zid: string = CryptoUtil.generateZid();
      // 格式：{timestamp}_{8 chars}
      const underscoreIdx: number = zid.indexOf('_');
      expect(underscoreIdx > 0).assertTrue();
      const parts: string[] = zid.split('_');
      expect(parts.length).assertEqual(2);
      expect(parts[1].length).assertEqual(8);
    });

    it('generateZid_unique', 0, () => {
      const zid1: string = CryptoUtil.generateZid();
      const zid2: string = CryptoUtil.generateZid();
      // 由于含时间戳和随机数，两次调用应不同（极小概率相同）
      expect(zid1).assertNotEqual(zid2);
    });
  });
}
