// #147 [AntiPeep-1] DLP 防窥保护工具类
// 封装 @kit.DeviceSecurityKit 的 dlpAntiPeep 模块全部 API
//
// 实现要点：
// 1. canUseAntiPeep() 用 canIUse 检测设备能力，返回 false 时其他 API 直接降级
// 2. 所有 API 调用包 try-catch，失败时返回 false/-1，不抛异常给业务层
// 3. listenOnAntiPeepStatus/listenOffAntiPeepStatus 配对使用，避免监听器泄漏
// 4. showSystemMaskLayer 调用 setAntiPeepMaskLayer(windowId) 拉起系统蒙层
// 5. requestAntiPeepOptions 拉起系统设置弹窗，引导用户开启防窥保护开关
//
// 对齐官方示例：https://gitcode.com/HarmonyOS_Samples/AntiPeep
// 官方文档：https://developer.huawei.com/consumer/cn/doc/HarmonyOS-Guides/devicesecurity-dlpantipeep
//
// 权限：ohos.permission.DLP_GET_HIDE_STATUS（system_grant 受限权限，需 AGC ACL profile）
// 最低版本：HarmonyOS 6.0.0 Beta1（API 23 Beta1），项目当前 API 23 满足
// 设备要求：需存在「设置 > 隐私与安全 > 防窥保护」选项 + 开启人脸识别

import { dlpAntiPeep } from '@kit.DeviceSecurityKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0000;
const TAG: string = 'AntiPeepUtil';

/**
 * 防窥状态变化回调接口
 * 业务方实现 onStatusChanged 方法，在 HIDE 状态时拉起系统蒙层
 */
export interface AntiPeepCallback {
  /**
   * 防窥状态变化回调
   * @param status dlpAntiPeep.DlpAntiPeepStatus
   *   - PASS：无人窥视
   *   - HIDE：有人窥屏，应用应进行隐私保护
   */
  onStatusChanged: (status: dlpAntiPeep.DlpAntiPeepStatus) => Promise<void>;
}

/**
 * DLP 防窥保护工具类
 * 全部方法为 static，业务方无需实例化
 */
