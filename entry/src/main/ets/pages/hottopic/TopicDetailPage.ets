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

import { router } from '@kit.ArkUI';
import { TiebaAPI } from '../../api/TiebaAPI';
import { TopicDetailResult, TopicInfo, TopicThread } from '../../model/TopicDetailModels';
import { LoadingView } from '../../components/LoadingView';
import { getResourceString } from '../../utils/ResourceUtil';
import { getStatusBarHeight } from '../../utils/StatusBarUtil';
import { getAvatarUrl } from '../../utils/AvatarUtil';
import { getAvatarImageUrl } from '../../utils/ImageLoadUtil';

/** 路由参数 */
interface TopicDetailPageParams {
  topicId: string;
  topicName: string;
}

@Entry
@Component
struct TopicDetailPage {
  @State topicId: string = '';
  @State topicName: string = '';
  @State statusBarHeight: number = 36;

  // 数据状态
  @State topicInfo: TopicInfo = new TopicInfo();
  @State threadList: TopicThread[] = [];
  @State isLoading: boolean = false;
  @State isRefreshing: boolean = false;
  @State isLoadingMore: boolean = false;
  @State hasMore: boolean = true;
  @State errorMessage: string = '';
  @State currentPage: number = 1;

  // 图片加载策略
  @StorageProp('imageLoadType') imageLoadType: number = 0;
  @StorageProp('isWifi') isWifi: boolean = false;
  // #93 底部安全高度，避让系统手势条
  @StorageProp('safeBottom') safeBottom: number = 0;

  private readonly pageSize: number = 10;

  private showToast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message });
  }

  async aboutToAppear(): Promise<void> {
    try {
      this.statusBarHeight = await getStatusBarHeight(getContext(this));
    } catch (err) {
      console.error(`[TiebaLite/TopicDetailPage] getStatusBarHeight failed: ${(err as Error).message}`);
    }

    // 路由参数防御性解析（用户反馈"一点就闪退"，加 try-catch 兜底）
    try {
      const params = router.getParams() as TopicDetailPageParams;
      if (params) {
        this.topicId = params.topicId || '';
        this.topicName = params.topicName || '';
      }
    } catch (err) {
      console.error(`[TiebaLite/TopicDetailPage] parse router params failed: ${(err as Error).message}`);
    }

    if (this.topicId.length > 0) {
      this.loadTopicDetail(true).catch((err: Error) => {
        console.error(`[TiebaLite/TopicDetailPage] loadTopicDetail failed: ${err.message}`);
      });
    } else {
      // topicId 为空时直接报错，避免空请求
      this.errorMessage = '话题 ID 为空';
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
      this.errorMessage = '话题 ID 为空';
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

      // [TiebaLite/TopicDetailPage] 诊断日志：验证返回数据
      console.info(`[TiebaLite/TopicDetailPage] load isRefresh=${isRefresh} threadList=${result.relateThread.length} hasMore=${result.hasMore} page=${result.currentPage}`);

      this.topicInfo = result.topicInfo;
      this.hasMore = result.hasMore;
      this.currentPage = result.currentPage + 1;

      if (isRefresh) {
        this.threadList = result.relateThread;
      } else {
        // 去重（按 feedId）
        const existingIds: Set<number> = new Set<number>();
        for (let i = 0; i < this.threadList.length; i++) {
          existingIds.add(this.threadList[i].feedId);
        }
        for (let i = 0; i < result.relateThread.length; i++) {
          const t: TopicThread = result.relateThread[i];
          if (!existingIds.has(t.feedId)) {
            this.threadList.push(t);
          }
        }
      }
    } catch (err) {
      const msg: string = (err as Error).message || '未知错误';
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
    router.pushUrl({
      url: 'pages/thread/ThreadPage',
      params: { tid: tid.toString() }
    }).catch((err: Error) => {
      console.error(`[TiebaLite/TopicDetailPage] navigate to thread failed: ${err.message}`);
    });
  }

  /** 格式化讨论数显示 */
  private formatDiscussNum(num: number): string {
    if (num >= 10000) {
      return (num / 10000).toFixed(1) + '万';
    }
    return num.toString();
  }

  build() {
    Column() {
      // 顶部导航栏
      Row() {
        Image($r('app.media.ic_back'))
          .width(24)
          .height(24)
          .fillColor($r('app.color.text_primary'))
          .onClick(() => router.back())

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
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
      .alignItems(VerticalAlign.Center)
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
            .fontColor($r('app.color.primary'))
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
        List({ space: 8 }) {
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

          // 帖子列表
          ForEach(this.threadList, (thread: TopicThread) => {
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
                  .fontColor($r('app.color.primary'))
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
        // #93 遮罩修复：List backgroundColor 与外层 Column 一致（page_background #F2F2F7），
        // 让 List 底部 safeBottom padding 区域颜色与外层统一，避免显示系统默认色形成"灰色遮罩"
        // 对齐 UserProfilePage.ets L327-L328 处理方式
        .backgroundColor($r('app.color.page_background'))
        .padding({ left: 16, right: 16, bottom: this.safeBottom + 16 })
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
    // #93 背景延伸到系统手势条区域，消除底部遮罩
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
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
              .fontColor($r('app.color.primary'))
              .backgroundColor($r('app.color.input_background'))
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .borderRadius(4)
              .margin({ right: 8 })
          }
          Text(`${thread.replyNum}回复`)
            .fontSize(11)
            .fontColor($r('app.color.text_caption'))
            .margin({ right: 8 })
          Text(`${thread.agreeNum}赞`)
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
        Image(getAvatarImageUrl(thread.media[0].smallPic, this.imageLoadType, this.isWifi))
          .width(72)
          .height(72)
          .borderRadius(8)
          .objectFit(ImageFit.Cover)
          .backgroundColor($r('app.color.input_background'))
          .alt($r('app.media.startIcon'))
          .margin({ left: 12 })
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
    .hitTestBehavior(HitTestMode.Block)
    .onClick(() => this.navigateToThread(thread.tid))
  }
}
