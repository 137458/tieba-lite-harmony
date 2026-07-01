import { router, promptAction } from '@kit.ArkUI';
import { TiebaAPI } from '../../api/TiebaAPI';
import { PostInfo, MediaInfo } from '../../model/ForumModels';
import { LoadingView } from '../../components/LoadingView';
import { ErrorView } from '../../components/ErrorView';
import { BaseViewModel, FetchDataResult } from '../../viewmodel/BaseViewModel';
import { getResourceString } from '../../utils/ResourceUtil';
import { CommonDataSource } from '../../utils/CommonDataSource';
import { getStatusBarHeight } from '../../utils/StatusBarUtil';

class ThreadViewModel extends BaseViewModel<PostInfo> {
  private tid: number = 0;
  // 主题帖标题（从 PbPageResult.thread.title 提取，syncState 读取）
  threadTitle: string = '';
  // 主题帖总回复数（从 PbPageResult.thread.replyNum 提取，修复评论数显示为 0 问题）
  threadReplyNum: number = 0;

  setTid(id: number): void {
    this.tid = id;
  }

  protected async fetchData(page: number, isRefresh: boolean): Promise<FetchDataResult<PostInfo>> {
    // getPosts 返回 PbPageResult（含 posts 分页 + thread 主题帖信息）
    const result = await TiebaAPI.getPosts(this.tid, page, false);
    this.threadTitle = result.thread.title;
    // 仅首页加载时同步总回复数（避免分页加载覆盖）
    if (isRefresh) {
      this.threadReplyNum = result.thread.replyNum;
    }
    return {
      list: result.posts.list,
      hasMore: result.posts.hasMore,
      currentPage: result.posts.currentPage
    };
  }
}

/**
 * 楼层卡片（issue #31 拆为独立 @Component）
 * PostInfo 已 @Observed，用 @ObjectLink 引用 dataSource 内部对象，
 * 修改 post.isAgreed/agreeNum 等字段会自动局部刷新，无需 slice() 触发重建
 */
@Component
struct PostItem {
  @ObjectLink post: PostInfo;
  @Prop isFirst: boolean = false;
  onAgreeClick?: (post: PostInfo) => void;
  onDisagreeClick?: (post: PostInfo) => void;
  onCommentClick?: () => void;

  build() {
    Column() {
      // 头像 + 名字 + 楼层 + 楼主标签
      Row() {
        Image(this.post.author.avatar)
          .width(40)
          .height(40)
          .borderRadius(20)
          .objectFit(ImageFit.Cover)

        Column() {
          Text(this.post.author.name)
            .fontSize(15)
            .fontColor($r('app.color.text_primary'))
            .fontWeight(FontWeight.Medium)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text($r('app.string.floor_label', this.post.floor))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
        }
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 12 })
        .layoutWeight(1)

        if (this.isFirst) {
          Text($r('app.string.author_label'))
            .fontSize(11)
            .fontColor($r('app.color.primary'))
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .border({ width: 0.5, color: $r('app.color.primary'), radius: 4 })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text(this.post.content)
        .fontSize(15)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: 12 })
        .width('100%')

      if (this.post.mediaList.length > 0) {
        Row() {
          ForEach(this.post.mediaList.slice(0, 3), (media: MediaInfo, index: number) => {
            Image(media.thumbnail.length > 0 ? media.thumbnail : media.url)
              .width(100)
              .height(100)
              .objectFit(ImageFit.Cover)
              .borderRadius(4)
              .margin({ right: index < 2 ? 4 : 0 })
              .onClick(() => {
                // 打开图片查看器（issue #15）
                router.pushUrl({
                  url: 'pages/viewer/ImageViewerPage',
                  params: {
                    urls: this.post.mediaList.map((m: MediaInfo) => m.url),
                    index: index
                  }
                });
              })
          }, (media: MediaInfo) => media.url)
        }
        .width('100%')
        .margin({ top: 8 })
      }

