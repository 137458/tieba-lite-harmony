import { common } from '@kit.AbilityKit';
import { HdsNavigation } from '@kit.UIDesignKit';
import { TiebaAPI } from '../api/TiebaAPI';
import { AppStorageManager } from '../data/AppStorage';
import { BooleanPrefs, NumberPrefs, StringPrefs } from '../data/PreferenceKeys';
import { CredentialVault } from '../data/CredentialVault';
import { CryptoUtil } from '../utils/CryptoUtil';
import { ErrorView } from '../components/ErrorView';
import { connectTheme, ThemeState, THEME_TIEBA } from '../theme/ThemeManager';
import { extractAvatarColor, toPrimaryLight } from '../utils/DynamicColorUtil';
import { ForumsNeedRefreshState, connectForumsNeedRefresh } from '../model/AppStorageV2Models';
import { RouterUtil } from '../utils/RouterUtil';
import { Logger } from '../utils/Logger';
import { getErrMessage } from '../utils/ResourceUtil';

const TAG: string = 'Index';

@Entry
@ComponentV2
struct Index {
  @Local isLoggedIn: boolean = false;
  @Local isLoading: boolean = true;
  // #96 AppStorage ensureReady 失败标志：true 时显示 ErrorView 错误页（非白屏）+ 重试按钮
  @Local storageError: boolean = false;
  @Local themeState: ThemeState = connectTheme();
  // #162 Navigation 容器的导航栈
  // 通过 RouterUtil.setStack 注册到全局，页面通过 RouterUtil.push/replace/back 操作
  @Local pathStack: NavPathStack = new NavPathStack();

  async aboutToAppear() {
    // #162 注册全局 NavPathStack
    // 各页面通过 RouterUtil.getStack() 或 NavDestinationContext.pathStack 获取栈实例
    RouterUtil.setStack(this.pathStack);
    // #167 P1 #3：NavPathStack 弹空兜底
    // 场景：用户在 MainPage（栈底）按返回键，系统默认 pop MainPage 导致栈空，
    // Index navBar 会显示空白 loading 页，用户卡住无法退出应用。
    // 方案：setInterception 监听 willShow，当 to === 'navBar'（栈弹空）时延迟检查
    // 栈大小——用户 pop 弹空：栈为空，terminateSelf() 退出应用；
    // 代码 clear+push（如 WebLoginPage 登录成功 backToRoot+replace）：clear 和 push
    // 同步连续执行，setTimeout 执行时栈已有新页面，不退出。
    // setTimeout 异步避免在 Navigation 路由切换回调内同步销毁组件导致状态不一致。
    // #195 路由清理：router.back() → UIAbilityContext.terminateSelf()
    // （RouterUtil.back() 基于 NavPathStack.pop()，栈空时不退出应用）
    const abilityContext: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.pathStack.setInterception({
      willShow: (from: NavDestinationContext | 'navBar', to: NavDestinationContext | 'navBar',
        operation: NavigationOperation, animated: boolean) => {
        if (to === 'navBar') {
          setTimeout(() => {
            if (RouterUtil.size() === 0) {
              abilityContext.terminateSelf();
            }
          }, 0);
        }
      }
    });
    // #156 主题冷启动修复：StartupTask_Theme 在 AbilityStage 上下文中设置 @Trace 属性，
    // 但 @ObservedV2 的变化在无 UI 观察者时可能不被 ArkUI 框架感知。
    // 在首个 @ComponentV2 页面的 aboutToAppear 中重新 setTheme，确保 @Trace 变化在 UI 上下文中生效。
    // M03：13 项偏好读回与哨兵迁移已迁入 StartupTask_Prefs（AbilityStage 期装配），
    // 此处仅保留 #156 所需的 setTheme 兜底与 #158 动态取色（后者含网络 I/O，
    // 迁入 waitOnMainThread 启动任务会阻塞 AbilityStage→loadContent，故留在 UI 侧）。
    try {
      await AppStorageManager.getInstance().ensureReady();
      const storage: AppStorageManager = AppStorageManager.getInstance();
      const pDynamicEnabled: Promise<boolean> = storage.getBoolean(BooleanPrefs.DYNAMIC_COLOR_ENABLED.key, false);
      const pThemeId: Promise<number> = storage.getNumber(NumberPrefs.THEME_ID.key, THEME_TIEBA);
      // 选带头像预先发起（仅 dynamicColorEnabled=true 时使用）
      const pAvatar: Promise<string> = storage.getString(StringPrefs.AVATAR.key, '');

      const dynamicEnabled: boolean = await pDynamicEnabled;
      if (dynamicEnabled) {
        // 动态取色已开启：从头像提取主色
        const portrait: string = await pAvatar;
        if (portrait.length > 0) {
          const primaryHex: string | null = await extractAvatarColor(portrait);
          if (primaryHex !== null) {
            const primaryLightHex: string = toPrimaryLight(primaryHex);
            this.themeState.setDynamicColor(primaryHex, primaryLightHex);
          } else {
            // 取色失败：回退到预设主题
            this.themeState.setTheme(await pThemeId);
          }
        } else {
          // 无头像：回退到预设主题
          this.themeState.setTheme(await pThemeId);
        }
      } else {
        // 动态取色未开启：应用预设主题
        this.themeState.setTheme(await pThemeId);
      }
    } catch (err) {
      // 读取失败时使用默认主题，不阻塞初始化
      // #172 记录主题初始化失败日志，避免静默吞错
      Logger.warn(TAG, `[Index] theme init failed: ${(err as Error).message || err}`);
    }
    // #172 initApp 调用包裹 try-catch，防止 initApp 内部未捕获的 rejection
    // 导致 aboutToAppear 抛出 unhandled rejection 引发白屏
    try {
      await this.initApp();
    } catch (err) {
      Logger.error(TAG, `[Index] initApp unhandled: ${(err as Error).message || err}`);
      this.storageError = true;
      this.isLoading = false;
    }
  }

