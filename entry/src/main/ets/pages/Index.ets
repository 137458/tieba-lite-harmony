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
    // 等待AppStorageManager初始化完成，防止EntryAbility.onCreate
    // 的async未被系统等待时读取到null pref（P0竞态修复）
    await AppStorageManager.getInstance().ensureReady();

    const bduss = await AppStorageManager.getInstance().getString('bduss');

    if (bduss.length > 0) {
      const stoken = await AppStorageManager.getInstance().getString('stoken');
      try {
        await TiebaAPI.login(bduss, stoken);
        this.isLoggedIn = true;

        // 恢复 tbs
        const tbs = await AppStorageManager.getInstance().getString('tbs');
        if (tbs.length > 0) {
          // 这里可以设置 tbs，但 TiebaAPI 没有暴露 setter，login 会自动获取
        }
      } catch (err) {
        this.isLoggedIn = false;
      }
    }

    this.isLoading = false;

    if (!this.isLoggedIn) {
      router.replaceUrl({ url: 'pages/main/LoginPage' });
    } else {
      router.replaceUrl({ url: 'pages/main/HomePage' });
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
