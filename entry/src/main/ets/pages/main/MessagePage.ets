// 消息页（"消息"tab）
// UI：iOS Large Title + Tabs 切换"回复我的"/"@我的"
// 数据：TiebaAPI.getReplys（protobuf /c/u/feed/replyme?cmd=303007）
//       TiebaAPI.getAts（form POST /c/u/feed/atme，JSON 响应）
// 列表：List + LazyForEach + onReachEnd 分页加载
// 点击：跳转 ThreadPage（tid 路由参数）

import { router } from '@kit.ArkUI';
import { TiebaAPI, AtMessage } from '../../api/TiebaAPI';
import { ReplyMessage } from '../../proto/MessageProto';
import { getResourceString } from '../../utils/ResourceUtil';
import { getStatusBarHeight } from '../../utils/StatusBarUtil';
import { getAvatarUrl } from '../../utils/AvatarUtil';
import { getAvatarImageUrl } from '../../utils/ImageLoadUtil';
import { formatRelativeTime } from '../../utils/TimeUtil';
import { CommonDataSource } from '../../utils/CommonDataSource';

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
@Component
export struct MessagePage {
  // 状态栏高度（vp），沉浸式避让状态栏，默认 36，aboutToAppear 动态获取
  @State statusBarHeight: number = 36;
  // 当前 Tab 索引：0=回复我的，1=@我的
  @State currentTab: number = 0;
  // bduss 是否存在（用于判断是否已登录），与 ProfilePage 联动登出
  @StorageProp('bduss') bduss: string = '';
  // #81 图片加载策略：通过 AppStorage 共享，SettingsPage 修改后自动响应
  @StorageProp('imageLoadType') imageLoadType: number = 0;
  @StorageProp('isWifi') isWifi: boolean = false;

  // ===== 回复我的 列表状态 =====
  replysDataSource: CommonDataSource<ReplyMessage> = new CommonDataSource<ReplyMessage>();
  @State replysLoading: boolean = false;
  @State replysLoadingMore: boolean = false;
  @State replysHasMore: boolean = false;
  @State replysPn: number = 1;
  @State replysError: string = '';
  // 标记首屏是否已加载过，避免切换 Tab 时重复触发首屏加载
  @State replysLoaded: boolean = false;

  // ===== @我的 列表状态 =====
  atsDataSource: CommonDataSource<AtMessage> = new CommonDataSource<AtMessage>();
  @State atsLoading: boolean = false;
  @State atsLoadingMore: boolean = false;
  @State atsHasMore: boolean = false;
  @State atsPn: number = 1;
  @State atsError: string = '';
  @State atsLoaded: boolean = false;

  /** Tabs 控制器 */
  private tabsController: TabsController = new TabsController();