  /**
   * #96 提取初始化逻辑为独立方法，支持重试调用
   * 流程：ensureReady → 读 bduss → 切到 MainPage 壳（后台补登录）  / 无凭证 → LoginPage
   * #290 冷启动优化：改为“先进壳、后台登录”
   *   - 此前顺序为 ensureReady → 读 bduss → await TiebaAPI.login（含 4 个 device key I/O
   *     + init_z_id/doLogin/sync/initNickname 多次网络）→ 才 replace 首页，首帧被网络阻塞。
   *   - 现在：读到凭证后同步 setAuth 写 cookie（immediately 可用，首页请求不再等登录完成），
   *     立即 replace 到 MainPage 壳；TiebaAPI.login 的设备指纹/认证等重活放后台 fire-and-forget。
   *   - bduss 失效兜底：后台 login 失败时回登录页（保持原有“没登录进登录页”语义）。
   * 失败策略：ensureReady 抛错时设置 storageError，UI 显示 ErrorView 重试，不再静默跳登录页
   */
  private async initApp(): Promise<void> {
    this.isLoading = true;
    this.storageError = false;
    let hasBduss: boolean = false;
    // 外层 try/catch 兜底 ensureReady/getString 抛错（preferences 初始化失败/磁盘异常），
    // 避免 unhandled rejection 导致 UI 永远停在 LoadingProgress 转圈
    try {
      // 等待AppStorageManager初始化完成，防止EntryAbility.onCreate
      // 的async未被系统等待时读取到null pref（P0竞态修复）
      await AppStorageManager.getInstance().ensureReady();

      // M03：凭证仍直读 CredentialVault（H05 后全局 LoginState 仅持布尔，
      // 凭证本体唯一来源为 CredentialVault；此处 setAuth/login 需要凭证字符串，
      // StartupTask_Bduss 的同源读取仅产出登录态布尔，字符串不缓存以避免扩大明文暴露面）
      const bduss = await CredentialVault.getBduss();
      hasBduss = bduss.length > 0;

      if (hasBduss) {
        const stoken = await CredentialVault.getStoken();
        // #290：同步写入 cookie + 从本地恢复 tbs，让首页请求立即可用，不必等后台 login 网络完成。
        // tbs 持久化的根因：首页 getFollowForums 强制依赖 tbs，而 tbs 只能由 doLogin 网络返回。
        TiebaAPI.setAuth(bduss, stoken);
        const storage: AppStorageManager = AppStorageManager.getInstance();
        const savedTbs: string = await storage.getString(StringPrefs.TBS.key, '');
        if (savedTbs.length > 0) {
          TiebaAPI.restoreTbs(savedTbs);
        }
        this.isLoggedIn = true;
        // 后台补齐登录：设备指纹 I/O + init_z_id/doLogin/sync/initNickname 网络，不阻塞首帧
        TiebaAPI.login(bduss, stoken).then((): void => {
          Logger.info(TAG, '[Index] auto login (background) succeeded');
        }).catch((err: Error) => {
          const msg: string = getErrMessage(err, '');
          // 仅在明确是凭证鉴权失效（非网络超时/无网波动）时，才跳转登录页引导重登
          // 避免无网或弱网环境下冷启动被误踢出登录态
          const isNetworkError: boolean = msg.includes('网络') || msg.includes('network') || msg.includes('HTTP') || msg.includes('Connect');
          if (!isNetworkError && msg.includes('Login failed')) {
            Logger.warn(TAG, `[Index] auto login credential invalid: ${msg}`);
            this.isLoggedIn = false;
            RouterUtil.replace(RouterUtil.ROUTE_LOGIN_PAGE);
          } else {
            Logger.warn(TAG, `[Index] auto login transient failure: ${msg}, keeping logged-in state`);
          }
        });
      }
    } catch (err) {
      // #96 storage 异常：显示错误页 + 重试按钮，不再静默跳登录页
      // 原因：ensureReady 失败意味着 preferences 不可用，登录后也无法持久化 bduss，
      // 用户应看到明确错误提示并可重试，而非进入登录页后再次失败
      Logger.error(TAG, `[Index] storage init failed: ${(err as Error).message || err}`);
      this.storageError = true;
      this.isLoading = false;
      return;
    }

    this.isLoading = false;

    if (!hasBduss) {
      // 默认进 LoginPage（保持 iOS 风格，BDUSS 手动登录 + 网页登录两种方式并存）
      // LoginPage 上提供 '使用百度账号登录' 按钮跳转到 WebLoginPage
      // #167 路由迁移：router.replaceUrl → RouterUtil.replace
      // LoginPage 已迁移为 NavDestination，用 RouterUtil 操作 Navigation 栈
      RouterUtil.replace(RouterUtil.ROUTE_LOGIN_PAGE);
    } else {
      // #162 [A4-S2] 已登录：通过 Navigation 栈 replace 到 MainPage 壳
      // MainPage 已迁移为 NavDestination，作为 Navigation 栈的根页面
      // 使用 replace 而非 push：Index 仅作为容器，MainPage 是栈底
      RouterUtil.replace(RouterUtil.ROUTE_MAIN_PAGE);
    }
  }

