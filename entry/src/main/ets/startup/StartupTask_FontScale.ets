// #110 A2 AppStartup 任务 3：字体缩放加载（依赖 AppStorageInit，主线程）
// 读取持久化的 fontScale 偏好，应用 setFontSizeScale
// 对齐原 EntryAbility.onCreate 中的 fontScale 读取 + setFontSizeScale 逻辑

import { StartupTask, common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppStorageManager } from '../data/AppStorage';

// @Sendable 类只能捕获 import 的变量，DOMAIN 字面量内联到 hilog 调用
// 见 arkts-sendable-imported-variables 规则

@Sendable
export default class StartupTask_FontScale extends StartupTask {
  constructor() {
    super();
  }

  async init(context: common.AbilityStageContext): Promise<string> {
    hilog.info(0x0000, 'testTag', '%{public}s', 'StartupTask_FontScale init start');
    try {
      const fontScale: number = await AppStorageManager.getInstance().getNumber('fontScale', 0);
      if (fontScale > 0) {
        // fontScale 持久化值：0=跟随系统（不调用 setFontSizeScale）, >0=用户设定的具体倍数
        context.getApplicationContext().setFontSizeScale(fontScale);
        hilog.info(0x0000, 'testTag', 'StartupTask_FontScale init success, fontScale=%{public}d', fontScale);
      } else {
        hilog.info(0x0000, 'testTag', '%{public}s', 'StartupTask_FontScale init skip (follow system)');
      }
    } catch (err) {
      hilog.error(0x0000, 'testTag',
        'StartupTask_FontScale init failed: %{public}s', JSON.stringify(err));
    }
    return 'StartupTask_FontScale';
  }

  onDependencyCompleted(dependence: string, result: Object): void {
    hilog.info(0x0000, 'testTag',
      'StartupTask_FontScale onDependencyCompleted, dependence=%{public}s', dependence);
  }
}
