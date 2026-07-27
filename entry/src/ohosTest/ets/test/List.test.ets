import abilityTest from './Ability.test';
import cryptoUtilTest from './CryptoUtil.test';
import loginWebSecurityUtilTest from './LoginWebSecurityUtil.test';

export default function testsuite() {
  abilityTest();
  cryptoUtilTest();
  loginWebSecurityUtilTest();
}
