// #127 消息通知工具类
// 封装 notificationManager + workScheduler API，发布"回复我的"/"@我的"通知
// 对齐 Android NotifyJobService：CHANNEL_REPLY=2/ID_REPLY=20，CHANNEL_AT=3/ID_AT=21
//
// 通知点击行为：通过 wantAgent 拉起 EntryAbility 到前台（简化方案，后续可扩展自动切消息 Tab）
//
// API：notificationManager @kit.NotificationKit
//   - addSlot(SlotType.SOCIAL_COMMUNICATION)  创建通知渠道（幂等）
//   - isNotificationEnabled()  检查通知权限
//   - requestEnableNotification()  请求通知权限
//   - publish(NotificationRequest)  发布通知
//   - cancel(id)  取消通知
//
// workScheduler @kit.BackgroundTasksKit：
//   - startWork(WorkInfo)  注册延迟任务（系统调度，最小重复间隔 2 小时）
//   - stopWork(WorkInfo)  取消延迟任务
//
// wantAgent @kit.AbilityKit：
//   - getWantAgent(WantAgentInfo)  创建 WantAgent，用于通知点击拉起 Ability

import { notificationManager } from '@kit.NotificationKit';
import { wantAgent, WantAgent, Want, common } from '@kit.AbilityKit';
import { workScheduler } from '@kit.BackgroundTasksKit';

/** 应用 bundleName（对齐 app.json5） */
const BUNDLE_NAME: string = 'com.isczjk.tieba';
/** 通知点击拉起的 Ability 名称 */
const ABILITY_NAME: string = 'EntryAbility';
/** WorkSchedulerExtensionAbility 名称（对齐 module.json5 声明） */
const NOTIFY_WORK_ABILITY_NAME: string = 'NotifyWorkSchedulerExtensionAbility';
/** workScheduler 延迟任务 ID */
const NOTIFY_WORK_ID: number = 1;
/** workScheduler 重复间隔：2 小时（系统最小允许值，单位毫秒） */
const NOTIFY_REPEAT_CYCLE_MS: number = 2 * 60 * 60 * 1000;
/** "回复我的"通知 ID（对齐 Android NotifyJobService.ID_REPLY=20） */
const NOTIFICATION_ID_REPLY: number = 20;
/** "@我的"通知 ID（对齐 Android NotifyJobService.ID_AT=21） */
const NOTIFICATION_ID_AT: number = 21;

/**
 * 消息通知工具类
 *
 * 使用方式：
 *   1. 应用启动时调用 NotificationUtil.init() 创建通知渠道
 *   2. SettingsPage 通知开关调用 NotificationUtil.isEnabled() / requestEnable()
 *   3. WorkSchedulerExtensionAbility.onWorkStart 调用 publishReplyNotification/publishAtNotification
 *
 * 所有方法静默处理异常（记录日志不抛出），避免通知失败影响主流程
 */
export class NotificationUtil {
  /** 通知渠道是否已创建（addSlot 幂等，但重复调用有性能开销） */
  private static slotCreated: boolean = false;

  /**
   * 初始化通知渠道
   * 应在应用启动时（EntryAbility.onCreate）调用，幂等安全
   */
  static async init(): Promise<void> {
    if (NotificationUtil.slotCreated) {
      return;
    }
    try {
      // API 21 注意：addSlot 传 SlotType 枚举，不传 NotificationSlot 对象
      const slotType: notificationManager.SlotType = notificationManager.SlotType.SOCIAL_COMMUNICATION;
      await notificationManager.addSlot(slotType);
      NotificationUtil.slotCreated = true;
    } catch (err) {
      console.error(`[NotificationUtil] init addSlot failed: ${(err as Error).message}`);
    }
  }

  /**
   * 检查通知是否已启用
   * @returns true=已启用 false=未启用或查询失败
   */
  static async isEnabled(): Promise<boolean> {
    try {
      return await notificationManager.isNotificationEnabled();
    } catch (err) {
      console.error(`[NotificationUtil] isEnabled failed: ${(err as Error).message}`);
      return false;
    }
  }

  /**
   * 请求启用通知（弹出系统授权对话框）
   * @returns true=用户已授权 false=用户拒绝或请求失败
   */
  static async requestEnable(): Promise<boolean> {
    try {
      await notificationManager.requestEnableNotification();
      return true;
    } catch (err) {
      console.error(`[NotificationUtil] requestEnable failed: ${(err as Error).message}`);
      return false;
    }
  }

