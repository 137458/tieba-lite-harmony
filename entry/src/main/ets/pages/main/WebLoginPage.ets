import { router, AppStorageV2 } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { AppStorageManager } from '../../data/AppStorage';
import { TiebaAPI } from '../../api/TiebaAPI';
import { CryptoUtil } from '../../utils/CryptoUtil';
import { getResourceString } from '../../utils/ResourceUtil';
import { getStatusBarHeight } from '../../utils/StatusBarUtil';
import { BdussState } from '../../model/AppStorageV2Models';
import { connectTheme, ThemeState } from '../../theme/ThemeManager';
import { VibratorUtil } from '../../utils/VibratorUtil';

const LOGIN_URL: string = 'https://wappass.baidu.com/passport?login&u=https%3A%2F%2Ftieba.baidu.com%2Findex%2Ftbwise%2Fmine';
const LOGIN_SUCCESS_URL_PREFIX_1: string = 'https://tieba.baidu.com/index/tbwise/';
const LOGIN_SUCCESS_URL_PREFIX_2: string = 'https://tiebac.baidu.com/index/tbwise/';

interface ParsedCookie {
  BDUSS: string;
  STOKEN: string;
  BAIDUID?: string;
}

@Entry
@ComponentV2
struct WebLoginPage {
  controller: webview.WebviewController = new webview.WebviewController();
  @Local isLoading: boolean = true;
  @Local progress: number = 0;
  @Local errorMessage: string = '';
  private isProcessingLogin: boolean = false;
  // 状态栏高度（vp），沉浸式避让状态栏，默认 36，aboutToAppear 动态获取
  @Local statusBarHeight: number = 36;
  @Local themeState: ThemeState = connectTheme();

  async aboutToAppear() {
    // 获取状态栏高度（沉浸式，P1 重构提取为 StatusBarUtil）
    // try-catch 兜底：失败不阻塞登录页加载，保留默认值 36
    try {
      this.statusBarHeight = await getStatusBarHeight(getContext(this));
    } catch (err) {
      console.warn(`[WebLoginPage] getStatusBarHeight failed: ${(err as Error).message}`);
    }
    // 清除所有 Cookie，确保干净登录
    // try-catch 兜底：清 cookie 失败不应阻断登录页加载（webview 内部异常时可能抛错）
    try {
      webview.WebCookieManager.clearAllCookiesSync();
    } catch (err) {
      console.warn(`[WebLoginPage] clearAllCookiesSync failed: ${(err as Error).message}`);
    }
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
    const matchedPrefix1: boolean = url.startsWith(LOGIN_SUCCESS_URL_PREFIX_1);
    const matchedPrefix2: boolean = url.startsWith(LOGIN_SUCCESS_URL_PREFIX_2);
    if (!matchedPrefix1 && !matchedPrefix2) {
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

      // 验证 BDUSS 和 STOKEN 长度（issue #25 放宽到 [100, 256]，防误粘贴，服务端 token 长度可能调整）
      if (cookies.BDUSS.length < 100 || cookies.BDUSS.length > 256) {
        console.warn(`[WebLoginPage] BDUSS length abnormal: ${cookies.BDUSS.length}`);
        this.errorMessage = `${getResourceString($r('app.string.bduss_length_abnormal'))}: ${cookies.BDUSS.length}`;
        this.isProcessingLogin = false;
        return;
      }

      if (cookies.STOKEN.length < 32 || cookies.STOKEN.length > 128) {
        console.warn(`[WebLoginPage] STOKEN length abnormal: ${cookies.STOKEN.length}`);
        this.errorMessage = `${getResourceString($r('app.string.stoken_length_abnormal'))}: ${cookies.STOKEN.length}`;
        this.isProcessingLogin = false;
        return;
      }

      // 调用登录 API 获取用户信息
      try {
        const userInfo = await TiebaAPI.login(cookies.BDUSS, cookies.STOKEN);

        // 保存登录信息
        await AppStorageManager.getInstance().setString('bduss', cookies.BDUSS);
        // #90 同步到 AppStorageV2，触发订阅方联动
        const bdussState = AppStorageV2.connect(BdussState, 'bduss', () => new BdussState())!;
        bdussState.value = cookies.BDUSS;
        await AppStorageManager.getInstance().setString('stoken', cookies.STOKEN);

        // 保存 tbs
        const tbs: string = TiebaAPI.getTbs();
        if (tbs.length > 0) {
          await AppStorageManager.getInstance().setString('tbs', tbs);
        }

        // 持久化用户信息（issue #41：登录成功后写入 uid/name/avatar/nickname，供 ProfilePage 卡片展示）
        // 注意：avatar 字段实际存的是 portrait path（参见 doLogin：avatar = data.user.portrait）
        // ProfilePage 用此字段拼完整头像 URL
        await AppStorageManager.getInstance().setString('uid', userInfo.uid.toString());
        await AppStorageManager.getInstance().setString('name', userInfo.name);
        await AppStorageManager.getInstance().setString('avatar', userInfo.avatar);
        await AppStorageManager.getInstance().setString('nickname', userInfo.nickname);

        // 保存 BAIDUID
        if (cookies.BAIDUID && cookies.BAIDUID.length > 0) {
          await AppStorageManager.getInstance().setString('baiduid', cookies.BAIDUID);
        }

        // 生成并保存 cuid
        const cuid: string = await CryptoUtil.generateCuid(await CryptoUtil.getOrCreateDeviceId());
        await AppStorageManager.getInstance().setString('cuid', cuid);
        TiebaAPI.setCuid(cuid);

        // 登录成功，跳转到主页
        // #171 MainPage 已迁移为 NavDestination（router_map.json），不在 main_pages.json 中。
        // router.replaceUrl 无法跳转 NavDestination，改为回到 Index 容器，
        // Index.initApp 检测已登录后用 RouterUtil.replace 跳转 MainPage。
        router.replaceUrl({ url: 'pages/Index' })
          .then(() => {
            // 跳转成功
          })
          .catch((err: Error) => {
            // 兜底：replaceUrl 失败（路由表配置错误等）时记录日志，避免静默吞错
            console.error(`[WebLoginPage] replaceUrl to Index failed: ${err.message}`);
            this.errorMessage = `${getResourceString($r('app.string.page_jump_failed'))}: ${err.message}`;
            this.isProcessingLogin = false;
          });
      } catch (err) {
        const error = err as Error;
        // 只打印 error.message，不传整个 err 对象，避免泄漏 BDUSS/STOKEN 凭据
        console.error(`[WebLoginPage] TiebaAPI.login failed: ${error.message}`);
        this.errorMessage = `${getResourceString($r('app.string.login_verify_failed'))}: ${error.message}`;
        this.isProcessingLogin = false;

        // 验证失败，重新加载登录页
        this.controller.loadUrl(LOGIN_URL);
      }
    } catch (err) {
      const error = err as Error;
      // 只打印 error.message，不传整个 err 对象，避免泄漏凭据
      console.error(`[WebLoginPage] fetchCookieSync/parse failed: ${error.message}`);
      this.errorMessage = `${getResourceString($r('app.string.get_cookie_failed'))}: ${error.message}`;
      this.isProcessingLogin = false;
    }
  }

