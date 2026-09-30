import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect } from '@ohos/hypium';
import { crc32 } from '../main/ets/utils/helios/CRC32';
import { xxhash32 } from '../main/ets/utils/helios/XXHash32';
import { base32Encode } from '../main/ets/utils/helios/Base32';
import { HashResult } from '../main/ets/utils/helios/HashResult';
import { heliosHash } from '../main/ets/utils/helios/Hasher';
import {
  shouldLoad,
  shouldLoadOrigin,
  getMediaImageUrl,
  getAvatarImageUrl,
  IMAGE_LOAD_SMART_ORIGIN,
  IMAGE_LOAD_SMART_NO,
  IMAGE_LOAD_ALL_ORIGIN,
  IMAGE_LOAD_ALL_NO
} from '../main/ets/utils/ImageLoadUtil';
import { BaseViewModel, FetchDataResult } from '../main/ets/viewmodel/BaseViewModel';
import { getAvatarUrl } from '../main/ets/utils/AvatarUtil';
import { isAllowedLoginUrl, isLoginSuccessUrl } from '../main/ets/utils/LoginWebSecurityUtil';
import { decodePbPageRes, encodePbPageReq, IPbPageReqParams } from '../main/ets/proto/PbPageProto';
import { ProtoReader, ProtoTag, ProtoWriter } from '../main/ets/proto/ProtoWire';
import { ReleaseInfo, UpdateChecker } from '../main/ets/utils/UpdateChecker';
import { dedupeByKey } from '../main/ets/utils/FormatUtil';
import {
  clearCommentPreviewCache,
  getCachedCommentPreview,
  requestCommentPreview,
  setCachedCommentPreview
} from '../main/ets/utils/ThreadCommentCache';
import { formatRelativeTime } from '../main/ets/utils/TimeUtil';
import { EmoticonManager, EmoticonInfo } from '../main/ets/utils/EmoticonManager';

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

/** dedupeByKey 测试用最小模型（模拟 SelfFollowForum.fid） */
class ForumRef {
  fid: number;
  constructor(fid: number) {
    this.fid = fid;
  }
}

/**
 * 构造 Agree 消息 bytes：agree_num(1) / has_agree(2)，hasAgree<0 时不写入
 * （模块级 helper：ArkTS 严格模式禁止嵌套函数 arkts-no-nested-funcs）
 */
function buildAgreeBytes(agreeNum: number, hasAgree: number): Uint8Array {
  const writer: ProtoWriter = new ProtoWriter();
  writer.writeInt32(1, agreeNum);
  if (hasAgree >= 0) {
    writer.writeInt32(2, hasAgree);
  }
  return writer.finish();
}

