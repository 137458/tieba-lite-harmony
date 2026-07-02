// 登录页
// UI 设计：iOS 风格 Logo + 34px ExtraBold 标题 + 12px 圆角按钮（对齐 design-prototype.html L191-205）
// 字段：BDUSS + STOKEN（可选），登录后跳转 MainPage

import { router } from '@kit.ArkUI';
import { AppStorageManager } from '../../data/AppStorage';
import { TiebaAPI } from '../../api/TiebaAPI';
import { CryptoUtil } from '../../utils/CryptoUtil';
import { getResourceString } from '../../utils/ResourceUtil';
import { getStatusBarHeight } from '../../utils/StatusBarUtil';

@Entry
@Component
struct LoginPage {
  @State bduss: string = '';
  @State stoken: string = '';
  @State isLoading: boolean = false;
  @State errorMessage: string = '';
  // 状态栏高度（vp），沉浸式避让状态栏
  @State statusBarHeight: number = 36;

  async aboutToAppear() {
    // 获取状态栏高度，失败不阻塞登录流程，保留默认值 36
    try {
      this.statusBarHeight = await getStatusBarHeight(getContext(this));
    } catch (err) {
      console.error(`[LoginPage] getStatusBarHeight failed: ${(err as Error).message}`);
    }
    // checkLoginStatus 内部仅 catch 了 login 失败，ensureReady/getString 抛错时需兜底
    // 避免 unhandled rejection 导致用户停在空白登录页无反馈
    this.checkLoginStatus().catch((err: Error) => {
      console.error(`[LoginPage] checkLoginStatus failed: ${err.message}`);
    });
  }

  async checkLoginStatus(): Promise<void> {
    // 等待AppStorageManager初始化完成（P0竞态修复）
    await AppStorageManager.getInstance().ensureReady();
    const bduss: string = await AppStorageManager.getInstance().getString('bduss');

    if (bduss.length > 0) {
      const stoken: string = await AppStorageManager.getInstance().getString('stoken');
      try {
        // 接住 UserInfo 以便刷新本地缓存（用户可能在 web 端改了头像/昵称）
        const userInfo = await TiebaAPI.login(bduss, stoken);
        // 持久化用户信息（issue #41）：自动登录路径同样刷新 uid/name/avatar/nickname
        await AppStorageManager.getInstance().setString('uid', userInfo.uid.toString());
        await AppStorageManager.getInstance().setString('name', userInfo.name);
        await AppStorageManager.getInstance().setString('avatar', userInfo.avatar);
        await AppStorageManager.getInstance().setString('nickname', userInfo.nickname);
        router.replaceUrl({ url: 'pages/main/MainPage' })
          .catch((err: Error) => {
            console.error(`[LoginPage] replaceUrl to MainPage failed: ${err.message}`);
          });
      } catch (err) {
        // BDUSS 已失效或网络异常，记录日志便于诊断，留在登录页让用户手动重试
        console.warn(`[LoginPage] auto login failed: ${(err as Error).message || err}`);
      }
    }
  }

  async handleLogin(): Promise<void> {
    if (this.bduss.length === 0) {
      this.errorMessage = getResourceString($r('app.string.bduss_required'));
      return;
    }

    // 验证 BDUSS 格式（长度范围 [100, 256]，主要防误粘贴；服务端 token 长度可能调整）
    if (this.bduss.length < 100 || this.bduss.length > 256) {
      this.errorMessage = getResourceString($r('app.string.bduss_length_invalid', this.bduss.length));
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

      // 持久化用户信息（issue #41：手动登录路径同样写入 uid/name/avatar/nickname）
      await AppStorageManager.getInstance().setString('uid', userInfo.uid.toString());
      await AppStorageManager.getInstance().setString('name', userInfo.name);
      await AppStorageManager.getInstance().setString('avatar', userInfo.avatar);
      await AppStorageManager.getInstance().setString('nickname', userInfo.nickname);

      const cuid: string = await CryptoUtil.generateCuid(await CryptoUtil.getOrCreateDeviceId());
      await AppStorageManager.getInstance().setString('cuid', cuid);
      TiebaAPI.setCuid(cuid);

      router.replaceUrl({ url: 'pages/main/MainPage' })
        .catch((err: Error) => {
          console.error(`[LoginPage] replaceUrl to MainPage failed: ${err.message}`);
        });
    } catch (err) {
      const error = err as Error;
      this.errorMessage = error.message || getResourceString($r('app.string.login_failed'));
    } finally {
      this.isLoading = false;
    }
  }

