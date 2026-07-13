// 网页登录页（百度账号登录）
// 加载百度登录页，登录成功后从 cookie 提取 BDUSS/STOKEN，调用 TiebaAPI.login 完成登录
//
// #167 [A4-S7] 迁移到 HdsNavDestination + hideTitleBar(true)（无标题栏/返回按钮，全屏 WebView）
// P1 #1 修复：登录成功后 RouterUtil.backToRoot() + RouterUtil.replace(MainPage)，
// 清空栈中残留的 LoginPage，避免用户从 MainPage 返回键回到 LoginPage

import { AppStorageV2 } from '@kit.ArkUI';
import { HdsNavDestination } from '@kit.UIDesignKit';
import { webview } from '@kit.ArkWeb';
import { AppStorageManager } from '../../data/AppStorage';
import { TiebaAPI } from '../../api/TiebaAPI';
import { CryptoUtil } from '../../utils/CryptoUtil';
import { getResourceString } from '../../utils/ResourceUtil';
import { BdussState } from '../../model/AppStorageV2Models';
import { connectTheme, ThemeState } from '../../theme/ThemeManager';
import { RouterUtil } from '../../utils/RouterUtil';
import { getStatusBarHeight } from '../../utils/StatusBarUtil';

const LOGIN_URL: string = 'https://wappass.baidu.com/passport?login&u=https%3A%2F%2Ftieba.baidu.com%2Findex%2Ftbwise%2Fmine';
const LOGIN_SUCCESS_URL_PREFIX_1: string = 'https://tieba.baidu.com/index/tbwise/';
const LOGIN_SUCCESS_URL_PREFIX_2: string = 'https://tiebac.baidu.com/index/tbwise/';

interface ParsedCookie {
  BDUSS: string;
  STOKEN: string;
  BAIDUID?: string;
}

// #167 [A4-S7] Navigation 路由表 @Builder：供 router_map.json 的 buildFunction 引用
@Builder
export function WebLoginPageBuilder() {
  WebLoginPage()
}

@ComponentV2
export struct WebLoginPage {
  controller: webview.WebviewController = new webview.WebviewController();
  @Local isLoading: boolean = true;
  @Local progress: number = 0;
  @Local errorMessage: string = '';
  private isProcessingLogin: boolean = false;
  @Local themeState: ThemeState = connectTheme();
  // 状态栏高度（vp），沉浸式避让状态栏，默认 36，aboutToAppear 动态获取
  @Local statusBarHeight: number = 36;

  async aboutToAppear() {
    // 获取状态栏高度，用于内容区 padding top 避让状态栏
    try {
      this.statusBarHeight = await getStatusBarHeight(getContext(this));
    } catch (err) {
      console.error(`[WebLoginPage] getStatusBarHeight failed: ${(err as Error).message}`);
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

        // #167 P1 #1 修复：清空栈中残留的 LoginPage，直接跳转 MainPage
        // backToRoot() 清空所有 NavDestination（包括 LoginPage 和 WebLoginPage 自己），
        // replace(MainPage) 在空栈上 pushPathByName(MainPage)。
        // clear 和 pushPathByName 同步执行，中间无 UI 渲染，用户不会看到 NavBar 闪烁
        // 登录成功 toast 提示（toast 是全局的，跳转后仍会显示）
        this.getUIContext().getPromptAction().showToast({
          message: getResourceString($r('app.string.login_success'))
        });
        RouterUtil.backToRoot();
        RouterUtil.replace(RouterUtil.ROUTE_MAIN_PAGE);
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

  build() {
    // #167 [A4-S7] HdsNavDestination 包装：hideTitleBar(true) 无标题栏/返回按钮，全屏 WebView
    HdsNavDestination() {
      Column() {
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
      .padding({ top: this.statusBarHeight })
      .backgroundColor($r('app.color.background'))
    }
    .hideTitleBar(true)
    .backgroundColor($r('app.color.background'))
  }
}
