// #111 A3 UnexpExit 崩溃监控 30s 重启
// 对齐 Android 原版 CrashUtil 30s 时间窗判断 + HarmonyOS appRecovery 自动重启
// 混合方案：appRecovery 负责自动重启，CrashRecoveryUtil 负责记录崩溃时间 + 频繁崩溃检测
//
// 实现要点：
// 1. enableRecovery() 在 AbilityStage.onCreate 调用，启用 appRecovery（JS Crash 时自动重启）
// 2. recordCrash() 在 errorManager.onException 回调中调用，记录崩溃时间到 preferences
// 3. checkAndConsumeFrequentCrash() 在 EntryAbility.onCreate 调用，检查是否频繁崩溃并消费标记
// 4. 频繁崩溃 = 上次崩溃距今 < 30s（对齐 Android CrashUtil.newCrash 时间窗判断）
//
// 注意：errorManager 回调中应用即将崩溃，preferences.flush() 是异步的可能来不及刷盘
// 用 putSync 同步写入内存 + flush 异步刷盘（best effort），appRecovery 重启间隔通常足够 flush 完成

import { appRecovery } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'CrashRecoveryUtil';

// preferences 存储 key
const KEY_LAST_CRASH_TIME = 'last_crash_time';
const KEY_FREQUENT_CRASH_FLAG = 'frequent_crash_flag';

// 30s 时间窗（对齐 Android CrashUtil.newCrash: System.currentTimeMillis() - time > 30 * 1000L）
const CRASH_TIME_WINDOW_MS = 30 * 1000;

// preferences 实例名（独立于 tieba_settings，避免崩溃时影响主配置）
const PREF_NAME = 'crash_recovery';

export class CrashRecoveryUtil {
  /**
   * 启用应用恢复（在 AbilityStage.onCreate 调用）
   * 配置：JS Crash 时自动重启 + 故障时保存状态 + 写文件缓存
   */
  static enableRecovery(): void {
    try {
      appRecovery.enableAppRecovery(
        appRecovery.RestartFlag.RESTART_WHEN_JS_CRASH,
        appRecovery.SaveOccasionFlag.SAVE_WHEN_ERROR,
        appRecovery.SaveModeFlag.SAVE_WITH_FILE
      );
      hilog.info(DOMAIN, TAG, 'enableAppRecovery success');
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'enableAppRecovery failed: %{public}s', JSON.stringify(err));
    }
  }

  /**
   * 记录崩溃时间（在 errorManager.onException 回调中调用）
   * 30s 时间窗判断：如果上次崩溃距今 < 30s，标记为频繁崩溃
   *
   * 注意：此方法在崩溃回调中执行，用 putSync 同步写入 + flush 异步刷盘（best effort）
   */
  static recordCrash(context: common.Context): void {
    try {
      const now = Date.now();
      const pref = preferences.getPreferencesSync(context, { name: PREF_NAME });
      const lastCrashTime = pref.getSync(KEY_LAST_CRASH_TIME, 0) as number;
      const isFrequent = lastCrashTime > 0 && (now - lastCrashTime) < CRASH_TIME_WINDOW_MS;

      pref.putSync(KEY_LAST_CRASH_TIME, now);
      if (isFrequent) {
        pref.putSync(KEY_FREQUENT_CRASH_FLAG, true);
        hilog.error(DOMAIN, TAG,
          'Frequent crash detected: lastCrash=%{public}d, now=%{public}d, diff=%{public}dms',
          lastCrashTime, now, now - lastCrashTime);
      }
      pref.flush();
      hilog.error(DOMAIN, TAG, 'Crash recorded: now=%{public}d, frequent=%{public}s', now, isFrequent.toString());
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'recordCrash failed: %{public}s', JSON.stringify(err));
    }
  }

  /**
   * 检查并消费频繁崩溃标记（在 EntryAbility.onCreate 调用）
   * 如果是频繁崩溃，返回 true 并清除标记（避免下次启动重复提示）
   */
  static checkAndConsumeFrequentCrash(context: common.Context): boolean {
    try {
      const pref = preferences.getPreferencesSync(context, { name: PREF_NAME });
      const flag = pref.getSync(KEY_FREQUENT_CRASH_FLAG, false) as boolean;
      if (flag) {
        pref.putSync(KEY_FREQUENT_CRASH_FLAG, false);
        pref.flush();
        hilog.warn(DOMAIN, TAG, 'Frequent crash flag consumed, will show dialog');
        return true;
      }
      return false;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'checkAndConsumeFrequentCrash failed: %{public}s', JSON.stringify(err));
      return false;
    }
  }
}
