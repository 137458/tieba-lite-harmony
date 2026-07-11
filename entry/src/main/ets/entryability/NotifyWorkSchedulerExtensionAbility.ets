// #127 消息轮询延迟任务
// 对齐 Android NotifyJobService：周期性调用 /c/s/msg 接口，有新消息时发通知
//
// 运行机制：
//   WorkSchedulerExtensionAbility 在独立 Extension 进程中运行（非主进程）
//   系统根据应用活跃度决定回调时机（活跃=2h/经常=4h/常用=24h/极少=48h/受限=禁止）
//   单次回调最长 2 分钟，回调结束进程销毁
//
// 进程隔离注意：
//   - Extension 进程不共享主进程内存（单例、AppStorageV2 均为新实例）
//   - preferences 基于文件级共享，同一文件名在不同进程访问同一底层文件
//   - 需要重新 init AppStorageManager + setAuth TiebaAPI 凭证

import { WorkSchedulerExtensionAbility, workScheduler } from '@kit.BackgroundTasksKit';
import { TiebaAPI } from '../api/TiebaAPI';
import { AppStorageManager } from '../data/AppStorage';
import { NotificationUtil } from '../utils/NotificationUtil';

/** 通知开关偏好 key（与 SettingsPage 一致） */
const PREF_KEY_NOTIFICATION_ENABLED: string = 'notificationEnabled';
/** BDUSS 凭证偏好 key（与 StartupTask_Bduss 一致） */
const PREF_KEY_BDUSS: string = 'bduss';
/** STOKEN 凭证偏好 key */
const PREF_KEY_STOKEN: string = 'stoken';

/**
 * 消息轮询延迟任务
 *
 * onWorkStart 流程：
 *   1. 初始化 preferences（Extension 进程首次访问需 init）
 *   2. 检查 notificationEnabled 偏好，关闭则直接返回
 *   3. 读取 bduss/stoken 凭证，未登录则直接返回
 *   4. TiebaAPI.setAuth 设置凭证（Extension 进程单例为新实例）
 *   5. NotificationUtil.init 创建通知渠道
 *   6. TiebaAPI.getMsg 获取消息未读计数
 *   7. replyMe > 0 → 发布"回复我的"通知
 *   8. atMe > 0 → 发布"@我的"通知
 *
 * 所有异常静默处理（记录日志不抛出），避免任务失败影响后续调度
 */
export default class NotifyWorkSchedulerExtensionAbility extends WorkSchedulerExtensionAbility {
  /**
   * 延迟任务回调入口
   * 系统满足调度条件时触发，在独立 Extension 进程中执行
   */
  async onWorkStart(workInfo: workScheduler.WorkInfo): Promise<void> {
    try {
      // Step 1: 初始化 preferences（Extension 进程首次访问需 init）
      await AppStorageManager.getInstance().init(this.context);

      // Step 2: 检查通知开关
      const enabled: boolean = await AppStorageManager.getInstance()
        .getBoolean(PREF_KEY_NOTIFICATION_ENABLED, false);
      if (!enabled) {
        return;
      }

      // Step 3: 读取登录凭证
      const bduss: string = await AppStorageManager.getInstance()
        .getString(PREF_KEY_BDUSS, '');
      if (bduss.length === 0) {
        return;
      }
      const stoken: string = await AppStorageManager.getInstance()
        .getString(PREF_KEY_STOKEN, '');

      // Step 4: 设置 TiebaAPI 凭证（Extension 进程单例为新实例，需重新设置）
      TiebaAPI.setAuth(bduss, stoken);

      // Step 5: 初始化通知渠道（幂等）
      await NotificationUtil.init();

      // Step 6: 获取消息未读计数
      const result = await TiebaAPI.getMsg();

      // Step 7-8: 按计数发布通知
      if (result.replyMe > 0) {
        await NotificationUtil.publishReplyNotification(this.context, result.replyMe);
      }
      if (result.atMe > 0) {
        await NotificationUtil.publishAtNotification(this.context, result.atMe);
      }
    } catch (err) {
      // 静默处理异常，避免任务失败影响后续调度
      console.error(`[NotifyWorkScheduler] onWorkStart failed: ${(err as Error).message}`);
    }
  }

  /**
   * 延迟任务结束回调
   * 系统结束任务时触发，当前无需处理
   */
  onWorkStop(workInfo: workScheduler.WorkInfo): void {
    // 无需处理
  }
}
