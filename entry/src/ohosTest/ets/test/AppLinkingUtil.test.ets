import { describe, it, expect } from '@ohos/hypium';
import { parseAppLinkingUri } from '../../../../main/ets/utils/AppLinkingUtil';

/**
 * AppLinkingUtil.parseAppLinkingUri instrumented 测试
 *
 * 解析逻辑内部使用 @kit.ArkTS 的 url.URL，其非 http scheme（tblite://）
 * 的 pathname 行为依赖系统真实实现，本地单元测试环境的模拟解析结果
 * 与 WHATWG 标准不一致（pathname 返回空导致 tid 提取失败），
 * 因此本组用例放置在 instrumented 测试层以真机行为为准。
 */
export default function appLinkingUtilTest() {
  describe('AppLinkingParse', () => {
    it('appLinking_acceptsOnlyDeclaredTrustedUris', 0, () => {
      expect(parseAppLinkingUri('tblite://thread/123456').threadId).assertEqual(123456);
      expect(parseAppLinkingUri('https://tieba.baidu.com/p/123456?see_lz=1').seeLz).assertTrue();
      expect(parseAppLinkingUri('http://tieba.baidu.com/p/123456').threadId).assertEqual(0);
      expect(parseAppLinkingUri('https://tieba.baidu.com.evil.example/p/123456').threadId).assertEqual(0);
      expect(parseAppLinkingUri('tblite://thread/9007199254740992').threadId).assertEqual(0);
    });
  });
}
