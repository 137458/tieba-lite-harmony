import { router, promptAction } from '@kit.ArkUI';
import { TiebaAPI } from '../../api/TiebaAPI';
import { FollowUserInfo, FollowsPageInfo, FansPageInfo } from '../../model/UserProfileModels';
import { getResourceString } from '../../utils/ResourceUtil';
import { getStatusBarHeight } from '../../utils/StatusBarUtil';
import { getAvatarUrl } from '../../utils/AvatarUtil';

/**
 * 关注/粉丝列表页
 *
 * 路由参数（router.pushUrl params）：
 *   - userId:     number  必需，目标用户 uid
 *   - userName:   string  可选，用于标题显示
 *   - initialTab: number  可选，0=关注（默认）/ 1=粉丝
 *
 * 实现：
 *   - 顶部 Tabs 切换关注/粉丝
 *   - List + LazyForEach 渲染用户项（头像 + 昵称 + 用户名）
 *   - 分页加载：onReachEnd 触发，pn 递增
 *   - 点击用户项跳转 UserProfilePage
 *   - 复用 TiebaAPI.getFollows / TiebaAPI.getFans（已封装）
 */
@Entry
@Component
struct FollowsPage {
  /** 目标用户 uid */
  @State userId: number = 0;
  /** 目标用户名（标题显示） */
  @State userName: string = '';
  /** 初始 Tab：0=关注，1=粉丝 */
  @State initialTab: number = 0;
  /** 状态栏高度 */
  @State statusBarHeight: number = 36;
  /** 当前 Tab 索引（0=关注，1=粉丝） */
  @State currentTab: number = 0;

  // 关注列表状态
  @State followsList: FollowUserInfo[] = [];
  @State followsLoading: boolean = false;
  @State followsLoadingMore: boolean = false;
  @State followsHasMore: boolean = false;
  @State followsPn: number = 1;
  @State followsTotalCount: number = 0;
  @State followsError: string = '';

  // 粉丝列表状态
  @State fansList: FollowUserInfo[] = [];
  @State fansLoading: boolean = false;
  @State fansLoadingMore: boolean = false;
  @State fansHasMore: boolean = false;
  @State fansPn: number = 1;
  @State fansTotalCount: number = 0;
  @State fansError: string = '';

  /** Tabs 控制器 */
  private tabsController: TabsController = new TabsController();

  async aboutToAppear(): Promise<void> {
    this.statusBarHeight = await getStatusBarHeight(getContext(this));

    const params = router.getParams() as Record<string, Object>;
    if (params !== null && params !== undefined) {
      const uidVal = params['userId'];
      if (typeof uidVal === 'number') {
        this.userId = uidVal as number;
      }
      const nameVal = params['userName'];
      if (typeof nameVal === 'string') {
        this.userName = nameVal as string;
      }
      const tabVal = params['initialTab'];
      if (typeof tabVal === 'number') {
        this.initialTab = tabVal as number;
        this.currentTab = this.initialTab;
      }
    }

    // 并发加载初始数据
    this.loadFollows(true);
    this.loadFans(true);
  }

  /** 顶部标题 */
  buildTitle(): string {
    if (this.userName.length > 0) {
      return getResourceString($r('app.string.follows_page_title_with_name', this.userName));
    }
    return getResourceString($r('app.string.follows_page_title'));
  }

  /** 加载关注列表 */
  async loadFollows(isRefresh: boolean): Promise<void> {
    if (this.userId <= 0) {
      this.followsError = getResourceString($r('app.string.follows_invalid_uid'));
      return;
    }
    if (isRefresh) {
      if (this.followsLoading) {
        return;
      }
      this.followsLoading = true;
      this.followsError = '';
      this.followsPn = 1;
    } else {
      if (this.followsLoadingMore || !this.followsHasMore) {
        return;
      }
      this.followsLoadingMore = true;
    }
    try {
      const result = await TiebaAPI.getFollows(this.userId, this.followsPn);
      if (isRefresh) {
        this.followsList = result.list;
      } else {
        this.followsList = this.followsList.concat(result.list);
      }
      this.followsHasMore = result.pageInfo.hasMore;
      this.followsTotalCount = result.pageInfo.totalCount;
      this.followsPn = this.followsPn + 1;
    } catch (err) {
      const msg: string = (err as Error).message || '';
      if (isRefresh) {
        this.followsError = msg;
      } else {
        promptAction.showToast({ message: msg });
      }
    } finally {
      this.followsLoading = false;
      this.followsLoadingMore = false;
    }
  }

