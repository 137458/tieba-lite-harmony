// 主页（"主页"tab）
// 展示当前账号关注的贴吧列表（issue #48 切片1）
// 数据来源：TiebaAPI.getFollowForums（/c/f/forum/forumGuide）
// 点击吧项跳转 ForumPage 查看该吧帖子
// UI 设计：iOS Large Title + 搜索框 + 圆角卡片列表（对齐 design-spec.md 第6节 ForumItem 规格）

import { router, AppStorageV2 } from '@kit.ArkUI';
import { TiebaAPI } from '../../api/TiebaAPI';
import { SelfFollowForum } from '../../model/ForumModels';
import { ImageLoadTypeState, IsWifiState, ForumsNeedRefreshState, HomeDualColumnState } from '../../model/AppStorageV2Models';
import { LoadingView } from '../../components/LoadingView';
import { ErrorView } from '../../components/ErrorView';
import { BaseViewModel, FetchDataResult } from '../../viewmodel/BaseViewModel';
import { CommonDataSource } from '../../utils/CommonDataSource';
import { getResourceString } from '../../utils/ResourceUtil';
import { getStatusBarHeight } from '../../utils/StatusBarUtil';
import { formatCount } from '../../utils/FormatUtil';
import { shouldLoad } from '../../utils/ImageLoadUtil';
import { connectTheme, ThemeState } from '../../theme/ThemeManager';
import { VibratorUtil } from '../../utils/VibratorUtil';
import { RouterUtil } from '../../utils/RouterUtil';

/**
 * 主页 ViewModel：关注贴吧列表
 * 调用 TiebaAPI.getFollowForums（web 端 /c/f/forum/forumGuide）
 */
class HomeForumsViewModel extends BaseViewModel<SelfFollowForum> {
  // 每页拉取吧数量（对齐 aiotieba 默认 rn）
  private static readonly PAGE_SIZE: number = 20;

  protected async fetchData(page: number, isRefresh: boolean): Promise<FetchDataResult<SelfFollowForum>> {
    return await TiebaAPI.getFollowForums(page, HomeForumsViewModel.PAGE_SIZE);
  }
}

@ComponentV2
export struct HomePage {
  private viewModel: HomeForumsViewModel = new HomeForumsViewModel();
  private dataSource: CommonDataSource<SelfFollowForum> = new CommonDataSource<SelfFollowForum>();

  @Local forumCount: number = 0;
  @Local isLoading: boolean = false;
  @Local isRefreshing: boolean = false;
  @Local hasMore: boolean = true;
  @Local errorMessage: string = '';
  @Local searchKeyword: string = '';
  // 状态栏高度（vp），沉浸式避让状态栏，默认 36，aboutToAppear 动态获取
  @Local statusBarHeight: number = 36;
  // #81 图片加载策略：通过 AppStorageV2 共享，SettingsPage 修改后自动响应
  @Local imageLoadTypeState: ImageLoadTypeState = AppStorageV2.connect(ImageLoadTypeState, 'imageLoadType', () => new ImageLoadTypeState())!;
  @Local isWifiState: IsWifiState = AppStorageV2.connect(IsWifiState, 'isWifi', () => new IsWifiState())!;
  // 签到中的吧 fname（用于按钮 loading 态防抖，避免连点），对齐 FollowForumsPage 实现
  @Local signingForumName: string = '';
  // 吧列表排序方式：true=按等级降序（默认），false=按吧名字母序
  @Local forumSortByLevel: boolean = true;
  // 关注吧变更标记：ForumPage 关注/取消关注成功后写入 AppStorageV2 触发本页自动刷新
  // 用 number 时间戳作为值，@Monitor 检测变化即触发刷新，避免布尔值重复设置不触发的问题
  @Local forumsNeedRefreshState: ForumsNeedRefreshState = AppStorageV2.connect(ForumsNeedRefreshState, 'forumsNeedRefresh', () => new ForumsNeedRefreshState())!;
  @Local themeState: ThemeState = connectTheme();
  // 首页双列展示开关（AppStorageV2 全局共享，SettingsPage 修改后自动响应）
  @Local homeDualColumnState: HomeDualColumnState = AppStorageV2.connect(HomeDualColumnState, 'homeDualColumn', () => new HomeDualColumnState())!;

