// #110 A2 AppStartup 任务 5：账号恢复（依赖 AppStorageInit，taskPool 异步线程）
// 读取持久化的 bduss 凭证，写入 ArkUI AppStorage 供 FavoritePage 等页面 @StorageProp('bduss') 联动登出
// 对齐原 EntryAbility.onCreate 中的 bduss 读取 + AppStorage.setOrCreate 逻辑

import { StartupTask, common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppStorageV2 } from '@kit.ArkUI';
import { AppStorageManager } from '../data/AppStorage';
import { BdussState } from '../model/AppStorageV2Models';

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
      const bdussState = AppStorageV2.connect(BdussState, 'bduss', () => new BdussState())!;
      bdussState.value = bduss;
      hilog.info(0x0000, 'testTag',
        'StartupTask_Bduss init success, bduss length=%{public}d', bduss.length);
    } catch (err) {
      // 读取失败时写入空串（未登录态）
      const bdussState = AppStorageV2.connect(BdussState, 'bduss', () => new BdussState())!;
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
