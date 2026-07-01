import { router } from '@kit.ArkUI';
import { TiebaAPI } from '../../api/TiebaAPI';
import { UserProfileInfo } from '../../model/UserProfileModels';
import { LoadingView } from '../../components/LoadingView';
import { ErrorView } from '../../components/ErrorView';
import { getResourceString } from '../../utils/ResourceUtil';
import { getStatusBarHeight } from '../../utils/StatusBarUtil';
import { getAvatarUrl } from '../../utils/AvatarUtil';

/**
 * 用户主页
 *
 * 对应 HarmonyOS_Migration_Plan.md Phase 3 W8 任务
 * 实现：
 *   - 通过 portrait/userName 调用 /home/get/panel 获取用户资料
 *   - 展示头像、昵称、性别、吧龄、发帖数、粉丝数、超级会员标识
 *   - 关注/取消关注按钮（调用 /c/c/user/{follow|unfollow}）
 *
 * 路由参数（router.pushUrl params）：
 *   - portrait: string  必需，作为 panel API 的 id 参数
 *   - userName: string  可选，portrait 为空时作为 un 参数 fallback
 *   - uid:      number  可选，回填到结果中（panel API 不返回此字段）
 *
 * 已知限制（后续 Phase 处理）：
 *   - isFollowing 默认 false，无服务端字段支撑，仅本地状态
 *   - "TA的发帖"区域为占位，需 get_user_contents API（protobuf，未实现）
 */
@Entry
@Component
struct UserProfilePage {
  /** 路由传入的头像标识，作为 panel API 主查询参数 */
  @State portrait: string = '';
  /** 路由传入的用户名，portrait 为空时作为 fallback */
  @State userName: string = '';
  /** 路由传入的旧版 user_id，仅用于回填到 UserProfileInfo.uid */
  @State uid: number = 0;

  /** 用户资料数据，aboutToAppear 后由 API 填充 */
  @State profile: UserProfileInfo = new UserProfileInfo();
  /** 主资料加载状态 */
  @State isLoading: boolean = false;
  /** 主资料加载错误信息，非空表示加载失败 */
  @State errorMessage: string = '';
  /** 关注/取消关注操作进行中，用于禁用按钮防止重复点击 */
  @State isFollowOpLoading: boolean = false;
  // 状态栏高度（vp），沉浸式避让状态栏，默认 36，aboutToAppear 动态获取
  @State statusBarHeight: number = 36;

  async aboutToAppear() {
    // 获取状态栏高度（沉浸式，P1 重构提取为 StatusBarUtil）
    this.statusBarHeight = await getStatusBarHeight(getContext(this));
    const params = router.getParams() as Record<string, string | number>;
    if (params) {
      const portraitVal = params['portrait'];
      if (typeof portraitVal === 'string') {
        this.portrait = portraitVal;
      }
      const userNameVal = params['userName'];
      if (typeof userNameVal === 'string') {
        this.userName = userNameVal;
      }
      const uidVal = params['uid'];
      if (typeof uidVal === 'number') {
        this.uid = uidVal;
      }
    }
    this.loadProfile().catch((err: Error) => {
      console.error(`[UserProfilePage] loadProfile failed: ${err.message}`);
    });
  }

  /** 拉取用户资料。portrait 优先，否则用 userName fallback */
  async loadProfile(): Promise<void> {
    this.isLoading = true;
    this.errorMessage = '';
    try {
      this.profile = await TiebaAPI.getUserProfile(this.portrait, this.userName, this.uid);
    } catch (err) {
      this.errorMessage = (err as Error).message || getResourceString($r('app.string.user_profile_load_failed'));
    } finally {
      this.isLoading = false;
    }
  }