export default function localUnitTest() {
  describe('UpdateChecker', () => {
    it('filtersDraftAndSelectsPrerelease', 0, () => {
      const stable: ReleaseInfo = new ReleaseInfo();
      stable.tag_name = 'v1.2.2';
      const beta: ReleaseInfo = new ReleaseInfo();
      beta.tag_name = 'v1.3.0-beta.1';
      beta.prerelease = true;
      const draft: ReleaseInfo = new ReleaseInfo();
      draft.tag_name = 'v2.0.0';
      draft.draft = true;
      expect(UpdateChecker.selectLatestRelease([stable, beta, draft], false)?.tag_name).assertEqual('v1.2.2');
      expect(UpdateChecker.selectLatestRelease([stable, beta, draft], true)?.tag_name).assertEqual('v1.3.0-beta.1');
    });

    it('stableReleaseSupersedesPrerelease', 0, () => {
      expect(UpdateChecker.compareVersions('1.3.0-beta.4', '1.3.0')).assertLarger(0);
    });
  });
  describe('FormatUtil.dedupeByKey', () => {
    it('filtersDuplicatesPreservingIncomingOrder', 0, () => {
      const existing: ForumRef[] = [new ForumRef(1), new ForumRef(2)];
      const incoming: ForumRef[] = [new ForumRef(2), new ForumRef(3), new ForumRef(4)];
      const result: ForumRef[] = dedupeByKey(existing, incoming, (f: ForumRef): number => f.fid);
      expect(result.length).assertEqual(2);
      expect(result[0].fid).assertEqual(3);
      expect(result[1].fid).assertEqual(4);
    });

    it('handlesEmptyExistingAndAllDuplicate', 0, () => {
      const single: ForumRef[] = [new ForumRef(9)];
      expect(dedupeByKey([], single, (f: ForumRef): number => f.fid).length).assertEqual(1);
      const existing: ForumRef[] = [new ForumRef(9)];
      expect(dedupeByKey(existing, single, (f: ForumRef): number => f.fid).length).assertEqual(0);
    });
  });
  describe('PbPageRequest', () => {
    it('includesFloorPreviewParameters', 0, () => {
      const params: IPbPageReqParams = {
        tid: 1,
        pn: 1,
        rn: 30,
        sort: 0,
        onlyAuthor: false,
        clientVersion: '12.64.1.1',
        withFloor: true,
        floorRn: 4
      };
      const rootReader: ProtoReader = new ProtoReader(encodePbPageReq(params));
      const rootTag: ProtoTag = rootReader.readTag();
      expect(rootTag.fieldNumber).assertEqual(1);
      const dataReader: ProtoReader = rootReader.readMessage();
      let withFloor: number = 0;
      let floorRn: number = 0;
      while (!dataReader.isEnd()) {
        const tag: ProtoTag = dataReader.readTag();
        if (tag.fieldNumber === 8) {
          withFloor = dataReader.readVarint();
        } else if (tag.fieldNumber === 9) {
          floorRn = dataReader.readVarint();
        } else {
          dataReader.skipField(tag.wireType);
        }
      }
      expect(withFloor).assertEqual(1);
      expect(floorRn).assertEqual(4);
    });
  });

  /**
   * decodePbPageRes 响应解码回归测试
   *
   * 真实 pb_page 响应中 thread 的 tid 在 field 1（id，对齐 aiotieba
   * ThreadInfo.proto 与实测响应），field 2（tid）为旧版定义兼容位；
   * Agree 消息的 has_agree（field 2）表示当前用户是否已赞，
   * 缺失时 isAgreed 必须保持 false（未赞默认值）。
   */
  describe('PbPageResponseAgreeDecode', () => {
    it('threadTidFromField1_propagatesToPosts', 0, () => {
      const threadWriter: ProtoWriter = new ProtoWriter();
      threadWriter.writeInt32(1, 87654321);
      threadWriter.writeMessage(126, buildAgreeBytes(66, 0));

      const postAgreeWriter: ProtoWriter = new ProtoWriter();
      postAgreeWriter.writeInt32(1, 7);
      const postWriter: ProtoWriter = new ProtoWriter();
      postWriter.writeInt32(1, 123456);
      postWriter.writeMessage(37, postAgreeWriter.finish());

      const dataWriter: ProtoWriter = new ProtoWriter();
      dataWriter.writeMessage(8, threadWriter.finish());
      dataWriter.writeMessage(6, postWriter.finish());
      const rootWriter: ProtoWriter = new ProtoWriter();
      rootWriter.writeMessage(2, dataWriter.finish());

      const result = decodePbPageRes(rootWriter.finish());
      expect(result.thread.tid).assertEqual(87654321);
      expect(result.posts.list.length).assertEqual(1);
      // decodePost 依赖外层 threadTid，tid 丢失会导致楼层点赞请求 thread_id=0
      expect(result.posts.list[0].tid).assertEqual(87654321);
      expect(result.posts.list[0].pid).assertEqual(123456);
    });

    it('threadTidFromField2Legacy_stillParsed', 0, () => {
      // 旧版 Thread.proto（tid=2）响应兼容：field 1 缺失时回退 field 2
      const threadWriter: ProtoWriter = new ProtoWriter();
      threadWriter.writeInt32(2, 87654321);
      const dataWriter: ProtoWriter = new ProtoWriter();
      dataWriter.writeMessage(8, threadWriter.finish());
      const rootWriter: ProtoWriter = new ProtoWriter();
      rootWriter.writeMessage(2, dataWriter.finish());

      const result = decodePbPageRes(rootWriter.finish());
      expect(result.thread.tid).assertEqual(87654321);
    });

    it('agreeHasAgree_marksThreadAndPostAgreed', 0, () => {
      const threadWriter: ProtoWriter = new ProtoWriter();
      threadWriter.writeInt32(1, 87654321);
      threadWriter.writeMessage(126, buildAgreeBytes(66, 1));

      const postWriter: ProtoWriter = new ProtoWriter();
      postWriter.writeInt32(1, 123456);
      postWriter.writeMessage(37, buildAgreeBytes(7, 1));

      const dataWriter: ProtoWriter = new ProtoWriter();
      dataWriter.writeMessage(8, threadWriter.finish());
      dataWriter.writeMessage(6, postWriter.finish());
      const rootWriter: ProtoWriter = new ProtoWriter();
      rootWriter.writeMessage(2, dataWriter.finish());

      const result = decodePbPageRes(rootWriter.finish());
      expect(result.thread.agreeNum).assertEqual(66);
      expect(result.thread.isAgreed).assertTrue();
      expect(result.posts.list[0].agreeNum).assertEqual(7);
      expect(result.posts.list[0].isAgreed).assertTrue();
    });

    it('agreeHasAgreeAbsent_defaultsToNotAgreed', 0, () => {
      const threadWriter: ProtoWriter = new ProtoWriter();
      threadWriter.writeInt32(1, 87654321);
      threadWriter.writeMessage(126, buildAgreeBytes(66, -1));

      const postWriter: ProtoWriter = new ProtoWriter();
      postWriter.writeInt32(1, 123456);
      postWriter.writeMessage(37, buildAgreeBytes(7, -1));

      const dataWriter: ProtoWriter = new ProtoWriter();
      dataWriter.writeMessage(8, threadWriter.finish());
      dataWriter.writeMessage(6, postWriter.finish());
      const rootWriter: ProtoWriter = new ProtoWriter();
      rootWriter.writeMessage(2, dataWriter.finish());

      const result = decodePbPageRes(rootWriter.finish());
      expect(result.thread.isAgreed).assertFalse();
      expect(result.posts.list[0].isAgreed).assertFalse();
    });
  });

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
      expect(h1 !== h2).assertTrue();
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

  /**
   * AvatarUtil.getAvatarUrl 单测
   *
   * 该函数是下游使用广泛的核心共享工具（11 处调用：DynamicColorUtil #158、
   * FrsPageProto/PbPageProto/UserPostProto、UserProfilePage/FollowsPage/
   * MessagePage/ProfilePage/TopicDetailPage、TiebaAPI），此前零覆盖。
   *
   * #158 动态取色流程首步 extractAvatarColor 即依赖此函数拼接头像 URL，
   * URL 拼接回归会静默导致动态取色失败（HTTP 404 → catch → 返回 null）。
   *
   * 重点覆盖：
   * - 空字符串/完整 URL 直通边界
   * - 三档尺寸路径映射（s/m/l）
   * - 默认参数（不传 size）等价于 'm'
   * - 百度 protobuf 垃圾数据清洗规则（含 '?' → 去末尾 13 字符）及其边界
   *   （对齐 aiotieba profile/_classdef.py:96-97）
   */
  describe('AvatarUtilGetAvatarUrl', () => {
    it('getAvatarUrl_emptyReturnsEmpty', 0, () => {
      expect(getAvatarUrl('', 'm')).assertEqual('');
    });

    it('getAvatarUrl_httpUrlPassthrough', 0, () => {
      // 已是完整 http URL 原样返回，不再拼接 host/路径
      const url: string = 'http://example.com/avatar.png';
      expect(getAvatarUrl(url, 'm')).assertEqual(url);
    });

    it('getAvatarUrl_httpsUrlPassthrough', 0, () => {
      const url: string = 'https://example.com/avatar.png';
      expect(getAvatarUrl(url, 'm')).assertEqual(url);
    });

    it('getAvatarUrl_sizeS_usesPortraitn', 0, () => {
      expect(getAvatarUrl('tb.1.abc', 's'))
        .assertEqual('http://tb.himg.baidu.com/sys/portraitn/item/tb.1.abc');
    });

    it('getAvatarUrl_sizeM_usesPortrait', 0, () => {
      expect(getAvatarUrl('tb.1.abc', 'm'))
        .assertEqual('http://tb.himg.baidu.com/sys/portrait/item/tb.1.abc');
    });

    it('getAvatarUrl_sizeL_usesPortraith', 0, () => {
      expect(getAvatarUrl('tb.1.abc', 'l'))
        .assertEqual('http://tb.himg.baidu.com/sys/portraith/item/tb.1.abc');
    });

    it('getAvatarUrl_defaultSizeEqualsM', 0, () => {
      // 不传 size 参数应等价于 'm'
      expect(getAvatarUrl('tb.1.abc'))
        .assertEqual('http://tb.himg.baidu.com/sys/portrait/item/tb.1.abc');
    });

    it('getAvatarUrl_noQuestionMark_noCleaning', 0, () => {
      // 无 '?' 标记：不触发清洗，原样拼接
      expect(getAvatarUrl('tb.1.abcdef', 's'))
        .assertEqual('http://tb.himg.baidu.com/sys/portraitn/item/tb.1.abcdef');
    });

    it('getAvatarUrl_questionMark_stripsLast13Chars', 0, () => {
      // 含 '?' → 去掉末尾 13 字符（对齐 aiotieba protobuf 垃圾数据清洗）
      // portrait = 'tb.1.abc?' + '1234567890123'（13 字符垃圾）→ 清洗后 'tb.1.abc?'
      // 注：规则按"末尾 13 字符"截断，不关心 '?' 位置
      const portrait: string = 'tb.1.abc?1234567890123';
      expect(getAvatarUrl(portrait, 's'))
        .assertEqual('http://tb.himg.baidu.com/sys/portraitn/item/tb.1.abc?');
    });

    it('getAvatarUrl_questionMarkBoundary_tooShortReturnsEmpty', 0, () => {
      // 边界：含 '?' 但长度 ≤ 13 时，Math.max(0, len-13)=0 → slice(0,0)='' → 返回 ''
      // 防御回归：若误用 slice(0, len-13) 不带 Math.max，会得到负索引 slice(0, -10)
      // 在 JS/ArkTS 中 slice(0, -10) 会截断为 length-10 而非空，导致返回非空错误 URL
      expect(getAvatarUrl('x?y', 's')).assertEqual('');
      expect(getAvatarUrl('?', 's')).assertEqual('');
    });

    it('getAvatarUrl_realisticPortrait_constructsFullUrl', 0, () => {
      // 真实 portrait 标识符（贴吧 tb.1.xxx 格式），验证完整 URL 构造
      const portrait: string = 'tb.1.abc123def456';
      expect(getAvatarUrl(portrait, 's'))
        .assertEqual('http://tb.himg.baidu.com/sys/portraitn/item/tb.1.abc123def456');
    });
  });

  describe('SecurityUrlBoundary', () => {
    it('loginUrl_allowsRequiredHttpsOrigins', 0, () => {
      expect(isAllowedLoginUrl('https://wappass.baidu.com/passport?login')).assertTrue();
      expect(isAllowedLoginUrl('https://passport.baidu.com/v2/api')).assertTrue();
      expect(isAllowedLoginUrl('https://tieba.baidu.com/index/tbwise/mine')).assertTrue();
      expect(isAllowedLoginUrl('https://tiebac.baidu.com/index/tbwise/mine')).assertTrue();
    });

    it('loginUrl_rejectsUntrustedOriginsAndPorts', 0, () => {
      expect(isAllowedLoginUrl('http://wappass.baidu.com/passport?login')).assertFalse();
      expect(isAllowedLoginUrl('https://wappass.baidu.com:8443/passport?login')).assertFalse();
      expect(isAllowedLoginUrl('https://wappass.baidu.com.evil.example/passport?login')).assertFalse();
      expect(isAllowedLoginUrl('https://evil.example/?next=https://tieba.baidu.com/index/tbwise/mine')).assertFalse();
    });

    it('loginSuccessUrl_requiresTrustedExpectedPath', 0, () => {
      expect(isLoginSuccessUrl('https://tieba.baidu.com/index/tbwise/mine')).assertTrue();
      expect(isLoginSuccessUrl('https://tiebac.baidu.com/index/tbwise/mine?from=passport')).assertTrue();
      expect(isLoginSuccessUrl('https://tieba.baidu.com/index/tbwiseevil/mine')).assertFalse();
      expect(isLoginSuccessUrl('https://tieba.baidu.com:443/index/tbwise/mine')).assertFalse();
    });
    // appLinking 解析用例移至 ohosTest/AppLinkingUtil.test.ets：
    // url.URL 对非 http scheme 的 pathname 依赖系统实现，本地单测环境模拟行为不一致
  });

  /**
   * ThreadCommentCache LRU 缓存表征测试（纯缓存面，不触网）：
   * - 超容量淘汰"最久未访问"条目（命中会刷新顺序）
   * - 写缓存同步通知订阅方一次，之后解除订阅
   * - requestCommentPreview 缓存命中走同步回调且不进入加载流程
   * 模块级全局状态，每个用例先 clearCommentPreviewCache 保证自包含
   */
  describe('ThreadCommentCacheLru', () => {
    it('evictsLeastRecentlyUsed_beyondCapacity', 0, () => {
      clearCommentPreviewCache();
      for (let i: number = 1; i <= 50; i++) {
        setCachedCommentPreview(i, []);
      }
      // 访问 tid=1 刷新其 LRU 顺序，随后插入 tid=51 应淘汰最久未访问的 tid=2
      expect(getCachedCommentPreview(1) !== undefined).assertTrue();
      setCachedCommentPreview(51, []);
      expect(getCachedCommentPreview(2) === undefined).assertTrue();
      expect(getCachedCommentPreview(1) !== undefined).assertTrue();
      expect(getCachedCommentPreview(51) !== undefined).assertTrue();
      clearCommentPreviewCache();
    });

    it('setCache_notifiesSubscriberOnce', 0, () => {
      clearCommentPreviewCache();
      let notifyCount: number = 0;
      setCachedCommentPreview(100, []);
      const entering: boolean = requestCommentPreview(100, () => {
        notifyCount++;
      });
      expect(entering).assertFalse();
      expect(notifyCount).assertEqual(1);
      // 订阅在首次通知后解除：再次写缓存不应重复通知
      setCachedCommentPreview(100, []);
      expect(notifyCount).assertEqual(1);
      clearCommentPreviewCache();
    });

    it('requestCommentPreview_cacheHit_isSyncAndNotLoading', 0, () => {
      clearCommentPreviewCache();
      setCachedCommentPreview(200, []);
      let called: boolean = false;
      const entering: boolean = requestCommentPreview(200, () => {
        called = true;
      });
      expect(entering).assertFalse();
      expect(called).assertTrue();
      clearCommentPreviewCache();
    });
  });

  /**
   * TimeUtil.formatRelativeTime 边界（NaN 路径不触 $r 资源，可在本地单测执行）：
   * NaN <= 0 为 false（Code_Wiki #98 经典陷阱），会漏过守卫走到日期分支
   * 渲染出 "NaN-NaN-NaN"，必须先做 Number.isFinite 防御
   */
  describe('TimeUtil.formatRelativeTime', () => {
    it('nanTimestamp_returnsEmptyString', 0, () => {
      expect(formatRelativeTime(Number.NaN)).assertEqual('');
    });

    it('nonPositiveTimestamp_returnsEmptyString', 0, () => {
      expect(formatRelativeTime(0)).assertEqual('');
      expect(formatRelativeTime(-5)).assertEqual('');
    });
  });

  /** EmoticonManager 并行映射表回归钉（纯查表逻辑） */
  describe('EmoticonManager', () => {
    it('mappingTables_stayParallel', 0, () => {
      const all: EmoticonInfo[] = EmoticonManager.getAllEmoticons();
      expect(all.length > 0).assertTrue();
      for (let i: number = 0; i < all.length; i++) {
        const found: EmoticonInfo | undefined = EmoticonManager.getEmoticonByName(all[i].name);
        expect(found !== undefined).assertTrue();
        if (found !== undefined) {
          expect(found.id).assertEqual(all[i].id);
        }
      }
    });

    it('hujie_idMatchesAndroid_andUnknownReturnsUndefined', 0, () => {
      expect(EmoticonManager.getEmoticonByName('滑稽')?.id).assertEqual('image_emoticon25');
      expect(EmoticonManager.getEmoticonByName('不存在的表情') === undefined).assertTrue();
    });

    it('urlAndMark_format', 0, () => {
      expect(EmoticonManager.getEmoticonUrl('image_emoticon25'))
        .assertEqual('http://static.tieba.baidu.com/tb/editor/images/client/image_emoticon25.png');
      expect(EmoticonManager.buildEmoticonMark('滑稽')).assertEqual('#(滑稽)');
    });
  });

  /**
   * ImageLoadUtil 省流模式 4×2 策略矩阵回归钉（对齐文件头矩阵表与 Android ImageUtil.kt）
   */
  describe('ImageLoadUtil matrix', () => {
    it('smartOrigin_wifiOriginCellularThumbnail', 0, () => {
      expect(shouldLoad(IMAGE_LOAD_SMART_ORIGIN, true)).assertTrue();
      expect(shouldLoadOrigin(IMAGE_LOAD_SMART_ORIGIN, true)).assertTrue();
      expect(shouldLoad(IMAGE_LOAD_SMART_ORIGIN, false)).assertTrue();
      expect(shouldLoadOrigin(IMAGE_LOAD_SMART_ORIGIN, false)).assertFalse();
    });

    it('smartNo_wifiOnlyThumbnail', 0, () => {
      expect(shouldLoad(IMAGE_LOAD_SMART_NO, true)).assertTrue();
      expect(shouldLoadOrigin(IMAGE_LOAD_SMART_NO, true)).assertFalse();
      expect(shouldLoad(IMAGE_LOAD_SMART_NO, false)).assertFalse();
      expect(shouldLoadOrigin(IMAGE_LOAD_SMART_NO, false)).assertFalse();
    });

    it('allOrigin_alwaysOrigin_andAllNo_neverLoad', 0, () => {
      expect(shouldLoad(IMAGE_LOAD_ALL_ORIGIN, true)).assertTrue();
      expect(shouldLoadOrigin(IMAGE_LOAD_ALL_ORIGIN, true)).assertTrue();
      expect(shouldLoad(IMAGE_LOAD_ALL_ORIGIN, false)).assertTrue();
      expect(shouldLoadOrigin(IMAGE_LOAD_ALL_ORIGIN, false)).assertTrue();
      expect(shouldLoad(IMAGE_LOAD_ALL_NO, true)).assertFalse();
      expect(shouldLoad(IMAGE_LOAD_ALL_NO, false)).assertFalse();
      expect(shouldLoadOrigin(IMAGE_LOAD_ALL_NO, true)).assertFalse();
    });

    it('mediaUrl_thumbnailFallbackAndPlaceholders', 0, () => {
      // 始终无图：返回空串显示占位图
      expect(getMediaImageUrl('thumb', 'origin', IMAGE_LOAD_ALL_NO, true)).assertEqual('');
      // 智能无图 + 非 WiFi：不加载
      expect(getMediaImageUrl('thumb', 'origin', IMAGE_LOAD_SMART_NO, false)).assertEqual('');
      // 小图模式但 thumbnail 为空：回退原图
      expect(getMediaImageUrl('', 'origin', IMAGE_LOAD_SMART_NO, true)).assertEqual('origin');
      // 小图模式且有 thumbnail：用小图
      expect(getMediaImageUrl('thumb', 'origin', IMAGE_LOAD_SMART_ORIGIN, false)).assertEqual('thumb');
    });
  });
}
