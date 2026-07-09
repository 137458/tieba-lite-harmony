import { router } from '@kit.ArkUI';
import { TiebaAPI } from '../api/TiebaAPI';
import { AppStorageManager } from '../data/AppStorage';
import { CryptoUtil } from '../utils/CryptoUtil';
import { ErrorView } from '../components/ErrorView';

@Entry
@ComponentV2
struct Index {
  @Local isLoggedIn: boolean = false;
  @Local isLoading: boolean = true;
  // #96 AppStorage ensureReady 失败标志：true 时显示 ErrorView 错误页（非白屏）+ 重试按钮
  @Local storageError: boolean = false;

  async aboutToAppear() {
    await this.initApp();
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
      console.error(`[Index] storage init failed: ${(err as Error).message}`);
      this.storageError = true;
      this.isLoading = false;
      return;
    }

    this.isLoading = false;

    if (!this.isLoggedIn) {
      // 默认进 LoginPage（保持 iOS 风格，BDUSS 手动登录 + 网页登录两种方式并存）
      // LoginPage 上提供 '使用百度账号登录' 按钮跳转到 WebLoginPage
      router.replaceUrl({ url: 'pages/main/LoginPage' }).catch((err: Error) => {
        console.error(`[Index] replaceUrl to LoginPage failed: ${err.message}`);
      });
    } else {
      router.replaceUrl({ url: 'pages/main/MainPage' }).catch((err: Error) => {
        console.error(`[Index] replaceUrl to MainPage failed: ${err.message}`);
      });
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
          .color($r('app.color.primary'))
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.page_background'))
  }
}