  /**
   * #96 重试：重新执行初始化流程
   */
  private retryInit(): void {
    this.initApp().catch((err: Error) => {
      Logger.error(TAG, `[Index] retry init failed: ${err.message}`);
    });
  }

  build() {
    // #169 [A4-S1'] HdsNavigation 容器：作为应用路由根容器
    // Navigation 的高级封装（@kit.UIDesignKit），支持 titleBar 滚动动态模糊 + 沉浸光感
    // Index 容器仅显示 loading/error，不配置 titleBar（hideTitleBar(true)）
    // 各子页面作为 HdsNavDestination 进栈后，使用自己的 titleBar 配置
    // pathStack 通过 RouterUtil.setStack 注册到全局，RouterUtil 无需修改
    HdsNavigation(this.pathStack) {
      // NavBar 区域（栈为空时显示）：loading / error 内容
      Column() {
        if (this.storageError) {
          // #96 ensureReady 失败时显示错误页（非白屏）+ 重试按钮
          ErrorView({
            message: '',
            onRetryClick: () => this.retryInit()
          })
        } else if (this.isLoading) {
          // #290 冷启动优化：进壳/登录决策很快（本地偏好+凭证读取），
          // 首帧不需要额外欢迎页（history 移除欢迎占位：splash 后直接进壳/登录页）
          Column().width('100%').height('100%')
        }
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .backgroundColor($r('app.color.page_background'))
    }
    .mode(NavigationMode.Stack)
    .hideTitleBar(true)
    .hideNavBar(true)
    .backgroundColor($r('app.color.page_background'))
  }
}
