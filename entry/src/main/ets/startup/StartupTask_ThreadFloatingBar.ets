import { StartupTask, common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppStorageManager } from '../data/AppStorage';
import { connectThreadFloatingBar } from '../model/AppStorageV2Models';

@Sendable
export default class StartupTask_ThreadFloatingBar extends StartupTask {
  constructor() {
    super();
  }

  async init(context: common.AbilityStageContext): Promise<string> {
    try {
      const enabled: boolean = await AppStorageManager.getInstance().getBoolean('threadFloatingBar', false);
      const state = connectThreadFloatingBar();
      state.value = enabled;
    } catch (err) {
      const state = connectThreadFloatingBar();
      state.value = false;
      hilog.error(0x0000, 'testTag', 'StartupTask_ThreadFloatingBar init failed: %{public}s',
        JSON.stringify(err));
    }
    return 'StartupTask_ThreadFloatingBar';
  }

  onDependencyCompleted(dependence: string, result: Object): void {
  }
}
