// 我的页（"我的"tab）
// 展示当前登录账号完整资料（头像/昵称/UID/发帖/粉丝/性别/吧龄/VIP）+ 操作菜单
// 数据来源：本地 storage 占位 + getUserProfile(/c/u/user/profile?cmd=303012) 完整资料（issue #51 切片4）
// UI 设计：iOS Large Title + Grouped Card 资料卡 + iOS Grouped List 菜单（对齐 design-spec.md 第6节）

import { router } from '@kit.ArkUI';
import { AppStorageManager } from '../../data/AppStorage';
import { TiebaAPI } from '../../api/TiebaAPI';
import { UserProfileInfo } from '../../model/UserProfileModels';
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
  // avatar 字段存的是 portrait 标识符（参见 doLogin：avatar = data.user.portrait）
  @State nickname: string = '';
  @State uid: string = '';
  @State avatar: string = '';
  // bduss 是否存在（用于判断是否已登录）
  @State bduss: string = '';

  // 完整用户资料（getUserProfile 返回，issue #51 切片4）
  @State profile: UserProfileInfo = new UserProfileInfo();
  // 完整资料是否已加载完成（区分占位与完整展示）
  @State profileLoaded: boolean = false;
  // 完整资料加载错误信息（非空表示加载失败，保留本地占位展示）
  @State profileErrorMessage: string = '';

  async aboutToAppear() {
    // 获取状态栏高度（沉浸式，P1 重构提取为 StatusBarUtil）
    // 失败不阻塞后续加载，保留默认值 36
    try {
      this.statusBarHeight = await getStatusBarHeight(getContext(this));
    } catch (err) {
      console.error(`[ProfilePage] getStatusBarHeight failed: ${(err as Error).message}`);
    }
    // 加载账号信息：storage 读取失败时记录日志，避免页面空白无反馈
    try {
      await this.loadAccountInfo();
    } catch (err) {
      console.error(`[ProfilePage] loadAccountInfo failed: ${(err as Error).message || err}`);
    }
    // 已登录则异步拉取完整资料（失败不影响占位展示）
    if (this.bduss.length > 0) {
      this.loadProfile().catch((err: Error) => {
        console.error(`[ProfilePage] loadProfile failed: ${err.message}`);
      });
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

  /** 拉取完整用户资料：portrait 优先，nickname fallback，均空则跳过 */
  private async loadProfile(): Promise<void> {
    this.profileErrorMessage = '';
    // portrait 标识符优先（本地 avatar 字段），其次 nickname 作为 un fallback
    const portrait: string = this.avatar;
    const userName: string = this.nickname;
    if (portrait.length === 0 && userName.length === 0) {
      return;
    }
    try {
      const uidNum: number = this.uid.length > 0 ? Number(this.uid) : 0;
      this.profile = await TiebaAPI.getUserProfile(portrait, userName, uidNum);
      this.profileLoaded = true;
    } catch (err) {
      this.profileErrorMessage = (err as Error).message || getResourceString($r('app.string.user_profile_load_failed'));
    }
  }

  /** 跳转到我的收藏页（issue #49 切片2） */
  private navigateToThreadStore(): void {
    router.pushUrl({ url: 'pages/thread/ThreadStorePage' })
      .catch((err: Error) => {
        console.error(`[ProfilePage] navigate to threadStore failed: ${err.message}`);
      });
  }

  /** 性别显示文本：1=男 2=女 其他=保密 */
  private getGenderText(gender: number): string {
    if (gender === 1) {
      return getResourceString($r('app.string.gender_male'));
    }
    if (gender === 2) {
      return getResourceString($r('app.string.gender_female'));
    }
    return getResourceString($r('app.string.gender_unknown'));
  }

  /** 吧龄显示文本：0 显示 "-"，非 0 显示 "x.x年" */
  private getAgeText(age: number): string {
    if (age <= 0) {
      return '-';
    }
    return getResourceString($r('app.string.age_years', age.toString()));
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
      // iOS Large Title 顶部栏（34px 800，对齐 design-spec.md 第2节）
      Row() {
        Text($r('app.string.profile_page_title'))
          .fontSize(34)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .textAlign(TextAlign.Start)
      }
      .width('100%')
      .height(56 + this.statusBarHeight)
      .padding({ left: 20, right: 20, top: this.statusBarHeight, bottom: 8 })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
      .alignItems(VerticalAlign.Center)

      Scroll() {
        Column() {
          // 账号信息卡片
          if (this.bduss.length > 0) {
            this.ProfileCard()
          } else {
            // 未登录：占位提示
            Row() {
              Text(getResourceString($r('app.string.profile_not_logged_in')))
                .fontSize(14)
                .fontColor($r('app.color.text_caption'))
                .layoutWeight(1)
            }
            .width('100%')
            .padding(16)
            .alignItems(VerticalAlign.Center)
            .backgroundColor($r('app.color.card_background'))
            .borderRadius(10)
            .margin({ left: 16, right: 16, top: 16 })
          }

          // 操作菜单（已登录才显示，iOS Grouped List 风格）
          if (this.bduss.length > 0) {
            // 第一组：我的收藏 + 切换账号
            Column() {
              this.MenuRow(
                $r('app.string.profile_my_store'),
                'M12 21.35l-1.45-1.32C5.4 15.36 2 12.28 2 8.5 2 5.42 4.42 3 7.5 3c1.74 0 3.41.81 4.5 2.09C13.09 3.81 14.76 3 16.5 3 19.58 3 22 5.42 22 8.5c0 3.78-3.4 6.86-8.55 11.54L12 21.35z',
                false,
                () => this.navigateToThreadStore()
              )
              this.MenuRow(
                $r('app.string.profile_switch_account'),
                'M4 6H2v14c0 1.1.9 2 2 2h14v-2H4V6zm16-4H8c-1.1 0-2 .9-2 2v12c0 1.1.9 2 2 2h12c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2zm0 14H8V4h12v12zm-8-2h2V8h-2v6zm4-4h2V8h-2v2z',
                true,
                () => this.showSwitchAccountConfirm()
              )
            }
            .width('100%')
            .backgroundColor($r('app.color.card_background'))
            .borderRadius(10)
            .margin({ left: 16, right: 16, top: 20 })

            // 第二组：设置
            Column() {
              this.MenuRow(
                $r('app.string.profile_settings'),
                'M19.14 12.94c.04-.3.06-.61.06-.94 0-.32-.02-.64-.07-.94l2.03-1.58a.49.49 0 0 0 .12-.61l-1.92-3.32a.49.49 0 0 0-.59-.22l-2.39.96c-.5-.38-1.03-.7-1.62-.94l-.36-2.54a.48.48 0 0 0-.48-.41h-3.84a.48.48 0 0 0-.48.41l-.36 2.54c-.59.24-1.13.57-1.62.94l-2.39-.96a.49.49 0 0 0-.59.22L2.74 8.87c-.12.21-.08.47.12.61l2.03 1.58c-.05.3-.07.62-.07.94s.02.64.07.94l-2.03 1.58a.49.49 0 0 0-.12.61l1.92 3.32c.12.22.37.29.59.22l2.39-.96c.5.38 1.03.7 1.62.94l.36 2.54c.05.24.24.41.48.41h3.84c.24 0 .44-.17.48-.41l.36-2.54c.59-.24 1.13-.56 1.62-.94l2.39.96c.22.08.47 0 .59-.22l1.92-3.32c.12-.22.07-.47-.12-.61l-2.01-1.58zM12 15.6A3.6 3.6 0 1 1 12 8.4a3.6 3.6 0 0 1 0 7.2z',
                false,
                () => {
                  router.pushUrl({ url: 'pages/settings/SettingsPage' })
                    .catch((err: Error) => {
                      console.error(`[ProfilePage] navigate to settings failed: ${err.message}`);
                    });
                }
              )
            }
            .width('100%')
            .backgroundColor($r('app.color.card_background'))
            .borderRadius(10)
            .margin({ left: 16, right: 16, top: 12 })

            // 第三组：退出登录（红色 danger 样式）
            Column() {
              this.MenuRowDanger(
                $r('app.string.profile_logout'),
                'M17 7l-1.41 1.41L18.17 11H8v2h10.17l-2.58 2.58L17 17l5-5zM4 5h8V3H4c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h8v-2H4V5z',
                () => this.showLogoutConfirm()
              )
            }
            .width('100%')
            .backgroundColor($r('app.color.card_background'))
            .borderRadius(10)
            .margin({ left: 16, right: 16, top: 12 })

            // 底部链接（登录页预览/帖子详情预览，对齐 design-prototype.html bottom-links）
            Row() {
              Text($r('app.string.login_title'))
                .fontSize(13)
                .fontColor($r('app.color.primary'))
                .fontWeight(FontWeight.Medium)
                .padding({ left: 14, right: 14, top: 6, bottom: 6 })
                .backgroundColor($r('app.color.primary_light'))
                .borderRadius(8)
                .onClick(() => {
                  router.pushUrl({ url: 'pages/main/LoginPage' })
                    .catch((err: Error) => {
                      console.error(`[ProfilePage] navigate to LoginPage failed: ${err.message}`);
                    });
                })
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
            .margin({ top: 12 })
          }

          // 底部留白
          Blank()
            .height(24)
        }
        .width('100%')
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  /**
   * iOS Grouped List 菜单项（对齐 design-spec.md 第6节 菜单列表规格）
   * 行高 44px，左图标(20px primary tint 色) + 文字(15px) + 右 chevron.right(14px)
   * showDivider：是否显示底部 inset 分割线（中间项显示，最后一项隐藏）
   */
  @Builder
  MenuRow(label: ResourceStr, iconPath: string, showDivider: boolean, onClick: () => void) {
    Row() {
      // Shape 包裹 Path 提供 viewPort
      Shape() {
        Path()
          .commands(iconPath)
          .fill($r('app.color.primary'))
      }
      .width(20)
      .height(20)
      .viewPort({ x: 0, y: 0, width: 24, height: 24 })

      Text(label)
        .fontSize(15)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
        .margin({ left: 12 })

      // Shape 包裹 Path 提供 viewPort
      Shape() {
        Path()
          .commands('M10 6L8.59 7.41 13.17 12l-4.58 4.59L10 18l6-6z')
          .fill($r('app.color.text_caption'))
      }
      .width(14)
      .height(14)
      .viewPort({ x: 0, y: 0, width: 24, height: 24 })
    }
    .width('100%')
    .height(44)
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
    .border(showDivider ? { width: { bottom: 0.5 }, color: $r('app.color.divider') } : { width: 0 })
    .onClick(() => onClick())
  }

  /** danger 菜单项（红色文字 + 红色图标，用于"退出登录"） */
  @Builder
  MenuRowDanger(label: ResourceStr, iconPath: string, onClick: () => void) {
    Row() {
      // Shape 包裹 Path 提供 viewPort
      Shape() {
        Path()
          .commands(iconPath)
          .fill($r('app.color.error'))
      }
      .width(20)
      .height(20)
      .viewPort({ x: 0, y: 0, width: 24, height: 24 })

      Text(label)
        .fontSize(15)
        .fontColor($r('app.color.error'))
        .layoutWeight(1)
        .margin({ left: 12 })

      // Shape 包裹 Path 提供 viewPort
      Shape() {
        Path()
          .commands('M10 6L8.59 7.41 13.17 12l-4.58 4.59L10 18l6-6z')
          .fill($r('app.color.text_caption'))
      }
      .width(14)
      .height(14)
      .viewPort({ x: 0, y: 0, width: 24, height: 24 })
    }
    .width('100%')
    .height(44)
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
    .onClick(() => onClick())
  }

  // 资料卡片：完整资料加载完展示完整字段，否则展示本地缓存占位
  // 对齐 design-spec.md 第6节 用户资料卡片规格
  @Builder
  ProfileCard() {
    Column() {
      // 头像（72px 圆形）
      Image(getAvatarUrl(this.profileLoaded ? this.profile.portrait : this.avatar, 'm'))
        .width(72)
        .height(72)
        .borderRadius(36)
        .objectFit(ImageFit.Cover)
        .backgroundColor($r('app.color.input_background'))

      // 昵称行：昵称(22px Bold) + VIP pill(10px Bold 金色渐变)
      Row() {
        Text(this.profileLoaded && this.profile.nickName.length > 0
          ? this.profile.nickName
          : (this.nickname.length > 0 ? this.nickname : getResourceString($r('app.string.profile_default_name'))))
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        // 超级会员标识（仅完整资料展示）
        if (this.profileLoaded && this.profile.isVip) {
          Text($r('app.string.vip_badge'))
            .fontSize(10)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .padding({ left: 8, right: 8, top: 2, bottom: 2 })
            .borderRadius(6)
            .margin({ left: 8 })
            .linearGradient({
              angle: 135,
              colors: [['#FFD700', 0.0], ['#FFA500', 1.0]]
            })
        }
      }
      .alignItems(VerticalAlign.Center)
      .margin({ top: 12 })

      // UID（13px text_secondary）
      if (this.uid.length > 0) {
        Text(`UID: ${this.uid}`)
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 4 })
      }

      // 统计行：发帖 / 粉丝 / 关注（数字 20px Bold + 标签 11px caption）
      if (this.profileLoaded) {
        Row() {
          // 发帖
          Column() {
            Text(this.profile.postNum.toString())
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
            Text($r('app.string.post_num_label'))
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .margin({ top: 2 })
          }
          .alignItems(HorizontalAlign.Center)

          // 粉丝
          Column() {
            Text(this.profile.fanNum.toString())
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
            Text($r('app.string.fan_num_label'))
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .margin({ top: 2 })
          }
          .alignItems(HorizontalAlign.Center)
          .margin({ left: 32 })

          // 关注（占位，profile 模型无 followNum 字段，预留 UI 位置）
          Column() {
            Text('0')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
            Text($r('app.string.follow_num_label'))
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .margin({ top: 2 })
          }
          .alignItems(HorizontalAlign.Center)
          .margin({ left: 32 })
        }
        .margin({ top: 16 })

        // meta-row：性别 + 吧龄（12px text_secondary，居中）
        Row() {
          Text(this.getGenderText(this.profile.gender))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))

          Text($r('app.string.age_label') + ': ' + this.getAgeText(this.profile.age))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .margin({ left: 12 })
        }
        .margin({ top: 12 })
        .justifyContent(FlexAlign.Center)
      }

      // 资料加载错误提示（保留本地占位，底部小字提示）
      if (this.profileErrorMessage.length > 0) {
        Text(this.profileErrorMessage)
          .fontSize(12)
          .fontColor($r('app.color.error'))
          .margin({ top: 12 })
      }
    }
    .width('100%')
    .padding({ top: 20, bottom: 20, left: 16, right: 16 })
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(10)
    .margin({ left: 16, right: 16, top: 16 })
    .alignItems(HorizontalAlign.Center)
  }
}
