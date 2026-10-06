// #110 A2 AppStartup 任务 5：账号恢复（依赖 AppStorageInit，mainThread 主线程执行）
// 读取持久化的 bduss 凭证，判定登录态布尔写入 AppStorageV2 供页面联动
// （H05：全局状态只持布尔登录态，凭证本体仅在 CredentialVault 与网络层内存态）
// #176 runOnThread 改为 mainThread：AppStorageV2.connect 不能在 taskPool 子线程使用
// （华为官方文档：AppStorageV2 与进程绑定，只能在 UI 主线程中使用）

import { StartupTask, common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AuthSessionManager } from '../data/AuthSessionManager';
import { connectLogin } from '../model/AppStorageV2Models';

// @Sendable 类只能捕获 import 的变量，DOMAIN 字面量内联到 hilog 调用
// 见 arkts-sendable-imported-variables 规则

@Sendable
export default class StartupTask_Bduss extends StartupTask {
  constructor() {
    super();
  }

  async init(context: common.AbilityStageContext): Promise<string> {
    hilog.info(0x0000, 'StartupTask_Bduss', '%{public}s', 'StartupTask_Bduss init start');
    try {
      const bduss: string = await AuthSessionManager.migrateLegacyCredentials();
      const loginState = connectLogin();
      loginState.value = bduss.length > 0;
      hilog.info(0x0000, 'StartupTask_Bduss',
        'StartupTask_Bduss init success, bduss length=%{public}d', bduss.length);
    } catch (err) {
      // 读取失败时写入未登录态
      const loginState = connectLogin();
      loginState.value = false;
      hilog.error(0x0000, 'StartupTask_Bduss',
        'StartupTask_Bduss init failed: %{public}s', JSON.stringify(err));
    }
    return 'StartupTask_Bduss';
  }

  onDependencyCompleted(dependence: string, result: Object): void {
    hilog.info(0x0000, 'StartupTask_Bduss',
      'StartupTask_Bduss onDependencyCompleted, dependence=%{public}s', dependence);
  }
}
