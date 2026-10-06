// 消息页（"消息"tab）
// UI：iOS Large Title + Tabs 切换"回复我的"/"@我的"
// 数据：TiebaAPI.getReplys（protobuf /c/u/feed/replyme?cmd=303007）
//       TiebaAPI.getAts（form POST /c/u/feed/atme，JSON 响应）
// 列表：List + LazyForEach + onReachEnd 分页加载
// 点击：跳转 ThreadPage（tid 路由参数）

import { TiebaAPI, AtMessage, AtsResult } from '../../api/TiebaAPI';
import { HdsNavDestination, hdsMaterial } from '@kit.UIDesignKit';
import { BdussState, ImageLoadTypeState, IsWifiState, MaterialLevelState, MainTabRefreshState, connectBduss, connectImageLoadType, connectIsWifi, connectMaterialLevel, connectMainTabRefresh } from '../../model/AppStorageV2Models';
import { MATERIAL_TYPE_IMMERSIVE, resolveMaterialLevel } from '../../theme/MaterialUtil';
import { ReplyMessage, ReplysResult } from '../../proto/MessageProto';
import { getResourceString } from '../../utils/ResourceUtil';
import { getStatusBarHeight } from '../../utils/StatusBarUtil';
import { getAvatarUrl } from '../../utils/AvatarUtil';
import { getAvatarImageUrl } from '../../utils/ImageLoadUtil';
import { formatRelativeTime } from '../../utils/TimeUtil';
import { CommonDataSource } from '../../utils/CommonDataSource';
import { connectTheme, ThemeState } from '../../theme/ThemeManager';
import { VibratorUtil } from '../../utils/VibratorUtil';
import { RouterUtil, ThreadNavParams } from '../../utils/RouterUtil';
import { Logger } from '../../utils/Logger';

const TAG: string = 'MessagePage';

// #166 HdsNavDestination titleBar mini 模式高度
const TITLE_BAR_HEIGHT: number = 48;

/**
 * 单个消息 Tab 的列表状态（H11 去重：回复我的/@我的 两 Tab 原各自维护 8 个 @Local 镜像，
 * 收敛为本状态类两实例；@ObservedV2/@Trace 模式同 H14 BaseViewModel 状态类）
 * dataSource 用 Object 承载 ReplyMessage/AtMessage（ArkTS 自定义组件不支持泛型参数），
 * 渲染经联合类型参数的 MessageItem，逻辑经 loadMessages 的 fetch 闭包分发
 */
@ObservedV2
class MessageTabState {
  dataSource: CommonDataSource<Object> = new CommonDataSource<Object>();
  /** 首屏加载中（驱动整页 LoadingProgress） */
  @Trace loading: boolean = false;
  /** 加载更多进行中（驱动列表尾部 footer） */
  @Trace loadingMore: boolean = false;
  @Trace hasMore: boolean = false;
  /** 下一页页码（客户端自增，成功后 +1） */
  pn: number = 1;
  /** 首屏加载失败信息（空串=无错误） */
  @Trace error: string = '';
  /** 首屏是否已加载过（避免切 Tab 重复触发首屏加载） */
  loaded: boolean = false;
}

/**
 * 消息页（主 Tab 第三页）
 *
 * 实现：
 *   - 顶部 iOS Large Title "消息"
 *   - Tabs 切换"回复我的"/"@我的"两种消息类型
 *   - List + LazyForEach 渲染消息项（头像 + 昵称 + 时间 + 贴吧名 + 内容预览）
 *   - 分页加载：onReachEnd 触发，pn 递增；has_more 控制是否继续
 *   - 点击消息跳转 ThreadPage（路由参数 tid）
 *   - 未登录态：占位提示"登录后查看消息"
 *
 * 数据源：
 *   - 回复我的：TiebaAPI.getReplys（protobuf 端点）
 *   - @我的：TiebaAPI.getAts（form POST + JSON 端点）
 */
@ComponentV2
export struct MessagePage {
  // 状态栏高度（vp），沉浸式避让状态栏，默认 36，aboutToAppear 动态获取
  @Local statusBarHeight: number = 36;
  // 当前 Tab 索引：0=回复我的，1=@我的
  @Local currentTab: number = 0;
  // bduss 是否存在（用于判断是否已登录），与 ProfilePage 联动登出
  @Local bdussState: BdussState = connectBduss();
  // #81 图片加载策略：通过 AppStorage 共享，SettingsPage 修改后自动响应
  @Local imageLoadTypeState: ImageLoadTypeState = connectImageLoadType();
  @Local isWifiState: IsWifiState = connectIsWifi();
  @Local themeState: ThemeState = connectTheme();
  // #201 沉浸光感材质强度档位（与 MainPage 共享，SettingsPage 修改后自动响应）
  @Local materialLevelState: MaterialLevelState = connectMaterialLevel();
  @Local mainTabRefreshState: MainTabRefreshState = connectMainTabRefresh();