      // 底部操作栏：左[👍数字][踩数字] 右[评论数字]（issue #17）
      Row() {
        // 左侧：赞 + 踩
        Row() {
          // 赞按钮
          Row() {
            Text('👍')
              .fontSize(14)
              .opacity(this.post.isAgreed ? 1.0 : 0.6)
            Text(this.post.agreeNum.toString())
              .fontSize(13)
              .fontColor(this.post.isAgreed ? $r('app.color.primary') : $r('app.color.text_secondary'))
              .margin({ left: 4 })
          }
          .alignItems(VerticalAlign.Center)
          .onClick(() => {
            if (this.onAgreeClick) {
              this.onAgreeClick(this.post);
            }
          })

          // 踩按钮
          Row() {
            Text('👎')
              .fontSize(14)
              .opacity(this.post.isDisagreed ? 1.0 : 0.6)
            Text(this.post.disagreeNum.toString())
              .fontSize(13)
              .fontColor(this.post.isDisagreed ? $r('app.color.error') : $r('app.color.text_secondary'))
              .margin({ left: 4 })
          }
          .alignItems(VerticalAlign.Center)
          .margin({ left: 16 })
          .onClick(() => {
            if (this.onDisagreeClick) {
              this.onDisagreeClick(this.post);
            }
          })
        }
        .alignItems(VerticalAlign.Center)

        Blank()

        // 右侧：评论按钮
        Row() {
          Text('💬')
            .fontSize(14)
          Text(this.post.replyNum.toString())
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .margin({ left: 4 })
        }
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          if (this.onCommentClick) {
            this.onCommentClick();
          }
        })
      }
      .width('100%')
      .margin({ top: 12 })
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(this.isFirst ? 0 : 8)
    .margin({ left: this.isFirst ? 0 : 12, right: this.isFirst ? 0 : 12, top: this.isFirst ? 0 : 8 })
  }
}

@Entry
@Component
struct ThreadPage {
  private viewModel: ThreadViewModel = new ThreadViewModel();
  private dataSource: CommonDataSource<PostInfo> = new CommonDataSource<PostInfo>();

  @State tid: number = 0;
  @State postCount: number = 0;
  @State isLoading: boolean = false;
  @State isRefreshing: boolean = false;
  @State hasMore: boolean = true;
  @State errorMessage: string = '';
  @State threadTitle: string = '';
  @State threadReplyNum: number = 0;
  // 状态栏高度（vp），沉浸式避让状态栏，默认 36，aboutToAppear 动态获取
  @State statusBarHeight: number = 36;

  async aboutToAppear() {
    // 获取状态栏高度（沉浸式，P1 重构提取为 StatusBarUtil）
    this.statusBarHeight = await getStatusBarHeight(getContext(this));
    const params = router.getParams() as Record<string, string>;
    if (params && params['tid']) {
      this.tid = Number(params['tid']);
      this.viewModel.setTid(this.tid);
      this.loadPosts(true);
    }
  }

  async loadPosts(isRefresh: boolean = false): Promise<void> {
    await this.viewModel.loadData(isRefresh);
    this.syncState();
  }

  private syncState(): void {
    const paginationData = this.viewModel.paginationData;
    const loadingState = this.viewModel.loadingState;

    // issue #39：刷新用 setData 全量替换，loadMore 用 appendData 增量追加
    if (this.viewModel.lastOpWasRefresh) {
      this.dataSource.setData(paginationData.dataList);
    } else {
      this.dataSource.appendData(this.viewModel.lastAddedList);
    }
    this.postCount = this.dataSource.totalCount();
    this.hasMore = paginationData.hasMore;
    this.isLoading = loadingState.isLoading;
    this.isRefreshing = loadingState.isRefreshing;
    this.errorMessage = loadingState.error;
    // 同步主题帖标题（首次加载后才有值，标题栏从通用"帖子详情"切换为实际标题）
    this.threadTitle = this.viewModel.threadTitle;
    // 同步主题帖总回复数（修复评论数显示为 0 问题）
    this.threadReplyNum = this.viewModel.threadReplyNum;
  }