  /** 切换关注状态。操作成功后立即更新本地 isFollowing，失败则弹出错误 */
  async toggleFollow(): Promise<void> {
    if (this.isFollowOpLoading || this.profile.portrait.length === 0) {
      return;
    }
    this.isFollowOpLoading = true;
    try {
      if (this.profile.isFollowing) {
        await TiebaAPI.unfollowUser(this.profile.portrait);
        this.profile.isFollowing = false;
      } else {
        await TiebaAPI.followUser(this.profile.portrait);
        this.profile.isFollowing = true;
      }
    } catch (err) {
      this.errorMessage = (err as Error).message || getResourceString($r('app.string.follow_operation_failed'));
    } finally {
      this.isFollowOpLoading = false;
    }
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

  build() {
    Column() {
      // 顶部导航栏
      Row() {
        Image($r('app.media.ic_back'))
          .width(24)
          .height(24)
          .fillColor($r('app.color.text_primary'))
          .onClick(() => {
            router.back();
          })

        Text($r('app.string.user_profile_title'))
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .textAlign(TextAlign.Start)
          .margin({ left: 12 })

        Blank()
          .width(24)
      }
      .width('100%')
      .height(56 + this.statusBarHeight)
      .padding({ left: 16, right: 16, top: this.statusBarHeight })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
      .alignItems(VerticalAlign.Center)
      .backgroundColor($r('app.color.background'))

      // 内容区：加载中 / 错误 / 资料卡
      if (this.isLoading && this.profile.userName.length === 0) {
        LoadingView({ message: getResourceString($r('app.string.loading')) })
          .layoutWeight(1)
      } else if (this.errorMessage.length > 0 && this.profile.userName.length === 0) {
        ErrorView({
          message: this.errorMessage,
          onRetryClick: () => this.loadProfile()
        })
          .layoutWeight(1)
      } else {
        Scroll() {
          Column() {
            this.ProfileCard()

            // 错误提示条（关注操作失败时显示，资料已加载成功所以不替换主内容）
            if (this.errorMessage.length > 0) {
              Text(this.errorMessage)
                .fontSize(12)
                .fontColor($r('app.color.error'))
                .backgroundColor($r('app.color.error_bg'))
                .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                .width('100%')
                .margin({ top: 8 })
            }

            this.UserPostsSection()
          }
          .width('100%')
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  ProfileCard() {
    Column() {
      // 头像 + 名称行
      Row() {
        Image(getAvatarUrl(this.profile.portrait, 'm'))
          .width(72)
          .height(72)
          .borderRadius(36)
          .objectFit(ImageFit.Cover)
          .backgroundColor($r('app.color.input_background'))

        Column() {
          Row() {
            Text(this.profile.nickName.length > 0 ? this.profile.nickName : this.profile.userName)
              .fontSize(18)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

            if (this.profile.isVip) {
              Text($r('app.string.vip_badge'))
                .fontSize(11)
                .fontColor($r('app.color.vip_badge_text'))
                .backgroundColor($r('app.color.vip_badge_bg'))
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                .borderRadius(4)
                .margin({ left: 8 })
            }
          }
          .alignItems(VerticalAlign.Center)

          if (this.profile.userName.length > 0 && this.profile.userName !== this.profile.nickName) {
            Text(this.profile.userName)
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ top: 4 })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 12 })
        .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // 统计行：发帖 / 粉丝 / 性别 / 吧龄
      Row() {
        Column() {
          Text(this.profile.postNum.toString())
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text($r('app.string.post_num_label'))
            .fontSize(11)
            .fontColor($r('app.color.text_caption'))
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Center)

        Column() {
          Text(this.profile.fanNum.toString())
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text($r('app.string.fan_num_label'))
            .fontSize(11)
            .fontColor($r('app.color.text_caption'))
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Center)
        .margin({ left: 24 })

        Blank()

        Text(this.getGenderText(this.profile.gender))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))

        Text($r('app.string.age_label') + ': ' + this.getAgeText(this.profile.age))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .margin({ left: 16 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .margin({ top: 20 })

      // 关注/取消关注按钮
      Button(this.profile.isFollowing
        ? $r('app.string.following_button')
        : $r('app.string.follow_button'))
        .width('100%')
        .height(40)
        .fontSize(14)
        .fontColor(this.profile.isFollowing
          ? $r('app.color.text_secondary')
          : Color.White)
        .backgroundColor(this.profile.isFollowing
          ? $r('app.color.input_background')
          : $r('app.color.primary'))
        .borderRadius(8)
        .margin({ top: 16 })
        .enabled(!this.isFollowOpLoading)
        .onClick(() => this.toggleFollow())
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(8)
    .margin({ left: 12, right: 12, top: 12 })
  }

  /** "TA的发帖"占位区，后续 Phase 接入 get_user_contents API */
  @Builder
  UserPostsSection() {
    Column() {
      Text($r('app.string.user_posts_title'))
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')

      Text($r('app.string.user_posts_empty'))
        .fontSize(14)
        .fontColor($r('app.color.text_caption'))
        .margin({ top: 24 })
        .textAlign(TextAlign.Center)
        .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(8)
    .margin({ left: 12, right: 12, top: 12 })
  }
}