  /**
   * #120 回到页面顶部
   * 调用 webview.WebviewController.scrollTo(0, 0) 滚动到顶部
   * 页面未加载时调用会抛异常，try-catch 静默处理
   */
  private scrollToTop(): void {
    // #121 触感反馈：返回顶部按钮触发轻震动
    VibratorUtil.light();
    try {
      this.controller.scrollTo(0, 0);
    } catch (err) {
      console.warn(`[WebLoginPage] scrollToTop failed: ${(err as Error).message}`);
    }
  }

  build() {
    Column() {
      // 顶部导航栏
      Row() {
        Image($r('app.media.ic_back'))
          .width(24)
          .height(24)
          .fillColor($r('app.color.text_primary'))
          // A5 图片优化：本地 SVG 图标，同步加载+低质量插值
          .syncLoad(true)
          .interpolation(ImageInterpolation.Low)
          .onClick(() => {
            router.back();
          })

        Text($r('app.string.baidu_login_title'))
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .margin({ left: 12 })

        // #120 回顶按钮：点击调用 controller.scrollTo(0,0) 回到页面顶部
        // 使用 ic_chevron_right 旋转 -90 度表示向上箭头（项目无 ic_arrow_up，复用现有图标）
        Image($r('app.media.ic_chevron_right'))
          .width(24)
          .height(24)
          .fillColor($r('app.color.text_primary'))
          .syncLoad(true)
          .interpolation(ImageInterpolation.Low)
          .rotate({ angle: -90 })
          .onClick(() => {
            this.scrollToTop();
          })
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
            .color(this.themeState.primary)
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
          .margin({ left: 16, right: 16 })
      }

      // WebView
      Web({ src: LOGIN_URL, controller: this.controller })
        .width('100%')
        .layoutWeight(1)
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .zoomAccess(true)
        // #120 Web 闪烁优化：设置 backgroundColor 防止页面加载前白闪
        .backgroundColor($r('app.color.background'))
        // #120 深色模式适配：Web 内容跟随系统深色模式（darkMode Auto + forceDarkAccess）
        .darkMode(WebDarkMode.Auto)
        .forceDarkAccess(true)
        // #120 缓存策略：Default 优先使用缓存，未命中再网络，加速二次加载
        .cacheMode(CacheMode.Default)
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
            this.checkLoginStatus(event.url).catch((err: Error) => {
              console.error(`[WebLoginPage] checkLoginStatus failed: ${err.message}`);
            });
          }
        })
        .onErrorReceive((event) => {
          this.isLoading = false;
          console.error(`[WebLoginPage] onErrorReceive: ${event.error.getErrorInfo()}`);
          this.errorMessage = `${getResourceString($r('app.string.page_load_error'))}: ${event.error.getErrorInfo()}`;
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.background'))
  }
}
