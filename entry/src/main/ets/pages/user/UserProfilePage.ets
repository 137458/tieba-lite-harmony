import { router } from '@kit.ArkUI';
import { TiebaAPI } from '../../api/TiebaAPI';
import { UserProfileInfo } from '../../model/UserProfileModels';
import { ThreadInfo } from '../../model/ForumModels';
import { ThreadCard } from '../../components/ThreadCard';
import { LoadingView } from '../../components/LoadingView';
import { ErrorView } from '../../components/ErrorView';
import { getResourceString } from '../../utils/ResourceUtil';
import { getStatusBarHeight } from '../../utils/StatusBarUtil';
import { getAvatarUrl } from '../../utils/AvatarUtil';
import { CommonDataSource } from '../../utils/CommonDataSource';
import { getAvatarImageUrl } from '../../utils/ImageLoadUtil';

/** UserProfilePage 路由参数 */
interface UserProfilePageParams {
  portrait?: string;
  userName?: string;
  uid?: number;
}

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
  // #80 图片加载策略：通过 AppStorage 共享，SettingsPage 修改后自动响应
  @StorageProp('imageLoadType') imageLoadType: number = 0;
  @StorageProp('isWifi') isWifi: boolean = false;
  // 底部系统手势条安全高度（vp），由 EntryAbility 写入 AppStorage，
  // 用于 List padding bottom 避让系统手势条，避免底部内容被遮挡
  @StorageProp('safeBottom') safeBottom: number = 0;

  // ===== #75 用户发帖列表状态 =====
  /** 用户发帖列表数据源（LazyForEach + CommonDataSource，长列表性能优化） */
  postsDataSource: CommonDataSource<ThreadInfo> = new CommonDataSource<ThreadInfo>();
  /** 发帖列表加载中（首次或刷新） */
  @State postsLoading: boolean = false;
  /** 发帖列表加载更多中（区别于首次，UI 显示底部加载条） */
  @State postsLoadingMore: boolean = false;
  /** 发帖列表是否有更多 */
  @State postsHasMore: boolean = true;
  /** 发帖列表当前页码（从 1 开始） */
  @State postsPn: number = 1;
  /** 发帖列表错误信息，非空表示加载失败 */
  @State postsError: string = '';
  /** 每页条数，对齐 aiotieba rn 默认 20 */
  private readonly POSTS_PAGE_SIZE: number = 20;

  async aboutToAppear() {
    // 获取状态栏高度（沉浸式，P1 重构提取为 StatusBarUtil），失败不阻塞页面加载，保留默认值 36
    try {
      this.statusBarHeight = await getStatusBarHeight(getContext(this));
    } catch (err) {
      console.error(`[UserProfilePage] getStatusBarHeight failed: ${(err as Error).message}`);
    }
    const params = router.getParams() as UserProfilePageParams;
    if (params) {
      const portraitVal = params.portrait;
      if (typeof portraitVal === 'string') {
        this.portrait = portraitVal;
      }
      const userNameVal = params.userName;
      if (typeof userNameVal === 'string') {
        this.userName = userNameVal;
      }
      const uidVal = params.uid;
      if (typeof uidVal === 'number') {
        this.uid = uidVal;
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
    console.info(`[DBG-Prof] loadProfile: enter, portrait=${this.portrait}, userName=${this.userName}, uid=${this.uid}`);
    this.isLoading = true;
    this.errorMessage = '';
    try {
      this.profile = await TiebaAPI.getUserProfile(this.portrait, this.userName, this.uid);
      console.info(`[DBG-Prof] loadProfile: success, uid=${this.profile.uid}, nickName=${this.profile.nickName}, portraitLen=${this.profile.portrait.length}, userNameLen=${this.profile.userName.length}, postNum=${this.profile.postNum}`);
    } catch (err) {
      this.errorMessage = (err as Error).message || getResourceString($r('app.string.user_profile_load_failed'));
      console.error(`[DBG-Prof] loadProfile: FAILED, msg=${(err as Error).message}, stack=${(err as Error).stack}`);
    } finally {
      this.isLoading = false;
      console.info(`[DBG-Prof] loadProfile: finally, isLoading=${this.isLoading}, errorMessage=${this.errorMessage}`);
    }
  }

  /**
   * #75 加载用户发帖列表
   * @param isRefresh true=首次/下拉刷新（重置 pn=1，清空列表），false=加载更多（pn+1）
   *
   * [DBG-Prof] #108 调试：loadUserPosts 入口/出口/分支/错误捕获均打日志，
   * 用于定位"加载更多无用"根因。定位后回滚。
   */
  async loadUserPosts(isRefresh: boolean): Promise<void> {
    console.info(`[DBG-Prof] loadUserPosts: enter, isRefresh=${isRefresh}, uid=${this.uid}, postsPn=${this.postsPn}, postsHasMore=${this.postsHasMore}, postsLoadingMore=${this.postsLoadingMore}`);
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
    console.info(`[DBG-Prof] loadUserPosts: calling getUserPosts, uid=${this.uid}, targetPn=${targetPn}, rn=${this.POSTS_PAGE_SIZE}`);
    try {
      const result = await TiebaAPI.getUserPosts(this.uid, targetPn, this.POSTS_PAGE_SIZE);
      console.info(`[DBG-Prof] loadUserPosts: got result, threadListLen=${result.threadList.length}, hasMore=${result.hasMore}, hidePost=${result.hidePost}`);
      if (isRefresh) {
        this.postsDataSource.setData(result.threadList);
      } else {
        // 加载更多：追加到列表末尾（增量通知，避免全量 reload）
        this.postsDataSource.appendData(result.threadList);
      }
      this.postsPn = targetPn;
      this.postsHasMore = result.hasMore;
      console.info(`[DBG-Prof] loadUserPosts: after update, postsPn=${this.postsPn}, postsHasMore=${this.postsHasMore}, totalCount=${this.postsDataSource.totalCount()}`);
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
      console.info(`[DBG-Prof] loadUserPosts: finally, postsLoading=${this.postsLoading}, postsLoadingMore=${this.postsLoadingMore}`);
    }
  }

  /** #75 跳转到帖子详情页 */
  navigateToThread(tid: number): void {
    if (tid <= 0) {
      console.warn(`[UserProfilePage] invalid tid: ${tid}, skip navigation`);
      return;
    }
    router.pushUrl({
      url: 'pages/thread/ThreadPage',
      params: { tid: tid.toString() }
    }).catch((err: Error) => {
      console.error(`[UserProfilePage] navigate to thread failed: ${err.message}`);
    });
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
    router.pushUrl({
      url: 'pages/user/FollowsPage',
      params: {
        userId: userId,
        userName: this.profile.nickName.length > 0 ? this.profile.nickName : this.profile.userName,
        initialTab: initialTab
      }
    }).catch((err: Error) => {
      console.error(`[UserProfilePage] navigate to FollowsPage failed: ${err.message}`);
    });
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
      } else {
        await TiebaAPI.followUser(this.profile.portrait);
      }
      // #86 重新赋值整个 profile 实例触发 @State 变更，确保 ProfileCard @Builder 立即刷新按钮文案
      // UserProfileInfo 已 @Observed，直接改字段理论上能刷新，但重新赋值整个实例更可靠
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
    Column() {
      // 顶部导航栏（对齐原型 detail-nav，44px + 状态栏，返回按钮 primary 蓝）
      Row() {
        Image($r('app.media.ic_back'))
          .width(20)
          .height(20)
          .fillColor($r('app.color.primary'))
          // A5 图片优化：SVG 图标同步加载
          .syncLoad(true)
          // A5 图片优化：SVG 图标低质量插值
          .interpolation(ImageInterpolation.Low)
          .onClick(() => {
            router.back();
          })

        Text($r('app.string.user_profile_title'))
          .fontSize(17)
          .fontWeight(600)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .margin({ left: 8, right: 8 })

        // 右侧占位，保持标题居中
        Blank()
          .width(20)
          .height(20)
      }
      .width('100%')
      .height(44 + this.statusBarHeight)
      .padding({ left: 16, right: 16, top: this.statusBarHeight })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
      .alignItems(VerticalAlign.Center)
      .backgroundColor($r('app.color.page_background'))

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
        List({ space: 0 }) {
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
        // #108 修复回归：用户明确要求"不要在系统底部手势导航条下面加任何遮罩"
        // 去掉 safeBottom padding 避让（用户接受内容被手势条遮挡），保留 16 正常 padding
        .padding({ left: 16, right: 16, bottom: 16 })
        .backgroundColor($r('app.color.page_background'))
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
        // #80 接入图片加载策略：shouldLoad=false 时返回空串，Image 组件显示 alt 占位图
        Image(getAvatarImageUrl(getAvatarUrl(this.profile.portrait, 'm'), this.imageLoadType, this.isWifi))
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

      // 统计行：发帖 / 关注 / 粉丝 / 性别 / 吧龄
      Row() {
        // 发帖数（点击跳转发帖列表，已在 #75 实现，这里不做点击）
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
          : $r('app.color.primary'))
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
              onCardClick: () => this.navigateToThread(thread.tid)
            })
          }
          .margin({ top: 8 })
        }
        .padding(0)
      }, (thread: ThreadInfo, index: number) => `${thread.tid}_${index}`)

      // 加载更多 / 已加载全部
      ListItem() {
        if (this.postsHasMore) {
          Row() {
            Text(this.postsLoadingMore
              ? $r('app.string.loading_more')
              : $r('app.string.click_to_load_more'))
              .fontSize(14)
              .fontColor($r('app.color.primary'))
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
