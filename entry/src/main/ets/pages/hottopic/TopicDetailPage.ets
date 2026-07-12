/**
 * 话题详情页（对齐 Android TopicDetailPage.kt）
 * 入口：FavoritePage HotTab 话题榜点击
 * 数据来源：TiebaAPI.getTopicDetail（GET /mo/q/newtopic/topicDetail，web JSON）
 *
 * UI 结构：
 *   - 顶部导航栏（返回 + 话题标题）
 *   - 话题头部（话题名 + 讨论数 + 描述 + 话题图片）
 *   - 相关帖子列表（FeedCard 样式，点击跳转 ThreadPage）
 *   - 下拉刷新 + 上拉加载更多（pn 分页）
 */

import { AppStorageV2 } from '@kit.ArkUI';
import { HdsNavDestination } from '@kit.UIDesignKit';
import { TiebaAPI } from '../../api/TiebaAPI';
import { ImageLoadTypeState, IsWifiState, SafeBottomState } from '../../model/AppStorageV2Models';
import { TopicDetailResult, TopicInfo, TopicThread } from '../../model/TopicDetailModels';
import { LoadingView } from '../../components/LoadingView';
import { getResourceString } from '../../utils/ResourceUtil';
import { getAvatarUrl } from '../../utils/AvatarUtil';
import { getAvatarImageUrl } from '../../utils/ImageLoadUtil';
import { CommonDataSource } from '../../utils/CommonDataSource';
import { getStatusBarHeight } from '../../utils/StatusBarUtil';
import { connectTheme, ThemeState } from '../../theme/ThemeManager';
import { RouterUtil, ThreadNavParams, TopicDetailNavParams } from '../../utils/RouterUtil';

// #165 [A4-S5] Navigation 路由表 @Builder：供 router_map.json 的 buildFunction 引用
@Builder
export function TopicDetailPageBuilder() {
  TopicDetailPage()
}

@ComponentV2
export struct TopicDetailPage {
  @Local topicId: string = '';
  @Local topicName: string = '';
  // #165 滚动器，绑定到 HdsNavDestination.bindToScrollable 实现标题栏滚动动态模糊
  private scroller: Scroller = new Scroller();

  // 数据状态
  @Local topicInfo: TopicInfo = new TopicInfo();
  @Local threadList: TopicThread[] = [];
  @Local isLoading: boolean = false;
  @Local isRefreshing: boolean = false;
  @Local isLoadingMore: boolean = false;
  @Local hasMore: boolean = true;
  @Local errorMessage: string = '';
  @Local currentPage: number = 1;

  // 帖子列表 LazyForEach 数据源（与 FollowForumsPage 一致，配合 cachedCount(5) 按需渲染）
  private threadDataSource: CommonDataSource<TopicThread> = new CommonDataSource<TopicThread>();

  // 图片加载策略
  @Local imageLoadTypeState: ImageLoadTypeState = AppStorageV2.connect(ImageLoadTypeState, 'imageLoadType', () => new ImageLoadTypeState())!;
  @Local isWifiState: IsWifiState = AppStorageV2.connect(IsWifiState, 'isWifi', () => new IsWifiState())!;
  @Local themeState: ThemeState = connectTheme();
  // 状态栏高度（vp），沉浸式避让状态栏，默认 36，aboutToAppear 动态获取
  @Local statusBarHeight: number = 36;

  private readonly pageSize: number = 10;

