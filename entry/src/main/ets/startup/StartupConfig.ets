// #110 A2 AppStartup 启动框架公共参数配置
// StartupConfigEntry 实现：设置任务超时时间（10s）+ 启动任务完成监听器
// 自动模式下，AbilityStage 创建后自动执行所有非 excludeFromAutoStart 任务

import { StartupConfig, StartupConfigEntry, StartupListener } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';

const DOMAIN = 0x0000;

export default class TiebaStartupConfigEntry extends StartupConfigEntry {
  onConfig(): StartupConfig {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'StartupConfig onConfig');

    // 所有启动任务执行完成时的回调（成功或失败都会触发）
    const onCompletedCallback = (error: BusinessError<void>) => {
      if (error) {
        hilog.error(DOMAIN, 'testTag',
          'StartupConfig onCompleted: failed, code=%{public}d, message=%{public}s',
          error.code, error.message);
      } else {
        hilog.info(DOMAIN, 'testTag', '%{public}s', 'StartupConfig onCompleted: success.');
      }
    };

    // StartupListener 是接口，用对象字面量赋值（对齐 errorManager.ErrorObserver 模式）
    const startupListener: StartupListener = {
      'onCompleted': onCompletedCallback
    };

    const config: StartupConfig = {
      'timeoutMs': 10000,
      'startupListener': startupListener
    };
    return config;
  }
}
