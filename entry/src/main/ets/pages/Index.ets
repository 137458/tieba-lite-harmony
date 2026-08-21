import { common } from '@kit.AbilityKit';
import { HdsNavigation } from '@kit.UIDesignKit';
import { TiebaAPI } from '../api/TiebaAPI';
import { AppStorageManager } from '../data/AppStorage';
import { CredentialVault } from '../data/CredentialVault';
import { CryptoUtil } from '../utils/CryptoUtil';
import { ErrorView } from '../components/ErrorView';
import { connectTheme, ThemeState, THEME_TIEBA } from '../theme/ThemeManager';
import { extractAvatarColor, toPrimaryLight } from '../utils/DynamicColorUtil';
import { HomeDualColumnState, connectHomeDualColumn, TabVisibilityState, MaterialLevelState, HomeListModeState, connectTabVisibility, connectMaterialLevel, connectHomeListMode, ForumPageVersionState, ForumFabFunctionState, DefaultHomePageState, connectForumPageVersion, connectForumFabFunction, connectDefaultHomePage, ForumCommentPreviewState, ThreadCommentPreviewState, RecentForumsState, connectForumCommentPreview, connectThreadCommentPreview, connectRecentForums, ForumsNeedRefreshState, connectForumsNeedRefresh } from '../model/AppStorageV2Models';
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
    // 栈大小——用户 pop 弹空：栈为空，terminateSelf() 退出应用；
    // 代码 clear+push（如 WebLoginPage 登录成功 backToRoot+replace）：clear 和 push
    // 同步连续执行，setTimeout 执行时栈已有新页面，不退出。
    // setTimeout 异步避免在 Navigation 路由切换回调内同步销毁组件导致状态不一致。
    // #195 路由清理：router.back() → UIAbilityContext.terminateSelf()
    // （RouterUtil.back() 基于 NavPathStack.pop()，栈空时不退出应用）
    const abilityContext: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
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
    // #158 动态取色冷启动：若 dynamicColorEnabled=true，从头像提取主色覆盖主题色，
    // 避免每次冷启动都需进入 ThemePage 才生效。
    try {
      await AppStorageManager.getInstance().ensureReady();
      const storage: AppStorageManager = AppStorageManager.getInstance();
      // #290 冷启动优化：并行发起所有独立偏好读取，preferences I/O 重叠执行，
      // 避免串行 await 逐个阻塞首帧渲染
      const pDynamicEnabled: Promise<boolean> = storage.getBoolean('dynamicColorEnabled', false);
      const pThemeId: Promise<number> = storage.getNumber('themeId', THEME_TIEBA);
      const pTabVisibility: Promise<number> = storage.getNumber('tabVisibility', 0b1111);
      const pMaterialLevel: Promise<number> = storage.getNumber('materialLevel', 10);
      const pHomeListMode: Promise<number> = storage.getNumber('homeListMode', -1);
      const pForumPageVersion: Promise<number> = storage.getNumber('forum_page_version', -1);
      const pForumFabFunction: Promise<number> = storage.getNumber('forum_fab_function', -1);
      const pDefaultHomePage: Promise<number> = storage.getNumber('default_home_page', -1);
      const pForumCommentPreview: Promise<boolean> = storage.getBoolean('forumCommentPreview', false);
      const pThreadCommentPreview: Promise<boolean> = storage.getBoolean('threadCommentPreview', true);
      const pShowRecentForums: Promise<boolean> = storage.getBoolean('showRecentForums', false);
      const pOldHomeDualColumn: Promise<boolean> = storage.getBoolean('homeDualColumn', false);
      // 选带头像预先发起（仅 dynamicColorEnabled=true 时使用，preferences I/O 很轻，成并联读收益更大）
      const pAvatar: Promise<string> = storage.getString('avatar', '');

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
      // #234 持久化机制：启动时读回 Tab 显隐 / 沉浸光感强度 / 列表模式偏好到 AppStorageV2
      // AppStorageV2 默认内存态，不持久化；SettingsPage 写入时已同步 setNumber 到 preferences，
      // 此处读回 preferences 写入 AppStorageV2，确保重启后用户偏好不丢失
      const tabVisibilityValue: number = await pTabVisibility;
      const tabVisibilityState: TabVisibilityState = connectTabVisibility();
      // 至少保留首页 bit0=1（防止 preferences 数据异常导致全部隐藏）
      tabVisibilityState.value = tabVisibilityValue | 0b0001;
      const materialLevelValue: number = await pMaterialLevel;
      const materialLevelState: MaterialLevelState = connectMaterialLevel();
      materialLevelState.value = materialLevelValue;
      // #234 首页列表模式（3档枚举）：
      // 1) 先读新 key 'homeListMode'，0=SINGLE/1=DOUBLE_FULL/2=DOUBLE_COMPACT
      // 2) 旧用户迁移：若 'homeListMode' 未设置（默认0）但旧 key 'homeDualColumn'=true，
      //    迁移为 DOUBLE_FULL=1，并立即写入新 key（避免下次启动重复迁移）
      // 3) 旧 key 'homeDualColumn' 的 AppStorageV2 同步仍保留（HomePage 历史代码暂未完全切换，
      //    slice D 将把 HomePage 改为读 HomeListModeState，届时旧 dualColumnState 不再被订阅）
      let homeListModeValue: number = await pHomeListMode;
      if (homeListModeValue < 0) {
        // 新 key 未设置：检查旧 key 是否为 true，是则迁移为 DOUBLE_FULL
        const oldHomeDualColumn: boolean = await pOldHomeDualColumn;
        homeListModeValue = oldHomeDualColumn ? 1 : 0;
        await storage.setNumber('homeListMode', homeListModeValue);
      }
      const homeListModeState: HomeListModeState = connectHomeListMode();
      homeListModeState.value = homeListModeValue;
      // 旧 dualColumnState 同步（向后兼容，slice D 完成后可移除）
      const dualColumnState: HomeDualColumnState = connectHomeDualColumn();
      dualColumnState.value = homeListModeValue !== 0;
      // 完整版吧内页面开关 + 吧内 FAB 功能模式（持久化 key='forum_page_version' / 'forum_fab_function'）
      // 新 key 启用迁移：先读新 key（默认 -1），不存在则写入默认值 0 并立即 setNumber 持久化
      let forumPageVersionValue: number = await pForumPageVersion;
      if (forumPageVersionValue < 0) {
        // 首次安装：写入默认值 0（简化版）并持久化
        forumPageVersionValue = 0;
        await storage.setNumber('forum_page_version', forumPageVersionValue);
      }
      const forumPageVersionState: ForumPageVersionState = connectForumPageVersion();
      forumPageVersionState.value = forumPageVersionValue;
      let forumFabFunctionValue: number = await pForumFabFunction;
      if (forumFabFunctionValue < 0) {
        // 首次安装：写入默认值 0（发帖）并持久化
        forumFabFunctionValue = 0;
        await storage.setNumber('forum_fab_function', forumFabFunctionValue);
      }
      const forumFabFunctionState: ForumFabFunctionState = connectForumFabFunction();
      forumFabFunctionState.value = forumFabFunctionValue;
      // 默认启动页（持久化 key='default_home_page'，0=首页/1=收藏/2=消息/3=我的）
      // 新 key 启用迁移：先读新 key（默认 -1），不存在则写入默认值 0 并立即 setNumber 持久化
      let defaultHomePageValue: number = await pDefaultHomePage;
      if (defaultHomePageValue < 0) {
        // 首次安装：写入默认值 0（首页）并持久化
        defaultHomePageValue = 0;
        await storage.setNumber('default_home_page', defaultHomePageValue);
      }
      const defaultHomePageState: DefaultHomePageState = connectDefaultHomePage();
      defaultHomePageState.value = defaultHomePageValue;
      const forumCommentPreviewState: ForumCommentPreviewState = connectForumCommentPreview();
      forumCommentPreviewState.value = await pForumCommentPreview;
      const threadCommentPreviewState: ThreadCommentPreviewState = connectThreadCommentPreview();
      threadCommentPreviewState.value = await pThreadCommentPreview;
      const recentForumsState: RecentForumsState = connectRecentForums();
      recentForumsState.value = await pShowRecentForums;
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

      const bduss = await CredentialVault.getBduss();
      hasBduss = bduss.length > 0;

      if (hasBduss) {
        const stoken = await CredentialVault.getStoken();
        // #290：同步写入 cookie + 从本地恢复 tbs，让首页请求立即可用，不必等后台 login 网络完成。
        // tbs 持久化的根因：首页 getFollowForums 强制依赖 tbs，而 tbs 只能由 doLogin 网络返回。
        TiebaAPI.setAuth(bduss, stoken);
        const storage: AppStorageManager = AppStorageManager.getInstance();
        const savedTbs: string = await storage.getString('tbs', '');
        if (savedTbs.length > 0) {
          TiebaAPI.restoreTbs(savedTbs);
        }
        this.isLoggedIn = true;
        // 后台补齐登录：设备指纹 I/O + init_z_id/doLogin/sync/initNickname 网络，不阻塞首帧
        TiebaAPI.login(bduss, stoken).then((): void => {
          console.info('[Index] auto login (background) succeeded');
          // #290 后台登录刷新了 tbs：递增 forumsNeedRefresh 触发 HomePage 自动重载，
          // 消除冷启动时"旧 tbs 过期需手动刷新"的情况（HomePage 的 @Monitor 订阅该字段）
          const forumsNeedRefresh: ForumsNeedRefreshState = connectForumsNeedRefresh();
          forumsNeedRefresh.value = Date.now();
        }).catch((err: Error) => {
          // bduss 失效：回登录页让用户重新登录
          console.warn(`[Index] auto login (background) failed: ${err.message || err}`);
          this.isLoggedIn = false;
          RouterUtil.replace(RouterUtil.ROUTE_LOGIN_PAGE);
        });
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