  build() {
    Column() {
      // 内容区（垂直居中 + 顶部状态栏避让）
      Column() {
        // Logo（80x80 圆角 20 蓝色渐变 + 40px 白色 chat.bubble SVG，对齐 design-prototype.html L192）
        Column() {
          Shape() {
            Path()
              .commands('M20 2H4c-1.1 0-2 .9-2 2v18l4-4h14c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2z')
              .fill(Color.White)
          }
          .width(40)
          .height(40)
          .viewPort({ x: 0, y: 0, width: 24, height: 24 })
        }
        .width(80)
        .height(80)
        .borderRadius(20)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .linearGradient({
          angle: 135,
          colors: [[$r('app.color.primary'), 0.0], [$r('app.color.accent_blue'), 1.0]]
        })

        // app-title（34px 800 ExtraBold，字距 0.37，对齐 design-prototype.html L194）
        Text($r('app.string.login_title'))
          .fontSize(34)
          .fontWeight(FontWeight.Bolder)
          .fontColor($r('app.color.text_primary'))
          .letterSpacing(0.37)
          .margin({ top: 20 })

        // app-subtitle（15px text_secondary，对齐 design-prototype.html L195）
        Text($r('app.string.login_subtitle'))
          .fontSize(15)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 4, bottom: 40 })

        // BDUSS form-group（label 13px 500 + input 44px 10px 圆角）
        Column() {
          Text('BDUSS')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_secondary'))
            .letterSpacing(0.5)
            .margin({ bottom: 6 })

          TextInput({ placeholder: $r('app.string.bduss_input_hint'), text: $$this.bduss })
            .width('100%')
            .height(44)
            .fontSize(15)
            .fontColor($r('app.color.text_primary'))
            .placeholderColor($r('app.color.text_caption'))
            .backgroundColor($r('app.color.input_background'))
            .borderRadius(10)
            .padding({ left: 16, right: 16 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .margin({ bottom: 14 })

        // STOKEN form-group
        Column() {
          Text('STOKEN')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_secondary'))
            .letterSpacing(0.5)
            .margin({ bottom: 6 })

          TextInput({ placeholder: $r('app.string.stoken_input_hint'), text: $$this.stoken })
            .width('100%')
            .height(44)
            .fontSize(15)
            .fontColor($r('app.color.text_primary'))
            .placeholderColor($r('app.color.text_caption'))
            .backgroundColor($r('app.color.input_background'))
            .borderRadius(10)
            .padding({ left: 16, right: 16 })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .margin({ bottom: 14 })

        // 错误信息
        if (this.errorMessage.length > 0) {
          Text(this.errorMessage)
            .fontSize(12)
            .fontColor($r('app.color.error'))
            .margin({ top: 4, bottom: 8 })
        }

        // btn-primary（50px 12px 圆角 primary 背景 白字 17px 600，对齐 design-prototype.html L201）
        Button(this.isLoading ? $r('app.string.login_loading') : $r('app.string.login_button'))
          .width('100%')
          .height(50)
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
          .backgroundColor($r('app.color.primary'))
          .borderRadius(12)
          .margin({ top: 20 })
          .enabled(!this.isLoading)
          .onClick(() => this.handleLogin())

        // btn-secondary（50px 12px 圆角 primary_light 背景 primary 文字 17px 600，对齐 design-prototype.html L203）
        Button($r('app.string.login_web_button'))
          .width('100%')
          .height(50)
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.primary'))
          .backgroundColor($r('app.color.primary_light'))
          .borderRadius(12)
          .margin({ top: 12 })
          .onClick(() => {
            router.pushUrl({ url: 'pages/main/WebLoginPage' })
              .catch((err: Error) => {
                console.error(`[LoginPage] pushUrl to WebLoginPage failed: ${err.message}`);
              });
          })

        // footer-text（12px text_caption 居中 行高 1.6，对齐 design-prototype.html L205）
        Text($r('app.string.disclaimer'))
          .fontSize(12)
          .fontColor($r('app.color.text_caption'))
          .textAlign(TextAlign.Center)
          .lineHeight(19.2)
          .margin({ top: 40 })
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 32, right: 32, top: this.statusBarHeight + 40, bottom: 40 })
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
  }
}
