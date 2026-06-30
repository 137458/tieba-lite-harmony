import { router } from '@kit.ArkUI';
import { AppStorageManager } from '../../data/AppStorage';
import { TiebaAPI } from '../../api/TiebaAPI';
import { CryptoUtil } from '../../utils/CryptoUtil';

@Entry
@Component
struct LoginPage {
  @State bduss: string = '';
  @State stoken: string = '';
  @State isLoading: boolean = false;
  @State errorMessage: string = '';

  aboutToAppear() {
    this.checkLoginStatus();
  }

  async checkLoginStatus(): Promise<void> {
    // 等待AppStorageManager初始化完成（P0竞态修复）
    await AppStorageManager.getInstance().ensureReady();
    const bduss: string = await AppStorageManager.getInstance().getString('bduss');

    if (bduss.length > 0) {
      const stoken: string = await AppStorageManager.getInstance().getString('stoken');
      try {
        await TiebaAPI.login(bduss, stoken);
        router.replaceUrl({ url: 'pages/main/HomePage' });
      } catch (err) {
        // 登录失败，留在登录页
      }
    }
  }

  async handleLogin(): Promise<void> {
    if (this.bduss.length === 0) {
      this.errorMessage = $r('app.string.bduss_required').toString();
      return;
    }

    // 验证 BDUSS 格式（192位字符）
    if (this.bduss.length !== 192) {
      this.errorMessage = `BDUSS 长度应为 192 个字符，当前为 ${this.bduss.length} 个字符`;
      return;
    }

    this.isLoading = true;
    this.errorMessage = '';

    try {
      const userInfo = await TiebaAPI.login(this.bduss, this.stoken);

      await AppStorageManager.getInstance().setString('bduss', this.bduss);
      if (this.stoken.length > 0) {
        await AppStorageManager.getInstance().setString('stoken', this.stoken);
      }

      // 保存 tbs
      const tbs: string = TiebaAPI.getTbs();
      if (tbs.length > 0) {
        await AppStorageManager.getInstance().setString('tbs', tbs);
      }

      const cuid: string = await CryptoUtil.generateCuid(await CryptoUtil.getOrCreateDeviceId());
      await AppStorageManager.getInstance().setString('cuid', cuid);
      TiebaAPI.setCuid(cuid);

      router.replaceUrl({ url: 'pages/main/HomePage' });
    } catch (err) {
      const error = err as Error;
      this.errorMessage = error.message || '登录失败';
    } finally {
      this.isLoading = false;
    }
  }

  build() {
    Column() {
      Column() {
        Text($r('app.string.login_title'))
          .fontSize(32)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary'))
          .margin({ top: 80 })

        Text($r('app.string.login_subtitle'))
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 8 })

        Column() {
          TextInput({ placeholder: $r('app.string.bduss_input_hint'), text: $$this.bduss })
            .width('100%')
            .height(48)
            .fontSize(14)
            .backgroundColor($r('app.color.input_background'))
            .borderRadius(8)
            .padding({ left: 16, right: 16 })

          TextInput({ placeholder: $r('app.string.stoken_input_hint'), text: $$this.stoken })
            .width('100%')
            .height(48)
            .fontSize(14)
            .backgroundColor($r('app.color.input_background'))
            .borderRadius(8)
            .padding({ left: 16, right: 16 })
            .margin({ top: 12 })

          if (this.errorMessage.length > 0) {
            Text(this.errorMessage)
              .fontSize(12)
              .fontColor($r('app.color.error'))
              .margin({ top: 8 })
          }

          Button(this.isLoading ? $r('app.string.login_loading') : $r('app.string.login_button'))
            .width('100%')
            .height(48)
            .fontSize(16)
            .fontColor(Color.White)
            .backgroundColor($r('app.color.primary'))
            .borderRadius(8)
            .margin({ top: 24 })
            .enabled(!this.isLoading)
            .onClick(() => this.handleLogin())

          Button($r('app.string.login_web_button'))
            .width('100%')
            .height(48)
            .fontSize(16)
            .fontColor($r('app.color.primary'))
            .backgroundColor(Color.Transparent)
            .border({ width: 1, color: $r('app.color.primary'), radius: 8 })
            .margin({ top: 16 })
            .onClick(() => {
              router.pushUrl({ url: 'pages/main/WebLoginPage' });
            })

          Text($r('app.string.login_help'))
            .fontSize(12)
            .fontColor($r('app.color.text_caption'))
            .margin({ top: 16 })
        }
        .width('100%')
        .padding({ left: 32, right: 32 })
        .margin({ top: 60 })
      }
      .width('100%')
      .layoutWeight(1)

      Text($r('app.string.disclaimer'))
        .fontSize(11)
        .fontColor($r('app.color.text_caption'))
        .textAlign(TextAlign.Center)
        .margin({ bottom: 24 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
  }
}
