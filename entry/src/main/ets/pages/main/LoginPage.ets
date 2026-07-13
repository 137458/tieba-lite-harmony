// 登录页（手动 BDUSS 备用入口）
// UI 设计：iOS 风格 Logo + 34px ExtraBold 标题 + 12px 圆角按钮（对齐 design-prototype.html L191-205）
// 主要登录方式为 WebLoginPage（网页登录），本页仅作为 BDUSS 手动登录备用入口
// 字段：BDUSS（Password 类型，敏感凭证不明文显示），登录后跳转 MainPage
// stoken 不在登录页输入：网页登录自动获取 stoken，API 层保留 stoken 支持
//
// #167 [A4-S7] 迁移到 HdsNavDestination + titleBar（scrollEffectOpts GRADIENT_BLUR + systemMaterialEffect ADAPTIVE）
// P1 #2 修复：移除 checkLoginStatus 自动登录逻辑，Index.initApp 负责冷启动 login，
// LoginPage 只提供手动登录入口，避免重复 login 导致登录循环

import { AppStorageV2 } from '@kit.ArkUI';
import { HdsNavDestination, hdsMaterial } from '@kit.UIDesignKit';
import { AppStorageManager } from '../../data/AppStorage';
import { TiebaAPI } from '../../api/TiebaAPI';
import { CryptoUtil } from '../../utils/CryptoUtil';
import { getResourceString } from '../../utils/ResourceUtil';
import { BdussState } from '../../model/AppStorageV2Models';
import { connectTheme, ThemeState } from '../../theme/ThemeManager';
import { RouterUtil } from '../../utils/RouterUtil';
import { getStatusBarHeight } from '../../utils/StatusBarUtil';

// HdsNavDestination titleBar mini 模式高度（vp）
const TITLE_BAR_HEIGHT: number = 48;

// #167 [A4-S7] Navigation 路由表 @Builder：供 router_map.json 的 buildFunction 引用
@Builder
export function LoginPageBuilder() {
  LoginPage()
}

@ComponentV2
export struct LoginPage {
  @Local bduss: string = '';
  @Local isLoading: boolean = false;
  @Local errorMessage: string = '';
  @Local themeState: ThemeState = connectTheme();
  // 状态栏高度（vp），沉浸式避让状态栏，默认 36，aboutToAppear 动态获取
  @Local statusBarHeight: number = 36;

  async aboutToAppear(): Promise<void> {
    // 获取状态栏高度，用于内容区 padding top 避让 titleBar
    try {
      this.statusBarHeight = await getStatusBarHeight(getContext(this));
    } catch (err) {
      console.error(`[LoginPage] getStatusBarHeight failed: ${(err as Error).message}`);
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

      // #167 登录成功直接跳转 MainPage，不经过 Index 中转（修复 P1 #1/#2）
      RouterUtil.replace(RouterUtil.ROUTE_MAIN_PAGE);
    } catch (err) {
      const error = err as Error;
      this.errorMessage = error.message || getResourceString($r('app.string.login_failed'));
    } finally {
      this.isLoading = false;
    }
  }

  build() {
    // #167 [A4-S7] HdsNavDestination 包装：titleBar 沉浸光感材质 + GRADIENT_BLUR 滚动模糊
    HdsNavDestination() {
      Column() {
        // 内容区（垂直居中）
        Column() {
          // Logo（应用图标 foreground.png，80x80 圆角 20）
          Image($r('app.media.foreground'))
            .width(80)
            .height(80)
            .borderRadius(20)
            .objectFit(ImageFit.Cover)
            // A5 图片优化：本地图标，同步加载+低质量插值
            .syncLoad(true)
            .interpolation(ImageInterpolation.Low)

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
              // #167 跳转 WebLoginPage 改为 RouterUtil.push
              RouterUtil.push(RouterUtil.ROUTE_WEB_LOGIN_PAGE);
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
        .padding({ left: 32, right: 32, top: 40, bottom: 40 })
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .height('100%')
      .padding({ top: this.statusBarHeight + TITLE_BAR_HEIGHT })
      .backgroundColor($r('app.color.background'))
    }
    .titleBar({
      content: {
        title: {
          mainTitle: $r('app.string.login_button')
        }
      },
      style: {
        // 登录表单不滚动，不配 scrollEffectOpts.GRADIENT_BLUR（仅 systemMaterialEffect 沉浸光感）
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        }
      },
      // 避让状态栏：setWindowLayoutFullScreen(true) 全屏模式下 titleBar 默认不避让状态栏，
      // 需显式设置 avoidLayoutSafeArea: true 让 titleBar 内容（标题/按钮）避让状态栏
      avoidLayoutSafeArea: true
    })
    .backgroundColor($r('app.color.background'))
  }
}
