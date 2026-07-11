import { AbilityConstant, errorManager, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window, KeyboardAvoidMode, promptAction, AppStorageV2 } from '@kit.ArkUI';
import { registerNetworkChangeListener, unregisterNetworkChangeListener } from '../utils/NetworkUtil';
import connection from '@ohos.net.connection';
import { parseAppLinkingUri } from '../utils/AppLinkingUtil';
import { CrashRecoveryUtil } from '../utils/CrashRecoveryUtil';
import { getResourceString } from '../utils/ResourceUtil';
import { IsWifiState, SafeBottomState, PendingAppLinkingTidState, PendingAppLinkingSeeLzState } from '../model/AppStorageV2Models';
import { AppStorageManager } from '../data/AppStorage';
import { dlpAntiPeep } from '@kit.DeviceSecurityKit';
import { AntiPeepUtil, AntiPeepCallback } from '../utils/AntiPeepUtil';
import { UserAuthUtil } from '../utils/UserAuthUtil';
import { NotificationUtil } from '../utils/NotificationUtil';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  // #81 网络变化监听句柄，onCreate 注册，onDestroy 注销
  private netConnection: connection.NetConnection | null = null;
  // #111 A3 频繁崩溃标记，onCreate 检测，onWindowStageCreate loadContent 后弹对话框
  private isFrequentCrash: boolean = false;
  // #135 应用锁标记：onBackground 设为 true，onForeground 检查后重置
  // 防止冷启动时触发应用锁（冷启动由用户主动发起，无需验证）
  private hasEnteredBackground: boolean = false;
  // #149 [AntiPeep-3] 防窥蒙层已拉起标记，避免 HIDE 状态持续期间频繁拉起
  // PASS 状态恢复时重置为 false，下次 HIDE 可再次拉起
  private hasShownAntiPeepMask: boolean = false;

  /**
   * #110 A2 AppStartup 重构后，以下初始化任务已迁移到 StartupTask 子类（AbilityStage 自动执行）：
   *   - StartupTask_AppStorageInit: preferences 初始化
   *   - StartupTask_ColorMode: 主题模式加载 + setColorMode
   *   - StartupTask_FontScale: 字体缩放加载 + setFontSizeScale
   *   - StartupTask_ImageLoadType: 图片加载策略写入 AppStorage
   *   - StartupTask_Bduss: 账号凭证恢复写入 AppStorage
   *   - StartupTask_NetworkCheck: 网络状态快照写入 AppStorage
   *   - StartupTask_ErrorManager: 全局异常监听注册（句柄写入 AppStorage('errorManagerId')）
   *
   * 保留在本方法的原因为需要 want 或 UIAbility context 长期持有：
   *   - handleAppLinkingWant: 需 want.uri 参数解析 AppLinking
   *   - registerNetworkChangeListener: 需 UIAbility context 长期持有 NetConnection + onDestroy 注销
   */
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // #111 A3 检查是否频繁崩溃（30s 内再次启动），标记后 onWindowStageCreate 弹对话框提示
    this.isFrequentCrash = CrashRecoveryUtil.checkAndConsumeFrequentCrash(this.context);

    // #109 A1 AppLinking：冷启动时解析 want.uri，写入 AppStorage('pendingAppLinkingNav')
    // MainPage.aboutToAppear 读取此值，若 threadId > 0 自动 router.pushUrl 跳转 ThreadPage
    // 跳转完成后 MainPage 会清零，避免重复跳转
    this.handleAppLinkingWant(want);

    // #81 注册网络变化监听：WiFi/移动网络切换时实时更新 AppStorage('isWifi')，
    // 触发所有 @StorageProp('isWifi') 订阅者重绘（ThreadCard/ThreadPage/SubPostsPage 等）
    // 保留在此处：NetConnection 需 UIAbility context 长期持有，onDestroy 时注销避免泄漏
    // 网络状态首屏快照已由 StartupTask_NetworkCheck 写入 AppStorage('isWifi')
    this.netConnection = registerNetworkChangeListener((isWifi: boolean) => {
      const isWifiState = AppStorageV2.connect(IsWifiState, 'isWifi', () => new IsWifiState())!;
      isWifiState.value = isWifi;
      hilog.info(DOMAIN, 'testTag', 'Network changed, isWifi=%{public}s', String(isWifi));
    });
    if (this.netConnection === null) {
      // 注册失败时仅 StartupTask_NetworkCheck 一次性快照生效，网络切换后 isWifi 不会自动更新
      hilog.error(DOMAIN, 'testTag', '%{public}s',
        'registerNetworkChangeListener failed, network change will not trigger isWifi update');
    }

    // #127 Push Kit：初始化通知渠道 + 根据偏好注册消息轮询 workScheduler 延迟任务
    this.setupNotification().catch((err: Error) => {
      hilog.error(DOMAIN, 'testTag', 'setupNotification failed: %{public}s', err.message);
    });

    // #149 [AntiPeep-3] 根据偏好注册防窥保护监听器（异步，不阻塞 onCreate）
    this.setupAntiPeepGuard().catch((err: Error) => {
      hilog.error(DOMAIN, 'testTag', 'setupAntiPeepGuard failed: %{public}s', err.message);
    });

    // #149 [AntiPeep-3] 注册 EventHub 事件：SettingsPage 开关切换后通知 EntryAbility 重新注册监听器
    // 用户在设置页打开/关闭防窥开关时，onAntiPeepToggle emit 此事件，EntryAbility 重新调用 setupAntiPeepGuard
    this.context.eventHub.on('setupAntiPeepGuard', () => {
      this.setupAntiPeepGuard().catch((err: Error) => {
        hilog.error(DOMAIN, 'testTag', 'setupAntiPeepGuard event failed: %{public}s', err.message);
      });
    });

    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  /**
   * #149 [AntiPeep-3] 根据 antiPeepEnabled 偏好注册/注销防窥保护监听器
   *
   * 流程（对齐官方示例 https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/devicesecurity-dlpantipeep）：
   * 1. canUseAntiPeep 检测设备支持（不支持直接返回）
   * 2. 先 listenOff 注销旧监听器（避免重复注册，setupAntiPeepGuard 会被多次调用）
   * 3. 读取 antiPeepEnabled 偏好（false 直接返回，保持已注销状态）
   * 4. 注册 dlpAntiPeep.on 监听器：
   *    - HIDE 状态时若未拉起蒙层则调用 showSystemMaskLayer（hasShownAntiPeepMask 避免频繁拉起）
   *    - PASS 状态时重置 hasShownAntiPeepMask，下次 HIDE 可再次拉起
   *
   * 调用时机：
   *   - EntryAbility.onCreate（冷启动根据偏好注册）
   *   - SettingsPage.onAntiPeepToggle 通过 eventHub.emit('setupAntiPeepGuard') 触发（开关切换后立即生效）
   */
  private async setupAntiPeepGuard(): Promise<void> {
    try {
      if (!AntiPeepUtil.canUseAntiPeep()) {
        return;
      }
      // 先注销旧监听器（setupAntiPeepGuard 可能被多次调用，避免重复注册）
      AntiPeepUtil.listenOffAntiPeepStatus();
      await AppStorageManager.getInstance().ensureReady();
      const enabled: boolean = await AppStorageManager.getInstance().getBoolean('antiPeepEnabled', false);
      if (!enabled) {
        return;
      }
      // 重置蒙层标记
      this.hasShownAntiPeepMask = false;
      // 注册监听器：HIDE 状态时拉起系统蒙层遮盖当前窗口
      const callback: AntiPeepCallback = {
        onStatusChanged: async (status: dlpAntiPeep.DlpAntiPeepStatus): Promise<void> => {
          if (status === dlpAntiPeep.DlpAntiPeepStatus.HIDE) {
            // hasShownAntiPeepMask 避免在 HIDE 状态持续期间频繁拉起蒙层
            if (this.hasShownAntiPeepMask) {
              return;
            }
            try {
              const win: window.Window = await window.getLastWindow(this.context);
              const windowId: number = win.getWindowProperties().id;
              await AntiPeepUtil.showSystemMaskLayer(windowId);
              this.hasShownAntiPeepMask = true;
            } catch (err) {
              hilog.error(DOMAIN, 'testTag',
                'AntiPeep showSystemMaskLayer failed: %{public}s', (err as Error).message);
            }
          } else if (status === dlpAntiPeep.DlpAntiPeepStatus.PASS) {
            // 无人窥视时重置标记，下次 HIDE 可再次拉起蒙层
            this.hasShownAntiPeepMask = false;
          }
        }
      };
      AntiPeepUtil.listenOnAntiPeepStatus(callback);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'setupAntiPeepGuard exception: %{public}s', (err as Error).message);
    }
  }

  /**
   * #127 Push Kit：初始化通知渠道 + 根据偏好注册消息轮询 workScheduler 延迟任务
   *
   * 流程：
   * 1. NotificationUtil.init() 创建通知渠道（SOCIAL_COMMUNICATION，幂等）
   * 2. 读取 notificationEnabled 偏好
   * 3. 若已开启，调用 NotificationUtil.startWorkScheduler() 注册延迟任务
   *    （系统每 2 小时调度一次，ExtensionAbility.onWorkStart 会再次检查偏好）
   *
   * 偏好关闭时不注册，避免不必要的后台唤醒
   */
  private async setupNotification(): Promise<void> {
    try {
      await NotificationUtil.init();
      await AppStorageManager.getInstance().ensureReady();
      const enabled: boolean = await AppStorageManager.getInstance().getBoolean('notificationEnabled', false);
      if (enabled) {
        NotificationUtil.startWorkScheduler();
      }
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'setupNotification exception: %{public}s', (err as Error).message);
    }
  }

  onDestroy(): void {
    // #81 注销网络变化监听，避免内存泄漏
    unregisterNetworkChangeListener(this.netConnection);
    this.netConnection = null;
    // #149 [AntiPeep-3] 注销防窥保护监听器，避免内存泄漏
    AntiPeepUtil.listenOffAntiPeepStatus();
    // #96 注销全局异常监听，避免内存泄漏
    // #110 errorManagerId 由 StartupTask_ErrorManager 写入 AppStorage，此处读取注销
    const errorManagerId: number = AppStorage.get<number>('errorManagerId') ?? -1;
    if (errorManagerId >= 0) {
      try {
        errorManager.off('error', errorManagerId);
      } catch (err) {
        hilog.error(DOMAIN, 'testTag', 'Failed to unregister errorManager: %{public}s', JSON.stringify(err));
      }
      AppStorage.setOrCreate<number>('errorManagerId', -1);
    }
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  async onWindowStageCreate(windowStage: window.WindowStage): Promise<void> {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    // 全局沉浸式配置（issue #18）
    // setWindowLayoutFullScreen 让窗口内容延伸到状态栏区域，配合组件 expandSafeArea 实现沉浸
    // #93 关键修复：setWindowLayoutFullScreen 失败时 safeBottom 必须为 0
    // - 全屏成功：App 自己处理避让，safeBottom = 实际导航指示器高度
    // - 全屏失败：系统处理避让（非全屏窗口），App 不再加 padding，否则双重 padding 导致底部灰色遮罩
    // #96 修复：getMainWindow 包入 try-catch，避免窗口服务异常时整个 onWindowStageCreate
    // 失败导致 loadContent 永不执行、应用永久白屏无恢复路径
    let mainWindow: window.Window | null = null;
    try {
      mainWindow = await windowStage.getMainWindow();
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'getMainWindow failed: %{public}s', JSON.stringify(err));
    }

    let isFullScreen: boolean = false;
    if (mainWindow !== null) {
      try {
        await mainWindow.setWindowLayoutFullScreen(true);
        isFullScreen = true;
      } catch (err) {
        // 部分设备/模拟器会返回 1300002（窗口服务异常）
        // 非全屏模式下系统自己处理状态栏和导航栏避让，App 不需要加 padding
        hilog.error(DOMAIN, 'testTag', 'setWindowLayoutFullScreen failed (non-fullscreen mode): %{public}s', JSON.stringify(err));
      }

      // 全局键盘避让 + safeBottom 写入
      try {
        // 全局键盘避让：OFFSET 模式只调整焦点组件位置，不压缩窗口布局
        // #93 修复 bindSheet 回复工具栏不跟键盘上移：
        // bindSheet 是半模态浮层，独立于页面根节点，不受全局 RESIZE 影响
        // 之前用 RESIZE + sheet keyboardAvoidMode=NONE 是错误判断（sheet 不响应全局 RESIZE）
        // 现在改为 OFFSET（让页面级 TextInput 走 OFFSET）+ sheet 自身用 TRANSLATE_AND_RESIZE
        // （见 ThreadPage.ets bindSheet keyboardAvoidMode 配置）
        // 避免双套避让机制冲突：全局 RESIZE + sheet TRANSLATE_AND_RESIZE 会双重压缩
        mainWindow.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.OFFSET);

        if (isFullScreen) {
          // 全屏模式：App 自己处理避让，写入实际避让高度
          const systemAvoid = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
          AppStorage.setOrCreate<number>('safeTop', px2vp(systemAvoid.topRect.height));
          const indicatorAvoid = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
          const indicatorHeight = px2vp(indicatorAvoid.bottomRect.height);
          // 设备无手势条（如非全面屏）时 indicatorHeight=0，用兜底值 24 避免底部 padding 不足
          const safeBottomState = AppStorageV2.connect(SafeBottomState, 'safeBottom', () => new SafeBottomState())!;
          safeBottomState.value = indicatorHeight > 0 ? indicatorHeight : 24;
          hilog.info(DOMAIN, 'testTag', 'FullScreen mode: safeBottom=%{public}d', indicatorHeight);
        } else {
          // 非全屏模式：系统处理避让，App 不加 padding
          // safeBottom=0 避免双重 padding（系统避让 + App padding = 底部灰色遮罩）
          AppStorage.setOrCreate<number>('safeTop', 0);
          const safeBottomState = AppStorageV2.connect(SafeBottomState, 'safeBottom', () => new SafeBottomState())!;
          safeBottomState.value = 0;
          hilog.info(DOMAIN, 'testTag', '%{public}s', 'Non-fullscreen mode: safeBottom=0 (system handles avoidance)');
        }
      } catch (err) {
        // 兜底：避让区获取失败时写入默认值
        AppStorage.setOrCreate<number>('safeTop', isFullScreen ? 36 : 0);
        const safeBottomState = AppStorageV2.connect(SafeBottomState, 'safeBottom', () => new SafeBottomState())!;
        safeBottomState.value = isFullScreen ? 24 : 0;
        hilog.error(DOMAIN, 'testTag', 'Failed to get avoid area. Cause: %{public}s', JSON.stringify(err));
      }
    } else {
      // getMainWindow 失败：写入默认避让值，让 loadContent 仍能执行（系统处理避让）
      AppStorage.setOrCreate<number>('safeTop', 0);
      const safeBottomState = AppStorageV2.connect(SafeBottomState, 'safeBottom', () => new SafeBottomState())!;
      safeBottomState.value = 0;
      hilog.info(DOMAIN, 'testTag', '%{public}s', 'MainWindow unavailable, safeBottom=0 (system handles avoidance)');
    }

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');

      // #111 A3 频繁崩溃提示对话框（loadContent 后 UIContext 可用）
      // 复用 onWindowStageCreate 开头已 await 的 mainWindow，避免再次异步获取
      if (this.isFrequentCrash && mainWindow !== null) {
        try {
          const uiContext = mainWindow.getUIContext();
          uiContext.getPromptAction().showDialog({
            title: getResourceString($r('app.string.frequent_crash_title')),
            message: getResourceString($r('app.string.frequent_crash_message')),
            buttons: [
              { text: getResourceString($r('app.string.frequent_crash_retry')), color: $r('app.color.primary') },
              { text: getResourceString($r('app.string.frequent_crash_exit')), color: $r('app.color.text_secondary') }
            ]
          }).then((result: promptAction.ShowDialogSuccessResponse) => {
            if (result.index === 1) {
              // 用户选择退出，终止应用
              this.context.terminateSelf();
            }
            // 用户选择重试，继续运行（已自动重启）
          }).catch((dialogErr: Error) => {
            hilog.error(DOMAIN, 'testTag', 'showDialog failed: %{public}s', dialogErr.message);
          });
        } catch (dialogErr) {
          hilog.error(DOMAIN, 'testTag', 'Frequent crash dialog failed: %{public}s', JSON.stringify(dialogErr));
        }
        this.isFrequentCrash = false;
      }
    });
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
    // #135 应用锁验证：应用从后台切回前台时，若开启了应用锁则拉起生物识别认证
    // 防止冷启动触发（冷启动由用户主动发起，无需验证；仅当应用曾进入后台后才检查）
    if (this.hasEnteredBackground) {
      this.hasEnteredBackground = false;
      this.checkAppLock().catch((err: Error) => {
        hilog.error(DOMAIN, 'testTag', '%{public}s', `checkAppLock failed: ${err.message}`);
      });
    }
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
    // #135 标记应用进入后台，供 onForeground 检查
    this.hasEnteredBackground = true;
  }

  /**
   * #135 应用锁验证
   * 读取 appLockEnabled 偏好，若开启则拉起系统生物识别认证
   * 认证失败/取消/异常：调用 terminateSelf 退出应用（保证未授权用户无法访问）
   */
  private async checkAppLock(): Promise<void> {
    try {
      const enabled: boolean = await AppStorageManager.getInstance().getBoolean('appLockEnabled', false);
      if (!enabled) {
        return;
      }
      const authed: boolean = await UserAuthUtil.authenticate(
        getResourceString($r('app.string.settings_app_lock'))
      );
      if (!authed) {
        // 认证失败/取消：退出应用
        this.context.terminateSelf();
      }
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', '%{public}s', `checkAppLock error: ${(err as Error).message}`);
      // 异常时也退出，保证安全
      this.context.terminateSelf();
    }
  }

  /**
   * #109 A1 AppLinking：热启动场景
   * 应用已在后台运行，用户点击外部链接拉起应用时回调
   * 解析 want.uri 写入 AppStorage('pendingAppLinkingNav')，
   * MainPage 通过 @StorageLink + @Watch 监听变化触发跳转
   */
  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.handleAppLinkingWant(want);
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onNewWant');
  }

  /**
   * #109 A1 AppLinking：解析 want.uri 提取 threadId/seeLz 写入 AppStorage
   * 冷启动 onCreate + 热启动 onNewWant 共用此方法
   * AppStorage key 设计：
   *   - pendingAppLinkingTid: number  目标帖子 ID（0 表示无待跳转）
   *   - pendingAppLinkingSeeLz: boolean  是否只看楼主
   * MainPage 消费后清零 pendingAppLinkingTid，避免重复跳转
   */
  private handleAppLinkingWant(want: Want): void {
    try {
      const uri: string | undefined = want.uri;
      if (!uri || uri.length === 0) {
        // 非链接拉起（桌面图标等），清零待跳转标志避免误跳
        const tidState = AppStorageV2.connect(PendingAppLinkingTidState, 'pendingAppLinkingTid', () => new PendingAppLinkingTidState())!;
        tidState.value = 0;
        const seeLzState = AppStorageV2.connect(PendingAppLinkingSeeLzState, 'pendingAppLinkingSeeLz', () => new PendingAppLinkingSeeLzState())!;
        seeLzState.value = false;
        return;
      }

      const result = parseAppLinkingUri(uri);
      if (result.threadId > 0) {
        const tidState = AppStorageV2.connect(PendingAppLinkingTidState, 'pendingAppLinkingTid', () => new PendingAppLinkingTidState())!;
        tidState.value = result.threadId;
        const seeLzState = AppStorageV2.connect(PendingAppLinkingSeeLzState, 'pendingAppLinkingSeeLz', () => new PendingAppLinkingSeeLzState())!;
        seeLzState.value = result.seeLz;
        hilog.info(DOMAIN, 'testTag',
          'AppLinking pending nav: tid=%{public}d, seeLz=%{public}s, uri=%{public}s',
          result.threadId, String(result.seeLz), uri);
      } else {
        // URI 解析失败（非帖子链接）：清零避免误跳
        const tidState = AppStorageV2.connect(PendingAppLinkingTidState, 'pendingAppLinkingTid', () => new PendingAppLinkingTidState())!;
        tidState.value = 0;
        const seeLzState = AppStorageV2.connect(PendingAppLinkingSeeLzState, 'pendingAppLinkingSeeLz', () => new PendingAppLinkingSeeLzState())!;
        seeLzState.value = false;
        hilog.warn(DOMAIN, 'testTag', 'AppLinking uri parsed no tid: %{public}s', uri);
      }
    } catch (err) {
      // 解析异常不应阻塞应用启动，记录日志并清零
      const tidState = AppStorageV2.connect(PendingAppLinkingTidState, 'pendingAppLinkingTid', () => new PendingAppLinkingTidState())!;
      tidState.value = 0;
      const seeLzState = AppStorageV2.connect(PendingAppLinkingSeeLzState, 'pendingAppLinkingSeeLz', () => new PendingAppLinkingSeeLzState())!;
      seeLzState.value = false;
      hilog.error(DOMAIN, 'testTag', 'handleAppLinkingWant exception: %{public}s', JSON.stringify(err));
    }
  }
}
