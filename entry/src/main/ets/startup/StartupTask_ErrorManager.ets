// #110 A2 AppStartup 任务 7：全局未捕获异常监听注册（无依赖，主线程）
// 注册 errorManager.on('error') 捕获 async 未 await / JSON.parse 失败等异常
// 对齐原 EntryAbility.onCreate 中的 errorManager 注册逻辑
// 注意：errorManagerId 写入 AppStorage('errorManagerId')，EntryAbility.onDestroy 读取注销
// #111 A3 扩展：onException 回调中调用 CrashRecoveryUtil.recordCrash 记录崩溃时间

import { StartupTask, common, errorManager } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CrashRecoveryUtil } from '../utils/CrashRecoveryUtil';

// @Sendable 类只能捕获 import 的变量，DOMAIN 字面量内联到 hilog 调用
// 见 arkts-sendable-imported-variables 规则

@Sendable
export default class StartupTask_ErrorManager extends StartupTask {
  constructor() {
    super();
  }

  async init(context: common.AbilityStageContext): Promise<string> {
    hilog.info(0x0000, 'testTag', '%{public}s', 'StartupTask_ErrorManager init start');
    try {
      // #97 修复：ArkTS 严格模式 arkts-implements-only-iface 禁止 implements 类，
      // errorManager.ErrorObserver 在 .d.ts 中被声明为类（非接口），
      // 改为对象字面量赋值（对齐华为官方 ErrorManagerDemo 示例写法）
      const errorObserver: errorManager.ErrorObserver = {
        onUnhandledException: (errMsg: string): void => {
          hilog.error(0x0000, 'testTag', 'Unhandled exception: %{public}s', errMsg);
        },
        onException: (errObject: Error): void => {
          // Error.stack 在 ArkTS 中可能为 undefined，需手动兜底避免 hilog 拼接异常
          const stack: string = errObject.stack ? errObject.stack : '';
          hilog.error(0x0000, 'testTag',
            'Unhandled error - name: %{public}s, message: %{public}s, stack: %{public}s',
            errObject.name, errObject.message, stack);
          // #111 A3 记录崩溃时间，用于 30s 时间窗频繁崩溃检测
          CrashRecoveryUtil.recordCrash(context);
        }
      };
      const id: number = errorManager.on('error', errorObserver);
      // 写入 AppStorage 供 EntryAbility.onDestroy 读取注销（跨模块共享句柄）
      AppStorage.setOrCreate<number>('errorManagerId', id);
      hilog.info(0x0000, 'testTag',
        'StartupTask_ErrorManager init success, errorManagerId=%{public}d', id);
    } catch (err) {
      hilog.error(0x0000, 'testTag',
        'StartupTask_ErrorManager init failed: %{public}s', JSON.stringify(err));
    }
    return 'StartupTask_ErrorManager';
  }

  onDependencyCompleted(dependence: string, result: Object): void {
    // 无依赖任务，此方法不会被调用
  }
}
