// #156 Theme-1 AppStartup 任务：主题加载（依赖 AppStorageInit，主线程）
// 读取持久化的 themeId 偏好，写入 AppStorageV2 ThemeState 供组件共享
// 对齐 StartupTask_ColorMode 的读写模式

import { StartupTask, common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppStorageV2 } from '@kit.ArkUI';
import { AppStorageManager } from '../data/AppStorage';
import { ThemeState, THEME_TIEBA } from '../theme/ThemeManager';

@Sendable
export default class StartupTask_Theme extends StartupTask {
  constructor() {
    super();
  }

  async init(context: common.AbilityStageContext): Promise<string> {
    hilog.info(0x0000, 'testTag', '%{public}s', 'StartupTask_Theme init start');
    try {
      const themeId: number = await AppStorageManager.getInstance().getNumber('themeId', THEME_TIEBA);
      const themeState = AppStorageV2.connect(ThemeState, 'theme', () => new ThemeState())!;
      themeState.setTheme(themeId);
      hilog.info(0x0000, 'testTag',
        'StartupTask_Theme init success, themeId=%{public}d', themeId);
    } catch (err) {
      // 读取失败时写入默认主题（tieba）
      const themeState = AppStorageV2.connect(ThemeState, 'theme', () => new ThemeState())!;
      themeState.setTheme(THEME_TIEBA);
      hilog.error(0x0000, 'testTag',
        'StartupTask_Theme init failed: %{public}s', JSON.stringify(err));
    }
    return 'StartupTask_Theme';
  }

  onDependencyCompleted(dependence: string, result: Object): void {
    hilog.info(0x0000, 'testTag',
      'StartupTask_Theme onDependencyCompleted, dependence=%{public}s', dependence);
  }
}
