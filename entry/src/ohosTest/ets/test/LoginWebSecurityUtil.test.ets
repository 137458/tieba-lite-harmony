import { describe, it, expect } from '@ohos/hypium';
import { isAllowedLoginUrl, isLoginSuccessUrl } from '../../../main/ets/utils/LoginWebSecurityUtil';

export default function loginWebSecurityUtilTest() {
  describe('LoginWebSecurityUtil', () => {
    it('allows_baidu_login_redirect_hosts', 0, () => {
      expect(isAllowedLoginUrl('https://wappass.baidu.com/v2/?login')).assertTrue();
      expect(isAllowedLoginUrl('https://passport.baidu.com/v3/login/main')).assertTrue();
      expect(isAllowedLoginUrl('https://tieba.baidu.com/f?kw=test')).assertTrue();
      expect(isAllowedLoginUrl('https://tiebac.baidu.com/index/tbwise/mine')).assertTrue();
    });

    it('rejects_untrusted_or_lookalike_hosts', 0, () => {
      expect(isAllowedLoginUrl('https://evil.example.com/login')).assertFalse();
      expect(isAllowedLoginUrl('https://tieba.baidu.com.evil.example.com/')).assertFalse();
      expect(isAllowedLoginUrl('http://tieba.baidu.com/index/tbwise/mine')).assertFalse();
    });

    it('recognizes_tieba_login_completion', 0, () => {
      expect(isLoginSuccessUrl('https://tieba.baidu.com/index/tbwise/mine')).assertTrue();
      expect(isLoginSuccessUrl('https://tiebac.baidu.com/index/tbwise/mine?from=login')).assertTrue();
      expect(isLoginSuccessUrl('https://tieba.baidu.com/index/tbwise/forum')).assertTrue();
      expect(isLoginSuccessUrl('https://tieba.baidu.com/f?kw=test')).assertFalse();
      expect(isLoginSuccessUrl('https://tieba.baidu.com/index/tbwiseevil/mine')).assertFalse();
    });
  });
}