export class AntiPeepUtil {
  /**
   * 检测设备是否支持 DLP 防窥保护能力
   * 用 canIUse 检测 SystemCapability.Security.DlpAntiPeep
   * @returns true=支持，false=设备不支持（部分老机型或无前置摄像头设备）
   */
  static canUseAntiPeep(): boolean {
    try {
      return canIUse('SystemCapability.Security.DlpAntiPeep');
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'canUseAntiPeep failed: %{public}s', JSON.stringify(err));
      return false;
    }
  }

  /**
   * 检查系统防窥保护总开关是否开启
   * 用户需在「设置 > 隐私与安全 > 防窥保护」开启开关 + 完成人脸验证
   * @returns true=已开启，false=未开启或不支持
   */
  static async isAntiPeepOn(): Promise<boolean> {
    if (!AntiPeepUtil.canUseAntiPeep()) {
      return false;
    }
    try {
      const result: boolean = await dlpAntiPeep.isDlpAntiPeepSwitchOn();
      hilog.info(DOMAIN, TAG, 'isDlpAntiPeepSwitchOn success: %{public}s', result.toString());
      return result;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'isDlpAntiPeepSwitchOn failed: %{public}s', JSON.stringify(err));
      return false;
    }
  }

  /**
   * 获取当前应用的窥视状态（手动查询，非订阅）
   * @returns dlpAntiPeep.DlpAntiPeepStatus，失败返回 -1
   */
  static getAntiPeepInfo(): dlpAntiPeep.DlpAntiPeepStatus {
    if (!AntiPeepUtil.canUseAntiPeep()) {
      return -1 as dlpAntiPeep.DlpAntiPeepStatus;
    }
    try {
      const status: dlpAntiPeep.DlpAntiPeepStatus = dlpAntiPeep.getDlpAntiPeepInfo();
      hilog.info(DOMAIN, TAG, 'getDlpAntiPeepInfo success: %{public}d', status);
      return status;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'getDlpAntiPeepInfo failed: %{public}s', JSON.stringify(err));
      return -1 as dlpAntiPeep.DlpAntiPeepStatus;
    }
  }

  /**
   * 订阅防窥保护状态变化通知
   * @param callback 业务方实现 AntiPeepCallback，在 HIDE 状态时拉起系统蒙层
   * @returns true=订阅成功，false=订阅失败或不支持
   */
  static listenOnAntiPeepStatus(callback: AntiPeepCallback): boolean {
    if (!AntiPeepUtil.canUseAntiPeep()) {
      return false;
    }
    try {
      dlpAntiPeep.on('dlpAntiPeep', (status: dlpAntiPeep.DlpAntiPeepStatus) => {
        hilog.info(DOMAIN, TAG, 'dlpAntiPeep callback: %{public}d', status);
        // 异步触发业务方回调，不阻塞系统回调线程
        callback.onStatusChanged(status).catch((err: Error) => {
          hilog.error(DOMAIN, TAG, 'onStatusChanged callback failed: %{public}s', err.message);
        });
      });
      hilog.info(DOMAIN, TAG, 'on(dlpAntiPeep) success');
      return true;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'dlpAntiPeep.on failed: %{public}s', JSON.stringify(err));
      return false;
    }
  }

  /**
   * 解除订阅防窥保护状态变化通知
   * 在 EntryAbility.onDestroy 调用，避免监听器泄漏
   */
  static listenOffAntiPeepStatus(): void {
    if (!AntiPeepUtil.canUseAntiPeep()) {
      return;
    }
    try {
      dlpAntiPeep.off('dlpAntiPeep');
      hilog.info(DOMAIN, TAG, 'off(dlpAntiPeep) success');
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'dlpAntiPeep.off failed: %{public}s', JSON.stringify(err));
    }
  }

  /**
   * 拉起系统级防窥蒙层遮盖指定窗口
   * @param windowId 目标窗口 ID（从 window.getLastWindow + getWindowProperties().id 获取）
   * @returns true=拉起成功，false=拉起失败或不支持
   */
  static async showSystemMaskLayer(windowId: number): Promise<boolean> {
    if (!AntiPeepUtil.canUseAntiPeep()) {
      return false;
    }
    try {
      await dlpAntiPeep.setAntiPeepMaskLayer(windowId);
      hilog.info(DOMAIN, TAG, 'setAntiPeepMaskLayer success, windowId=%{public}d', windowId);
      return true;
    } catch (err) {
      const be = err as BusinessError;
      hilog.error(DOMAIN, TAG,
        'setAntiPeepMaskLayer failed, code=%{public}d, msg=%{public}s', be.code, be.message);
      return false;
    }
  }

  /**
   * 拉起系统设置弹窗，引导用户开启防窥保护开关
   * 用户首次开启应用内防窥保护开关时调用，引导用户去系统设置完成人脸验证 + 开启防窥保护
   * @param context UIAbilityContext（从 getUIContext().getHostContext() 获取）
   * @returns AntiPeepOptionsResult，失败返回 -1
   *   - SUCCESS：用户在弹窗中开启了防窥保护
   *   - ALREADY_ON：防窥保护已开启
   *   - 其他值：用户取消或失败
   */
  static async requestAntiPeepOptions(context: common.UIAbilityContext): Promise<dlpAntiPeep.AntiPeepOptionsResult> {
    if (!AntiPeepUtil.canUseAntiPeep()) {
      return -1 as dlpAntiPeep.AntiPeepOptionsResult;
    }
    try {
      const result: dlpAntiPeep.AntiPeepOptionsResult = await dlpAntiPeep.requestAntiPeepOptions(context);
      hilog.info(DOMAIN, TAG, 'requestAntiPeepOptions success: %{public}d', result);
      return result;
    } catch (err) {
      const be = err as BusinessError;
      hilog.error(DOMAIN, TAG,
        'requestAntiPeepOptions failed, code=%{public}d, msg=%{public}s', be.code, be.message);
      return -1 as dlpAntiPeep.AntiPeepOptionsResult;
    }
  }
}
