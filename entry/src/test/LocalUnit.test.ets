import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect } from '@ohos/hypium';
import { crc32 } from '../../main/ets/utils/helios/CRC32';
import { xxhash32 } from '../../main/ets/utils/helios/XXHash32';
import { base32Encode } from '../../main/ets/utils/helios/Base32';
import { HashResult } from '../../main/ets/utils/helios/HashResult';
import { heliosHash } from '../../main/ets/utils/helios/Hasher';
import { dedupByKey } from '../../main/ets/viewmodel/BaseViewModel';

/**
 * ASCII 字符串转 Uint8Array
 * 本地单元测试环境无法依赖 @kit.ArkTS 的 TextEncoder，使用纯 JS 实现
 */
function toBytes(str: string): Uint8Array {
  const bytes: Uint8Array = new Uint8Array(str.length);
  for (let i: number = 0; i < str.length; i++) {
    bytes[i] = str.charCodeAt(i) & 0xFF;
  }
  return bytes;
}

export default function localUnitTest() {
  describe('CRC32', () => {
    beforeAll(() => {});
    beforeEach(() => {});
    afterEach(() => {});
    afterAll(() => {});

    it('crc32_empty', 0, () => {
      const input: Uint8Array = new Uint8Array(0);
      expect(crc32(input, 0, 0)).assertEqual(0);
    });

    it('crc32_standardCheckValue', 0, () => {
      // CRC32("123456789") = 0xCBF43926（标准校验值）
      const input: Uint8Array = toBytes('123456789');
      expect(crc32(input, 0, 9)).assertEqual(0xCBF43926);
    });

    it('crc32_hello', 0, () => {
      // CRC32("hello") = 0x3610A686
      const input: Uint8Array = toBytes('hello');
      expect(crc32(input, 0, 5)).assertEqual(0x3610A686);
    });
  });

  describe('XXHash32', () => {
    it('xxhash32_empty', 0, () => {
      // XXH32("", seed=0) = 0x02CC5D05（官方测试向量）
      const input: Uint8Array = new Uint8Array(0);
      expect(xxhash32(input, 0, 0)).assertEqual(0x02CC5D05);
    });

    it('xxhash32_deterministic', 0, () => {
      const input: Uint8Array = toBytes('hello');
      const h1: number = xxhash32(input, 0, 5);
      const h2: number = xxhash32(input, 0, 5);
      expect(h1).assertEqual(h2);
    });

    it('xxhash32_differentInputs', 0, () => {
      const h1: number = xxhash32(toBytes('hello'), 0, 5);
      const h2: number = xxhash32(toBytes('world'), 0, 5);
      expect(h1).assertNotEqual(h2);
    });

    it('xxhash32_isUnsigned32', 0, () => {
      // 验证返回值在无符号 32 位范围内
      const input: Uint8Array = toBytes('test input for xxhash');
      const h: number = xxhash32(input, 0, input.length);
      expect(h >= 0).assertTrue();
      expect(h <= 0xFFFFFFFF).assertTrue();
    });
  });

  describe('Base32', () => {
    it('base32Encode_5bytes', 0, () => {
      // Base32("hello") = "NBSWY3DP"（5 字节 → 8 字符，无填充）
      const input: Uint8Array = toBytes('hello');
      expect(base32Encode(input)).assertEqual('NBSWY3DP');
    });

    it('base32Encode_1byte', 0, () => {
      // helios 变体：1 字节 → 2 字符（无填充）
      // [0x68] 二进制 01101000 → 5 位组 [01101, 00000] → 索引 [13, 0] → "NA"
      const input: Uint8Array = new Uint8Array([0x68]);
      expect(base32Encode(input)).assertEqual('NA');
    });

    it('base32Encode_empty', 0, () => {
      const input: Uint8Array = new Uint8Array(0);
      expect(base32Encode(input)).assertEqual('');
    });

    it('base32Encode_10bytes', 0, () => {
      // 10 字节 → 2 组 × 8 字符 = 16 字符
      const input: Uint8Array = toBytes('helloworld');
      const result: string = base32Encode(input);
      expect(result.length).assertEqual(16);
      // 前 8 字符应等于 base32Encode("hello")
      expect(result.substring(0, 8)).assertEqual('NBSWY3DP');
    });
  });

  describe('HashResult', () => {
    it('initialState_allOnes', 0, () => {
      // 初始状态：40 位全 1 → 5 字节全 0xFF
      const result: HashResult = new HashResult();
      const bytes: Uint8Array = result.toBytes();
      expect(bytes.length).assertEqual(5);
      expect(bytes[0]).assertEqual(0xFF);
      expect(bytes[1]).assertEqual(0xFF);
      expect(bytes[2]).assertEqual(0xFF);
      expect(bytes[3]).assertEqual(0xFF);
      expect(bytes[4]).assertEqual(0xFF);
    });

    it('update_AND_zeros', 0, () => {
      // 用 0 AND 位 [8..40) → 上 32 位变 0，下 8 位保持 1
      const result: HashResult = new HashResult();
      result.update(0x00000000, 8, 32, 0); // flag=0: AND
      const bytes: Uint8Array = result.toBytes();
      expect(bytes[0]).assertEqual(0xFF); // 低 8 位保持
      expect(bytes[1]).assertEqual(0x00);
      expect(bytes[2]).assertEqual(0x00);
      expect(bytes[3]).assertEqual(0x00);
      expect(bytes[4]).assertEqual(0x00);
    });

    it('update_XOR_zeros', 0, () => {
      // 用 0 XOR → 状态不变（全 1）
      const result: HashResult = new HashResult();
      result.update(0x00000000, 8, 32, 1); // flag=1: XOR
      const bytes: Uint8Array = result.toBytes();
      expect(bytes[0]).assertEqual(0xFF);
      expect(bytes[1]).assertEqual(0xFF);
      expect(bytes[2]).assertEqual(0xFF);
      expect(bytes[3]).assertEqual(0xFF);
      expect(bytes[4]).assertEqual(0xFF);
    });

    it('update_XOR_ones', 0, () => {
      // 用 0xFFFFFFFF XOR 位 [8..40) → 上 32 位翻转（全 1 → 全 0）
      const result: HashResult = new HashResult();
      result.update(0xFFFFFFFF, 8, 32, 1); // flag=1: XOR
      const bytes: Uint8Array = result.toBytes();
      expect(bytes[0]).assertEqual(0xFF); // 低 8 位不受影响
      expect(bytes[1]).assertEqual(0x00);
      expect(bytes[2]).assertEqual(0x00);
      expect(bytes[3]).assertEqual(0x00);
      expect(bytes[4]).assertEqual(0x00);
    });
  });

  describe('HeliosHash', () => {
    it('heliosHash_outputLength', 0, () => {
      const input: Uint8Array = toBytes('test');
      const output: Uint8Array = heliosHash(input);
      expect(output.length).assertEqual(5);
    });

    it('heliosHash_deterministic', 0, () => {
      const input: Uint8Array = toBytes('test');
      const h1: Uint8Array = heliosHash(input);
      const h2: Uint8Array = heliosHash(input);
      expect(h1[0]).assertEqual(h2[0]);
      expect(h1[1]).assertEqual(h2[1]);
      expect(h1[2]).assertEqual(h2[2]);
      expect(h1[3]).assertEqual(h2[3]);
      expect(h1[4]).assertEqual(h2[4]);
    });

    it('heliosHash_differentInputs', 0, () => {
      const h1: Uint8Array = heliosHash(toBytes('hello'));
      const h2: Uint8Array = heliosHash(toBytes('world'));
      let same: boolean = true;
      for (let i: number = 0; i < 5; i++) {
        if (h1[i] !== h2[i]) {
          same = false;
          break;
        }
      }
      expect(same).assertFalse();
    });

    it('heliosHash_md5hexLength', 0, () => {
      // cuid_galaxy2 中 heliosHash 接收 32 字符 MD5 hex 的 ASCII 字节
      // 验证 32 字节输入也能正常输出 5 字节
      const input: Uint8Array = toBytes('0123456789abcdef0123456789abcdef');
      const output: Uint8Array = heliosHash(input);
      expect(output.length).assertEqual(5);
    });
  });

  describe('DedupByKey', () => {
    // 复用 dedupByKey 的最小结构，避免引入 @Observed 的 ThreadInfo
    interface Item { tid: number; }
    const keyOf = (item: Item): number => item.tid;

    it('allDuplicates_terminatesPagination', 0, () => {
      // 缺陷回归：getPersonalized 的 hasMore 由原始返回数量判定（>=rn 即 true），
      // 当一页全部为已加载过的重复 tid 时，去重后 list 为空但 hasMore 仍为 true，
      // 会导致 onReachEnd 持续触发空 loadMore，主页陷入无限加载循环。
      // 修复后：去重归零时 hasMore 必须置 false 以终止分页。
      const existing: Item[] = [{ tid: 1 }, { tid: 2 }, { tid: 3 }];
      const incoming: Item[] = [{ tid: 1 }, { tid: 2 }, { tid: 3 }];
      const result = dedupByKey(existing, incoming, true, keyOf);
      expect(result.list.length).assertEqual(0);
      expect(result.hasMore).assertFalse();
    });

    it('partialDuplicates_keepsNewAndPreservesHasMore', 0, () => {
      // 部分重复：保留新帖，hasMore 维持上游判定（仍可能有更多新内容）
      const existing: Item[] = [{ tid: 1 }, { tid: 2 }];
      const incoming: Item[] = [{ tid: 2 }, { tid: 3 }, { tid: 4 }];
      const result = dedupByKey(existing, incoming, true, keyOf);
      expect(result.list.length).assertEqual(2);
      expect(result.list[0].tid).assertEqual(3);
      expect(result.list[1].tid).assertEqual(4);
      expect(result.hasMore).assertTrue();
    });

    it('noDuplicates_keepsAll', 0, () => {
      const existing: Item[] = [{ tid: 1 }];
      const incoming: Item[] = [{ tid: 2 }, { tid: 3 }];
      const result = dedupByKey(existing, incoming, true, keyOf);
      expect(result.list.length).assertEqual(2);
      expect(result.hasMore).assertTrue();
    });

    it('emptyExisting_noDedup', 0, () => {
      // 首屏 / dataList 为空时不做去重，原样返回
      const existing: Item[] = [];
      const incoming: Item[] = [{ tid: 1 }, { tid: 1 }];
      const result = dedupByKey(existing, incoming, true, keyOf);
      expect(result.list.length).assertEqual(2);
      expect(result.hasMore).assertTrue();
    });
  });
}
