import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window, KeyboardAvoidMode } from '@kit.ArkUI';
import { AppStorageManager } from '../data/AppStorage';
import { isWifi as checkIsWifi, registerNetworkChangeListener, unregisterNetworkChangeListener } from '../utils/NetworkUtil';
import connection from '@ohos.net.connection';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  // #81 网络变化监听句柄，onCreate 注册，onDestroy 注销
  private netConnection: connection.NetConnection | null = null;
  async onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): Promise<void> {
    // 必须await：确保preferences初始化完成后再进入onWindowStageCreate，
    // 否则Index.aboutToAppear读取时pref仍为null，getString返回默认空串，
    // 已登录用户会被误判为未登录跳转到LoginPage（P0竞态修复）
    try {
      await AppStorageManager.getInstance().init(this.context);
    } catch (err) {
      // preferences 初始化失败（磁盘异常/权限问题）时记录错误日志，
      // 不抛出避免应用无法启动，降级为内存态运行（数据不持久化）
      hilog.error(DOMAIN, 'testTag', 'Failed to init AppStorage. Cause: %{public}s', JSON.stringify(err));
    }

    // 读取持久化的颜色模式偏好（设置页 SettingsPage.setColorMode 写入）
    // 必须在 AppStorageManager.init 之后调用，否则 getNumber 返回默认值 0
    try {
      const colorMode: number = await AppStorageManager.getInstance().getNumber('colorMode', 0);
      const colorModeValue: number = colorMode === 1
        ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK
        : (colorMode === 2
          ? ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT
          : ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
      this.context.getApplicationContext().setColorMode(colorModeValue);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }

    // 读取持久化的字体大小倍数（设置页 SettingsPage.setFontScale 写入）
    // setFontSizeScale 是 API 13+ 应用级字体缩放 API，自动影响所有 fp 单位的 Text 组件
    // 调用后应用字体不再跟随系统变化，由用户在设置页手动控制
    try {
      const fontScale: number = await AppStorageManager.getInstance().getNumber('fontScale', 0);
      if (fontScale > 0) {
        // fontScale 持久化值：0=跟随系统（不调用 setFontSizeScale）, >0=用户设定的具体倍数
        this.context.getApplicationContext().setFontSizeScale(fontScale);
      }
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set fontScale. Cause: %{public}s', JSON.stringify(err));
    }

    // 预读 imageLoadType 和 isWifi 写入 AppStorage，
    // 供 ThreadCard / ThreadPage / SubPostsPage 等组件通过 @StorageProp 共享读取
    // SettingsPage.setImageLoadType 修改后会同步更新 AppStorage('imageLoadType')
    // #81 网络变化监听在 onCreate 末尾注册，这里先做一次性快照保证首屏正确
    try {
      const imageLoadType: number = await AppStorageManager.getInstance().getNumber('imageLoadType', 0);
      AppStorage.setOrCreate('imageLoadType', imageLoadType);
    } catch (err) {
      AppStorage.setOrCreate('imageLoadType', 0);
      hilog.error(DOMAIN, 'testTag', 'Failed to load imageLoadType. Cause: %{public}s', JSON.stringify(err));
    }
    try {
      const wifi: boolean = await checkIsWifi();
      AppStorage.setOrCreate('isWifi', wifi);
    } catch (err) {
      AppStorage.setOrCreate('isWifi', false);
      hilog.error(DOMAIN, 'testTag', 'Failed to check isWifi. Cause: %{public}s', JSON.stringify(err));
    }

    // #81 注册网络变化监听：WiFi/移动网络切换时实时更新 AppStorage('isWifi')，
    // 触发所有 @StorageProp('isWifi') 订阅者重绘（ThreadCard/ThreadPage/SubPostsPage 等）
    // onDestroy 时注销，避免内存泄漏
    this.netConnection = registerNetworkChangeListener((isWifi: boolean) => {
      AppStorage.setOrCreate('isWifi', isWifi);
      hilog.info(DOMAIN, 'testTag', 'Network changed, isWifi=%{public}s', String(isWifi));
    });
    if (this.netConnection === null) {
      // 注册失败时仅 onCreate 一次性快照生效，网络切换后 isWifi 不会自动更新
      hilog.error(DOMAIN, 'testTag', '%{public}s',
        'registerNetworkChangeListener failed, network change will not trigger isWifi update');
    }

    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    // #81 注销网络变化监听，避免内存泄漏
    unregisterNetworkChangeListener(this.netConnection);
    this.netConnection = null;
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  async onWindowStageCreate(windowStage: window.WindowStage): Promise<void> {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    // 全局键盘避让：RESIZE 压缩窗口布局，让底部工具栏（发送/照片/表情按钮）可见
    // 解决 ReplyBox（bindSheet 内 TextArea）/ ReplyPage 底部工具栏不跟键盘抬起的问题
    // 默认 OFFSET 模式只调整焦点组件位置，底部工具栏会被键盘遮挡
    // 沉浸式效果由各页面 expandSafeArea 组件级方案实现（华为官方推荐，setWindowLayoutFullScreen 已废弃）
    try {
      const mainWindow = await windowStage.getMainWindow();
      mainWindow.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set keyboard avoid mode. Cause: %{public}s', JSON.stringify(err));
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
}