  /** 加载粉丝列表 */
  async loadFans(isRefresh: boolean): Promise<void> {
    if (this.userId <= 0) {
      this.fansError = getResourceString($r('app.string.follows_invalid_uid'));
      return;
    }
    if (isRefresh) {
      if (this.fansLoading) {
        return;
      }
      this.fansLoading = true;
      this.fansError = '';
      this.fansPn = 1;
    } else {
      if (this.fansLoadingMore || !this.fansHasMore) {
        return;
      }
      this.fansLoadingMore = true;
    }
    try {
      const result = await TiebaAPI.getFans(this.userId, this.fansPn);
      if (isRefresh) {
        this.fansList = result.list;
      } else {
        this.fansList = this.fansList.concat(result.list);
      }
      this.fansHasMore = result.pageInfo.hasMore;
      this.fansTotalCount = result.pageInfo.totalCount;
      this.fansPn = this.fansPn + 1;
    } catch (err) {
      const msg: string = (err as Error).message || '';
      if (isRefresh) {
        this.fansError = msg;
      } else {
        promptAction.showToast({ message: msg });
      }
    } finally {
      this.fansLoading = false;
      this.fansLoadingMore = false;
    }
  }

  /** 跳转用户主页 */
  navigateToUserProfile(user: FollowUserInfo): void {
    if (user.userId <= 0) {
      return;
    }
    router.pushUrl({
      url: 'pages/user/UserProfilePage',
      params: {
        uid: user.userId,
        portrait: user.portrait,
        userName: user.userName
      }
    }).catch((err: Error) => {
      console.error(`[FollowsPage] navigate to user profile failed: ${err.message}`);
    });
  }

  /** Tab 切换 */
  onTabChange(index: number): void {
    this.currentTab = index;
  }

