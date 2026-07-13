// #110 A2 AppStartup 任务 4：图片加载策略加载（依赖 AppStorageInit，mainThread 主线程执行）
// 读取持久化的 imageLoadType 偏好，写入 AppStorageV2 供组件共享
// 对齐原 EntryAbility.onCreate 中的 imageLoadType 读取 + AppStorage.setOrCreate 逻辑
// #176 runOnThread 改为 mainThread：AppStorageV2.connect 不能在 taskPool 子线程使用

import { StartupTask, common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppStorageManager } from '../data/AppStorage';
import { connectImageLoadType } from '../model/AppStorageV2Models';

// @Sendable 类只能捕获 import 的变量，DOMAIN 字面量内联到 hilog 调用
// 见 arkts-sendable-imported-variables 规则

@Sendable
export default class StartupTask_ImageLoadType extends StartupTask {
  constructor() {
    super();
  }

  async init(context: common.AbilityStageContext): Promise<string> {
    hilog.info(0x0000, 'testTag', '%{public}s', 'StartupTask_ImageLoadType init start');
    try {
      const imageLoadType: number = await AppStorageManager.getInstance().getNumber('imageLoadType', 0);
      const imageLoadTypeState = connectImageLoadType();
      imageLoadTypeState.value = imageLoadType;
      hilog.info(0x0000, 'testTag',
        'StartupTask_ImageLoadType init success, imageLoadType=%{public}d', imageLoadType);
    } catch (err) {
      // 读取失败时写入默认值 0（智能原图）
      const imageLoadTypeState = connectImageLoadType();
      imageLoadTypeState.value = 0;
      hilog.error(0x0000, 'testTag',
        'StartupTask_ImageLoadType init failed: %{public}s', JSON.stringify(err));
    }
    return 'StartupTask_ImageLoadType';
  }

  onDependencyCompleted(dependence: string, result: Object): void {
    hilog.info(0x0000, 'testTag',
      'StartupTask_ImageLoadType onDependencyCompleted, dependence=%{public}s', dependence);
  }
}
