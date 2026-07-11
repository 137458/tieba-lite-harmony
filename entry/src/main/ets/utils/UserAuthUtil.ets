// #135 应用锁工具类
// 封装 userAuth API，提供生物识别认证能力
// 用于应用锁功能：进入应用时验证用户身份（FACE/FINGERPRINT/PIN）
//
// API：@kit.UserAuthenticationKit 的 userAuth
//   - getAvailableStatus(type, level)：同步检测是否支持某种认证类型
//   - getUserAuthInstance(authParam, widgetParam)：获取认证实例
//   - userAuthInstance.on('result', ...)：订阅认证结果
//   - userAuthInstance.start()：启动认证
//
// 权限：无需声明权限（userAuth 为公开 API，系统会拉起系统级认证界面）

import { userAuth } from '@kit.UserAuthenticationKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';

/**
 * 应用锁工具类
 *
 * 使用方式：
 *   1. SettingsPage 调用 canUseUserAuth() 检测设备是否支持，决定是否显示应用锁开关
 *   2. 用户开启应用锁时调用 authenticate(title) 拉起系统认证界面
 *   3. EntryAbility.onForeground 中读取 appLockEnabled 偏好，若开启则调用 authenticate 验证
 */
export class UserAuthUtil {
  /**
   * 检测设备是否支持生物识别认证（FACE 或 FINGERPRINT，ATL3 等级）
   * 同步方法，无副作用，可用于 SettingsPage 决定是否显示应用锁开关
   * @returns true=至少支持一种生物识别 false=都不支持
   */
  static canUseUserAuth(): boolean {
    // 优先检测 FACE 认证
    try {
      userAuth.getAvailableStatus(userAuth.UserAuthType.FACE, userAuth.AuthTrustLevel.ATL3);
      return true;
    } catch (err) {
      // FACE 不支持，尝试 FINGERPRINT
      try {
        userAuth.getAvailableStatus(userAuth.UserAuthType.FINGERPRINT, userAuth.AuthTrustLevel.ATL3);
        return true;
      } catch (err2) {
        return false;
      }
    }
  }

  /**
   * 拉起系统生物识别认证（FACE/FINGERPRINT/PIN 任一通过即可）
   * @param title 认证界面标题（如"应用锁验证"）
   * @returns Promise<boolean>，true=认证成功 false=认证失败/取消/异常
   */
  static authenticate(title: string): Promise<boolean> {
    return new Promise<boolean>((resolve: (value: boolean) => void) => {
      try {
        // 生成随机 challenge，防止重放攻击（官方推荐做法）
        const rand = cryptoFramework.createRandom();
        const randData: Uint8Array = rand.generateRandomSync(16).data;

        // 认证参数：支持 PIN/FACE/FINGERPRINT，ATL3 等级
        const authParam: userAuth.AuthParam = {
          challenge: randData,
          authType: [userAuth.UserAuthType.PIN, userAuth.UserAuthType.FACE, userAuth.UserAuthType.FINGERPRINT],
          authTrustLevel: userAuth.AuthTrustLevel.ATL3,
        };
        const widgetParam: userAuth.WidgetParam = {
          title: title,
        };
        const userAuthInstance: userAuth.UserAuthInstance = userAuth.getUserAuthInstance(authParam, widgetParam);
        userAuthInstance.on('result', {
          onResult: (result: userAuth.UserAuthResult) => {
            try {
              userAuthInstance.off('result');
              // SUCCESS 表示认证成功（值=12500000），其他均为失败/取消
              resolve(result.result === userAuth.UserAuthResultCode.SUCCESS);
            } catch (err) {
              console.error(`[UserAuthUtil] off result failed: ${(err as BusinessError).message}`);
              resolve(false);
            }
          }
        });
        userAuthInstance.start();
      } catch (err) {
        console.error(`[UserAuthUtil] authenticate failed: ${(err as BusinessError).message}`);
        resolve(false);
      }
    });
  }
}