  onReachEnd(): void {
    if (this.viewModel.canLoadMore()) {
      this.loadPosts(false);
    }
  }

  /**
   * 点赞/取消赞（issue #17，#31 改 LazyForEach）
   * PostInfo 是回复（pid>0），isComment=false
   * PostInfo 已 @Observed，PostItem 用 @ObjectLink，
   * 修改 post 字段会自动局部刷新，无需 slice() 触发重建
   */
  async handleAgree(post: PostInfo): Promise<void> {
    try {
      if (post.isAgreed) {
        await TiebaAPI.unagree(post.tid, post.pid, false);
        post.isAgreed = false;
        post.agreeNum = Math.max(0, post.agreeNum - 1);
      } else {
        await TiebaAPI.agree(post.tid, post.pid, false);
        post.isAgreed = true;
        post.agreeNum += 1;
      }
      // @Observed + @ObjectLink 自动局部刷新，无需 slice()
    } catch (err) {
      promptAction.showToast({ message: (err as Error).message || getResourceString($r('app.string.follow_operation_failed')) });
    }
  }

  /**
   * 点踩/取消点踩（issue #17，#31 改 LazyForEach）
   */
  async handleDisagree(post: PostInfo): Promise<void> {
    try {
      if (post.isDisagreed) {
        await TiebaAPI.undisagree(post.tid, post.pid, false);
        post.isDisagreed = false;
        post.disagreeNum = Math.max(0, post.disagreeNum - 1);
      } else {
        await TiebaAPI.disagree(post.tid, post.pid, false);
        post.isDisagreed = true;
        post.disagreeNum += 1;
      }
      // @Observed + @ObjectLink 自动局部刷新
    } catch (err) {
      promptAction.showToast({ message: (err as Error).message || getResourceString($r('app.string.follow_operation_failed')) });
    }
  }

  /** 评论按钮点击：提示功能开发中（issue #17，评论 API 后续实现） */
  showCommentToast(): void {
    promptAction.showToast({ message: getResourceString($r('app.string.page_developing')) });
  }

  build() {
    Column() {
      Row() {
        Image($r('app.media.ic_back'))
          .width(24)
          .height(24)
          .fillColor($r('app.color.text_primary'))
          .onClick(() => {
            router.back();
          })

        Column() {
          Text(this.threadTitle.length > 0 ? this.threadTitle : getResourceString($r('app.string.thread_detail_title')))
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .textAlign(TextAlign.Start)
          // 显示总评论数（修复进入帖子详情后评论数显示为 0 的问题）
          if (this.threadReplyNum > 0) {
            Text(getResourceString($r('app.string.reply_count_label', this.threadReplyNum)))
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .margin({ top: 2 })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
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

      if (this.errorMessage.length > 0 && this.postCount === 0) {
        ErrorView({
          message: this.errorMessage,
          onRetryClick: () => this.loadPosts(true)
        })
          .layoutWeight(1)
      } else {
        List() {
          LazyForEach(this.dataSource, (post: PostInfo, index: number) => {
            ListItem() {
              PostItem({
                post: post,
                isFirst: index === 0,
                onAgreeClick: (p: PostInfo) => {
                  this.handleAgree(p).catch((err: Error) => {
                    console.error(`[ThreadPage] handleAgree failed: ${err.message}`);
                  });
                },
                onDisagreeClick: (p: PostInfo) => {
                  this.handleDisagree(p).catch((err: Error) => {
                    console.error(`[ThreadPage] handleDisagree failed: ${err.message}`);
                  });
                },
                onCommentClick: () => this.showCommentToast()
              })
            }
          }, (post: PostInfo) => post.pid.toString())

          if (this.isLoading && this.postCount > 0) {
            ListItem() {
              LoadingView({ message: getResourceString($r('app.string.loading_more')) })
                .height(60)
            }
          }
        }
        .width('100%')
        .layoutWeight(1)
        .divider({ strokeWidth: 0 })
        .edgeEffect(EdgeEffect.Spring)
        .cachedCount(5)
        .onReachEnd(() => this.onReachEnd())
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }
}
