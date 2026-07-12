// 登录页（手动 BDUSS 备用入口）
// UI 设计：iOS 风格 Logo + 34px ExtraBold 标题 + 12px 圆角按钮（对齐 design-prototype.html L191-205）
// 主要登录方式为 WebLoginPage（网页登录），本页仅作为 BDUSS 手动登录备用入口
// 字段：BDUSS（Password 类型，敏感凭证不明文显示），登录后跳转 MainPage
// stoken 不在登录页输入：网页登录自动获取 stoken，API 层保留 stoken 支持

import { router, AppStorageV2 } from '@kit.ArkUI';
import { AppStorageManager } from '../../data/AppStorage';
import { TiebaAPI } from '../../api/TiebaAPI';
import { CryptoUtil } from '../../utils/CryptoUtil';
import { getResourceString } from '../../utils/ResourceUtil';
import { getStatusBarHeight } from '../../utils/StatusBarUtil';
import { BdussState } from '../../model/AppStorageV2Models';
import { connectTheme, ThemeState } from '../../theme/ThemeManager';

@Entry
@ComponentV2
struct LoginPage {
  @Local bduss: string = '';
  @Local isLoading: boolean = false;
  @Local errorMessage: string = '';
  // 状态栏高度（vp），沉浸式避让状态栏
  @Local statusBarHeight: number = 36;
  @Local themeState: ThemeState = connectTheme();

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
        // #90 同步到 AppStorageV2（防御 EntryAbility 同步未完成的竞态）
        const bdussState = AppStorageV2.connect(BdussState, 'bduss', () => new BdussState())!;
        bdussState.value = bduss;
        // #171 MainPage 已迁移为 NavDestination（router_map.json），不在 main_pages.json 中。
        // router.replaceUrl 无法跳转 NavDestination，改为回到 Index 容器，
        // Index.initApp 检测已登录后用 RouterUtil.replace 跳转 MainPage。
        router.replaceUrl({ url: 'pages/Index' })
          .catch((err: Error) => {
            console.error(`[LoginPage] replaceUrl to Index failed: ${err.message}`);
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
      // 手动登录不传 stoken：stoken 由网页登录自动获取并持久化
      // 此处仅用 BDUSS 完成认证，API 层保留 stoken 支持（如已存在旧 stoken 会被 TiebaAPI.setAuth 覆盖为空）
      const userInfo = await TiebaAPI.login(this.bduss, '');

      await AppStorageManager.getInstance().setString('bduss', this.bduss);
      // #90 同步到 AppStorageV2，触发订阅方联动
      const bdussState = AppStorageV2.connect(BdussState, 'bduss', () => new BdussState())!;
      bdussState.value = this.bduss;
      // 手动登录路径不清除已持久化的 stoken：若用户之前网页登录过仍可复用
      // 若用户从未网页登录，stoken 为空，需 stoken 的接口（如取消点赞）会返回错误提示用户重新网页登录

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

      // #171 MainPage 已迁移为 NavDestination，router 无法跳转，回到 Index 容器
      router.replaceUrl({ url: 'pages/Index' })
        .catch((err: Error) => {
          console.error(`[LoginPage] replaceUrl to Index failed: ${err.message}`);
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
          Image($r('app.media.ic_chat_bubble'))
            .width(40)
            .height(40)
            .fillColor(Color.White)
            // A5 图片优化：本地 SVG 图标，同步加载+低质量插值
            .syncLoad(true)
            .interpolation(ImageInterpolation.Low)
        }
        .width(80)
        .height(80)
        .borderRadius(20)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .linearGradient({
          angle: 135,
          colors: [[this.themeState.primary, 0.0], [$r('app.color.accent_blue'), 1.0]]
        })

        // app-title（34px 800 ExtraBold，字距 0.37，对齐 design-prototype.html L194）
        Text($r('app.string.login_title'))
          .fontSize(34)
          .fontWeight(800)
          .fontColor($r('app.color.text_primary'))
          .letterSpacing(0.37)
          .margin({ top: 20 })

        // app-subtitle（15px text_secondary，对齐 design-prototype.html L195）
        Text($r('app.string.login_subtitle'))
          .fontSize(15)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 4, bottom: 40 })

        // BDUSS form-group（label 13px 500 + input 44px 10px 圆角）
        // Password 类型：敏感凭证不明文显示（P0 安全修复）
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
            .type(InputType.Password)
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
          .fontWeight(600)
          .fontColor(Color.White)
          .backgroundColor(this.themeState.primary)
          .borderRadius(12)
          .margin({ top: 20 })
          .enabled(!this.isLoading)
          .onClick(() => this.handleLogin())

        Button($r('app.string.login_web_button'))
          .width('100%')
          .height(50)
          .fontSize(17)
          .fontWeight(600)
          .fontColor(this.themeState.primary)
          .backgroundColor(this.themeState.primary_light)
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