  /**
   * 注册消息轮询 workScheduler 延迟任务
   * 系统 每 2 小时调度一次 NotifyWorkSchedulerExtensionAbility.onWorkStart
   * startWork 幂等：相同 workId 重复调用不会创建多个任务
   *
   * EntryAbility.onCreate（偏好开启时）和 SettingsPage 开关开启时调用
   */
  static startWorkScheduler(): void {
    try {
      const workInfo: workScheduler.WorkInfo = {
        workId: NOTIFY_WORK_ID,
        bundleName: BUNDLE_NAME,
        abilityName: NOTIFY_WORK_ABILITY_NAME,
        isRepeat: true,
        isPersisted: true,
        repeatCycleTime: NOTIFY_REPEAT_CYCLE_MS,
        networkType: workScheduler.NetworkType.NETWORK_TYPE_ANY
      };
      workScheduler.startWork(workInfo);
      console.info('[NotificationUtil] workScheduler startWork success');
    } catch (err) {
      console.error(`[NotificationUtil] workScheduler startWork failed: ${(err as Error).message}`);
    }
  }

  /**
   * 取消消息轮询 workScheduler 延迟任务
   * SettingsPage 开关关闭时调用，避免不必要的后台唤醒
   */
  static stopWorkScheduler(): void {
    try {
      const workInfo: workScheduler.WorkInfo = {
        workId: NOTIFY_WORK_ID,
        bundleName: BUNDLE_NAME,
        abilityName: NOTIFY_WORK_ABILITY_NAME,
        isRepeat: true,
        isPersisted: true,
        repeatCycleTime: NOTIFY_REPEAT_CYCLE_MS
      };
      workScheduler.stopWork(workInfo, true);
      console.info('[NotificationUtil] workScheduler stopWork success');
    } catch (err) {
      console.error(`[NotificationUtil] workScheduler stopWork failed: ${(err as Error).message}`);
    }
  }

  /**
   * 构建 WantAgent：通知点击时拉起 EntryAbility 到前台
   * 使用 UPDATE_PRESENT_FLAG：如果 Ability 已存在则拉到前台，不存在则创建
   */
  private static async buildWantAgent(): Promise<WantAgent> {
    const info: wantAgent.WantAgentInfo = {
      wants: [{
        bundleName: BUNDLE_NAME,
        abilityName: ABILITY_NAME
      } as Want],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: 0,
      wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    };
    return await wantAgent.getWantAgent(info);
  }

  /**
   * 发布"回复我的"通知
   * @param context 上下文（用于获取资源字符串）
   * @param count 未读回复数
   */
  static async publishReplyNotification(context: common.Context, count: number): Promise<void> {
    const title: string = context.resourceManager.getStringSync(
      $r('app.string.notification_reply_title').id, count);
    const text: string = context.resourceManager.getStringSync(
      $r('app.string.notification_touch_to_view').id);
    await NotificationUtil.publishNotification(NOTIFICATION_ID_REPLY, title, text);
  }

  /**
   * 发布"@我的"通知
   * @param context 上下文（用于获取资源字符串）
   * @param count 未读@消息数
   */
  static async publishAtNotification(context: common.Context, count: number): Promise<void> {
    const title: string = context.resourceManager.getStringSync(
      $r('app.string.notification_at_title').id, count);
    const text: string = context.resourceManager.getStringSync(
      $r('app.string.notification_touch_to_view').id);
    await NotificationUtil.publishNotification(NOTIFICATION_ID_AT, title, text);
  }

  /**
   * 发布通知（内部方法）
   * API 21 注意：NotificationRequest.slotType 省略（类型不兼容，由 addSlot 创建的渠道自动路由）
   */
  private static async publishNotification(id: number, title: string, text: string): Promise<void> {
    try {
      const agent: WantAgent = await NotificationUtil.buildWantAgent();
      const request: notificationManager.NotificationRequest = {
        id: id,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: { title: title, text: text }
        },
        deliveryTime: Date.now(),
        showDeliveryTime: true,
        tapDismissed: true,
        wantAgent: agent
      };
      await notificationManager.publish(request);
    } catch (err) {
      console.error(`[NotificationUtil] publish failed: ${(err as Error).message}`);
    }
  }

  /**
   * 取消通知
   * @param id 通知 ID
   */
  static async cancel(id: number): Promise<void> {
    try {
      await notificationManager.cancel(id);
    } catch (err) {
      // 取消失败静默忽略（通知可能已不存在）
    }
  }
}
