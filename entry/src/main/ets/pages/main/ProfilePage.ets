// 我的页（"我的"tab）
// 展示当前登录账号信息卡片 + 操作菜单（切换账号/退出登录/设置）
// 后续切片接入完整用户资料（头像/昵称/UID/发帖/粉丝/吧龄等）

import { router } from '@kit.ArkUI';
import { AppStorageManager } from '../../data/AppStorage';
import { TiebaAPI } from '../../api/TiebaAPI';
import { getResourceString } from '../../utils/ResourceUtil';
import { getStatusBarHeight } from '../../utils/StatusBarUtil';
import { getAvatarUrl } from '../../utils/AvatarUtil';

@Component
export struct ProfilePage {
  // 状态栏高度（vp），沉浸式避让状态栏，默认 36，aboutToAppear 动态获取
  @State statusBarHeight: number = 36;
  // 退出登录进行中，防止重复点击
  @State isLoggingOut: boolean = false;
  // 本地存储的账号信息（昵称/UID/avatar，登录成功后由 LoginPage/WebLoginPage 写入，issue #41）
  // 字段名与 UserInfo 类对齐：nickname/avatar（避免 nickName/portrait 大小写不一致）
  @State nickname: string = '';
  @State uid: string = '';
  @State avatar: string = '';
  // bduss 是否存在（用于判断是否已登录）
  @State bduss: string = '';

  async aboutToAppear() {
    // 获取状态栏高度（沉浸式，P1 重构提取为 StatusBarUtil）
    this.statusBarHeight = await getStatusBarHeight(getContext(this));
    // 加载账号信息（issue #40-3）：storage 读取失败时记录日志，避免页面空白无反馈
    try {
      await this.loadAccountInfo();
    } catch (err) {
      console.error(`[ProfilePage] loadAccountInfo failed: ${(err as Error).message || err}`);
    }
  }

  /** 从本地 storage 加载账号信息（用于卡片占位展示） */
  private async loadAccountInfo(): Promise<void> {
    const storage: AppStorageManager = AppStorageManager.getInstance();
    await storage.ensureReady();
    this.bduss = await storage.getString('bduss', '');
    this.uid = await storage.getString('uid', '');
    this.nickname = await storage.getString('nickname', '');
    // avatar 字段存的是 portrait path（参见 doLogin：avatar = data.user.portrait）
    this.avatar = await storage.getString('avatar', '');
  }

  /** 弹出"退出登录"确认弹窗 */
  private showLogoutConfirm(): void {
    if (this.isLoggingOut) {
      return;
    }
    this.getUIContext().getPromptAction().showDialog({
      title: getResourceString($r('app.string.profile_logout_confirm_title')),
      message: getResourceString($r('app.string.profile_logout_confirm_message')),
      buttons: [
        { text: getResourceString($r('app.string.cancel_button')), color: $r('app.color.text_secondary') },
        { text: getResourceString($r('app.string.profile_logout_button')), color: $r('app.color.error') }
      ]
    }).then((result) => {
      // result.index = 用户点击的按钮索引（0=取消，1=退出）
      if (result.index === 1) {
        this.performLogout('pages/main/LoginPage');
      }
    }).catch((err: Error) => {
      // 弹窗异常兜底：记录日志，不强制退出
      console.error(`[ProfilePage] logout dialog failed: ${err.message}`);
    });
  }

  /** 弹出"切换账号"确认弹窗 */
  private showSwitchAccountConfirm(): void {
    if (this.isLoggingOut) {
      return;
    }
    this.getUIContext().getPromptAction().showDialog({
      title: getResourceString($r('app.string.profile_switch_confirm_title')),
      message: getResourceString($r('app.string.profile_switch_confirm_message')),
      buttons: [
        { text: getResourceString($r('app.string.cancel_button')), color: $r('app.color.text_secondary') },
        { text: getResourceString($r('app.string.profile_switch_button')), color: $r('app.color.primary') }
      ]
    }).then((result) => {
      if (result.index === 1) {
        // 切换账号 = 退出 + 直接跳 WebLoginPage
        this.performLogout('pages/main/WebLoginPage');
      }
    }).catch((err: Error) => {
      console.error(`[ProfilePage] switch dialog failed: ${err.message}`);
    });
  }