  // ===== 列表状态（H11 去重：原 2×8 个 @Local 收敛为两份 MessageTabState） =====
  private replysState: MessageTabState = new MessageTabState();
  private atsState: MessageTabState = new MessageTabState();
  // #137 下拉刷新转圈状态：Refresh 组件通过 $$ 双向绑定要求状态变量，
  // 无法指向 MessageTabState 深路径，故保留两个镜像（onRefreshing 置位由组件内部写入，
  // 加载完成后在 loadReplys/loadAts 的 finally 中复位停止转圈）
  @Local replysRefreshing: boolean = false;
  @Local atsRefreshing: boolean = false;

  /** Tabs 控制器 */
  private tabsController: TabsController = new TabsController();

  // Toast 提示 helper（API 12+ 推荐用 UIContext.getPromptAction() 替代全局 promptAction）
  private showToast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message });
  }

  async aboutToAppear(): Promise<void> {
    // 获取状态栏高度，失败不阻塞页面渲染，保留默认值 36
    try {
      this.statusBarHeight = await getStatusBarHeight(this.getUIContext());
    } catch (err) {
      Logger.error(TAG, `[MessagePage] getStatusBarHeight failed: ${(err as Error).message}`);
    }
    // 已登录则加载首屏数据（默认 Tab 0=回复我的）
    // 注：StartupTask_Bduss 异步写入 bdussState.value，aboutToAppear 时可能尚未就绪
    //     未就绪时由 @Monitor('bdussState.value') 在 bduss 写入后自动触发加载
    if (this.bdussState.value.length > 0) {
      this.loadReplys(true).catch((err: Error) => {
        Logger.error(TAG, `[MessagePage] loadReplys initial failed: ${err.message}`);
      });
    }
  }

  /**
   * 监听 bduss 变化：StartupTask_Bduss 异步写入 bduss 后自动触发首屏加载
   * 触发场景：冷启动时 aboutToAppear 早于 StartupTask_Bduss 完成，bduss 从空变为非空
   * 跳过空值（登出场景），避免登出后误触发加载
   */
  @Monitor('bdussState.value')
  onBdussChange(monitor: IMonitor): void {
    if (this.bdussState.value.length === 0) {
      return;
    }
    // 仅在尚未加载时触发，避免重复加载（如切换账号后重新进入）
    if (!this.replysState.loaded && this.currentTab === 0) {
      this.loadReplys(true).catch((err: Error) => {
        Logger.error(TAG, `[MessagePage] loadReplys onBdussChange failed: ${err.message}`);
      });
    }
  }

  @Monitor('mainTabRefreshState.requestId')
  onMainTabRefresh(_monitor: IMonitor): void {
    if (this.mainTabRefreshState.targetIndex !== 2 || this.bdussState.value.length === 0) {
      return;
    }
    if (this.currentTab === 0) {
      this.loadReplys(true).catch((err: Error) => {
        Logger.error(TAG, `[MessagePage] loadReplys on tab refresh failed: ${err.message}`);
      });
      return;
    }
    this.loadAts(true).catch((err: Error) => {
      Logger.error(TAG, `[MessagePage] loadAts on tab refresh failed: ${err.message}`);
    });
  }

  /** 加载回复我的列表（H11 去重：转发到参数化 loadMessages） */
  private loadReplys(isRefresh: boolean): Promise<void> {
    return this.loadMessages(isRefresh, this.replysState,
      (pn: number): Promise<ReplysResult> => TiebaAPI.getReplys(pn))
      .finally((): void => {
        // #137 下拉刷新完成（成功或失败）后停止转圈
        this.replysRefreshing = false;
      });
  }

  /** 加载@我的列表（H11 去重：转发到参数化 loadMessages） */
  private loadAts(isRefresh: boolean): Promise<void> {
    return this.loadMessages(isRefresh, this.atsState,
      (pn: number): Promise<AtsResult> => TiebaAPI.getAts(pn))
      .finally((): void => {
        // #137 下拉刷新完成（成功或失败）后停止转圈
        this.atsRefreshing = false;
      });
  }

  /**
   * 参数化加载消息列表（H11 去重：合并原 loadReplys/loadAts，仅 API 与状态实例不同）
   *
   * @param isRefresh true=首屏/下拉刷新（重置 pn=1，清空错误），false=加载更多
   * @param state 目标 Tab 的列表状态
   * @param fetch 按 pn 拉取数据的 API 闭包
   */
  private async loadMessages(isRefresh: boolean, state: MessageTabState,
    fetch: (pn: number) => Promise<ReplysResult | AtsResult>): Promise<void> {
    if (this.bdussState.value.length === 0) {
      state.error = getResourceString($r('app.string.message_login_required'));
      return;
    }
    if (isRefresh) {
      if (state.loading) {
        return;
      }
      state.loading = true;
      state.loadingMore = false;
      state.error = '';
      state.pn = 1;
    } else {
      if (state.loadingMore || !state.hasMore) {
        return;
      }
      state.loadingMore = true;
    }
    try {
      const result = await fetch(state.pn);
      if (isRefresh) {
        state.dataSource.setData(result.list as Object[]);
      } else {
        state.dataSource.appendData(result.list as Object[]);
      }
      state.hasMore = result.page.hasMore;
      state.pn = state.pn + 1;
      state.loaded = true;
    } catch (err) {
      const msg: string = (err as Error).message || '';
      if (isRefresh) {
        state.error = msg;
      } else {
        this.showToast(msg);
      }
    } finally {
      state.loading = false;
      state.loadingMore = false;
    }
  }

  /** Tab 切换处理：首次切到 Tab 时触发首屏加载 */
  onTabChange(index: number): void {
    this.currentTab = index;
    if (index === 0 && !this.replysState.loaded && this.bdussState.value.length > 0) {
      this.loadReplys(true).catch((err: Error) => {
        Logger.error(TAG, `[MessagePage] loadReplys on tab switch failed: ${err.message}`);
      });
    } else if (index === 1 && !this.atsState.loaded && this.bdussState.value.length > 0) {
      this.loadAts(true).catch((err: Error) => {
        Logger.error(TAG, `[MessagePage] loadAts on tab switch failed: ${err.message}`);
      });
    }
  }

  /** 跳转帖子详情页（tid 路由参数） */
  navigateToThread(tid: number): void {
    if (tid <= 0) {
      return;
    }
    // #163 路由迁移：router.pushUrl → RouterUtil.push
    RouterUtil.push(RouterUtil.ROUTE_THREAD_PAGE, new ThreadNavParams(tid));
  }

  build() {
    // #166 HdsNavDestination + titleBar 沉浸光感材质（模式一非穿透）
    HdsNavDestination() {
      Column() {
        // 未登录态：占位提示（与原占位页保持一致的视觉）
        if (this.bdussState.value.length === 0) {
          Column() {
            Image($r('app.media.ic_message'))
              .width(64)
              .height(64)
              .fillColor($r('app.color.text_caption'))
              .opacity(0.4)
              .margin({ bottom: 20 })
              // A5 图片优化：本地 SVG 图标，同步加载避免闪烁 + 低质量插值
              .syncLoad(true)
              .interpolation(ImageInterpolation.Low)
            Text($r('app.string.message_login_required'))
              .fontSize(16)
              .fontColor($r('app.color.text_caption'))
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else {
          // 已登录态：Tabs 切换"回复我的"/"@我的"
          Tabs({ barPosition: BarPosition.Start, index: this.currentTab, controller: this.tabsController }) {
            TabContent() {
              this.ReplysTab()
            }
            .tabBar(this.TabBarBuilder($r('app.string.message_tab_reply'), 0))

            TabContent() {
              this.AtsTab()
            }
            .tabBar(this.TabBarBuilder($r('app.string.message_tab_at'), 1))
          }
          .onChange((index: number) => this.onTabChange(index))
          .layoutWeight(1)
          .barMode(BarMode.Fixed)
          .barWidth('100%')
          .barHeight(44)
        }
      }
      .width('100%')
      .height('100%')
      // 模式一：外层 Column padding top 避让状态栏 + titleBar
      .padding({ top: this.statusBarHeight + TITLE_BAR_HEIGHT })
      .backgroundColor($r('app.color.page_background'))
    }
    .titleBar({
      content: {
        title: {
          mainTitle: $r('app.string.message_page_title')
        }
      },
      style: {
        systemMaterialEffect: {
          materialType: MATERIAL_TYPE_IMMERSIVE,
          materialLevel: resolveMaterialLevel(this.materialLevelState.value)
        },
        originalStyle: {
          contentStyle: {
            menuStyle: { iconColor: this.themeState.primary }
          }
        }
      },
      avoidLayoutSafeArea: true
    })
    .hideBackButton(true)
    .backgroundColor($r('app.color.page_background'))
  }

  /**
   * 通用 TabBar Builder：参考 guide-snippets-master ArkUISample/ScrollableComponent/
   * entry/src/main/ets/pages/tabs/ContentPageNoAndTabLinkage.ets 官方样例模式
   * 单 @Builder + targetIndex 形参，@Builder 内部引用 @Local currentTab 触发高亮刷新
   *
   * 关键：targetIndex 是常量参数（0/1），不会随 @Local 变化；真正变化的是 this.currentTab
   * @Builder 内部 `this.currentTab === targetIndex` 三元判断会随 @Local currentTab 变化重新求值
   * （之前 buildTabBar(label, isActive) 的 isActive 是值类型快照，不会刷新，已废弃）
   */
  @Builder
  TabBarBuilder(title: ResourceStr, targetIndex: number) {
    Column() {
      Text(title)
        .fontSize(15)
        .fontWeight(this.currentTab === targetIndex ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.currentTab === targetIndex ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
        .height(42)

      // 下划线 indicator：颜色 + 宽度同步切换（保留 24px 短下划线视觉风格）
      Divider()
        .color(this.currentTab === targetIndex ? this.themeState.primary : Color.Transparent)
        .strokeWidth(2)
        .width(this.currentTab === targetIndex ? 24 : 0)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }

  /** 回复我的 Tab：Refresh $$ 绑定要求页面级状态变量，内容委托给参数化 MessageTabContent */
  @Builder
  ReplysTab() {
    // #137 所有分支都用 Refresh 包裹，支持下拉刷新（包括空列表/加载中/错误状态）
    Refresh({ refreshing: $$this.replysRefreshing }) {
      this.MessageTabContent(this.replysState, $r('app.string.message_reply_empty'),
        (fname: string): Resource => $r('app.string.message_reply_in_forum', fname), 'reply_',
        (): void => {
          this.loadReplys(true).catch((err: Error) => {
            Logger.error(TAG, `[MessagePage] retry failed: ${err.message}`);
          });
        },
        (): void => {
          this.loadReplys(false).catch((err: Error) => {
            Logger.error(TAG, `[MessagePage] load more failed: ${err.message}`);
          });
        })
    }
    .onRefreshing(() => {
      // #121 触感反馈：下拉刷新触发轻震动
      VibratorUtil.light();
      // #137 下拉触发刷新：复用 loadReplys(true)，防抖由 loading 锁保证
      this.loadReplys(true).catch((err: Error) => {
        Logger.error(TAG, `[MessagePage] onRefreshing loadReplys failed: ${err.message}`);
      });
    })
  }

  /** @我的 Tab：Refresh $$ 绑定要求页面级状态变量，内容委托给参数化 MessageTabContent */
  @Builder
  AtsTab() {
    // #137 所有分支都用 Refresh 包裹，支持下拉刷新（包括空列表/加载中/错误状态）
    Refresh({ refreshing: $$this.atsRefreshing }) {
      this.MessageTabContent(this.atsState, $r('app.string.message_at_empty'),
        (fname: string): Resource => $r('app.string.message_at_in_forum', fname), 'at_',
        (): void => {
          this.loadAts(true).catch((err: Error) => {
            Logger.error(TAG, `[MessagePage] retry failed: ${err.message}`);
          });
        },
        (): void => {
          this.loadAts(false).catch((err: Error) => {
            Logger.error(TAG, `[MessagePage] load more failed: ${err.message}`);
          });
        })
    }
    .onRefreshing(() => {
      // #121 触感反馈：下拉刷新触发轻震动
      VibratorUtil.light();
      // #137 下拉触发刷新：复用 loadAts(true)，防抖由 loading 锁保证
      this.loadAts(true).catch((err: Error) => {
        Logger.error(TAG, `[MessagePage] onRefreshing loadAts failed: ${err.message}`);
      });
    })
  }

  /**
   * 参数化消息 Tab 内容（H11 去重：合并原 ReplysTab/AtsTab 的四态分支树与列表）
   * 含 loading / error / empty / list 四种状态
   *
   * @param state      目标 Tab 的列表状态
   * @param emptyText  空列表文案资源
   * @param inForumFmt "在{吧名}中回复了你/@了你"文案资源工厂（两 Tab 唯一文案差异）
   * @param keyPrefix  LazyForEach 键前缀（reply_/at_）
   * @param onRetry    首屏失败重试回调
   * @param onLoadMore 加载更多回调（点击 footer 与 onReachEnd 共用）
   */
  @Builder
  MessageTabContent(state: MessageTabState, emptyText: ResourceStr,
    inForumFmt: (fname: string) => Resource, keyPrefix: string,
    onRetry: () => void, onLoadMore: () => void) {
    if (state.loading && state.dataSource.totalCount() === 0) {
      // 首屏加载中
      Column() {
        LoadingProgress()
          .width(32)
          .height(32)
          .color(this.themeState.primary)
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    } else if (state.error.length > 0 && state.dataSource.totalCount() === 0) {
      // 首屏加载失败
      Column() {
        Text(getResourceString($r('app.string.message_load_failed')))
          .fontSize(14)
          .fontColor($r('app.color.text_caption'))
        Text(state.error)
          .fontSize(12)
          .fontColor($r('app.color.text_caption'))
          .margin({ top: 4 })
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(getResourceString($r('app.string.retry')))
          .fontSize(14)
          .fontColor(this.themeState.primary)
          .margin({ top: 12 })
          .hitTestBehavior(HitTestMode.Block)
          .onClick(() => onRetry())
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ left: 32, right: 32 })
    } else if (state.dataSource.totalCount() === 0) {
      // 空列表
      Column() {
        Text(emptyText)
          .fontSize(14)
          .fontColor($r('app.color.text_caption'))
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    } else {
      List({ space: 0 }) {
        LazyForEach(state.dataSource, (msg: ReplyMessage | AtMessage) => {
          ListItem() {
            this.MessageItem(msg, inForumFmt)
          }
        }, (msg: ReplyMessage | AtMessage) => `${keyPrefix}${msg.pid}`)

        // 加载更多 / 已加载完毕提示
        ListItem() {
          if (state.loadingMore) {
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
          } else if (!state.hasMore) {
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
                .fontColor(this.themeState.primary)
            }
            .width('100%')
            .height(48)
            .justifyContent(FlexAlign.Center)
            .hitTestBehavior(HitTestMode.Block)
            .onClick(() => onLoadMore())
          }
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.page_background'))
      .scrollBar(BarState.Off)
      // Refresh 子组件禁用 Spring 边缘效果，避免与 Refresh 下拉手势冲突
      .edgeEffect(EdgeEffect.None)
      .cachedCount(5)
      .onReachEnd(() => {
        // onReachEnd 回调不处理 async 返回值，需 catch 避免 unhandled rejection
        onLoadMore()
      })
    }
  }

  /**
   * 消息列表项（H11 去重：合并原 ReplyItem/AtItem，仅"回复了你/@了你"文案资源不同）
   * 头像 + 昵称 + 时间 + 贴吧名 + 内容预览
   */
  @Builder
  MessageItem(msg: ReplyMessage | AtMessage, inForumFmt: (fname: string) => Resource) {
    Row() {
      // #81 接入图片加载策略：shouldLoad=false 时返回空串，Image 组件显示 alt 占位图
      Image(getAvatarImageUrl(getAvatarUrl(msg.user.portrait, 's'), this.imageLoadTypeState.value, this.isWifiState.value))
        .width(40)
        .height(40)
        .borderRadius(20)
        .objectFit(ImageFit.Cover)
        .backgroundColor($r('app.color.input_background'))
        .alt($r('app.media.startIcon'))
        // A5 图片优化：消息列表头像，同步加载避免闪烁 + 低质量插值 + 错误兜底
        .syncLoad(true)
        .interpolation(ImageInterpolation.Low)
        .onError(() => { /* 消息头像加载失败静默处理 */ })
        .hitTestBehavior(HitTestMode.Transparent)

      Column() {
        // 昵称 + 时间
        Row() {
          Text(msg.user.getDisplayName())
            .fontSize(14)
            .fontWeight(600)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)

          Text(formatRelativeTime(msg.createTime))
            .fontSize(12)
            .fontColor($r('app.color.text_caption'))
            .margin({ left: 8 })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        // "在 {贴吧名} 中回复了你/@了你"
        if (msg.fname.length > 0) {
          Text(getResourceString(inForumFmt(msg.fname)))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 4 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }

        // 内容预览
        if (msg.text.length > 0) {
          Text(msg.text)
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 4 })
            .maxLines(2)
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
        // A5 图片优化：本地 SVG 图标，同步加载避免闪烁 + 低质量插值
        .syncLoad(true)
        .interpolation(ImageInterpolation.Low)
        .hitTestBehavior(HitTestMode.Transparent)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .alignItems(VerticalAlign.Center)
    .hitTestBehavior(HitTestMode.Transparent)
    .onClick(() => this.navigateToThread(msg.tid))
  }
}