  // Toast 提示 helper（API 12+ 推荐用 UIContext.getPromptAction() 替代全局 promptAction）
  private showToast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message });
  }

  async aboutToAppear(): Promise<void> {
    // 获取状态栏高度，失败不阻塞页面渲染，保留默认值 36
    try {
      this.statusBarHeight = await getStatusBarHeight(getContext(this));
    } catch (err) {
      console.error(`[MessagePage] getStatusBarHeight failed: ${(err as Error).message}`);
    }
    // 已登录则加载首屏数据（默认 Tab 0=回复我的）
    // 注意：aboutToAppear 时 @StorageProp('bduss') 可能还未填充（AppStorage 已写入但组件订阅首次回调时机晚）
    // 故此处用 AppStorage.get 直接读，避免首屏延迟
    const bdussValue: string = AppStorage.get<string>('bduss') || '';
    if (bdussValue.length > 0) {
      this.loadReplys(true).catch((err: Error) => {
        console.error(`[MessagePage] loadReplys initial failed: ${err.message}`);
      });
    }
  }

  /**
   * 加载回复我的列表
   *
   * @param isRefresh true=首屏/下拉刷新（重置 pn=1，清空错误），false=加载更多
   */
  async loadReplys(isRefresh: boolean): Promise<void> {
    if (this.bduss.length === 0) {
      this.replysError = getResourceString($r('app.string.message_login_required'));
      return;
    }
    if (isRefresh) {
      if (this.replysLoading) {
        return;
      }
      this.replysLoading = true;
      this.replysLoadingMore = false;
      this.replysError = '';
      this.replysPn = 1;
    } else {
      if (this.replysLoadingMore || !this.replysHasMore) {
        return;
      }
      this.replysLoadingMore = true;
    }
    try {
      const result = await TiebaAPI.getReplys(this.replysPn);
      if (isRefresh) {
        this.replysDataSource.setData(result.list);
      } else {
        this.replysDataSource.appendData(result.list);
      }
      this.replysHasMore = result.page.hasMore;
      this.replysPn = this.replysPn + 1;
      this.replysLoaded = true;
    } catch (err) {
      const msg: string = (err as Error).message || '';
      if (isRefresh) {
        this.replysError = msg;
      } else {
        this.showToast(msg);
      }
    } finally {
      this.replysLoading = false;
      this.replysLoadingMore = false;
    }
  }

  /**
   * 加载@我的列表
   *
   * @param isRefresh true=首屏/下拉刷新（重置 pn=1，清空错误），false=加载更多
   */
  async loadAts(isRefresh: boolean): Promise<void> {
    if (this.bduss.length === 0) {
      this.atsError = getResourceString($r('app.string.message_login_required'));
      return;
    }
    if (isRefresh) {
      if (this.atsLoading) {
        return;
      }
      this.atsLoading = true;
      this.atsLoadingMore = false;
      this.atsError = '';
      this.atsPn = 1;
    } else {
      if (this.atsLoadingMore || !this.atsHasMore) {
        return;
      }
      this.atsLoadingMore = true;
    }
    try {
      const result = await TiebaAPI.getAts(this.atsPn);
      if (isRefresh) {
        this.atsDataSource.setData(result.list);
      } else {
        this.atsDataSource.appendData(result.list);
      }
      this.atsHasMore = result.page.hasMore;
      this.atsPn = this.atsPn + 1;
      this.atsLoaded = true;
    } catch (err) {
      const msg: string = (err as Error).message || '';
      if (isRefresh) {
        this.atsError = msg;
      } else {
        this.showToast(msg);
      }
    } finally {
      this.atsLoading = false;
      this.atsLoadingMore = false;
    }
  }

  /** Tab 切换处理：首次切到 Tab 时触发首屏加载 */
  onTabChange(index: number): void {
    this.currentTab = index;
    if (index === 0 && !this.replysLoaded && this.bduss.length > 0) {
      this.loadReplys(true).catch((err: Error) => {
        console.error(`[MessagePage] loadReplys on tab switch failed: ${err.message}`);
      });
    } else if (index === 1 && !this.atsLoaded && this.bduss.length > 0) {
      this.loadAts(true).catch((err: Error) => {
        console.error(`[MessagePage] loadAts on tab switch failed: ${err.message}`);
      });
    }
  }

  /** 跳转帖子详情页（tid 路由参数） */
  navigateToThread(tid: number): void {
    if (tid <= 0) {
      return;
    }
    router.pushUrl({
      url: 'pages/thread/ThreadPage',
      params: { tid: tid }
    }).catch((err: Error) => {
      console.error(`[MessagePage] navigate to thread failed: ${err.message}`);
    });
  }

  build() {
    Column() {
      // iOS Large Title 顶部栏（34px Bold，对齐 HomePage/ProfilePage 风格）
      Row() {
        Text($r('app.string.message_page_title'))
          .fontSize(34)
          .fontWeight(800)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
      }
      .width('100%')
      .height(56 + this.statusBarHeight)
      .padding({ left: 16, right: 16, top: this.statusBarHeight, bottom: 8 })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
      .alignItems(VerticalAlign.Center)

      // 未登录态：占位提示（与原占位页保持一致的视觉）
      if (this.bduss.length === 0) {
        Column() {
          Image($r('app.media.ic_message'))
            .width(64)
            .height(64)
            .fillColor($r('app.color.text_caption'))
            .opacity(0.4)
            .margin({ bottom: 20 })
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
          .tabBar(this.buildTabBar($r('app.string.message_tab_reply'), this.currentTab === 0))

          TabContent() {
            this.AtsTab()
          }
          .tabBar(this.buildTabBar($r('app.string.message_tab_at'), this.currentTab === 1))
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
    // 不加底部 padding：悬浮 TabBar 遮挡内容可接受（对齐 ProfilePage 决策）
    .backgroundColor($r('app.color.page_background'))
  }

  /** 构建 TabBar：文字 + 选中下划线 */
  @Builder
  buildTabBar(label: ResourceStr, isActive: boolean) {
    Column() {
      Text(label)
        .fontSize(15)
        .fontWeight(isActive ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(isActive ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
        .height(42)

      // 选中下划线
      Divider()
        .color(isActive ? $r('app.color.primary') : Color.Transparent)
        .strokeWidth(2)
        .width(isActive ? 24 : 0)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }

  /** 回复我的 Tab 内容（含 loading / error / empty / list 四种状态） */
  @Builder
  ReplysTab() {
    if (this.replysLoading && this.replysDataSource.totalCount() === 0) {
      // 首屏加载中
      Column() {
        LoadingProgress()
          .width(32)
          .height(32)
          .color($r('app.color.primary'))
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    } else if (this.replysError.length > 0 && this.replysDataSource.totalCount() === 0) {
      // 首屏加载失败
      Column() {
        Text(getResourceString($r('app.string.message_load_failed')))
          .fontSize(14)
          .fontColor($r('app.color.text_caption'))
        Text(this.replysError)
          .fontSize(12)
          .fontColor($r('app.color.text_caption'))
          .margin({ top: 4 })
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(getResourceString($r('app.string.retry')))
          .fontSize(14)
          .fontColor($r('app.color.primary'))
          .margin({ top: 12 })
          .hitTestBehavior(HitTestMode.Block)
          .onClick(() => this.loadReplys(true).catch((err: Error) => {
            console.error(`[MessagePage] loadReplys retry failed: ${err.message}`);
          }))
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ left: 32, right: 32 })
    } else if (this.replysDataSource.totalCount() === 0) {
      // 空列表
      Column() {
        Text(getResourceString($r('app.string.message_reply_empty')))
          .fontSize(14)
          .fontColor($r('app.color.text_caption'))
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    } else {
      // 列表
      List({ space: 0 }) {
        LazyForEach(this.replysDataSource, (msg: ReplyMessage) => {
          ListItem() {
            this.ReplyItem(msg)
          }
        }, (msg: ReplyMessage) => `reply_${msg.pid}`)

        // 加载更多 / 已加载完毕提示
        ListItem() {
          if (this.replysLoadingMore) {
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
          } else if (!this.replysHasMore) {
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
            .onClick(() => this.loadReplys(false).catch((err: Error) => {
              console.error(`[MessagePage] loadReplys more failed: ${err.message}`);
            }))
          }
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.page_background'))
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .cachedCount(5)
      .onReachEnd(() => {
        // onReachEnd 回调不处理 async 返回值，需 catch 避免 unhandled rejection
        this.loadReplys(false).catch((err: Error) => {
          console.error(`[MessagePage] onReachEnd loadReplys failed: ${err.message}`);
        });
      })
    }
  }

  /** @我的 Tab 内容（含 loading / error / empty / list 四种状态） */
  @Builder
  AtsTab() {
    if (this.atsLoading && this.atsDataSource.totalCount() === 0) {
      Column() {
        LoadingProgress()
          .width(32)
          .height(32)
          .color($r('app.color.primary'))
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    } else if (this.atsError.length > 0 && this.atsDataSource.totalCount() === 0) {
      Column() {
        Text(getResourceString($r('app.string.message_load_failed')))
          .fontSize(14)
          .fontColor($r('app.color.text_caption'))
        Text(this.atsError)
          .fontSize(12)
          .fontColor($r('app.color.text_caption'))
          .margin({ top: 4 })
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(getResourceString($r('app.string.retry')))
          .fontSize(14)
          .fontColor($r('app.color.primary'))
          .margin({ top: 12 })
          .hitTestBehavior(HitTestMode.Block)
          .onClick(() => this.loadAts(true).catch((err: Error) => {
            console.error(`[MessagePage] loadAts retry failed: ${err.message}`);
          }))
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ left: 32, right: 32 })
    } else if (this.atsDataSource.totalCount() === 0) {
      Column() {
        Text(getResourceString($r('app.string.message_at_empty')))
          .fontSize(14)
          .fontColor($r('app.color.text_caption'))
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    } else {
      List({ space: 0 }) {
        LazyForEach(this.atsDataSource, (msg: AtMessage) => {
          ListItem() {
            this.AtItem(msg)
          }
        }, (msg: AtMessage) => `at_${msg.pid}`)

        ListItem() {
          if (this.atsLoadingMore) {
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
          } else if (!this.atsHasMore) {
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
            .onClick(() => this.loadAts(false).catch((err: Error) => {
              console.error(`[MessagePage] loadAts more failed: ${err.message}`);
            }))
          }
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.page_background'))
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .cachedCount(5)
      .onReachEnd(() => {
        this.loadAts(false).catch((err: Error) => {
          console.error(`[MessagePage] onReachEnd loadAts failed: ${err.message}`);
        });
      })
    }
  }

  /** 回复消息列表项（头像 + 昵称 + 时间 + 贴吧名 + 内容预览） */
  @Builder
  ReplyItem(msg: ReplyMessage) {
    Row() {
      // #81 接入图片加载策略：shouldLoad=false 时返回空串，Image 组件显示 alt 占位图
      Image(getAvatarImageUrl(getAvatarUrl(msg.user.portrait, 's'), this.imageLoadType, this.isWifi))
        .width(40)
        .height(40)
        .borderRadius(20)
        .objectFit(ImageFit.Cover)
        .backgroundColor($r('app.color.input_background'))
        .alt($r('app.media.startIcon'))
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

        // "在 {贴吧名} 中回复了你"
        if (msg.fname.length > 0) {
          Text(getResourceString($r('app.string.message_reply_in_forum', msg.fname)))
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
        .hitTestBehavior(HitTestMode.Transparent)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .alignItems(VerticalAlign.Center)
    .hitTestBehavior(HitTestMode.Transparent)
    .onClick(() => this.navigateToThread(msg.tid))
  }

  /** @我的消息列表项（与 ReplyItem 类似，提示文案改为"@了你"） */
  @Builder
  AtItem(msg: AtMessage) {
    Row() {
      Image(getAvatarImageUrl(getAvatarUrl(msg.user.portrait, 's'), this.imageLoadType, this.isWifi))
        .width(40)
        .height(40)
        .borderRadius(20)
        .objectFit(ImageFit.Cover)
        .backgroundColor($r('app.color.input_background'))
        .alt($r('app.media.startIcon'))
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

        // "在 {贴吧名} 中@了你"
        if (msg.fname.length > 0) {
          Text(getResourceString($r('app.string.message_at_in_forum', msg.fname)))
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

      Image($r('app.media.ic_chevron_right'))
        .width(16)
        .height(16)
        .fillColor($r('app.color.text_caption'))
        .hitTestBehavior(HitTestMode.Transparent)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .alignItems(VerticalAlign.Center)
    .hitTestBehavior(HitTestMode.Transparent)
    .onClick(() => this.navigateToThread(msg.tid))
  }
}
