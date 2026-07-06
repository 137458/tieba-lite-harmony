import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect } from '@ohos/hypium';
import { crc32 } from '../../main/ets/utils/helios/CRC32';
import { xxhash32 } from '../../main/ets/utils/helios/XXHash32';
import { base32Encode } from '../../main/ets/utils/helios/Base32';
import { HashResult } from '../../main/ets/utils/helios/HashResult';
import { heliosHash } from '../../main/ets/utils/helios/Hasher';
import {
  shouldLoad,
  shouldLoadOrigin,
  getMediaImageUrl,
  getAvatarImageUrl,
  IMAGE_LOAD_SMART_ORIGIN,
  IMAGE_LOAD_SMART_NO,
  IMAGE_LOAD_ALL_ORIGIN,
  IMAGE_LOAD_ALL_NO
} from '../../main/ets/utils/ImageLoadUtil';
import { BaseViewModel, FetchDataResult } from '../../main/ets/viewmodel/BaseViewModel';

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

/**
 * BaseViewModel 测试用 mock 子类
 * 通过 shouldFail 控制 fetchData 是否抛错，nextItems 控制返回数据
 */
class TestViewModel extends BaseViewModel<number> {
  shouldFail: boolean = false;
  nextItems: number[] = [];

  protected async fetchData(page: number, isRefresh: boolean): Promise<FetchDataResult<number>> {
    if (this.shouldFail) {
      throw new Error('mock network error');
    }
    return {
      list: this.nextItems,
      hasMore: true,
      currentPage: page
    };
  }
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

  /**
   * ImageLoadUtil 图片加载策略单测（#77 切片1）
   *
   * 覆盖 shouldLoad 8 种组合（4 档 × 2 网络状态）
   * 覆盖 shouldLoadOrigin 5 种组合（shouldLoad=true 的场景，shouldLoad=false 时不应调用）
   *
   * 加载策略矩阵（对齐 Android ImageUtil.kt:492-498, 563-568）：
   * - 智能原图(0)：始终加载，WiFi 原图/移动网络小图
   * - 智能无图(1)：仅 WiFi 加载小图
   * - 始终原图(2)：始终加载原图
   * - 始终无图(3)：始终不加载
   */
  describe('ImageLoadUtilShouldLoad', () => {
    // shouldLoad 8 种组合（4 档 × 2 网络状态）

    it('shouldLoad_smartOrigin_wifi_true', 0, () => {
      // 智能原图 + WiFi → 加载原图
      expect(shouldLoad(IMAGE_LOAD_SMART_ORIGIN, true)).assertTrue();
    });

    it('shouldLoad_smartOrigin_nonWifi_true', 0, () => {
      // 智能原图 + 移动网络 → 加载小图
      expect(shouldLoad(IMAGE_LOAD_SMART_ORIGIN, false)).assertTrue();
    });

    it('shouldLoad_smartNo_wifi_true', 0, () => {
      // 智能无图 + WiFi → 加载
      expect(shouldLoad(IMAGE_LOAD_SMART_NO, true)).assertTrue();
    });

    it('shouldLoad_smartNo_nonWifi_false', 0, () => {
      // 智能无图 + 移动网络 → 不加载
      expect(shouldLoad(IMAGE_LOAD_SMART_NO, false)).assertFalse();
    });

    it('shouldLoad_allOrigin_wifi_true', 0, () => {
      // 始终原图 + WiFi → 加载原图
      expect(shouldLoad(IMAGE_LOAD_ALL_ORIGIN, true)).assertTrue();
    });

    it('shouldLoad_allOrigin_nonWifi_true', 0, () => {
      // 始终原图 + 移动网络 → 加载原图
      expect(shouldLoad(IMAGE_LOAD_ALL_ORIGIN, false)).assertTrue();
    });

    it('shouldLoad_allNo_wifi_false', 0, () => {
      // 始终无图 + WiFi → 不加载
      expect(shouldLoad(IMAGE_LOAD_ALL_NO, true)).assertFalse();
    });

    it('shouldLoad_allNo_nonWifi_false', 0, () => {
      // 始终无图 + 移动网络 → 不加载
      expect(shouldLoad(IMAGE_LOAD_ALL_NO, false)).assertFalse();
    });
  });

