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
import { getAvatarImageUrl } from '../../utils/ImageLoadUtil';

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
  // #81 图片加载策略：通过 AppStorage 共享，SettingsPage 修改后自动响应
  @StorageProp('imageLoadType') imageLoadType: number = 0;
  @StorageProp('isWifi') isWifi: boolean = false;

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

  /**
   * 获取当前显示昵称（profile 优先，fallback 到本地 nickname，再 fallback 到默认名）
   * 用于头像 fallback 首字 + 昵称行显示
   */
  private getDisplayName(): string {
    if (this.profileLoaded && this.profile.nickName.length > 0) {
      return this.profile.nickName;
    }
    if (this.nickname.length > 0) {
      return this.nickname;
    }
    return getResourceString($r('app.string.profile_default_name'));
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
          .fontWeight(800)
          .fontColor($r('app.color.text_primary'))
          .letterSpacing(0.37)
          .layoutWeight(1)
          .textAlign(TextAlign.Start)
      }
      .width('100%')
      .height(56 + this.statusBarHeight)
      .padding({ left: 16, right: 16, top: this.statusBarHeight, bottom: 8 })
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

          // 操作菜单（已登录才显示，iOS Grouped List 风格，对齐原型 page-profile 分组）
          if (this.bduss.length > 0) {
            // 第一组：我的收藏 + 切换账号 + 设置（对齐原型 menu-group 三项同组）
            Column() {
              this.MenuRow(
                $r('app.string.profile_my_store'),
                $r('app.media.ic_favorite'),
                true,
                () => this.navigateToThreadStore()
              )
              this.MenuRow(
                $r('app.string.profile_switch_account'),
                $r('app.media.ic_switch_account'),
                true,
                () => this.showSwitchAccountConfirm()
              )
              this.MenuRow(
                $r('app.string.profile_settings'),
                $r('app.media.ic_settings'),
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
            .margin({ left: 16, right: 16, top: 20 })

            // 第二组：退出登录（红色 danger 样式）
            Column() {
              this.MenuRowDanger(
                $r('app.string.profile_logout'),
                $r('app.media.ic_logout'),
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

          // 不加底部留白：用户明确表示悬浮 TabBar 遮挡内容可接受，加留白反而显示灰色遮罩
        }
        .width('100%')
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  MenuRow(label: ResourceStr, iconRes: Resource, showDivider: boolean, onClick: () => void) {
    Column() {
      Row() {
        Image(iconRes)
          .width(22)
          .height(22)
          .fillColor($r('app.color.primary'))

        Text(label)
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .margin({ left: 12 })

        Image($r('app.media.ic_chevron_right'))
          .width(14)
          .height(14)
          .fillColor($r('app.color.text_caption'))
      }
      .width('100%')
      .height(44)
      .padding({ left: 16, right: 16 })
      .alignItems(VerticalAlign.Center)

      if (showDivider) {
        Divider()
          .strokeWidth(0.5)
          .color($r('app.color.divider'))
          .margin({ left: 52 })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .onClick(() => onClick())
  }

  @Builder
  MenuRowDanger(label: ResourceStr, iconRes: Resource, onClick: () => void) {
    Row() {
      Image(iconRes)
        .width(22)
        .height(22)
        .fillColor($r('app.color.error'))

      Text(label)
        .fontSize(16)
        .fontColor($r('app.color.error'))
        .layoutWeight(1)
        .margin({ left: 12 })

      Image($r('app.media.ic_chevron_right'))
        .width(14)
        .height(14)
        .fillColor($r('app.color.text_caption'))
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
      // portrait 为空时 fallback 显示昵称首字 + primary 渐变背景（避免 Image 空白）
      // 根因：登录时 data.user.portrait 可能返回空，或 getUserProfile 失败 profile.portrait 为空
      // #81 接入图片加载策略：shouldLoad=false 时返回空串，Image 组件显示 alt 占位图
      // 注：ArkUI @Builder 内不允许声明 const/let 变量，getAvatarUrl 重复调用
      if (getAvatarUrl(this.profileLoaded ? this.profile.portrait : this.avatar, 'm').length > 0) {
        Image(getAvatarImageUrl(getAvatarUrl(this.profileLoaded ? this.profile.portrait : this.avatar, 'm'), this.imageLoadType, this.isWifi))
          .width(72)
          .height(72)
          .borderRadius(36)
          .objectFit(ImageFit.Cover)
          .backgroundColor($r('app.color.input_background'))
          .alt($r('app.media.startIcon'))
      } else {
        // 占位头像：昵称首字大写 + primary 渐变背景（对齐 LoginPage Logo 风格）
        Column() {
          Text(this.getDisplayName().charAt(0).toUpperCase())
            .fontSize(32)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
        }
        .width(72)
        .height(72)
        .borderRadius(36)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .linearGradient({
          angle: 135,
          colors: [[$r('app.color.primary'), 0.0], [$r('app.color.accent_blue'), 1.0]]
        })
      }

      // 昵称行：昵称(22px Bold) + VIP pill(10px Bold 金色渐变)
      Row() {
        Text(this.getDisplayName())
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

          // 关注（followNum 已在 UserProfileModels 中定义，对齐 concern_num#31）
          Column() {
            Text(this.profile.followNum.toString())
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

          Text(getResourceString($r('app.string.age_label')) + ': ' + this.getAgeText(this.profile.age))
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
