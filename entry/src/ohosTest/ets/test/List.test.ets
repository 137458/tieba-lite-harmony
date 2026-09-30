import abilityTest from './Ability.test';
import cryptoUtilTest from './CryptoUtil.test';
import loginWebSecurityUtilTest from './LoginWebSecurityUtil.test';
import appLinkingUtilTest from './AppLinkingUtil.test';

export default function testsuite() {
  abilityTest();
  cryptoUtilTest();
  loginWebSecurityUtilTest();
  appLinkingUtilTest();
}