  describe('ImageLoadUtilShouldLoadOrigin', () => {
    // shouldLoadOrigin 5 种组合（仅 shouldLoad=true 的场景）

    it('shouldLoadOrigin_smartOrigin_wifi_true', 0, () => {
      // 智能原图 + WiFi → 加载原图
      expect(shouldLoadOrigin(IMAGE_LOAD_SMART_ORIGIN, true)).assertTrue();
    });

    it('shouldLoadOrigin_smartOrigin_nonWifi_false', 0, () => {
      // 智能原图 + 移动网络 → 加载小图
      expect(shouldLoadOrigin(IMAGE_LOAD_SMART_ORIGIN, false)).assertFalse();
    });

    it('shouldLoadOrigin_smartNo_wifi_false', 0, () => {
      // 智能无图 + WiFi → 加载小图（对齐 Android needReverse=true，用高质量小图但仍非原图）
      expect(shouldLoadOrigin(IMAGE_LOAD_SMART_NO, true)).assertFalse();
    });

    it('shouldLoadOrigin_allOrigin_wifi_true', 0, () => {
      // 始终原图 + WiFi → 加载原图
      expect(shouldLoadOrigin(IMAGE_LOAD_ALL_ORIGIN, true)).assertTrue();
    });

    it('shouldLoadOrigin_allOrigin_nonWifi_true', 0, () => {
      // 始终原图 + 移动网络 → 加载原图
      expect(shouldLoadOrigin(IMAGE_LOAD_ALL_ORIGIN, false)).assertTrue();
    });

    // 边界用例：ALL_NO(3) shouldLoad=false 时调用 shouldLoadOrigin，验证防御性检查不崩溃
    it('shouldLoadOrigin_allNo_wifi_false', 0, () => {
      // ALL_NO + WiFi：shouldLoad=false，防御性检查返回 false（不应加载原图）
      expect(shouldLoadOrigin(IMAGE_LOAD_ALL_NO, true)).assertFalse();
    });

    it('shouldLoadOrigin_smartNo_nonWifi_false', 0, () => {
      // 智能无图 + 移动网络：shouldLoad=false，防御性检查返回 false
      expect(shouldLoadOrigin(IMAGE_LOAD_SMART_NO, false)).assertFalse();
    });
  });

  /**
   * getMediaImageUrl 单测（#77 切片1 补充）
   *
   * 覆盖关键路径：
   * - shouldLoad=false 返回空字符串
   * - shouldLoad=true + shouldLoadOrigin=true 返回原图 URL
   * - shouldLoad=true + shouldLoadOrigin=false 返回缩略图 URL
   * - thumbnail 为空时 fallback 到原图 URL
   */
  describe('ImageLoadUtilGetMediaImageUrl', () => {
    it('getMediaImageUrl_allNo_returnsEmpty', 0, () => {
      // 始终无图：shouldLoad=false，返回空字符串
      expect(getMediaImageUrl('thumb.jpg', 'origin.jpg', IMAGE_LOAD_ALL_NO, true))
        .assertEqual('');
    });

    it('getMediaImageUrl_smartNo_nonWifi_returnsEmpty', 0, () => {
      // 智能无图 + 移动网络：shouldLoad=false，返回空字符串
      expect(getMediaImageUrl('thumb.jpg', 'origin.jpg', IMAGE_LOAD_SMART_NO, false))
        .assertEqual('');
    });

    it('getMediaImageUrl_smartOrigin_wifi_returnsOrigin', 0, () => {
      // 智能原图 + WiFi：shouldLoad=true + shouldLoadOrigin=true，返回原图
      expect(getMediaImageUrl('thumb.jpg', 'origin.jpg', IMAGE_LOAD_SMART_ORIGIN, true))
        .assertEqual('origin.jpg');
    });

    it('getMediaImageUrl_smartOrigin_nonWifi_returnsThumbnail', 0, () => {
      // 智能原图 + 移动网络：shouldLoad=true + shouldLoadOrigin=false，返回缩略图
      expect(getMediaImageUrl('thumb.jpg', 'origin.jpg', IMAGE_LOAD_SMART_ORIGIN, false))
        .assertEqual('thumb.jpg');
    });

    it('getMediaImageUrl_allOrigin_nonWifi_returnsOrigin', 0, () => {
      // 始终原图 + 移动网络：shouldLoad=true + shouldLoadOrigin=true，返回原图
      expect(getMediaImageUrl('thumb.jpg', 'origin.jpg', IMAGE_LOAD_ALL_ORIGIN, false))
        .assertEqual('origin.jpg');
    });

    it('getMediaImageUrl_emptyThumbnail_returnsOrigin', 0, () => {
      // thumbnail 为空时 fallback 到原图（即使 shouldLoadOrigin=false 也返回原图）
      expect(getMediaImageUrl('', 'origin.jpg', IMAGE_LOAD_SMART_ORIGIN, false))
        .assertEqual('origin.jpg');
    });
  });

