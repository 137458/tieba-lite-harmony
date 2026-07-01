import { router } from '@kit.ArkUI';
import { TiebaAPI } from '../api/TiebaAPI';
import { AppStorageManager } from '../data/AppStorage';
import { CryptoUtil } from '../utils/CryptoUtil';

@Entry
@Component
struct Index {
  @State isLoggedIn: boolean = false;
  @State isLoading: boolean = true;
  @State bduss: string = '';
  @State stoken: string = '';

  async aboutToAppear() {
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
      // storage 异常：记录日志并跳转登录页兜底，保证 UI 不会卡死
      console.error(`[Index] storage init failed: ${(err as Error).message}`);
      this.isLoggedIn = false;
    }

    this.isLoading = false;

    if (!this.isLoggedIn) {
      router.replaceUrl({ url: 'pages/main/LoginPage' }).catch((err: Error) => {
        console.error(`[Index] replaceUrl to LoginPage failed: ${err.message}`);
      });
    } else {
      router.replaceUrl({ url: 'pages/main/MainPage' }).catch((err: Error) => {
        console.error(`[Index] replaceUrl to MainPage failed: ${err.message}`);
      });
    }
  }

  build() {
    Column() {
      LoadingProgress()
        .width(50)
        .height(50)
        .color($r('app.color.primary'))
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.page_background'))
  }
}
