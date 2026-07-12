import { AppStorageV2 } from '@kit.ArkUI';
import { HdsNavDestination, ScrollEffectType, hdsMaterial } from '@kit.UIDesignKit';
import { TiebaAPI } from '../../api/TiebaAPI';
import { ImageLoadTypeState, IsWifiState, SafeBottomState } from '../../model/AppStorageV2Models';
import { UserProfileInfo } from '../../model/UserProfileModels';
import { ThreadInfo } from '../../model/ForumModels';
import { ThreadCard } from '../../components/ThreadCard';
import { LoadingView } from '../../components/LoadingView';
import { ErrorView } from '../../components/ErrorView';
import { getResourceString } from '../../utils/ResourceUtil';
import { getAvatarUrl } from '../../utils/AvatarUtil';
import { CommonDataSource } from '../../utils/CommonDataSource';
import { getAvatarImageUrl } from '../../utils/ImageLoadUtil';
import { connectTheme, ThemeState } from '../../theme/ThemeManager';
import { VibratorUtil } from '../../utils/VibratorUtil';
import { RouterUtil, ThreadNavParams, UserProfileNavParams, FollowsNavParams } from '../../utils/RouterUtil';

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
 *   - "TA的发帖"区域为占位，需 get_user_contents API（protobuf，未实现）
 */
// #165 [A4-S5] Navigation 路由表 @Builder：供 router_map.json 的 buildFunction 引用
@Builder
export function UserProfilePageBuilder() {
  UserProfilePage()
}

@ComponentV2
export struct UserProfilePage {
  /** 路由传入的头像标识，作为 panel API 主查询参数 */
  @Local portrait: string = '';
  /** 路由传入的用户名，portrait 为空时作为 fallback */
  @Local userName: string = '';
  /** 路由传入的旧版 user_id，仅用于回填到 UserProfileInfo.uid */
  @Local uid: number = 0;

  /** 用户资料数据，aboutToAppear 后由 API 填充 */
  @Local profile: UserProfileInfo = new UserProfileInfo();
  /** 主资料加载状态 */
  @Local isLoading: boolean = false;
  /** 主资料加载错误信息，非空表示加载失败 */
  @Local errorMessage: string = '';
  /** 关注/取消关注操作进行中，用于禁用按钮防止重复点击 */
  @Local isFollowOpLoading: boolean = false;
  // #165 滚动器，绑定到 HdsNavDestination.bindToScrollable 实现标题栏滚动动态模糊
  private scroller: Scroller = new Scroller();
  // #80 图片加载策略：通过 AppStorage 共享，SettingsPage 修改后自动响应
  @Local imageLoadTypeState: ImageLoadTypeState = AppStorageV2.connect(ImageLoadTypeState, 'imageLoadType', () => new ImageLoadTypeState())!;
  @Local isWifiState: IsWifiState = AppStorageV2.connect(IsWifiState, 'isWifi', () => new IsWifiState())!;
  @Local themeState: ThemeState = connectTheme();

  // ===== #75 用户发帖列表状态 =====
  /** 用户发帖列表数据源（LazyForEach + CommonDataSource，长列表性能优化） */
  postsDataSource: CommonDataSource<ThreadInfo> = new CommonDataSource<ThreadInfo>();
  /** 发帖列表加载中（首次或刷新） */
  @Local postsLoading: boolean = false;
  /** 发帖列表加载更多中（区别于首次，UI 显示底部加载条） */
  @Local postsLoadingMore: boolean = false;
  /** 发帖列表是否有更多 */
  @Local postsHasMore: boolean = true;
  /** 发帖列表当前页码（从 1 开始） */
  @Local postsPn: number = 1;
  /** 发帖列表错误信息，非空表示加载失败 */
  @Local postsError: string = '';
  /** 每页条数，对齐 aiotieba rn 默认 20 */
  private readonly POSTS_PAGE_SIZE: number = 20;