  /**
   * 执行退出登录 + 跳转到指定页面
   * 共享给"退出登录"和"切换账号"两个入口
   *
   * 清理范围：bduss/stoken/tbs/cuid/baiduid/z_id/client_id/sample_id/tieba_uid
   *           + 本地账号信息 uid/name/avatar/nickname
   *
   * @param targetPage 退出后跳转的页面路由
   */
  private async performLogout(targetPage: string): Promise<void> {
    if (this.isLoggingOut) {
      return;
    }
    this.isLoggingOut = true;
    try {
      const storage: AppStorageManager = AppStorageManager.getInstance();
      // 清理所有登录相关字段（凭证 + 设备标识 + 用户资料缓存）
      // 用户资料字段对齐 UserInfo 类（issue #41）：uid/name/avatar/nickname
      const keysToRemove: string[] = [
        'bduss', 'stoken', 'tbs', 'cuid', 'baiduid',
        'z_id', 'client_id', 'sample_id', 'tieba_uid',
        'uid', 'name', 'avatar', 'nickname'
      ];
      for (let i: number = 0; i < keysToRemove.length; i++) {
        try {
          await storage.remove(keysToRemove[i]);
        } catch (err) {
          // 单个字段清理失败不阻塞，继续清理其他字段
          console.warn(`[ProfilePage] remove ${keysToRemove[i]} failed: ${(err as Error).message}`);
        }
      }
      // 清 TiebaHttpClient 内存态凭证（防止下一页面残留 cookie）
      TiebaAPI.setAuth('', '');
      // 替换路由栈，避免返回到 MainPage（issue #40-2 加 .catch 防止 replaceUrl 失败被静默吞错）
      router.replaceUrl({ url: targetPage }).catch((err: Error) => {
        console.error(`[ProfilePage] replaceUrl to ${targetPage} failed: ${err.message}`);
      });
    } catch (err) {
      // 兜底：即使清理失败也跳转，避免用户卡在已退出态
      console.error(`[ProfilePage] logout failed: ${(err as Error).message}`);
      router.replaceUrl({ url: targetPage }).catch((err2: Error) => {
        console.error(`[ProfilePage] fallback replaceUrl to ${targetPage} failed: ${err2.message}`);
      });
    } finally {
      this.isLoggingOut = false;
    }
  }

  build() {
    Column() {
      // 顶部标题栏
      Row() {
        Text($r('app.string.profile_page_title'))
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
      }
      .width('100%')
      .height(56 + this.statusBarHeight)
      .padding({ top: this.statusBarHeight })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
      .alignItems(VerticalAlign.Center)
      .backgroundColor($r('app.color.background'))

      // 账号信息卡片（占位，后续切片接入完整用户资料）
      Row() {
        if (this.bduss.length > 0) {
          // 已登录：头像 + 昵称 + UID
          Image(getAvatarUrl(this.avatar, 'm'))
            .width(64)
            .height(64)
            .borderRadius(32)
            .backgroundColor($r('app.color.input_background'))
            .objectFit(ImageFit.Cover)

          Column() {
            Text(this.nickname.length > 0 ? this.nickname : getResourceString($r('app.string.profile_default_name')))
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

            if (this.uid.length > 0) {
              Text(`UID: ${this.uid}`)
                .fontSize(12)
                .fontColor($r('app.color.text_caption'))
                .margin({ top: 4 })
            }
          }
          .alignItems(HorizontalAlign.Start)
          .margin({ left: 12 })
          .layoutWeight(1)
        } else {
          // 未登录：显示"未登录"占位
          Text(getResourceString($r('app.string.profile_not_logged_in')))
            .fontSize(14)
            .fontColor($r('app.color.text_caption'))
            .layoutWeight(1)
        }
      }
      .width('100%')
      .padding(16)
      .alignItems(VerticalAlign.Center)
      .backgroundColor($r('app.color.card_background'))
      .borderRadius(8)
      .margin({ left: 12, right: 12, top: 12 })

      // 操作菜单
      Column() {
        // 切换账号
        Row() {
          Text($r('app.string.profile_switch_account'))
            .fontSize(16)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
          Text('>')
            .fontSize(16)
            .fontColor($r('app.color.text_caption'))
        }
        .width('100%')
        .height(56)
        .padding({ left: 16, right: 16 })
        .alignItems(VerticalAlign.Center)
        .onClick(() => this.showSwitchAccountConfirm())

        Divider()
          .color($r('app.color.divider'))
          .margin({ left: 16, right: 16 })

        // 退出登录
        Row() {
          Text($r('app.string.profile_logout'))
            .fontSize(16)
            .fontColor($r('app.color.error'))
            .layoutWeight(1)
          Text('>')
            .fontSize(16)
            .fontColor($r('app.color.text_caption'))
        }
        .width('100%')
        .height(56)
        .padding({ left: 16, right: 16 })
        .alignItems(VerticalAlign.Center)
        .onClick(() => this.showLogoutConfirm())

        Divider()
          .color($r('app.color.divider'))
          .margin({ left: 16, right: 16 })

        // 设置
        Row() {
          Text($r('app.string.profile_settings'))
            .fontSize(16)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
          Text('>')
            .fontSize(16)
            .fontColor($r('app.color.text_caption'))
        }
        .width('100%')
        .height(56)
        .padding({ left: 16, right: 16 })
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          router.pushUrl({ url: 'pages/settings/SettingsPage' });
        })
      }
      .width('100%')
      .backgroundColor($r('app.color.card_background'))
      .borderRadius(8)
      .margin({ left: 12, right: 12, top: 12 })

      // 底部留白
      Blank()
        .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }
}
