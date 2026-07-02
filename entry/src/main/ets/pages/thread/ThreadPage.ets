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
  // 主题帖作者 uid（用于判断楼层是否为楼主，对齐原 APP post.author.id == thread.author.id）
  threadAuthorUid: number = 0;
  // #69 主题帖点赞数和点赞状态（从 PbPageResult.thread.agreeNum/isAgreed 提取）
  threadAgreeNum: number = 0;
  threadIsAgreed: boolean = false;

  setTid(id: number): void {
    this.tid = id;
  }

  protected async fetchData(page: number, isRefresh: boolean): Promise<FetchDataResult<PostInfo>> {
    // getPosts 返回 PbPageResult（含 posts 分页 + thread 主题帖信息）
    const result = await TiebaAPI.getPosts(this.tid, page, false);
    this.threadTitle = result.thread.title;
    // 仅首页加载时同步主题帖作者 uid 和总回复数（避免分页加载覆盖）
    if (isRefresh) {
      this.threadAuthorUid = result.thread.author.uid;
      this.threadReplyNum = result.thread.replyNum;
      // #69 同步主题帖点赞数和状态
      this.threadAgreeNum = result.thread.agreeNum;
      this.threadIsAgreed = result.thread.isAgreed;
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
  // 是否为楼主楼层（用 post.author.uid === thread.author.uid 判断，对齐原 APP，分页后仍正确）
  @Prop isAuthor: boolean = false;
  onAgreeClick?: (post: PostInfo) => void;
  onDisagreeClick?: (post: PostInfo) => void;
  onCommentClick?: () => void;

  /** P1 优化：展开写的图片项，避免 build 中 slice+ForEach 创建新数组 */
  @Builder
  MediaImage(index: number) {
    Image(this.post.mediaList[index].thumbnail.length > 0 ?
      this.post.mediaList[index].thumbnail : this.post.mediaList[index].url)
      .width(100)
      .height(100)
      .objectFit(ImageFit.Cover)
      .borderRadius(4)
      .backgroundColor($r('app.color.input_background'))
      .alt($r('app.media.startIcon'))
      .margin({ right: index < 2 ? 4 : 0 })
      .onClick(() => {
        // 打开图片查看器（issue #15）
        router.pushUrl({
          url: 'pages/viewer/ImageViewerPage',
          params: {
            urls: this.post.mediaList.map((m: MediaInfo) => m.url),
            index: index
          }
        }).catch((err: Error) => {
          console.error(`[ThreadPage] navigate to ImageViewer failed: ${err.message}`);
        });
      })
  }

  build() {
    Column() {
      // 头像 + 名字 + 楼层 + 楼主标签
      Row() {
        Image(this.post.author.avatar)
          .width(40)
          .height(40)
          .borderRadius(20)
          .objectFit(ImageFit.Cover)
          .backgroundColor($r('app.color.input_background'))
          .alt($r('app.media.startIcon'))

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

        if (this.isAuthor) {
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
          this.MediaImage(0)
          if (this.post.mediaList.length > 1) {
            this.MediaImage(1)
          }
          if (this.post.mediaList.length > 2) {
            this.MediaImage(2)
          }
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
    .borderRadius(this.isAuthor ? 0 : 8)
    .renderGroup(true)
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
  // 主题帖作者 uid（用于判断楼层是否为楼主，对齐原 APP）
  @State threadAuthorUid: number = 0;
  // #69 主题帖点赞数和状态（syncState 从 viewModel 同步）
  @State threadAgreeNum: number = 0;
  @State threadIsAgreed: boolean = false;
  // #69 收藏状态（本地管理，进入帖子时默认未收藏，点击切换）
  @State isFavorited: boolean = false;
  // #69 操作防抖标志（防止重复点击）
  @State isProcessingFavorite: boolean = false;
  @State isProcessingAgree: boolean = false;
  // 状态栏高度（vp），沉浸式避让状态栏，默认 36，aboutToAppear 动态获取
  @State statusBarHeight: number = 36;

  async aboutToAppear() {
    // 获取状态栏高度（沉浸式，失败时保留默认 36，不阻塞页面初始化）
    try {
      this.statusBarHeight = await getStatusBarHeight(getContext(this));
    } catch (err) {
      console.error(`[ThreadPage] getStatusBarHeight failed: ${(err as Error).message}`);
    }
    const params = router.getParams() as Record<string, string>;
    if (params && params['tid']) {
      this.tid = Number(params['tid']);
      this.viewModel.setTid(this.tid);
      this.loadPosts(true).catch((err: Error) => {
        console.error(`[ThreadPage] loadPosts failed: ${err.message}`);
      });
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
    // 同步主题帖作者 uid（用于楼主标识判断，对齐原 APP）
    this.threadAuthorUid = this.viewModel.threadAuthorUid;
    // #69 同步主题帖点赞数和状态（仅刷新时同步，避免 loadMore 覆盖乐观更新）
    if (this.viewModel.lastOpWasRefresh) {
      this.threadAgreeNum = this.viewModel.threadAgreeNum;
      this.threadIsAgreed = this.viewModel.threadIsAgreed;
    }
  }

  onReachEnd(): void {
    if (this.viewModel.canLoadMore()) {
      this.loadPosts(false);
    }
  }

  /**
   * 点赞/取消赞（issue #17，#31 改 LazyForEach）
   * PostInfo 是回复（pid>0），isComment=false
   * 乐观更新 + 失败回滚（对齐原 APP，保证 UI 与服务端一致）
   * PostInfo 已 @Observed，PostItem 用 @ObjectLink，
   * 修改 post 字段会自动局部刷新，无需 slice() 触发重建
   */
  async handleAgree(post: PostInfo): Promise<void> {
    // 保存原状态用于失败回滚（对齐原 APP）
    const prevIsAgreed: boolean = post.isAgreed;
    const prevAgreeNum: number = post.agreeNum;
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
      // 失败回滚到原状态（对齐原 APP，保证 UI 与服务端一致）
      post.isAgreed = prevIsAgreed;
      post.agreeNum = prevAgreeNum;
      promptAction.showToast({ message: (err as Error).message || getResourceString($r('app.string.follow_operation_failed')) });
    }
  }

  /**
   * 点踩/取消点踩（issue #17，#31 改 LazyForEach）
   * 乐观更新 + 失败回滚（对齐原 APP，保证 UI 与服务端一致）
   */
  async handleDisagree(post: PostInfo): Promise<void> {
    // 保存原状态用于失败回滚（对齐原 APP）
    const prevIsDisagreed: boolean = post.isDisagreed;
    const prevDisagreeNum: number = post.disagreeNum;
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
      // 失败回滚到原状态（对齐原 APP，保证 UI 与服务端一致）
      post.isDisagreed = prevIsDisagreed;
      post.disagreeNum = prevDisagreeNum;
      promptAction.showToast({ message: (err as Error).message || getResourceString($r('app.string.follow_operation_failed')) });
    }
  }

  /** 评论按钮点击：提示功能开发中（issue #17，评论 API 后续实现） */
  showCommentToast(): void {
    promptAction.showToast({ message: getResourceString($r('app.string.page_developing')) });
  }

  /**
   * #69 主题帖点赞/取消赞（objType=3, pid=0）
   * 乐观更新 + 失败回滚，对齐原 APP ThreadViewModel.kt
   * 注意：主题帖不是 PostInfo，不在 dataSource 中，直接操作 @State 变量
   */
  async handleThreadAgree(): Promise<void> {
    if (this.isProcessingAgree) {
      return;
    }
    this.isProcessingAgree = true;
    const prevIsAgreed: boolean = this.threadIsAgreed;
    const prevAgreeNum: number = this.threadAgreeNum;
    try {
      if (this.threadIsAgreed) {
        await TiebaAPI.unagree(this.tid, 0, false);
        this.threadIsAgreed = false;
        this.threadAgreeNum = Math.max(0, this.threadAgreeNum - 1);
      } else {
        await TiebaAPI.agree(this.tid, 0, false);
        this.threadIsAgreed = true;
        this.threadAgreeNum += 1;
      }
    } catch (err) {
      this.threadIsAgreed = prevIsAgreed;
      this.threadAgreeNum = prevAgreeNum;
      promptAction.showToast({ message: (err as Error).message || getResourceString($r('app.string.follow_operation_failed')) });
    } finally {
      this.isProcessingAgree = false;
    }
  }

  /**
   * #69 收藏/取消收藏
   * 调用 TiebaAPI.addStore/removeStore，Toast 反馈
   * 收藏状态本地管理（进入帖子时默认未收藏）
   */
  async handleThreadFavorite(): Promise<void> {
    if (this.isProcessingFavorite) {
      return;
    }
    this.isProcessingFavorite = true;
    try {
      if (this.isFavorited) {
        await TiebaAPI.removeStore(this.tid);
        this.isFavorited = false;
        promptAction.showToast({ message: getResourceString($r('app.string.favorite_removed')) });
      } else {
        await TiebaAPI.addStore(this.tid, 0);
        this.isFavorited = true;
        promptAction.showToast({ message: getResourceString($r('app.string.favorite_added')) });
      }
    } catch (err) {
      promptAction.showToast({ message: (err as Error).message || getResourceString($r('app.string.follow_operation_failed')) });
    } finally {
      this.isProcessingFavorite = false;
    }
  }

  build() {
    Column() {
      // #69 顶部导航栏（对齐 iOS 原型 detail-nav：返回+标题+操作按钮）
      Row() {
        // 返回按钮（30px 圆形，对齐原型 .back-btn）
        Row() {
          Image($r('app.media.ic_back'))
            .width(20)
            .height(20)
            .fillColor($r('app.color.text_primary'))
        }
        .width(30)
        .height(30)
        .borderRadius(15)
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          router.back();
        })

        // 标题 + 回复数（居中，17px SemiBold，对齐原型 .forum-name）
        Column() {
          Text(this.threadTitle.length > 0 ? this.threadTitle : getResourceString($r('app.string.thread_detail_title')))
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .textAlign(TextAlign.Center)
          // 显示总评论数（修复进入帖子详情后评论数显示为 0 的问题）
          if (this.threadReplyNum > 0) {
            Text(getResourceString($r('app.string.reply_count_label', this.threadReplyNum)))
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .margin({ top: 2 })
          }
        }
        .alignItems(HorizontalAlign.Center)
        .layoutWeight(1)
        .margin({ left: 8, right: 8 })

        // #69 主题帖点赞按钮（👍 + 数量，objType=3）
        Row() {
          Text('👍')
            .fontSize(14)
            .opacity(this.threadIsAgreed ? 1.0 : 0.6)
          if (this.threadAgreeNum > 0) {
            Text(this.threadAgreeNum.toString())
              .fontSize(13)
              .fontColor(this.threadIsAgreed ? $r('app.color.primary') : $r('app.color.text_secondary'))
              .margin({ left: 4 })
          }
        }
        .alignItems(VerticalAlign.Center)
        .height(30)
        .borderRadius(15)
        .padding({ left: 8, right: 8 })
        .onClick(() => {
          this.handleThreadAgree().catch((err: Error) => {
            console.error(`[ThreadPage] handleThreadAgree failed: ${err.message}`);
          });
        })

        // #69 收藏按钮（★/☆）
        Row() {
          Text(this.isFavorited ? '★' : '☆')
            .fontSize(20)
            .fontColor(this.isFavorited ? $r('app.color.primary') : $r('app.color.text_secondary'))
        }
        .width(30)
        .height(30)
        .borderRadius(15)
        .justifyContent(FlexAlign.Center)
        .margin({ left: 12 })
        .onClick(() => {
          this.handleThreadFavorite().catch((err: Error) => {
            console.error(`[ThreadPage] handleThreadFavorite failed: ${err.message}`);
          });
        })
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
                // 用 author.uid 判断楼主，对齐原 APP，分页后仍正确（index===0 在第2页失效）
                isAuthor: post.author.uid === this.threadAuthorUid && this.threadAuthorUid > 0,
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
            .margin({ top: 4, bottom: 4 })
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
        .padding({ left: 12, right: 12 })
        .onReachEnd(() => this.onReachEnd())
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }
}