  async aboutToAppear() {
    // #165 路由迁移：router.getParams() → NavPathStack.getParamByName()
    // SDK 返回 Array<unknown>，ArkTS 不支持 unknown，用 as Object[] 断言
    const paramsStack: Object[] = RouterUtil.getStack().getParamByName(RouterUtil.ROUTE_USER_PROFILE_PAGE) as Object[];
    if (paramsStack && paramsStack.length > 0) {
      const params = paramsStack[paramsStack.length - 1] as UserProfileNavParams;
      if (params) {
        this.portrait = params.portrait;
        this.userName = params.userName;
        this.uid = params.uid;
      }
    }
    this.loadProfile().catch((err: Error) => {
      console.error(`[UserProfilePage] loadProfile failed: ${err.message}`);
    });
    // #75 资料加载完成后异步加载发帖列表（不阻塞主资料渲染）
    this.loadUserPosts(true).catch((err: Error) => {
      console.error(`[UserProfilePage] loadUserPosts failed: ${err.message}`);
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
      console.error(`[DBG-Prof] loadProfile: FAILED, msg=${(err as Error).message}, stack=${(err as Error).stack}`);
    } finally {
      this.isLoading = false;
    }
  }

  /**
   * #75 加载用户发帖列表
   * @param isRefresh true=首次/下拉刷新（重置 pn=1，清空列表），false=加载更多（pn+1）
   */
  async loadUserPosts(isRefresh: boolean): Promise<void> {
    // 未传入 uid 时无法查询（panel API 不返回 uid 字段）
    if (this.uid <= 0) {
      console.warn(`[DBG-Prof] loadUserPosts: uid<=0, skip (uid=${this.uid})`);
      this.postsError = '';
      this.postsHasMore = false;
      return;
    }
    // 加载更多时若已经在加载或已无更多，跳过
    if (!isRefresh) {
      if (this.postsLoadingMore || !this.postsHasMore) {
        console.warn(`[DBG-Prof] loadUserPosts: skip loadMore, postsLoadingMore=${this.postsLoadingMore}, postsHasMore=${this.postsHasMore}`);
        return;
      }
    }
    // 设置加载状态
    if (isRefresh) {
      this.postsLoading = true;
      this.postsError = '';
    } else {
      this.postsLoadingMore = true;
    }
    const targetPn: number = isRefresh ? 1 : this.postsPn + 1;
    try {
      const result = await TiebaAPI.getUserPosts(this.uid, targetPn, this.POSTS_PAGE_SIZE);
      if (isRefresh) {
        this.postsDataSource.setData(result.threadList);
      } else {
        // 加载更多：追加到列表末尾（增量通知，避免全量 reload）
        this.postsDataSource.appendData(result.threadList);
      }
      this.postsPn = targetPn;
      this.postsHasMore = result.hasMore;
    } catch (err) {
      const errObj: Error = err as Error;
      this.postsError = errObj.message || getResourceString($r('app.string.user_posts_load_failed'));
      console.error(`[DBG-Prof] loadUserPosts: FAILED, msg=${errObj.message}, stack=${errObj.stack}`);
    } finally {
      if (isRefresh) {
        this.postsLoading = false;
      } else {
        this.postsLoadingMore = false;
      }
    }
  }

  /** #75 跳转到帖子详情页 */
  navigateToThread(tid: number): void {
    if (tid <= 0) {
      console.warn(`[UserProfilePage] invalid tid: ${tid}, skip navigation`);
      return;
    }
    // #163 路由迁移：router.pushUrl → RouterUtil.push
    RouterUtil.push(RouterUtil.ROUTE_THREAD_PAGE, new ThreadNavParams(tid));
  }

  /**
   * 跳转到关注/粉丝列表页
   * @param initialTab 0=关注（默认）/ 1=粉丝
   */
  navigateToFollows(initialTab: number = 0): void {
    // #86 uid=0 时用 tiebaUid 兜底，仍无效时 toast 提示
    const userId: number = this.profile.uid > 0 ? this.profile.uid : this.profile.tiebaUid;
    if (userId <= 0) {
      this.getUIContext().getPromptAction().showToast({
        message: getResourceString($r('app.string.user_id_invalid'))
      });
      return;
    }
    // #165 路由迁移：router.pushUrl → RouterUtil.push
    RouterUtil.push(RouterUtil.ROUTE_FOLLOWS_PAGE,
      new FollowsNavParams(userId,
        this.profile.nickName.length > 0 ? this.profile.nickName : this.profile.userName,
        initialTab));
  }

  /** 切换关注状态。操作成功后立即更新本地 isFollowing，失败则弹出错误 */
  async toggleFollow(): Promise<void> {
    if (this.isFollowOpLoading || this.profile.portrait.length === 0) {
      return;
    }
    this.isFollowOpLoading = true;
    // #121 触感反馈：关注/取关用户属于强调交互，触发重震动
    VibratorUtil.heavy();
    try {
      if (this.profile.isFollowing) {
        await TiebaAPI.unfollowUser(this.profile.portrait);
      } else {
        await TiebaAPI.followUser(this.profile.portrait);
      }
      // #86 重新赋值整个 profile 实例触发 @Local 变更，确保 ProfileCard @Builder 立即刷新按钮文案
      // UserProfileInfo 已 @ObservedV2 + @Trace，直接改字段理论上能刷新，但重新赋值整个实例更可靠
      const newProfile = new UserProfileInfo(this.profile);
      newProfile.isFollowing = !this.profile.isFollowing;
      this.profile = newProfile;
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
    // #165 [A4-S5] HdsNavDestination 包装：替代 @Entry + router，纳入 HdsNavigation 路由栈
    // 顶部栏简单（返回+标题+占位），用 titleBar 配置 + scrollEffectOpts + systemMaterialEffect
    HdsNavDestination() {
      Column() {
        // 内容区：加载中 / 错误 / 列表（List + LazyForEach 长列表优化）
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
          List({ space: 0, scroller: this.scroller }) {
            // ProfileCard 作为首项
            ListItem() {
              this.ProfileCard()
            }
            .padding(0)

            // 错误提示条（关注操作失败时显示，资料已加载成功所以不替换主内容）
            if (this.errorMessage.length > 0) {
              ListItem() {
                Text(this.errorMessage)
                  .fontSize(12)
                  .fontColor($r('app.color.error'))
                  .backgroundColor($r('app.color.error_bg'))
                  .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                  .width('100%')
                  .margin({ top: 8 })
              }
              .padding(0)
            }

            // "TA的发帖"区域（标题 + 列表 + 加载更多，作为 List 子项展开）
            this.UserPostsSection()
          }
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
          .cachedCount(5)
          // #104 底部色差根因：List bottom padding safeBottom+16 会在底部留出纯色浅灰区域，
          // 与窗口默认白色背景形成色差。去掉 bottom padding，与 HomePage/ForumPage 一致，
          // 内容直接延伸到手势条区域，手势条半透明覆盖在最后一条内容上。
          .padding({ left: 16, right: 16 })
          .backgroundColor($r('app.color.page_background'))
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.page_background'))
    }
    .titleBar({
      content: { title: { mainTitle: $r('app.string.user_profile_title') } },
      style: {
        scrollEffectOpts: { enableScrollEffect: true, scrollEffectType: ScrollEffectType.GRADIENT_BLUR },
        systemMaterialEffect: { materialType: hdsMaterial.MaterialType.ADAPTIVE, materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE }
      },
      // 避让状态栏：setWindowLayoutFullScreen(true) 全屏模式下 titleBar 默认不避让状态栏，
      // 需显式设置 avoidLayoutSafeArea: true 让 titleBar 内容（标题/按钮）避让状态栏
      // 保留 systemMaterialEffect 沉浸光感模糊效果（按钮浮在模糊层上）
      avoidLayoutSafeArea: true
    })
    .bindToScrollable([this.scroller])
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  ProfileCard() {
    Column() {
      // 头像 + 名称行
      Row() {
        // #80 接入图片加载策略：shouldLoad=false 时返回空串，Image 组件显示 alt 占位图
        Image(getAvatarImageUrl(getAvatarUrl(this.profile.portrait, 'm'), this.imageLoadTypeState.value, this.isWifiState.value))
          .width(72)
          .height(72)
          .borderRadius(36)
          .objectFit(ImageFit.Cover)
          .backgroundColor($r('app.color.input_background'))
          .alt($r('app.media.startIcon'))
          // A5 图片优化：头像同步加载
          .syncLoad(true)
          // A5 图片优化：头像低质量插值
          .interpolation(ImageInterpolation.Low)
          // A5 图片优化：头像加载失败静默
          .onError(() => { /* 头像加载失败静默处理 */ })
          // #92 HitTestMode.Transparent：让触控穿透到父 List，避免 fling 期间碰到图片导致触控丢失
          .hitTestBehavior(HitTestMode.Transparent)

        Column() {
          Row() {
            Text(this.profile.nickName.length > 0 ? this.profile.nickName : this.profile.userName)
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
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

      // 统计行：回复 / 关注 / 粉丝 / 性别 / 吧龄
      // post_num 字段对齐 Android 原版 title_profile_posts_tab="回复 %s"，isThread=false 表示含回复
      Row() {
        // 回复数（post_num 字段，包括主题帖+回复）
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

        // 关注数（点击跳转 FollowsPage 关注 Tab）
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
        .hitTestBehavior(HitTestMode.Block)
        .onClick(() => this.navigateToFollows(0))

        // 粉丝数（点击跳转 FollowsPage 粉丝 Tab）
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
        .hitTestBehavior(HitTestMode.Block)
        .onClick(() => this.navigateToFollows(1))

        Blank()

        Text(this.getGenderText(this.profile.gender))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))

        Text(getResourceString($r('app.string.age_label')) + ': ' + this.getAgeText(this.profile.age))
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
          : this.themeState.primary)
        .borderRadius(10)
        .margin({ top: 16 })
        .enabled(!this.isFollowOpLoading)
        .onClick(() => this.toggleFollow())
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(10)
    .margin({ top: 16 })
  }

  /**
   * #75 "TA的发帖"区域
   * 展示用户发帖历史（每条 PostInfoList 转为 ThreadInfo 卡片）
   * 状态分支：加载中 / 错误 / 空列表 / 列表+加载更多
   * 注意：本 @Builder 的内容会被展开到外层 List 内，因此直接产出 ListItem / LazyForEach
   */
  @Builder
  UserPostsSection() {
    // 区域标题
    ListItem() {
      Text($r('app.string.user_posts_title'))
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .padding({ top: 16, bottom: 8 })
    }
    .padding(0)

    // 首次加载中
    if (this.postsLoading) {
      ListItem() {
        LoadingView({ message: getResourceString($r('app.string.loading')) })
          .width('100%')
          .height(120)
      }
      .padding(0)
    }
    // 错误提示 + 重试
    else if (this.postsError.length > 0 && this.postsDataSource.totalCount() === 0) {
      ListItem() {
        ErrorView({
          message: this.postsError,
          onRetryClick: () => this.loadUserPosts(true)
        })
          .width('100%')
          .height(120)
      }
      .padding(0)
    }
    // 空列表（uid 无效或返回空）
    else if (this.postsDataSource.totalCount() === 0) {
      ListItem() {
        Text($r('app.string.user_posts_empty'))
          .fontSize(14)
          .fontColor($r('app.color.text_caption'))
          .margin({ top: 24, bottom: 24 })
          .textAlign(TextAlign.Center)
          .width('100%')
      }
      .padding(0)
    }
    // 列表 + 加载更多
    else {
      LazyForEach(this.postsDataSource, (thread: ThreadInfo) => {
        ListItem() {
          Column() {
            ThreadCard({
              thread: thread,
              imageLoadType: this.imageLoadTypeState.value,
              isWifi: this.isWifiState.value,
              onCardClick: () => this.navigateToThread(thread.tid)
            })
          }
          .margin({ top: 8 })
        }
        .padding(0)
      }, (thread: ThreadInfo) => `${thread.tid}`)

      // 加载更多 / 已加载全部
      ListItem() {
        if (this.postsHasMore) {
          Row() {
            Text(this.postsLoadingMore
              ? $r('app.string.loading_more')
              : $r('app.string.click_to_load_more'))
              .fontSize(14)
              .fontColor(this.themeState.primary)
          }
          .width('100%')
          .height(48)
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
          .hitTestBehavior(this.postsLoadingMore ? HitTestMode.None : HitTestMode.Block)
          .onClick(() => {
            this.loadUserPosts(false).catch((err: Error) => {
              console.error(`[UserProfilePage] loadMore failed: ${err.message}`);
            });
          })
        } else {
          // 已加载全部
          Text($r('app.string.no_more_posts'))
            .fontSize(12)
            .fontColor($r('app.color.text_caption'))
            .margin({ top: 16, bottom: 16 })
            .textAlign(TextAlign.Center)
            .width('100%')
        }
      }
      .padding(0)

      // 加载更多失败提示（非阻塞，列表已展示）
      if (this.postsError.length > 0 && this.postsDataSource.totalCount() > 0) {
        ListItem() {
          Text(this.postsError)
            .fontSize(12)
            .fontColor($r('app.color.error'))
            .textAlign(TextAlign.Center)
            .width('100%')
            .margin({ top: 8, bottom: 16 })
        }
        .padding(0)
      }
    }
  }
}
