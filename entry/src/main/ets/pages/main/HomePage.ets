// 主页（"主页"tab）
// 展示当前账号关注的贴吧列表（issue #48 切片1）
// 数据来源：TiebaAPI.getFollowForums（/c/f/forum/forumGuide）
// 点击吧项跳转 ForumPage 查看该吧帖子
// #194 HdsNavDestination titleBar 沉浸光感材质（GRADIENT_BLUR + ADAPTIVE）+ bindToScrollable 联动滚动模糊

import { AppStorageV2 } from '@kit.ArkUI';
import { HdsNavDestination, ScrollEffectType, hdsMaterial } from '@kit.UIDesignKit';
import { TiebaAPI } from '../../api/TiebaAPI';
import { SelfFollowForum } from '../../model/ForumModels';
import { ImageLoadTypeState, IsWifiState, ForumsNeedRefreshState, HomeDualColumnState } from '../../model/AppStorageV2Models';
import { LoadingView } from '../../components/LoadingView';
import { ErrorView } from '../../components/ErrorView';
import { BaseViewModel, FetchDataResult } from '../../viewmodel/BaseViewModel';
import { CommonDataSource } from '../../utils/CommonDataSource';
import { getResourceString } from '../../utils/ResourceUtil';
import { formatCount } from '../../utils/FormatUtil';
import { shouldLoad } from '../../utils/ImageLoadUtil';
import { connectTheme, ThemeState } from '../../theme/ThemeManager';
import { VibratorUtil } from '../../utils/VibratorUtil';
import { RouterUtil, ForumNavParams } from '../../utils/RouterUtil';
import { getStatusBarHeight } from '../../utils/StatusBarUtil';

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

// #194 HdsNavDestination titleBar 高度（mini 模式约 48vp），用于内容区顶部占位避让
const TITLE_BAR_HEIGHT: number = 48;

@ComponentV2
export struct HomePage {
  private viewModel: HomeForumsViewModel = new HomeForumsViewModel();
  private dataSource: CommonDataSource<SelfFollowForum> = new CommonDataSource<SelfFollowForum>();
  // #194 滚动器，绑定到 HdsNavDestination.bindToScrollable 实现 titleBar 滚动动态模糊
  private scroller: Scroller = new Scroller();
  // #194 状态栏高度（vp），aboutToAppear 中通过 getStatusBarHeight 获取
  // 用于内容区顶部 Blank 占位高度，让初始内容不顶到状态栏
  @Local statusBarHeight: number = 36;

  @Local forumCount: number = 0;
  @Local isLoading: boolean = false;
  @Local isRefreshing: boolean = false;
  @Local hasMore: boolean = true;
  @Local errorMessage: string = '';
  @Local searchKeyword: string = '';
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
    // #194 获取状态栏高度，用于内容区顶部 Blank 占位避让状态栏 + titleBar
    this.statusBarHeight = await getStatusBarHeight(getContext(this));
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
   * #193 P2 @Monitor 方法签名要求 monitor: IMonitor 参数，但本方法未使用该参数，
   * 用 _monitor 前缀表示有意未使用（对齐 MainPage.onAppLinkingTidChange 模式）
   */
  @Monitor('forumsNeedRefreshState.value')
  onForumsNeedRefresh(_monitor: IMonitor): void {
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
   * 成功后直接修改 forum.isSigned = true，@ObservedV2 + @Trace 自动触发 ForumItem 局部刷新
   * 不需要创建新实例替换，避免 LazyForEach keyGenerator=fid 不变导致复用旧实例
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
      // 签到成功：直接修改原实例的 isSigned 字段
      // @ObservedV2 + @Trace isSigned 会自动触发 ForumItem 的 @Param forum 局部刷新
      forum.isSigned = true;
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
    // #164 路由迁移：router.pushUrl → RouterUtil.push
    RouterUtil.push(RouterUtil.ROUTE_FORUM_PAGE, new ForumNavParams(forumName));
  }

  /** 右上角"搜索"图标：直接跳转搜索页 */
  navigateToSearch(): void {
    // #121 触感反馈：搜索按钮点击触发轻震动
    VibratorUtil.light();
    // #165 路由迁移：router.pushUrl → RouterUtil.push
    RouterUtil.push(RouterUtil.ROUTE_SEARCH_PAGE);
  }

  /** 点击"设置"图标跳转设置页 */
  // #162 [A4-S2] SettingsPage 已迁移到 Navigation 栈，改用 RouterUtil.push
  navigateToSettings(): void {
    // #194 触感反馈：设置按钮点击触发轻震动
    VibratorUtil.light();
    RouterUtil.push(RouterUtil.ROUTE_SETTINGS_PAGE);
  }

  /**
   * #194 切换吧列表排序方式（按等级/按名称）
   * titleBar menu 排序按钮点击回调，切换后立即重排并 Toast 提示
   */
  toggleForumSort(): void {
    VibratorUtil.light();
    this.forumSortByLevel = !this.forumSortByLevel;
    this.applyForumSort();
    const tip: string = getResourceString(
      this.forumSortByLevel ? $r('app.string.sort_by_level') : $r('app.string.sort_by_name')
    );
    this.showToast(tip);
  }

