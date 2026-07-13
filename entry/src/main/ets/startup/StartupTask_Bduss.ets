// #110 A2 AppStartup 任务 5：账号恢复（依赖 AppStorageInit，mainThread 主线程执行）
// 读取持久化的 bduss 凭证，写入 AppStorageV2 供 FavoritePage 等页面联动登出
// 对齐原 EntryAbility.onCreate 中的 bduss 读取 + AppStorage.setOrCreate 逻辑
// #176 runOnThread 改为 mainThread：AppStorageV2.connect 不能在 taskPool 子线程使用
// （华为官方文档：AppStorageV2 与进程绑定，只能在 UI 主线程中使用）

import { StartupTask, common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppStorageManager } from '../data/AppStorage';
import { connectBduss } from '../model/AppStorageV2Models';

// @Sendable 类只能捕获 import 的变量，DOMAIN 字面量内联到 hilog 调用
// 见 arkts-sendable-imported-variables 规则

@Sendable
export default class StartupTask_Bduss extends StartupTask {
  constructor() {
    super();
  }

  async init(context: common.AbilityStageContext): Promise<string> {
    hilog.info(0x0000, 'testTag', '%{public}s', 'StartupTask_Bduss init start');
    try {
      const bduss: string = await AppStorageManager.getInstance().getString('bduss', '');
      const bdussState = connectBduss();
      bdussState.value = bduss;
      hilog.info(0x0000, 'testTag',
        'StartupTask_Bduss init success, bduss length=%{public}d', bduss.length);
    } catch (err) {
      // 读取失败时写入空串（未登录态）
      const bdussState = connectBduss();
      bdussState.value = '';
      hilog.error(0x0000, 'testTag',
        'StartupTask_Bduss init failed: %{public}s', JSON.stringify(err));
    }
    return 'StartupTask_Bduss';
  }

  onDependencyCompleted(dependence: string, result: Object): void {
    hilog.info(0x0000, 'testTag',
      'StartupTask_Bduss onDependencyCompleted, dependence=%{public}s', dependence);
  }
}
