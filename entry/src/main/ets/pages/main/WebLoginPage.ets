import { router, window } from '@kit.ArkUI';
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
  // 状态栏高度（vp），沉浸式避让状态栏，默认 36，aboutToAppear 动态获取
  @State statusBarHeight: number = 36;

  async aboutToAppear() {
    // 获取状态栏高度（沉浸式，对齐 HomePage 实现）
    try {
      const mainWindow = await window.getLastWindow(getContext(this));
      const avoidArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      this.statusBarHeight = px2vp(avoidArea.topRect.height);
    } catch (err) {
      // 获取失败保留默认值 36，记录日志便于排查（issue #33）
      console.warn(`[WebLoginPage] getStatusBarHeight failed: ${(err as Error).message || err}`);
    }
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
    // [DEBUG-WL] 入口：每次 pageEnd 触发时打印实际 URL，用于确认百度登录后跳转地址
    console.info(`[DEBUG-WL] checkLoginStatus enter, url=${url}, isProcessingLogin=${this.isProcessingLogin}`);

    if (this.isProcessingLogin) {
      console.info('[DEBUG-WL] early return: isProcessingLogin=true');
      return;
    }

    // 检查是否跳转到登录成功页面
    const matchedPrefix1: boolean = url.startsWith(LOGIN_SUCCESS_URL_PREFIX_1);
    const matchedPrefix2: boolean = url.startsWith(LOGIN_SUCCESS_URL_PREFIX_2);
    if (!matchedPrefix1 && !matchedPrefix2) {
      // [DEBUG-WL] URL 不匹配任何 prefix —— 这是"卡在个人界面"最可能的失败点
      console.info(`[DEBUG-WL] URL not matched. prefix1=${LOGIN_SUCCESS_URL_PREFIX_1}(match=${matchedPrefix1}), prefix2=${LOGIN_SUCCESS_URL_PREFIX_2}(match=${matchedPrefix2})`);
      return;
    }
    console.info(`[DEBUG-WL] URL matched (prefix1=${matchedPrefix1}, prefix2=${matchedPrefix2})`);

    try {
      const cookieStr: string = webview.WebCookieManager.fetchCookieSync(url);
      // [DEBUG-WL] fetchCookieSync 返回的原始 cookie 字符串长度 + 前 200 字符（用于确认 cookie 是否真的拿到）
      const preview: string = cookieStr.length > 200 ? cookieStr.substring(0, 200) : cookieStr;
      console.info(`[DEBUG-WL] fetchCookieSync len=${cookieStr.length}, preview=${preview}`);
      if (!cookieStr || cookieStr.length === 0) {
        console.info('[DEBUG-WL] early return: cookieStr empty');
        return;
      }

      const cookies: ParsedCookie = this.parseCookie(cookieStr);
      // [DEBUG-WL] 解析出的 BDUSS/STOKEN 长度（不打印值，防泄漏）
      console.info(`[DEBUG-WL] parsed BDUSS.len=${cookies.BDUSS.length}, STOKEN.len=${cookies.STOKEN.length}, BAIDUID.len=${cookies.BAIDUID ? cookies.BAIDUID.length : 0}`);

      if (cookies.BDUSS.length === 0 || cookies.STOKEN.length === 0) {
        console.info('[DEBUG-WL] early return: BDUSS or STOKEN empty');
        return;
      }

      this.isProcessingLogin = true;

      // 验证 BDUSS 和 STOKEN
      if (cookies.BDUSS.length !== 192) {
        console.warn(`[DEBUG-WL] BDUSS length mismatch (expected 192, got ${cookies.BDUSS.length})`);
        this.errorMessage = `BDUSS 长度异常: ${cookies.BDUSS.length}`;
        this.isProcessingLogin = false;
        return;
      }

      if (cookies.STOKEN.length !== 64) {
        console.warn(`[DEBUG-WL] STOKEN length mismatch (expected 64, got ${cookies.STOKEN.length})`);
        this.errorMessage = `STOKEN 长度异常: ${cookies.STOKEN.length}`;
        this.isProcessingLogin = false;
        return;
      }

      console.info('[DEBUG-WL] all checks passed, calling TiebaAPI.login');
      // 调用登录 API 获取用户信息
      try {
        const userInfo = await TiebaAPI.login(cookies.BDUSS, cookies.STOKEN);
        console.info(`[DEBUG-WL] TiebaAPI.login success, userInfo.uid=${userInfo.uid}, name=${userInfo.name}`);

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
        const cuid: string = await CryptoUtil.generateCuid(await CryptoUtil.getOrCreateDeviceId());
        await AppStorageManager.getInstance().setString('cuid', cuid);
        TiebaAPI.setCuid(cuid);

        // 登录成功，跳转到主页
        // 路由目标必须是 'pages/main/MainPage'（带底部 tab 的主页容器），
        // 'pages/main/HomePage' 是 MainPage 的子组件，未在 main_pages.json 注册，跳转会失败
        console.info('[DEBUG-WL] all storage saved, replacing route to MainPage');
        router.replaceUrl({ url: 'pages/main/MainPage' })
          .then(() => {
            console.info('[DEBUG-WL] replaceUrl to MainPage SUCCESS');
          })
          .catch((err: Error) => {
            // 兜底：replaceUrl 失败（路由表配置错误等）时记录日志，避免静默吞错
            console.error(`[DEBUG-WL] replaceUrl to MainPage FAILED: ${err.message}`);
            this.errorMessage = `页面跳转失败: ${err.message}`;
            this.isProcessingLogin = false;
          });
      } catch (err) {
        const error = err as Error;
        console.error(`[DEBUG-WL] TiebaAPI.login failed: ${error.message}`, err);
        this.errorMessage = `登录验证失败: ${error.message}`;
        this.isProcessingLogin = false;

        // 验证失败，重新加载登录页
        this.controller.loadUrl(LOGIN_URL);
      }
    } catch (err) {
      const error = err as Error;
      console.error(`[DEBUG-WL] fetchCookieSync/parse failed: ${error.message}`, err);
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
      .height(56 + this.statusBarHeight)
      .padding({ left: 16, right: 16, top: this.statusBarHeight })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
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

          // [DEBUG-WL] pageEnd 事件本身是否触发（百度 SPA 可能不触发 pageEnd）
          console.info(`[DEBUG-WL] onPageEnd fired, event.url=${event.url ? event.url : '(empty)'}`);
          // 页面加载完成，检查是否登录成功
          if (event.url) {
            this.checkLoginStatus(event.url);
          }
        })
        .onErrorReceive((event) => {
          this.isLoading = false;
          // [DEBUG-WL] 页面加载错误
          console.error(`[DEBUG-WL] onErrorReceive: ${event.error.getErrorInfo()}`);
          this.errorMessage = `页面加载错误: ${event.error.getErrorInfo()}`;
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
  }
}
