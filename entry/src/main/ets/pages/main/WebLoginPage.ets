import { router } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { AppStorageManager } from '../../data/AppStorage';
import { TiebaAPI } from '../../api/TiebaAPI';
import { CryptoUtil } from '../../utils/CryptoUtil';

const LOGIN_URL: string = 'https://wappass.baidu.com/passport?login&u=https%3A%2F%2Ftieba.baidu.com%2Findex%2Ftbwise%2Fmine';
const LOGIN_SUCCESS_URL_PREFIX_1: string = 'https://tieba.baidu.com/index/tbwise/';
const LOGIN_SUCCESS_URL_PREFIX_2: string = 'https://tiebac.baidu.com/index/tbwise/';

interface ParsedCookie {
  BDUSS: string;
  STOKEN: string;
  BAIDUID?: string;
}

@Entry
@Component
struct WebLoginPage {
  controller: webview.WebviewController = new webview.WebviewController();
  @State isLoading: boolean = true;
  @State progress: number = 0;
  @State errorMessage: string = '';
  private isProcessingLogin: boolean = false;

  aboutToAppear() {
    // 清除所有 Cookie，确保干净登录
    webview.WebCookieManager.clearAllCookiesSync();
  }

  private parseCookie(cookieStr: string): ParsedCookie {
    const cookies: Record<string, string> = {};
    const pairs: string[] = cookieStr.split(';');

    for (let i: number = 0; i < pairs.length; i++) {
      const pair: string = pairs[i].trim();
      const eqIndex: number = pair.indexOf('=');
      if (eqIndex > 0) {
        const key: string = pair.substring(0, eqIndex).trim();
        const value: string = pair.substring(eqIndex + 1).trim();
        cookies[key] = value;
      }
    }

    return {
      BDUSS: cookies['BDUSS'] || '',
      STOKEN: cookies['STOKEN'] || '',
      BAIDUID: cookies['BAIDUID'] || ''
    };
  }

  private async checkLoginStatus(url: string): Promise<void> {
    if (this.isProcessingLogin) {
      return;
    }

    // 检查是否跳转到登录成功页面
    if (!url.startsWith(LOGIN_SUCCESS_URL_PREFIX_1) && !url.startsWith(LOGIN_SUCCESS_URL_PREFIX_2)) {
      return;
    }

    try {
      const cookieStr: string = webview.WebCookieManager.fetchCookieSync(url);
      if (!cookieStr || cookieStr.length === 0) {
        return;
      }

      const cookies: ParsedCookie = this.parseCookie(cookieStr);

      if (cookies.BDUSS.length === 0 || cookies.STOKEN.length === 0) {
        return;
      }

      this.isProcessingLogin = true;

      // 验证 BDUSS 和 STOKEN
      if (cookies.BDUSS.length !== 192) {
        this.errorMessage = `BDUSS 长度异常: ${cookies.BDUSS.length}`;
        this.isProcessingLogin = false;
        return;
      }

      if (cookies.STOKEN.length !== 64) {
        this.errorMessage = `STOKEN 长度异常: ${cookies.STOKEN.length}`;
        this.isProcessingLogin = false;
        return;
      }

      // 调用登录 API 获取用户信息
      try {
        const userInfo = await TiebaAPI.login(cookies.BDUSS, cookies.STOKEN);

        // 保存登录信息
        await AppStorageManager.getInstance().setString('bduss', cookies.BDUSS);
        await AppStorageManager.getInstance().setString('stoken', cookies.STOKEN);

        // 保存 tbs
        const tbs: string = TiebaAPI.getTbs();
        if (tbs.length > 0) {
          await AppStorageManager.getInstance().setString('tbs', tbs);
        }

        // 保存 BAIDUID
        if (cookies.BAIDUID && cookies.BAIDUID.length > 0) {
          await AppStorageManager.getInstance().setString('baiduid', cookies.BAIDUID);
        }

        // 生成并保存 cuid
        const cuid: string = CryptoUtil.generateCuid();
        await AppStorageManager.getInstance().setString('cuid', cuid);
        TiebaAPI.setCuid(cuid);

        // 登录成功，跳转到主页
        router.replaceUrl({ url: 'pages/main/HomePage' });
      } catch (err) {
        const error = err as Error;
        this.errorMessage = `登录验证失败: ${error.message}`;
        this.isProcessingLogin = false;

        // 验证失败，重新加载登录页
        this.controller.loadUrl(LOGIN_URL);
      }
    } catch (err) {
      const error = err as Error;
      this.errorMessage = `获取 Cookie 失败: ${error.message}`;
      this.isProcessingLogin = false;
    }
  }

  build() {
    Column() {
      // 顶部导航栏
      Row() {
        Image('')
          .width(24)
          .height(24)
          .fillColor($r('app.color.text_primary'))
          .onClick(() => {
            router.back();
          })

        Text($r('app.string.baidu_login_title'))
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)

        Blank()
          .width(24)
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .alignItems(VerticalAlign.Center)
      .backgroundColor($r('app.color.background'))

      // 进度条
      if (this.isLoading) {
        Row() {
          Progress({ value: this.progress, total: 100 })
            .width('100%')
            .height(2)
            .color($r('app.color.primary'))
        }
        .width('100%')
      }

      // 错误提示
      if (this.errorMessage.length > 0) {
        Text(this.errorMessage)
          .fontSize(12)
          .fontColor($r('app.color.error'))
          .padding(8)
          .backgroundColor($r('app.color.error_bg'))
          .width('100%')
          .textAlign(TextAlign.Center)
      }

      // WebView
      Web({ src: LOGIN_URL, controller: this.controller })
        .width('100%')
        .layoutWeight(1)
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .zoomAccess(true)
        .onPageBegin((event) => {
          this.isLoading = true;
          this.progress = 0;
        })
        .onProgressChange((event) => {
          this.progress = event.newProgress;
        })
        .onPageEnd((event) => {
          this.isLoading = false;
          this.progress = 100;

          // 页面加载完成，检查是否登录成功
          if (event.url) {
            this.checkLoginStatus(event.url);
          }
        })
        .onErrorReceive((event) => {
          this.isLoading = false;
          this.errorMessage = `页面加载错误: ${event.error.getErrorInfo()}`;
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
  }
}