  // Toast 提示 helper（API 12+ 推荐用 UIContext.getPromptAction()）
  private showToast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message });
  }

  async aboutToAppear() {
    // 获取状态栏高度（沉浸式，P1 重构提取为 StatusBarUtil）
    // 失败不阻塞后续加载，保留默认值 36
    try {
      this.statusBarHeight = await getStatusBarHeight(getContext(this));
    } catch (err) {
      console.error(`[HomePage] getStatusBarHeight failed: ${(err as Error).message}`);
    }
    this.loadForums(true).catch((err: Error) => {
      console.error(`[HomePage] loadForums failed: ${err.message}`);
    });
  }

  async loadForums(isRefresh: boolean = false): Promise<void> {
    await this.viewModel.loadData(isRefresh);
    this.syncState();
  }

  private syncState(): void {
    const paginationData = this.viewModel.paginationData;
    const loadingState = this.viewModel.loadingState;

    // issue #39：刷新用 setData 全量替换，loadMore 用 appendData 增量追加
    if (this.viewModel.lastOpWasRefresh) {
      // 刷新时先排序再 setData，保证列表按当前排序方式展示
      this.dataSource.setData(this.sortForums(paginationData.dataList));
    } else {
      // loadMore：追加新数据后全量重排（关注吧列表数据量小，全量 diff 性能可接受）
      this.dataSource.appendData(this.viewModel.lastAddedList);
      const sorted: SelfFollowForum[] = this.sortForums(this.dataSource.getAllData());
      this.dataSource.setData(sorted);
    }
    this.forumCount = this.dataSource.totalCount();
    this.hasMore = paginationData.hasMore;
    this.isLoading = loadingState.isLoading;
    this.isRefreshing = loadingState.isRefreshing;
    this.errorMessage = loadingState.error;
  }

  /**
   * 对 dataSource 内部数据按当前排序方式重新排序并刷新
   * forumSortByLevel=true：按 level 降序（高等级在前）
   * forumSortByLevel=false：按 fname 字母序升序
   */
  applyForumSort(): void {
    const sorted: SelfFollowForum[] = this.sortForums(this.dataSource.getAllData());
    this.dataSource.setData(sorted);
  }

  /**
   * 排序论坛数组（返回新数组，不改原数组）
   * @param forums 待排序数组
   * @return 排序后的新数组
   */
  private sortForums(forums: SelfFollowForum[]): SelfFollowForum[] {
    const result: SelfFollowForum[] = forums.slice();
    if (this.forumSortByLevel) {
      // 按等级降序：高等级在前，等级相同按吧名字母序兜底
      result.sort((a: SelfFollowForum, b: SelfFollowForum) => {
        if (a.level !== b.level) {
          return b.level - a.level;
        }
        return a.fname.localeCompare(b.fname);
      });
    } else {
      // 按吧名字母序升序
      result.sort((a: SelfFollowForum, b: SelfFollowForum) => {
        return a.fname.localeCompare(b.fname);
      });
    }
    return result;
  }

  onReachEnd(): void {
    if (this.viewModel.canLoadMore()) {
      // onReachEnd 回调不处理 async 返回值，需 catch 避免 unhandled rejection
      this.loadForums(false).catch((err: Error) => {
        console.error(`[HomePage] onReachEnd loadForums failed: ${err.message}`);
      });
    }
  }

  /**
   * AppStorageV2 'forumsNeedRefresh' 标记变化回调（issue #2 首页刷新）
   * ForumPage 关注/取消关注成功后会写入时间戳，本方法监听到变化即触发刷新
   * 跳过初值 0，避免组件首次 aboutToAppear 时重复加载
   */
  @Monitor('forumsNeedRefreshState.value')
  onForumsNeedRefresh(monitor: IMonitor): void {
    if (this.forumsNeedRefreshState.value === 0) {
      return;
    }
    this.loadForums(true).catch((err: Error) => {
      console.error(`[HomePage] onForumsNeedRefresh loadForums failed: ${err.message}`);
    });
  }

  /**
   * 下拉刷新回调（issue #2 首页刷新）
   * Refresh 组件 onRefreshing 触发，加载完成后置 isRefreshing=false
   */
  onRefresh(): void {
    // #121 触感反馈：下拉刷新触发轻震动
    VibratorUtil.light();
    this.loadForums(true).catch((err: Error) => {
      console.error(`[HomePage] onRefresh loadForums failed: ${err.message}`);
    });
  }

  /**
   * 签到（issue 功能4，对齐 FollowForumsPage.handleSignForum）
   * 成功后创建新的 forum 实例替换旧的，触发 LazyForEach 刷新
   * SelfFollowForum 已是 @ObservedV2 + @Trace isSigned，可直接修改 forum.isSigned = true 触发局部刷新
   */
  async handleSignForum(forum: SelfFollowForum): Promise<void> {
    // 防抖：已签到或签到进行中时直接返回
    if (forum.isSigned || this.signingForumName.length > 0) {
      return;
    }
    this.signingForumName = forum.fname;
    // #121 触感反馈：签到属于强调交互，触发重震动
    VibratorUtil.heavy();
    try {
      await TiebaAPI.signForum(forum.fname);
      // 签到成功：创建新的 forum 实例（isSigned=true）替换旧的
      // 逐字段复制（对齐 TiebaAPI.getFollowForums 构造方式），避免引用旧对象
      const newForum: SelfFollowForum = new SelfFollowForum();
      newForum.fid = forum.fid;
      newForum.fname = forum.fname;
      newForum.level = forum.level;
      newForum.isSigned = true;
      newForum.avatar = forum.avatar;
      newForum.memberCount = forum.memberCount;
      newForum.threadNum = forum.threadNum;
      // 构造新数组对象，替换 dataSource 内部数组，触发 onDataReloaded
      const oldData: SelfFollowForum[] = this.dataSource.getAllData();
      const newData: SelfFollowForum[] = [];
      for (let i = 0; i < oldData.length; i++) {
        if (oldData[i].fid === forum.fid) {
          newData.push(newForum);
        } else {
          newData.push(oldData[i]);
        }
      }
      this.dataSource.setData(newData);
      this.showToast(getResourceString($r('app.string.sign_success')));
    } catch (err) {
      const msg: string = (err as Error).message || getResourceString($r('app.string.sign_failed'));
      this.showToast(msg);
    } finally {
      this.signingForumName = '';
    }
  }

  /** 点击吧项跳转 ForumPage 查看该吧帖子 */
  navigateToForum(forumName: string): void {
    if (forumName.length === 0) {
      console.warn(`[HomePage] empty forumName, skip navigation`);
      return;
    }
    router.pushUrl({
      url: 'pages/forum/ForumPage',
      params: { forumName: forumName }
    }).catch((err: Error) => {
      console.error(`[HomePage] navigate to forum failed: ${err.message}`);
    });
  }

  /** 右上角"搜索"图标：直接跳转搜索页 */
  navigateToSearch(): void {
    // #121 触感反馈：搜索按钮点击触发轻震动
    VibratorUtil.light();
    router.pushUrl({
      url: 'pages/search/SearchPage'
    }).catch((err: Error) => {
      console.error(`[HomePage] navigate to search failed: ${err.message}`);
    });
  }

  /** 点击"设置"图标跳转设置页 */
  // #162 [A4-S2] SettingsPage 已迁移到 Navigation 栈，改用 RouterUtil.push
  navigateToSettings(): void {
    RouterUtil.push(RouterUtil.ROUTE_SETTINGS_PAGE);
  }

  build() {
    Column() {
      // iOS Large Title 顶部栏（对齐 design-spec.md 第6节）
      // 左侧 Large Title 34px 800 + 右侧 设置图标按钮
      // 注：搜索入口已整合到下方搜索框占位，顶部不再重复搜索图标
      Row() {
        Text($r('app.string.tab_home'))
          .fontSize(34)
          .fontWeight(800)
          .fontColor($r('app.color.text_primary'))
          .letterSpacing(0.37)
          .layoutWeight(1)

        Row() {
          Image($r('app.media.ic_settings'))
            .width(24)
            .height(24)
            .fillColor(this.themeState.primary)
            // A5 图片优化：本地 SVG 图标，同步加载避免闪烁 + 低质量插值
            .syncLoad(true)
            .interpolation(ImageInterpolation.Low)
        }
        .width(36)
        .height(36)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .onClick(() => this.navigateToSettings())
      }
      .width('100%')
      .height(56 + this.statusBarHeight)
      .padding({ left: 16, right: 16, top: this.statusBarHeight, bottom: 8 })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
      .alignItems(VerticalAlign.Center)

      // iOS 搜索框（36px 高度，10px 圆角，对齐 design-spec.md 第3节）
      // 搜索框本身就是搜索入口，点击跳转搜索页
      // 注：不加 width('100%')，否则 margin 会被挤出屏幕（#93 同类问题）
      Row() {
        Image($r('app.media.ic_search'))
          .width(16)
          .height(16)
          .fillColor($r('app.color.text_caption'))
          .margin({ right: 6 })
          // A5 图片优化：本地 SVG 图标，同步加载避免闪烁 + 低质量插值
          .syncLoad(true)
          .interpolation(ImageInterpolation.Low)

        Text($r('app.string.search_hint'))
          .fontSize(15)
          .fontColor($r('app.color.text_caption'))
          .layoutWeight(1)

        // 吧列表排序切换按钮（按等级/按名称）
        Text(this.forumSortByLevel ? $r('app.string.sort_by_level') : $r('app.string.sort_by_name'))
          .fontSize(12)
          .fontColor(this.themeState.primary)
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .borderRadius(8)
          .backgroundColor(this.themeState.primary_light)
          .onClick(() => {
            // #121 触感反馈：切换排序触发轻震动
            VibratorUtil.light();
            this.forumSortByLevel = !this.forumSortByLevel;
            this.applyForumSort();
          })
      }
      .height(36)
      .padding({ left: 10, right: 8 })
      .margin({ left: 16, right: 16, bottom: 12 })
      .backgroundColor($r('app.color.input_background'))
      .borderRadius(10)
      .onClick(() => this.navigateToSearch())

      // 内容区
      if (this.errorMessage.length > 0 && this.forumCount === 0) {
        ErrorView({
          message: this.errorMessage,
          onRetryClick: () => this.loadForums(true).catch((err: Error) => {
            console.error(`[HomePage] loadForums retry failed: ${err.message}`);
          })
        })
          .layoutWeight(1)
      } else if (this.forumCount === 0 && !this.isLoading) {
        // 空状态
        Column() {
          Text($r('app.string.follow_forums_empty'))
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        // 下拉刷新（issue #2 首页刷新）：Refresh 包裹 List/Grid，用户下拉触发 onRefresh
        Refresh({ refreshing: $$this.isRefreshing }) {
          if (this.homeDualColumnState.value) {
            // 双列 Grid 布局：每个卡片独立圆角，左右两列并排，列间距 12vp
            Grid() {
              LazyForEach(this.dataSource, (forum: SelfFollowForum) => {
                GridItem() {
                  ForumItem({
                    forum: forum,
                    imageLoadType: this.imageLoadTypeState.value,
                    isWifi: this.isWifiState.value,
                    signingForumName: this.signingForumName,
                    isDualColumn: true,
                    onSignClick: (f: SelfFollowForum) => {
                      this.handleSignForum(f).catch((err: Error) => {
                        console.error(`[HomePage] handleSignForum failed: ${err.message}`);
                      });
                    },
                    onItemClick: (fname: string) => this.navigateToForum(fname)
                  })
                }
              }, (forum: SelfFollowForum, index: number) => `${forum.fid}`)

              if (this.isLoading && this.forumCount > 0) {
                GridItem() {
                  LoadingView({ message: getResourceString($r('app.string.loading_more')) })
                    .height(60)
                    .width('100%')
                }
              }
            }
            .columnsTemplate('1fr 1fr')
            .columnsGap(12)
            .rowsGap(12)
            .padding({ left: 16, right: 16, top: 12, bottom: 12 })
            .scrollBar(BarState.Off)
            .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
            .cachedCount(4)
            .onReachEnd(() => this.onReachEnd())
          } else {
            // 单列 List 布局：整个 List 共享 4 个圆角容器
            List({ space: 0 }) {
              LazyForEach(this.dataSource, (forum: SelfFollowForum) => {
                ListItem() {
                  // #138 改用独立子组件 + @Param，签到状态变化时精准触发 UI 更新
                  ForumItem({
                    forum: forum,
                    imageLoadType: this.imageLoadTypeState.value,
                    isWifi: this.isWifiState.value,
                    signingForumName: this.signingForumName,
                    onSignClick: (f: SelfFollowForum) => {
                      this.handleSignForum(f).catch((err: Error) => {
                        console.error(`[HomePage] handleSignForum failed: ${err.message}`);
                      });
                    },
                    onItemClick: (fname: string) => this.navigateToForum(fname)
                  })
                }
              }, (forum: SelfFollowForum, index: number) => `${forum.fid}`)

              if (this.isLoading && this.forumCount > 0) {
                ListItem() {
                  LoadingView({ message: getResourceString($r('app.string.loading_more')) })
                    .height(60)
                }
              }
            }
            // #93 不设 width('100%')：width 100% + margin 会导致宽度溢出屏幕，margin 被忽略
            // Refresh 内子组件默认铺满，margin 能正确生效提供左右 16vp 边距
            .height('100%')
            .divider({ strokeWidth: 0.5, color: $r('app.color.divider'), startMargin: 76, endMargin: 0 })
            // #93 左右边距：List 用 margin 提供与屏幕边缘 16vp 边距（露出 page_background）
            // 不用 padding：ForumItemBuilder 内 Row 已有 padding 16，避免双重内边距
            .margin({ left: 16, right: 16 })
            .scrollBar(BarState.Off)
            .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
            .cachedCount(5)
            // #93 整个 List 共享 4 个圆角（用户要求"一共就四个圆角"），
            // 而不是每个 ForumItem 一个圆角卡片
            .backgroundColor($r('app.color.card_background'))
            .borderRadius(10)
            .clip(true)
            .onReachEnd(() => this.onReachEnd())
          }
        }
        .layoutWeight(1)
        .onRefreshing(() => this.onRefresh())
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  // #138 ForumItemBuilder 已抽为独立 @ComponentV2 ForumItem（文件末尾定义）
  // @ObservedV2 SelfFollowForum + @Param forum 字段变化时精准触发 UI 更新
  // 解决下拉刷新签到状态不更新问题
}

/**
 * #138 关注吧列表项独立子组件
 * @Param forum：@ObservedV2 SelfFollowForum 字段变化时精准触发 UI 更新
 * 解决 LazyForEach keyGenerator 用 fid 导致相同 fid item 复用旧实例、isSigned 变化不刷新的问题
 * A11 GlobalReuse：加 @ReusableV2，吧列表滚动时复用减少创建/销毁开销（无 @Local 字段，无需 aboutToReuse）
 */
@ReusableV2
@ComponentV2
struct ForumItem {
  @Require @Param forum: SelfFollowForum;
  // 图片加载策略（#81）通过 @Param 从父组件传入，避免子组件直接访问 AppStorageV2
  @Param imageLoadType: number = 0;
  @Param isWifi: boolean = false;
  // 签到中的吧 fname（用于按钮 loading 态防抖）
  @Param signingForumName: string = '';
  // 双列模式标记：true=双列纵向布局（头像在上）+ 独立圆角卡片；false=单列横向布局
  @Param isDualColumn: boolean = false;
  // 签到回调（父组件处理 API 调用 + 状态更新）
  @Event onSignClick: (forum: SelfFollowForum) => void = () => {};
  // 点击跳转吧页回调
  @Event onItemClick: (fname: string) => void = () => {};
  @Local themeState: ThemeState = connectTheme();

  build() {
    if (this.isDualColumn) {
      // 双列模式：纵向布局（头像在上 + 吧名/meta 在中 + 签在底）+ 独立圆角卡片
      Column() {
        // 头像（居中，72px）
        if (this.forum.avatar.length > 0 && shouldLoad(this.imageLoadType, this.isWifi)) {
          Image(this.forum.avatar)
            .width(72)
            .height(72)
            .borderRadius(36)
            .objectFit(ImageFit.Cover)
            .backgroundColor($r('app.color.input_background'))
            .alt($r('app.media.startIcon'))
            .syncLoad(true)
            .interpolation(ImageInterpolation.Low)
            .onError(() => { })
            .hitTestBehavior(HitTestMode.Transparent)
        } else {
          Column() {
            Text(this.forum.fname.length > 0 ? this.forum.fname.charAt(0).toUpperCase() : '?')
              .fontSize(28)
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
            colors: [[this.themeState.primary, 0.0], [$r('app.color.accent_blue'), 1.0]]
          })
        }

        // 吧名
        Text(this.forum.fname)
          .fontSize(15)
          .fontWeight(600)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 10 })

        // Lv 标签
        Text(`Lv.${this.forum.level}`)
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.themeState.primary)
          .backgroundColor(this.themeState.primary_light)
          .padding({ left: 7, right: 7, top: 1, bottom: 1 })
          .borderRadius(6)
          .margin({ top: 6 })

        // 签到按钮 / 已签到 pill
        if (this.forum.isSigned) {
          Text($r('app.string.forum_signed'))
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.success'))
            .backgroundColor($r('app.color.success_light'))
            .borderRadius(6)
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .margin({ top: 8 })
            .hitTestBehavior(HitTestMode.Transparent)
        } else {
          Text(this.signingForumName === this.forum.fname ? $r('app.string.loading') : $r('app.string.forum_sign'))
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.themeState.primary)
            .backgroundColor(this.themeState.primary_light)
            .borderRadius(6)
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .margin({ top: 8 })
            .hitTestBehavior(HitTestMode.Block)
            .onClick(() => {
              this.onSignClick(this.forum);
            })
        }
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 16, bottom: 16 })
      .alignItems(HorizontalAlign.Center)
      .backgroundColor($r('app.color.card_background'))
      .borderRadius(12)
      .onClick(() => this.onItemClick(this.forum.fname))
    } else {
      // 单列模式：横向布局（头像在左 + 文字在中 + 签在右）
      Row() {
        // #81 shouldLoad=false（如智能无图+移动网络）时走首字母 fallback，省流且 UX 一致
        if (this.forum.avatar.length > 0 && shouldLoad(this.imageLoadType, this.isWifi)) {
          Image(this.forum.avatar)
            .width(48)
            .height(48)
            .borderRadius(24)
            .objectFit(ImageFit.Cover)
            .backgroundColor($r('app.color.input_background'))
            .alt($r('app.media.startIcon'))
            // A5 图片优化：吧头像，同步加载避免闪烁 + 低质量插值 + 错误兜底
            .syncLoad(true)
            .interpolation(ImageInterpolation.Low)
            .onError(() => { /* 吧头像加载失败静默处理 */ })
            // #92 HitTestMode.Transparent：让触控穿透到父 List，避免 fling 期间碰到图片导致触控丢失
            .hitTestBehavior(HitTestMode.Transparent)
        } else {
          Column() {
            Text(this.forum.fname.length > 0 ? this.forum.fname.charAt(0).toUpperCase() : '?')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
          }
          .width(48)
          .height(48)
          .borderRadius(24)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .linearGradient({
            angle: 135,
            colors: [[this.themeState.primary, 0.0], [$r('app.color.accent_blue'), 1.0]]
          })
        }

        Column() {
          // 吧名独占一行：吧名长时不被 Lv 标签挤压，省略号显示更自然
          Text(this.forum.fname)
            .fontSize(16)
            .fontWeight(600)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          // meta 行：Lv 标签 + 关注数 · 帖子数
          // Lv 标签从吧名行移到此处，避免吧名长时与签到按钮视觉拥挤
          Row() {
            Text(`Lv.${this.forum.level}`)
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.themeState.primary)
              .backgroundColor(this.themeState.primary_light)
              .padding({ left: 7, right: 7, top: 1, bottom: 1 })
              .borderRadius(6)
              .margin({ right: 6 })

            Text($r('app.string.forum_meta_format', formatCount(this.forum.memberCount), formatCount(this.forum.threadNum)))
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }
          .alignItems(VerticalAlign.Center)
          .margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 12 })
        .layoutWeight(1)

        // 右侧：签到按钮（未签到）/ 已签到 pill（已签到），issue 功能4
        // #138 @Param forum.isSigned 变化时自动触发本 if 分支重新求值
        if (this.forum.isSigned) {
          // 已签到 pill：不可点击，仅展示
          Text($r('app.string.forum_signed'))
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.success'))
            .backgroundColor($r('app.color.success_light'))
            .borderRadius(6)
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            // 已签到状态下允许触控穿透到父 ListItem，保留点击跳转吧页能力
            .hitTestBehavior(HitTestMode.Transparent)
        } else {
          // 签到按钮：可点击，调用 signForum
          Text(this.signingForumName === this.forum.fname ? $r('app.string.loading') : $r('app.string.forum_sign'))
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.themeState.primary)
            .backgroundColor(this.themeState.primary_light)
            .borderRadius(6)
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            // Block：阻止触控穿透到父 ListItem，避免签到时同时触发跳转
            .hitTestBehavior(HitTestMode.Block)
            .onClick(() => {
              this.onSignClick(this.forum);
            })
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })
      .alignItems(VerticalAlign.Center)
      // #93 移除 item 级 backgroundColor + borderRadius：
      // 整个 List 共享 4 个圆角容器，避免每个 item 独立圆角卡片
      .onClick(() => this.onItemClick(this.forum.fname))
    }
  }
}
