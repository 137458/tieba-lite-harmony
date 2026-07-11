// #121 触感反馈工具类
// 封装 vibrator API，提供轻/重两种震动强度
// 受设置开关控制（vibratorEnabled 偏好），关闭时不触发震动
//
// 权限：ohos.permission.VIBRATE（system_grant 普通权限，无需用户授权）
// API：vibrator.startVibration(effect, attribute) 返回 Promise<void>
// effect 类型：{ type: 'time', duration: ms } 或 { type: 'preset', effectId, count?, intensity? }
// attribute：{ id: 0, usage: 'unknown' | 'alarm' | 'ring' | 'notification' }

import { vibrator } from '@kit.BasicServicesKit';
import { AppStorageManager } from '../data/AppStorage';

/** 触感反馈强度 */
export type VibrationIntensity = 'light' | 'heavy';

/** 触感反馈偏好 key */
const PREF_KEY_VIBRATOR_ENABLED: string = 'vibratorEnabled';

/**
 * 触感反馈工具类
 *
 * 使用方式：
 *   1. 应用启动时调用 VibratorUtil.init() 读取偏好
 *   2. 设置页 Toggle 调用 VibratorUtil.setEnabled()
 *   3. 交互场景调用 VibratorUtil.light() 或 VibratorUtil.heavy()
 *
 * 关闭时所有调用静默跳过，不抛异常
 */
export class VibratorUtil {
  /** 是否启用触感反馈（内存缓存，避免每次触发都读 preferences） */
  private static enabled: boolean = true;

  /**
   * 初始化：从 preferences 读取开关状态
   * 应在应用启动时（如 StartupTask 或 SettingsPage.aboutToAppear）调用
   */
  static async init(): Promise<void> {
    try {
      const storage: AppStorageManager = AppStorageManager.getInstance();
      await storage.ensureReady();
      VibratorUtil.enabled = await storage.getBoolean(PREF_KEY_VIBRATOR_ENABLED, true);
    } catch (err) {
      console.error(`[VibratorUtil] init failed: ${(err as Error).message}`);
    }
  }

  /**
   * 设置开关状态（设置页 Toggle onChange 调用）
   * @param enabled true=开启 false=关闭
   */
  static async setEnabled(enabled: boolean): Promise<void> {
    VibratorUtil.enabled = enabled;
    try {
      const storage: AppStorageManager = AppStorageManager.getInstance();
      await storage.setBoolean(PREF_KEY_VIBRATOR_ENABLED, enabled);
    } catch (err) {
      console.error(`[VibratorUtil] setEnabled failed: ${(err as Error).message}`);
    }
  }

  /**
   * 获取当前开关状态
   * @returns true=开启 false=关闭
   */
  static isEnabled(): boolean {
    return VibratorUtil.enabled;
  }

  /**
   * 轻震动（15ms）—— 按钮点击、Toggle 切换等常规交互
   */
  static light(): void {
    if (!VibratorUtil.enabled) {
      return;
    }
    vibrator.startVibration({ type: 'time', duration: 15 }, { id: 0, usage: 'unknown' })
      .catch((err: Error) => {
        console.error(`[VibratorUtil] light failed: ${err.message}`);
      });
  }

  /**
   * 重震动（30ms）—— 点赞、发送、长按等强调交互
   */
  static heavy(): void {
    if (!VibratorUtil.enabled) {
      return;
    }
    vibrator.startVibration({ type: 'time', duration: 30 }, { id: 0, usage: 'unknown' })
      .catch((err: Error) => {
        console.error(`[VibratorUtil] heavy failed: ${err.message}`);
      });
  }
}