  build() {
    // #194 HdsNavDestination + titleBar 沉浸光感材质（GRADIENT_BLUR + ADAPTIVE）
    // titleBar 配置渐变模糊 + 自适应材质，bindToScrollable 绑定 List Scroller 联动滚动模糊
    // enableComponentSafeArea: true 让内容区自动避让 titleBar
    // cachedCount(10, true) 第二个参数 true 防止列表穿透到 titleBar 下方后消失
    HdsNavDestination() {
      Column() {
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
          // #194 混合式：外层 Column padding top 避让 titleBar，Refresh clip(false) 让内容穿透
          Refresh({ refreshing: $$this.isRefreshing }) {
            if (this.homeDualColumnState.value) {
              // 双列 Grid 布局：每个卡片独立圆角，左右两列并排，列间距 12vp
              // #194 Grid 绑定 this.scroller，与 List 共用（条件渲染同一时间只存在一个）
              Grid(this.scroller) {
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
              // #194 混合式：padding top 改为小值（避让已由外层 Column padding top 处理）
              .padding({ top: 8, left: 16, right: 16, bottom: 12 })
              .scrollBar(BarState.Off)
              .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
              .cachedCount(4, true)
              // #194 clip(false) 让内容穿透到 titleBar 下方，titleBar 对穿透内容做模糊
              .clip(false)
              // #194 backgroundColor 让穿透区域有内容背景色，避免 titleBar 下方显示灰色遮罩
              .backgroundColor($r('app.color.page_background'))
              .onReachEnd(() => this.onReachEnd())
            } else {
              // 单列 List 布局
              List({ space: 0, scroller: this.scroller }) {
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
              .height('100%')
              .divider({ strokeWidth: 0.5, color: $r('app.color.divider'), startMargin: 76, endMargin: 0 })
              // #194 混合式：padding top 改为小值（避让已由外层 Column padding top 处理）
              .padding({ top: 8, left: 16, right: 16 })
              .scrollBar(BarState.Off)
              .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
              .cachedCount(10, true)
              // #194 clip(false) 让内容穿透到 titleBar 下方，titleBar 对穿透内容做模糊
              .clip(false)
              // #194 backgroundColor 让穿透区域有内容背景色，避免 titleBar 下方显示灰色遮罩
              .backgroundColor($r('app.color.page_background'))
              .onReachEnd(() => this.onReachEnd())
            }
          }
          .layoutWeight(1)
          // #194 混合式：Refresh clip(false) 让 List/Grid 穿透内容不被裁剪
          .clip(false)
          .backgroundColor($r('app.color.page_background'))
          .onRefreshing(() => this.onRefresh())
        }
      }
      .width('100%')
      .height('100%')
      // #194 混合式：外层 Column padding top 避让状态栏 + titleBar
      .padding({ top: this.statusBarHeight + TITLE_BAR_HEIGHT })
      .backgroundColor($r('app.color.page_background'))
    }
    .titleBar({
      // #194 不设 enableComponentSafeArea，让内容穿透到 titleBar 下方（配合 clip(false) + cachedCount）
      // titleBar 的 GRADIENT_BLUR + ADAPTIVE 对穿透内容做模糊，避免不透明背景板遮挡
      content: {
        title: {
          mainTitle: $r('app.string.tab_home')
        },
        menu: {
          value: [{
            content: {
              icon: $r('app.media.ic_search'),
              isEnabled: true,
              action: () => this.navigateToSearch()
            }
          }, {
            content: {
              icon: $r('app.media.ic_sort'),
              isEnabled: true,
              action: () => this.toggleForumSort()
            }
          }, {
            content: {
              icon: $r('app.media.ic_settings'),
              isEnabled: true,
              action: () => this.navigateToSettings()
            }
          }]
        }
      },
      style: {
        // GRADIENT_BLUR 渐变模糊：标题栏顶部模糊→底部清晰，无硬边
        scrollEffectOpts: {
          enableScrollEffect: true,
          scrollEffectType: ScrollEffectType.GRADIENT_BLUR
        },
        // ADAPTIVE 沉浸光感材质：系统自适应模糊，不依赖下层内容（不会因内容滚出屏幕而变白）
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        },
        // #194 originalStyle：滚动效果生效前的初始样式，图标颜色跟随主题色（标题用默认色）
        originalStyle: {
          contentStyle: {
            menuStyle: { iconColor: this.themeState.primary }
          }
        },
        // #194 scrollEffectStyle：滚动效果生效后的样式，图标颜色跟随主题色（标题用默认色）
        scrollEffectStyle: {
          contentStyle: {
            menuStyle: { iconColor: this.themeState.primary }
          }
        }
      },
      // 避让状态栏：setWindowLayoutFullScreen(true) 全屏模式下 titleBar 默认不避让状态栏
      avoidLayoutSafeArea: true
    })
    .bindToScrollable([this.scroller])
    // #194 HomePage 是 Tab 子页面，不需要返回按钮
    .hideBackButton(true)
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