  private showToast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message });
  }

  async aboutToAppear(): Promise<void> {
    // #165 路由迁移：router.getParams() → NavPathStack.getParamByName()
    // SDK 返回 Array<unknown>，ArkTS 不支持 unknown，用 as Object[] 断言
    // 注意：参数读取必须在任何 await 之前，避免 await 挂起期间其他代码用默认空 topicId 发请求
    // （对齐 ForumPage 的正确做法，修复 ThreadPage 350004 同类时序问题）
    const paramsStack: Object[] = RouterUtil.getStack().getParamByName(RouterUtil.ROUTE_TOPIC_DETAIL_PAGE) as Object[];
    if (paramsStack && paramsStack.length > 0) {
      const params = paramsStack[paramsStack.length - 1] as TopicDetailNavParams;
      if (params) {
        this.topicId = params.topicId;
        this.topicName = params.topicName;
      }
    }

    if (this.topicId.length > 0) {
      this.loadTopicDetail(true).catch((err: Error) => {
        console.error(`[TiebaLite/TopicDetailPage] loadTopicDetail failed: ${err.message}`);
      });
    } else {
      // topicId 为空时直接报错，避免空请求
      this.errorMessage = getResourceString($r('app.string.topic_detail_id_empty'));
    }
    // 获取状态栏高度（沉浸式避让状态栏，对齐 HomePage/ThreadPage 等页面做法）
    // 失败不阻塞后续加载，保留默认值 36
    // 放在参数读取+loadTopicDetail 之后，避免 await 挂起期间参数未就绪
    try {
      this.statusBarHeight = await getStatusBarHeight(getContext(this));
    } catch (err) {
      console.error(`[TopicDetailPage] getStatusBarHeight failed: ${(err as Error).message}`);
    }
  }

  /** 加载话题详情（首页/刷新/加载更多） */
  async loadTopicDetail(isRefresh: boolean): Promise<void> {
    if (this.isLoading || this.isLoadingMore) {
      return;
    }
    if (!isRefresh && !this.hasMore) {
      return;
    }
    if (this.topicId.length === 0) {
      this.errorMessage = getResourceString($r('app.string.topic_detail_id_empty'));
      return;
    }

    if (isRefresh) {
      this.isRefreshing = true;
      this.errorMessage = '';
      this.currentPage = 1;
    } else {
      this.isLoadingMore = true;
    }

    try {
      const offset: number = isRefresh ? 0 : (this.currentPage - 1) * this.pageSize;
      // lastId：首页空字符串，加载更多用最后一项 feedId（数组非空时才访问）
      const lastId: string = isRefresh ? '' : (this.threadList.length > 0 ? this.threadList[this.threadList.length - 1].feedId.toString() : '');
      const result: TopicDetailResult = await TiebaAPI.getTopicDetail({
        topicId: this.topicId,
        topicName: this.topicName,
        page: this.currentPage,
        pageSize: this.pageSize,
        offset: offset,
        lastId: lastId
      });

      this.topicInfo = result.topicInfo;
      this.hasMore = result.hasMore;
      this.currentPage = result.currentPage + 1;

      if (isRefresh) {
        this.threadList = result.relateThread;
        // LazyForEach 整体刷新（首次加载/下拉刷新场景）
        this.threadDataSource.setData(this.threadList);
      } else {
        // 去重（按 feedId），收集新增项用于 appendData 增量刷新
        const existingIds: Set<number> = new Set<number>();
        for (let i = 0; i < this.threadList.length; i++) {
          existingIds.add(this.threadList[i].feedId);
        }
        const newThreads: TopicThread[] = [];
        for (let i = 0; i < result.relateThread.length; i++) {
          const t: TopicThread = result.relateThread[i];
          if (!existingIds.has(t.feedId)) {
            this.threadList.push(t);
            newThreads.push(t);
          }
        }
        // 增量通知 LazyForEach，避免全量 reload 引起整列 diff（仅刷新新增区域）
        this.threadDataSource.appendData(newThreads);
      }
    } catch (err) {
      const msg: string = (err as Error).message || getResourceString($r('app.string.topic_detail_unknown_error'));
      console.error(`[TiebaLite/TopicDetailPage] load failed: ${msg}`);
      if (isRefresh) {
        this.errorMessage = msg;
      } else {
        this.showToast(msg);
      }
    } finally {
      // finally 只重置本次实际设置的标志，避免误清其他状态的语义
      if (isRefresh) {
        this.isRefreshing = false;
      } else {
        this.isLoadingMore = false;
      }
    }
  }

  navigateToThread(tid: number): void {
    if (tid <= 0) {
      return;
    }
    // #163 路由迁移：router.pushUrl → RouterUtil.push
    RouterUtil.push(RouterUtil.ROUTE_THREAD_PAGE, new ThreadNavParams(tid));
  }

  /** 格式化讨论数显示 */
  private formatDiscussNum(num: number): string {
    if (num >= 10000) {
      return getResourceString($r('app.string.topic_detail_wan_format', (num / 10000).toFixed(1)));
    }
    return num.toString();
  }

  build() {
    // #165 [A4-S5] HdsNavDestination 包装：替代 @Entry + router，纳入 HdsNavigation 路由栈
    // 顶部栏简单但标题动态（topicName 优先），用 hideTitleBar(true) 保留自定义顶部栏
    HdsNavDestination() {
      Column() {
        // 顶部导航栏
        Row() {
          Image($r('app.media.ic_back'))
            .width(24)
            .height(24)
            .fillColor($r('app.color.text_primary'))
            // A5 图片优化：SVG 图标同步加载
            .syncLoad(true)
            // A5 图片优化：SVG 图标低质量插值
            .interpolation(ImageInterpolation.Low)
            .onClick(() => RouterUtil.back())

          Text(this.topicName.length > 0 ? this.topicName : getResourceString($r('app.string.topic_detail_title')))
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
            .margin({ left: 12 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          // 右侧占位
          Blank().width(24)
        }
        .width('100%')
        .height(56 + this.statusBarHeight)
        .padding({ left: 16, right: 16, top: this.statusBarHeight })
        .alignItems(VerticalAlign.Center)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
        .backgroundColor($r('app.color.page_background'))

        // 内容区
        if (this.errorMessage.length > 0 && this.threadList.length === 0) {
          // 错误状态
          Column() {
            Text(this.errorMessage)
              .fontSize(14)
              .fontColor($r('app.color.text_caption'))
              .textAlign(TextAlign.Center)
              .margin({ left: 32, right: 32 })
            Text(getResourceString($r('app.string.retry')))
              .fontSize(14)
              .fontColor(this.themeState.primary)
              .margin({ top: 12 })
              .hitTestBehavior(HitTestMode.Block)
              .onClick(() => this.loadTopicDetail(true).catch((err: Error) => {
                console.error(`[TiebaLite/TopicDetailPage] retry failed: ${err.message}`);
              }))
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else if (this.isRefreshing && this.threadList.length === 0) {
          // 首次加载
          Column() {
            LoadingView({ message: getResourceString($r('app.string.loading')) })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.threadList.length === 0) {
          // 空状态
          Column() {
            Text(getResourceString($r('app.string.topic_detail_empty')))
              .fontSize(14)
              .fontColor($r('app.color.text_caption'))
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          // 列表区
          List({ space: 8, scroller: this.scroller }) {
            // 话题头部
            ListItem() {
              this.TopicHeader()
            }

            // 相关帖子标题
            ListItem() {
              Text(getResourceString($r('app.string.topic_detail_relate_thread')))
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
                .width('100%')
                .padding({ left: 16, top: 12, bottom: 4 })
            }

            // 帖子列表（LazyForEach 按需渲染，配合 List.cachedCount(5) 预加载 5 条）
            LazyForEach(this.threadDataSource, (thread: TopicThread) => {
              ListItem() {
                this.TopicThreadItem(thread)
              }
            }, (thread: TopicThread) => thread.feedId.toString())

            // 加载更多 / 加载中 / 已加载完毕
            ListItem() {
              if (this.isLoadingMore) {
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
              } else if (this.hasMore) {
                Row() {
                  Text(getResourceString($r('app.string.click_to_load_more')))
                    .fontSize(13)
                    .fontColor(this.themeState.primary)
                }
                .width('100%')
                .height(48)
                .justifyContent(FlexAlign.Center)
                .hitTestBehavior(HitTestMode.Block)
                .onClick(() => this.loadTopicDetail(false).catch((err: Error) => {
                  console.error(`[TiebaLite/TopicDetailPage] loadMore failed: ${err.message}`);
                }))
              } else {
                Text(getResourceString($r('app.string.no_more_data')))
                  .fontSize(12)
                  .fontColor($r('app.color.text_caption'))
                  .width('100%')
                  .height(48)
                  .textAlign(TextAlign.Center)
              }
            }
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
          .cachedCount(5)
          .backgroundColor($r('app.color.page_background'))
          .padding({ left: 16, right: 16 })
          .onReachEnd(() => {
            if (this.hasMore && !this.isLoadingMore) {
              this.loadTopicDetail(false).catch((err: Error) => {
                console.error(`[TiebaLite/TopicDetailPage] onReachEnd failed: ${err.message}`);
              });
            }
          })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.page_background'))
    }
    .hideTitleBar(true)
    .bindToScrollable([this.scroller])
    .backgroundColor($r('app.color.page_background'))
  }

  /** 话题头部 */
  @Builder
  TopicHeader() {
    Column() {
      // 话题图片（如有）
      if (this.topicInfo.topicImage.length > 0) {
        Image(this.topicInfo.topicImage)
          .width('100%')
          .height(160)
          .objectFit(ImageFit.Cover)
          .borderRadius(12)
          .backgroundColor($r('app.color.input_background'))
          .alt($r('app.media.startIcon'))
          // A5 图片优化：话题图片异步加载
          .syncLoad(false)
          // A5 图片优化：话题图片高质量插值
          .interpolation(ImageInterpolation.High)
          // A5 图片优化：话题图片自适应尺寸
          .autoResize(true)
          // A5 图片优化：话题图片加载失败静默
          .onError(() => { /* 话题图片加载失败静默处理 */ })
          // #92 HitTestMode.Transparent：让触控穿透到父 List，避免 fling 期间碰到图片导致触控丢失
          .hitTestBehavior(HitTestMode.Transparent)
      }

      // 话题名
      Text(this.topicInfo.topicName)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .margin({ top: 12 })

      // 讨论数
      Row() {
        Text(getResourceString($r('app.string.topic_detail_discuss_format', this.formatDiscussNum(this.topicInfo.discussNum))))
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      .margin({ top: 4 })

      // 话题描述（如有）
      if (this.topicInfo.topicDesc.length > 0) {
        Text(this.topicInfo.topicDesc)
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .margin({ top: 8 })
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(10)
    // #93 圆角裁剪：ArkUI 中 Column 的 borderRadius 仅设置背景色圆角，
    // 不会自动裁剪子内容（如 Image 的方形 alt 占位图会溢出覆盖圆角）
    // 必须配合 clip(true) 强制将子内容裁剪到圆角范围内，圆角才视觉生效
    .clip(true)
  }

  /** 帖子项 */
  @Builder
  TopicThreadItem(thread: TopicThread) {
    Row() {
      Column() {
        // 帖子标题
        Text(thread.title.length > 0 ? thread.title : thread.abstractText)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        // 摘要（如有且与标题不同）
        if (thread.abstractText.length > 0 && thread.abstractText !== thread.title) {
          Text(thread.abstractText)
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 4 })
            .width('100%')
        }

        // 底部信息：吧名 + 回复数 + 点赞数
        Row() {
          if (thread.forumName.length > 0) {
            Text(thread.forumName)
              .fontSize(11)
              .fontColor(this.themeState.primary)
              .backgroundColor($r('app.color.input_background'))
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .borderRadius(4)
              .margin({ right: 8 })
          }
          Text(getResourceString($r('app.string.topic_detail_reply_count', thread.replyNum)))
            .fontSize(11)
            .fontColor($r('app.color.text_caption'))
            .margin({ right: 8 })
          Text(getResourceString($r('app.string.topic_detail_agree_count', thread.agreeNum)))
            .fontSize(11)
            .fontColor($r('app.color.text_caption'))
        }
        .width('100%')
        .margin({ top: 8 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      // 右侧缩略图（如有媒体）
      if (thread.media.length > 0) {
        Image(getAvatarImageUrl(thread.media[0].smallPic, this.imageLoadTypeState.value, this.isWifiState.value))
          .width(72)
          .height(72)
          .borderRadius(8)
          .objectFit(ImageFit.Cover)
          .backgroundColor($r('app.color.input_background'))
          .alt($r('app.media.startIcon'))
          .margin({ left: 12 })
          // A5 图片优化：缩略图同步加载
          .syncLoad(true)
          // A5 图片优化：缩略图低质量插值
          .interpolation(ImageInterpolation.Low)
          // A5 图片优化：缩略图加载失败静默
          .onError(() => { /* 缩略图加载失败静默处理 */ })
          // #92 HitTestMode.Transparent：让触控穿透到父 List，避免 fling 期间碰到图片导致触控丢失
          .hitTestBehavior(HitTestMode.Transparent)
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(10)
    // #93 配合 borderRadius 裁剪子内容（右侧缩略图 Image 的方形 alt 不再溢出圆角）
    .clip(true)
    // #93 HitTestMode.Transparent：让卡片 onClick 仍能触发，同时让触控穿透到父 List
    // Block 会阻止事件向父 List 传播，导致 List 无法滑动（对齐 ThreadCard 的做法）
    .hitTestBehavior(HitTestMode.Transparent)
    .onClick(() => this.navigateToThread(thread.tid))
  }
}
