// #110 A2 AppStartup AbilityStage
// AppStartup 自动模式下，AbilityStage 创建后自动执行 startup_config.json 中配置的所有非 excludeFromAutoStart 任务
// 任务在 AbilityStage.onCreate 回调之前执行（由系统自动调度）
// 本类只需声明，无需手动调用 startupManager.run()

import { AbilityStage, AbilityConstant } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;

export default class EntryAbilityStage extends AbilityStage {
  onCreate(): void {
    // AppStartup 任务已在此回调之前由系统自动执行完成
    // 所有偏好值（colorMode/fontScale/imageLoadType/bduss/isWifi）已写入 AppStorage
    // errorManager 已注册（句柄在 StartupTask_ErrorManager 模块的 errorManagerId 变量）
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'EntryAbilityStage onCreate');
  }
}
