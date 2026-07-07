import { AbilityConstant, errorManager, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window, KeyboardAvoidMode } from '@kit.ArkUI';
import { registerNetworkChangeListener, unregisterNetworkChangeListener } from '../utils/NetworkUtil';
import connection from '@ohos.net.connection';
import { parseAppLinkingUri } from '../utils/AppLinkingUtil';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  // #81 网络变化监听句柄，onCreate 注册，onDestroy 注销
  private netConnection: connection.NetConnection | null = null;

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
    // #109 A1 AppLinking：冷启动时解析 want.uri，写入 AppStorage('pendingAppLinkingNav')
    // MainPage.aboutToAppear 读取此值，若 threadId > 0 自动 router.pushUrl 跳转 ThreadPage
    // 跳转完成后 MainPage 会清零，避免重复跳转
    this.handleAppLinkingWant(want);

    // #81 注册网络变化监听：WiFi/移动网络切换时实时更新 AppStorage('isWifi')，
    // 触发所有 @StorageProp('isWifi') 订阅者重绘（ThreadCard/ThreadPage/SubPostsPage 等）
    // 保留在此处：NetConnection 需 UIAbility context 长期持有，onDestroy 时注销避免泄漏
    // 网络状态首屏快照已由 StartupTask_NetworkCheck 写入 AppStorage('isWifi')
    this.netConnection = registerNetworkChangeListener((isWifi: boolean) => {
      AppStorage.setOrCreate('isWifi', isWifi);
      hilog.info(DOMAIN, 'testTag', 'Network changed, isWifi=%{public}s', String(isWifi));
    });
    if (this.netConnection === null) {
      // 注册失败时仅 StartupTask_NetworkCheck 一次性快照生效，网络切换后 isWifi 不会自动更新
      hilog.error(DOMAIN, 'testTag', '%{public}s',
        'registerNetworkChangeListener failed, network change will not trigger isWifi update');
    }

    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    // #81 注销网络变化监听，避免内存泄漏
    unregisterNetworkChangeListener(this.netConnection);
    this.netConnection = null;
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
          AppStorage.setOrCreate<number>('safeBottom', indicatorHeight > 0 ? indicatorHeight : 24);
          hilog.info(DOMAIN, 'testTag', 'FullScreen mode: safeBottom=%{public}d', indicatorHeight);
        } else {
          // 非全屏模式：系统处理避让，App 不加 padding
          // safeBottom=0 避免双重 padding（系统避让 + App padding = 底部灰色遮罩）
          AppStorage.setOrCreate<number>('safeTop', 0);
          AppStorage.setOrCreate<number>('safeBottom', 0);
          hilog.info(DOMAIN, 'testTag', '%{public}s', 'Non-fullscreen mode: safeBottom=0 (system handles avoidance)');
        }
      } catch (err) {
        // 兜底：避让区获取失败时写入默认值
        AppStorage.setOrCreate<number>('safeTop', isFullScreen ? 36 : 0);
        AppStorage.setOrCreate<number>('safeBottom', isFullScreen ? 24 : 0);
        hilog.error(DOMAIN, 'testTag', 'Failed to get avoid area. Cause: %{public}s', JSON.stringify(err));
      }
    } else {
      // getMainWindow 失败：写入默认避让值，让 loadContent 仍能执行（系统处理避让）
      AppStorage.setOrCreate<number>('safeTop', 0);
      AppStorage.setOrCreate<number>('safeBottom', 0);
      hilog.info(DOMAIN, 'testTag', '%{public}s', 'MainWindow unavailable, safeBottom=0 (system handles avoidance)');
    }

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
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
        AppStorage.setOrCreate<number>('pendingAppLinkingTid', 0);
        AppStorage.setOrCreate<boolean>('pendingAppLinkingSeeLz', false);
        return;
      }

      const result = parseAppLinkingUri(uri);
      if (result.threadId > 0) {
        AppStorage.setOrCreate<number>('pendingAppLinkingTid', result.threadId);
        AppStorage.setOrCreate<boolean>('pendingAppLinkingSeeLz', result.seeLz);
        hilog.info(DOMAIN, 'testTag',
          'AppLinking pending nav: tid=%{public}d, seeLz=%{public}s, uri=%{public}s',
          result.threadId, String(result.seeLz), uri);
      } else {
        // URI 解析失败（非帖子链接）：清零避免误跳
        AppStorage.setOrCreate<number>('pendingAppLinkingTid', 0);
        AppStorage.setOrCreate<boolean>('pendingAppLinkingSeeLz', false);
        hilog.warn(DOMAIN, 'testTag', 'AppLinking uri parsed no tid: %{public}s', uri);
      }
    } catch (err) {
      // 解析异常不应阻塞应用启动，记录日志并清零
      AppStorage.setOrCreate<number>('pendingAppLinkingTid', 0);
      AppStorage.setOrCreate<boolean>('pendingAppLinkingSeeLz', false);
      hilog.error(DOMAIN, 'testTag', 'handleAppLinkingWant exception: %{public}s', JSON.stringify(err));
    }
  }
}
