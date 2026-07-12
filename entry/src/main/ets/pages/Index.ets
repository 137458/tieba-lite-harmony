import { router, AppStorageV2 } from '@kit.ArkUI';
import { HdsNavigation } from '@kit.UIDesignKit';
import { TiebaAPI } from '../api/TiebaAPI';
import { AppStorageManager } from '../data/AppStorage';
import { CryptoUtil } from '../utils/CryptoUtil';
import { ErrorView } from '../components/ErrorView';
import { connectTheme, ThemeState, THEME_TIEBA } from '../theme/ThemeManager';
import { extractAvatarColor, toPrimaryLight } from '../utils/DynamicColorUtil';
import { HomeDualColumnState } from '../model/AppStorageV2Models';
import { VibratorUtil } from '../utils/VibratorUtil';
import { RouterUtil } from '../utils/RouterUtil';

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
    // 栈大小——用户 pop 弹空：栈为空，router.back() 退出应用；
    // 代码 clear+push（如 WebLoginPage 登录成功 backToRoot+replace）：clear 和 push
    // 同步连续执行，setTimeout 执行时栈已有新页面，不退出。
    // setTimeout 异步避免在 Navigation 路由切换回调内同步销毁组件导致状态不一致。
    this.pathStack.setInterception({
      willShow: (from: NavDestinationContext | 'navBar', to: NavDestinationContext | 'navBar',
        operation: NavigationOperation, animated: boolean) => {
        if (to === 'navBar') {
          setTimeout(() => {
            if (RouterUtil.size() === 0) {
              router.back();
            }
          }, 0);
        }
      }
    });
    // #156 主题冷启动修复：StartupTask_Theme 在 AbilityStage 上下文中设置 @Trace 属性，
    // 但 @ObservedV2 的变化在无 UI 观察者时可能不被 ArkUI 框架感知。
    // 在首个 @ComponentV2 页面的 aboutToAppear 中重新 setTheme，确保 @Trace 变化在 UI 上下文中生效。
    // #158 动态取色冷启动：若 dynamicColorEnabled=true，从头像提取主色覆盖主题色，
    // 避免每次冷启动都需进入 ThemePage 才生效。
    try {
      await AppStorageManager.getInstance().ensureReady();
      const storage: AppStorageManager = AppStorageManager.getInstance();
      const dynamicEnabled: boolean = await storage.getBoolean('dynamicColorEnabled', false);
      if (dynamicEnabled) {
        // 动态取色已开启：从头像提取主色
        const portrait: string = await storage.getString('avatar', '');
        if (portrait.length > 0) {
          const primaryHex: string | null = await extractAvatarColor(portrait);
          if (primaryHex !== null) {
            const primaryLightHex: string = toPrimaryLight(primaryHex);
            this.themeState.setDynamicColor(primaryHex, primaryLightHex);
          } else {
            // 取色失败：回退到预设主题
            const themeId: number = await storage.getNumber('themeId', THEME_TIEBA);
            this.themeState.setTheme(themeId);
          }
        } else {
          // 无头像：回退到预设主题
          const themeId: number = await storage.getNumber('themeId', THEME_TIEBA);
          this.themeState.setTheme(themeId);
        }
      } else {
        // 动态取色未开启：应用预设主题
        const themeId: number = await storage.getNumber('themeId', THEME_TIEBA);
        this.themeState.setTheme(themeId);
      }
      // 首页双列展示偏好同步到 AppStorageV2（冷启动时 AppStorageV2 无值，需从 preferences 读取写入）
      const homeDualColumn: boolean = await storage.getBoolean('homeDualColumn', false);
      const dualColumnState: HomeDualColumnState = AppStorageV2.connect(HomeDualColumnState, 'homeDualColumn', () => new HomeDualColumnState())!;
      dualColumnState.value = homeDualColumn;
      // 触感反馈偏好同步到 VibratorUtil 内存（冷启动时需 init 才能全局生效）
      await VibratorUtil.init();
    } catch (err) {
      // 读取失败时使用默认主题，不阻塞初始化
      // #172 记录主题初始化失败日志，避免静默吞错
      console.warn(`[Index] theme init failed: ${(err as Error).message || err}`);
    }
    // #172 initApp 调用包裹 try-catch，防止 initApp 内部未捕获的 rejection
    // 导致 aboutToAppear 抛出 unhandled rejection 引发白屏
    try {
      await this.initApp();
    } catch (err) {
      console.error(`[Index] initApp unhandled: ${(err as Error).message || err}`);
      this.storageError = true;
      this.isLoading = false;
    }
  }

  /**
   * #96 提取初始化逻辑为独立方法，支持重试调用
   * 流程：ensureReady → 读 bduss → 自动 login → 跳转 MainPage/LoginPage
   * 失败策略：ensureReady 抛错时设置 storageError，UI 显示 ErrorView 重试，不再静默跳登录页
   */
  private async initApp(): Promise<void> {
    this.isLoading = true;
    this.storageError = false;
    // 外层 try/catch 兜底 ensureReady/getString 抛错（preferences 初始化失败/磁盘异常），
    // 避免 unhandled rejection 导致 UI 永远停在 LoadingProgress 转圈
    try {
      // 等待AppStorageManager初始化完成，防止EntryAbility.onCreate
      // 的async未被系统等待时读取到null pref（P0竞态修复）
      await AppStorageManager.getInstance().ensureReady();

      const bduss = await AppStorageManager.getInstance().getString('bduss');

      if (bduss.length > 0) {
        const stoken = await AppStorageManager.getInstance().getString('stoken');
        try {
          // login 流程内部会自动获取并设置 tbs，无需在此手动恢复
          await TiebaAPI.login(bduss, stoken);
          this.isLoggedIn = true;
        } catch (err) {
          console.warn(`[Index] auto login failed: ${(err as Error).message || err}`);
          this.isLoggedIn = false;
        }
      }
    } catch (err) {
      // #96 storage 异常：显示错误页 + 重试按钮，不再静默跳登录页
      // 原因：ensureReady 失败意味着 preferences 不可用，登录后也无法持久化 bduss，
      // 用户应看到明确错误提示并可重试，而非进入登录页后再次失败
      console.error(`[Index] storage init failed: ${(err as Error).message || err}`);
      this.storageError = true;
      this.isLoading = false;
      return;
    }

    this.isLoading = false;

    if (!this.isLoggedIn) {
      // 默认进 LoginPage（保持 iOS 风格，BDUSS 手动登录 + 网页登录两种方式并存）
      // LoginPage 上提供 '使用百度账号登录' 按钮跳转到 WebLoginPage
      // #167 路由迁移：router.replaceUrl → RouterUtil.replace
      // LoginPage 已迁移为 NavDestination，用 RouterUtil 操作 Navigation 栈
      RouterUtil.replace(RouterUtil.ROUTE_LOGIN_PAGE);
    } else {
      // #162 [A4-S2] 已登录：通过 Navigation 栈 replace 到 MainPage
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
      console.error(`[Index] retry init failed: ${err.message}`);
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
          LoadingProgress()
            .width(50)
            .height(50)
            .color(this.themeState.primary)
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