  /**
   * getAvatarImageUrl 单测（#77 切片1 补充）
   *
   * 头像本身是小图，无需 shouldLoadOrigin 判断，仅根据 shouldLoad 决定是否加载
   */
  describe('ImageLoadUtilGetAvatarImageUrl', () => {
    it('getAvatarImageUrl_allNo_returnsEmpty', 0, () => {
      // 始终无图：shouldLoad=false，返回空字符串
      expect(getAvatarImageUrl('avatar.jpg', IMAGE_LOAD_ALL_NO, true))
        .assertEqual('');
    });

    it('getAvatarImageUrl_smartNo_nonWifi_returnsEmpty', 0, () => {
      // 智能无图 + 移动网络：shouldLoad=false，返回空字符串
      expect(getAvatarImageUrl('avatar.jpg', IMAGE_LOAD_SMART_NO, false))
        .assertEqual('');
    });

    it('getAvatarImageUrl_smartOrigin_wifi_returnsAvatar', 0, () => {
      // 智能原图 + WiFi：shouldLoad=true，返回原 avatar（头像无需 shouldLoadOrigin）
      expect(getAvatarImageUrl('avatar.jpg', IMAGE_LOAD_SMART_ORIGIN, true))
        .assertEqual('avatar.jpg');
    });

    it('getAvatarImageUrl_allOrigin_nonWifi_returnsAvatar', 0, () => {
      // 始终原图 + 移动网络：shouldLoad=true，返回原 avatar
      expect(getAvatarImageUrl('avatar.jpg', IMAGE_LOAD_ALL_ORIGIN, false))
        .assertEqual('avatar.jpg');
    });
  });

  /**
   * BaseViewModel 数据完整性测试
   *
   * 验证场景：loadMore 成功后 refresh 失败，lastFetchList/lastOpIsRefresh 应被重置，
   * 避免 syncState 用旧值调用 appendData 导致 dataSource 数据重复
   */
  describe('BaseViewModelDataIntegrity', () => {
    it('loadData_refreshFailure_resetsLastFetchState', 0, async () => {
      const vm: TestViewModel = new TestViewModel();

      // Step 1: refresh 成功，返回 [1, 2]
      vm.nextItems = [1, 2];
      await vm.loadData(true);
      expect(vm.lastOpWasRefresh).assertTrue();
      expect(vm.lastAddedList.length).assertEqual(2);
      expect(vm.paginationData.dataList.length).assertEqual(2);

      // Step 2: loadMore 成功，返回 [3, 4]
      vm.nextItems = [3, 4];
      await vm.loadData(false);
      expect(vm.lastOpWasRefresh).assertFalse();
      expect(vm.lastAddedList.length).assertEqual(2);
      expect(vm.lastAddedList[0]).assertEqual(3);
      expect(vm.paginationData.dataList.length).assertEqual(4);

      // Step 3: refresh 失败（模拟网络错误）
      vm.shouldFail = true;
      vm.nextItems = [99]; // 不应被使用
      await vm.loadData(true);

      // 验证：lastFetchList 被重置为空（修复后），避免 syncState appendData 旧数据
      expect(vm.lastAddedList.length).assertEqual(0);
      // 验证：lastOpIsRefresh 被重置为 false
      expect(vm.lastOpWasRefresh).assertFalse();
      // 验证：error 已设置
      expect(vm.loadingState.error.length > 0).assertTrue();
      // 验证：dataList 未被失败的操作覆盖，仍为 [1, 2, 3, 4]
      expect(vm.paginationData.dataList.length).assertEqual(4);
      // 验证：currentPage 已回滚（loadMore 后为 3，refresh 失败回滚到 3）
      expect(vm.paginationData.currentPage).assertEqual(3);
    });

    it('loadData_loadMoreFailure_resetsLastFetchState', 0, async () => {
      const vm: TestViewModel = new TestViewModel();

      // Step 1: refresh 成功
      vm.nextItems = [1, 2];
      await vm.loadData(true);
      expect(vm.lastAddedList.length).assertEqual(2);

      // Step 2: loadMore 失败
      vm.shouldFail = true;
      vm.nextItems = [99]; // 不应被使用
      await vm.loadData(false);

      // 验证：lastFetchList 被重置为空
      expect(vm.lastAddedList.length).assertEqual(0);
      // 验证：dataList 未变
      expect(vm.paginationData.dataList.length).assertEqual(2);
      // 验证：currentPage 回滚到 2（refresh 后为 2，loadMore 失败回滚）
      expect(vm.paginationData.currentPage).assertEqual(2);
    });

    it('loadData_refreshFailure_thenRefreshSuccess_recovers', 0, async () => {
      const vm: TestViewModel = new TestViewModel();

      // refresh 成功
      vm.nextItems = [1, 2];
      await vm.loadData(true);

      // refresh 失败
      vm.shouldFail = true;
      await vm.loadData(true);
      expect(vm.lastAddedList.length).assertEqual(0);

      // refresh 再次成功
      vm.shouldFail = false;
      vm.nextItems = [5, 6, 7];
      await vm.loadData(true);

      // 验证：恢复后 lastFetchList 为新数据
      expect(vm.lastOpWasRefresh).assertTrue();
      expect(vm.lastAddedList.length).assertEqual(3);
      expect(vm.lastAddedList[0]).assertEqual(5);
      // dataList 被全量替换为新数据
      expect(vm.paginationData.dataList.length).assertEqual(3);
    });
  });
}