  @Builder
  UserItem(user: FollowUserInfo) {
    Row() {
      Image(getAvatarUrl(user.portrait, 's'))
        .width(44)
        .height(44)
        .borderRadius(22)
        .objectFit(ImageFit.Cover)
        .backgroundColor($r('app.color.input_background'))
        .alt($r('app.media.startIcon'))

      Column() {
        Text(user.nickName.length > 0 ? user.nickName : user.userName)
          .fontSize(15)
          .fontWeight(600)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (user.userName.length > 0 && user.nickName !== user.userName) {
          Text(getResourceString($r('app.string.follows_username_label', user.userName)))
            .fontSize(12)
            .fontColor($r('app.color.text_caption'))
            .margin({ top: 2 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 })
      .layoutWeight(1)

      // 右侧箭头
      Image($r('app.media.ic_chevron_right'))
        .width(16)
        .height(16)
        .fillColor($r('app.color.text_caption'))
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .alignItems(VerticalAlign.Center)
    .hitTestBehavior(HitTestMode.Block)
    .onClick(() => this.navigateToUserProfile(user))
  }

  @Builder
  FollowsTab() {
    if (this.followsLoading && this.followsList.length === 0) {
      Column() {
        LoadingProgress()
          .width(32)
          .height(32)
          .color($r('app.color.primary'))
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    } else if (this.followsError.length > 0 && this.followsList.length === 0) {
      Column() {
        Text(this.followsError)
          .fontSize(14)
          .fontColor($r('app.color.text_caption'))
        Text(getResourceString($r('app.string.retry')))
          .fontSize(14)
          .fontColor($r('app.color.primary'))
          .margin({ top: 12 })
          .hitTestBehavior(HitTestMode.Block)
          .onClick(() => this.loadFollows(true))
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    } else if (this.followsList.length === 0) {
      Column() {
        Text(getResourceString($r('app.string.follows_empty')))
          .fontSize(14)
          .fontColor($r('app.color.text_caption'))
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    } else {
      List({ space: 0 }) {
        ForEach(this.followsList, (user: FollowUserInfo, idx: number) => {
          ListItem() {
            this.UserItem(user)
          }
        }, (user: FollowUserInfo, idx: number) => `follow_${user.userId}_${idx}`)

        // 加载更多 / 已加载完毕提示
        ListItem() {
          if (this.followsLoadingMore) {
            Row() {
              LoadingProgress().width(20).height(20).color($r('app.color.text_caption'))
              Text(getResourceString($r('app.string.loading_more')))
                .fontSize(12)
                .fontColor($r('app.color.text_caption'))
                .margin({ left: 8 })
            }
            .width('100%')
            .height(48)
            .justifyContent(FlexAlign.Center)
          } else if (!this.followsHasMore) {
            Text(getResourceString($r('app.string.no_more_data')))
              .fontSize(12)
              .fontColor($r('app.color.text_caption'))
              .width('100%')
              .height(48)
              .textAlign(TextAlign.Center)
          } else {
            Row() {
              Text(getResourceString($r('app.string.click_to_load_more')))
                .fontSize(13)
                .fontColor($r('app.color.primary'))
            }
            .width('100%')
            .height(48)
            .justifyContent(FlexAlign.Center)
            .hitTestBehavior(HitTestMode.Block)
            .onClick(() => this.loadFollows(false))
          }
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.page_background'))
      .onReachEnd(() => this.loadFollows(false))
    }
  }

  @Builder
  FansTab() {
    if (this.fansLoading && this.fansList.length === 0) {
      Column() {
        LoadingProgress()
          .width(32)
          .height(32)
          .color($r('app.color.primary'))
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    } else if (this.fansError.length > 0 && this.fansList.length === 0) {
      Column() {
        Text(this.fansError)
          .fontSize(14)
          .fontColor($r('app.color.text_caption'))
        Text(getResourceString($r('app.string.retry')))
          .fontSize(14)
          .fontColor($r('app.color.primary'))
          .margin({ top: 12 })
          .hitTestBehavior(HitTestMode.Block)
          .onClick(() => this.loadFans(true))
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    } else if (this.fansList.length === 0) {
      Column() {
        Text(getResourceString($r('app.string.fans_empty')))
          .fontSize(14)
          .fontColor($r('app.color.text_caption'))
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    } else {
      List({ space: 0 }) {
        ForEach(this.fansList, (user: FollowUserInfo, idx: number) => {
          ListItem() {
            this.UserItem(user)
          }
        }, (user: FollowUserInfo, idx: number) => `fan_${user.userId}_${idx}`)

        ListItem() {
          if (this.fansLoadingMore) {
            Row() {
              LoadingProgress().width(20).height(20).color($r('app.color.text_caption'))
              Text(getResourceString($r('app.string.loading_more')))
                .fontSize(12)
                .fontColor($r('app.color.text_caption'))
                .margin({ left: 8 })
            }
            .width('100%')
            .height(48)
            .justifyContent(FlexAlign.Center)
          } else if (!this.fansHasMore) {
            Text(getResourceString($r('app.string.no_more_data')))
              .fontSize(12)
              .fontColor($r('app.color.text_caption'))
              .width('100%')
              .height(48)
              .textAlign(TextAlign.Center)
          } else {
            Row() {
              Text(getResourceString($r('app.string.click_to_load_more')))
                .fontSize(13)
                .fontColor($r('app.color.primary'))
            }
            .width('100%')
            .height(48)
            .justifyContent(FlexAlign.Center)
            .hitTestBehavior(HitTestMode.Block)
            .onClick(() => this.loadFans(false))
          }
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.page_background'))
      .onReachEnd(() => this.loadFans(false))
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
          .hitTestBehavior(HitTestMode.Block)
          .onClick(() => router.back())

        Text(this.buildTitle())
          .fontSize(17)
          .fontWeight(600)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .margin({ left: 8, right: 32 })

        // 占位，保持标题居中
        Row().width(24).height(24)
      }
      .width('100%')
      .height(44 + this.statusBarHeight)
      .padding({ left: 16, right: 16, top: this.statusBarHeight })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
      .alignItems(VerticalAlign.Center)
      .backgroundColor($r('app.color.page_background'))

      // Tabs：关注 / 粉丝
      Tabs({ barPosition: BarPosition.Start, index: this.currentTab, controller: this.tabsController }) {
        TabContent() {
          this.FollowsTab()
        }
        .tabBar(this.buildTabBar(getResourceString($r('app.string.follows_tab')),
          this.followsTotalCount, this.currentTab === 0))

        TabContent() {
          this.FansTab()
        }
        .tabBar(this.buildTabBar(getResourceString($r('app.string.fans_tab')),
          this.fansTotalCount, this.currentTab === 1))
      }
      .onChange((index: number) => this.onTabChange(index))
      .layoutWeight(1)
      .barMode(BarMode.Fixed)
      .barWidth('100%')
      .barHeight(44)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  /** 构建 TabBar：文字 + 数量 + 选中下划线 */
  @Builder
  buildTabBar(label: string, count: number, isActive: boolean) {
    Column() {
      Row() {
        Text(label)
          .fontSize(15)
          .fontWeight(isActive ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(isActive ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
        if (count > 0) {
          Text(count.toString())
            .fontSize(12)
            .fontColor(isActive ? $r('app.color.primary') : $r('app.color.text_caption'))
            .margin({ left: 4 })
        }
      }
      .height(42)
      .alignItems(VerticalAlign.Center)

      // 选中下划线
      Divider()
        .color(isActive ? $r('app.color.primary') : Color.Transparent)
        .strokeWidth(2)
        .width(isActive ? 24 : 0)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }
}
