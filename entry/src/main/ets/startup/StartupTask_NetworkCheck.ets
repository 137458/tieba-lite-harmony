// #110 A2 AppStartup 任务 6：网络状态快照（无依赖，mainThread 主线程执行）
// 一次性查询当前是否 WiFi 网络，写入 AppStorageV2 供图片加载策略组件使用
// 对齐原 EntryAbility.onCreate 中的 isWifi 检查 + AppStorage.setOrCreate 逻辑
// #176 runOnThread 改为 mainThread：AppStorageV2.connect 不能在 taskPool 子线程使用
// 注意：网络变化监听（registerNetworkChangeListener）仍保留在 EntryAbility.onCreate，
//       因为需要 UIAbility context 长期持有 NetConnection 对象 + onDestroy 注销

import { StartupTask, common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { isWifi as checkIsWifi } from '../utils/NetworkUtil';
import { connectIsWifi } from '../model/AppStorageV2Models';

// @Sendable 类只能捕获 import 的变量，DOMAIN 字面量内联到 hilog 调用
// 见 arkts-sendable-imported-variables 规则

@Sendable
export default class StartupTask_NetworkCheck extends StartupTask {
  constructor() {
    super();
  }

  async init(context: common.AbilityStageContext): Promise<string> {
    hilog.info(0x0000, 'testTag', '%{public}s', 'StartupTask_NetworkCheck init start');
    try {
      const wifi: boolean = await checkIsWifi();
      const isWifiState = connectIsWifi();
      isWifiState.value = wifi;
      hilog.info(0x0000, 'testTag',
        'StartupTask_NetworkCheck init success, isWifi=%{public}s', String(wifi));
    } catch (err) {
      // 检查失败时按非 WiFi 处理（保守省流）
      const isWifiState = connectIsWifi();
      isWifiState.value = false;
      hilog.error(0x0000, 'testTag',
        'StartupTask_NetworkCheck init failed: %{public}s', JSON.stringify(err));
    }
    return 'StartupTask_NetworkCheck';
  }

  onDependencyCompleted(dependence: string, result: Object): void {
    // 无依赖任务，此方法不会被调用
  }
}
