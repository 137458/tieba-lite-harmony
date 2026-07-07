// #110 A2 AppStartup 任务 2：主题模式加载（依赖 AppStorageInit，主线程）
// 读取持久化的 colorMode 偏好，应用 setColorMode
// 对齐原 EntryAbility.onCreate 中的 colorMode 读取 + setColorMode 逻辑

import { StartupTask, common, ConfigurationConstant } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppStorageManager } from '../data/AppStorage';

// @Sendable 类只能捕获 import 的变量，DOMAIN 字面量内联到 hilog 调用
// 见 arkts-sendable-imported-variables 规则

@Sendable
export default class StartupTask_ColorMode extends StartupTask {
  constructor() {
    super();
  }

  async init(context: common.AbilityStageContext): Promise<string> {
    hilog.info(0x0000, 'testTag', '%{public}s', 'StartupTask_ColorMode init start');
    try {
      const colorMode: number = await AppStorageManager.getInstance().getNumber('colorMode', 0);
      const colorModeValue: number = colorMode === 1
        ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK
        : (colorMode === 2
          ? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
          : ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
      context.getApplicationContext().setColorMode(colorModeValue);
      hilog.info(0x0000, 'testTag', 'StartupTask_ColorMode init success, colorMode=%{public}d', colorMode);
    } catch (err) {
      hilog.error(0x0000, 'testTag',
        'StartupTask_ColorMode init failed: %{public}s', JSON.stringify(err));
    }
    return 'StartupTask_ColorMode';
  }

  onDependencyCompleted(dependence: string, result: Object): void {
    hilog.info(0x0000, 'testTag',
      'StartupTask_ColorMode onDependencyCompleted, dependence=%{public}s', dependence);
  }
}
