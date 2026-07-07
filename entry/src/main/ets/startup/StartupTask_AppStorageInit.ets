// #110 A2 AppStartup 任务 1：preferences 初始化（无依赖，主线程，主线程等待）
// 所有偏好读取任务（ColorMode/FontScale/ImageLoadType/Bduss）都依赖此任务完成
// 对齐原 EntryAbility.onCreate 中的 AppStorageManager.getInstance().init(this.context)

import { StartupTask, common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppStorageManager } from '../data/AppStorage';

// @Sendable 类只能捕获 import 的变量，DOMAIN 字面量内联到 hilog 调用
// 见 arkts-sendable-imported-variables 规则

@Sendable
export default class StartupTask_AppStorageInit extends StartupTask {
  constructor() {
    super();
  }

  async init(context: common.AbilityStageContext): Promise<string> {
    hilog.info(0x0000, 'testTag', '%{public}s', 'StartupTask_AppStorageInit init start');
    try {
      // AbilityStageContext 是 Context 子类，可直接传给 AppStorageManager.init
      await AppStorageManager.getInstance().init(context);
      hilog.info(0x0000, 'testTag', '%{public}s', 'StartupTask_AppStorageInit init success');
    } catch (err) {
      // preferences 初始化失败不抛错，降级为内存态运行（数据不持久化）
      hilog.error(0x0000, 'testTag',
        'StartupTask_AppStorageInit init failed: %{public}s', JSON.stringify(err));
    }
    return 'StartupTask_AppStorageInit';
  }

  onDependencyCompleted(dependence: string, result: Object): void {
    // 无依赖任务，此方法不会被调用
  }
}
