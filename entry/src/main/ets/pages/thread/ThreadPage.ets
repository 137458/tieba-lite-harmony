import { router, promptAction } from '@kit.ArkUI';
import { TiebaAPI } from '../../api/TiebaAPI';
import { PostInfo, MediaInfo } from '../../model/ForumModels';
import { LoadingView } from '../../components/LoadingView';
import { ErrorView } from '../../components/ErrorView';
import { BaseViewModel, FetchDataResult } from '../../viewmodel/BaseViewModel';
import { getResourceString } from '../../utils/ResourceUtil';

class ThreadViewModel extends BaseViewModel<PostInfo> {
  private tid: number = 0;
  // 主题帖标题（从 PbPageResult.thread.title 提取，syncState 读取）
  threadTitle: string = '';

  setTid(id: number): void {
    this.tid = id;
  }

  protected async fetchData(page: number, isRefresh: boolean): Promise<FetchDataResult<PostInfo>> {
    // getPosts 返回 PbPageResult（含 posts 分页 + thread 主题帖信息）
    const result = await TiebaAPI.getPosts(this.tid, page, false);
    this.threadTitle = result.thread.title;
    return {
      list: result.posts.list,
      hasMore: result.posts.hasMore,
      currentPage: result.posts.currentPage
    };
  }
}

@Entry
@Component
struct ThreadPage {
  private viewModel: ThreadViewModel = new ThreadViewModel();

  @State tid: number = 0;
  @State postList: PostInfo[] = [];
  @State isLoading: boolean = false;
  @State isRefreshing: boolean = false;
  @State hasMore: boolean = true;
  @State errorMessage: string = '';
  @State threadTitle: string = '';

  aboutToAppear() {
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

    this.postList = paginationData.dataList;
    this.hasMore = paginationData.hasMore;
    this.isLoading = loadingState.isLoading;
    this.isRefreshing = loadingState.isRefreshing;
    this.errorMessage = loadingState.error;
    // 同步主题帖标题（首次加载后才有值，标题栏从通用"帖子详情"切换为实际标题）
    this.threadTitle = this.viewModel.threadTitle;
  }

  onReachEnd(): void {
    if (this.viewModel.canLoadMore()) {
      this.loadPosts(false);
    }
  }

  /**
   * 点赞/取消赞（issue #17）
   * PostInfo 是回复（pid>0），isComment=false
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
      // 触发 List 重新渲染（postList 重新赋值）
      this.postList = this.postList.slice();
    } catch (err) {
      promptAction.showToast({ message: (err as Error).message || getResourceString($r('app.string.follow_operation_failed')) });
    }
  }

  /**
   * 点踩/取消点踩（issue #17）
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
      this.postList = this.postList.slice();
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
        Image('')
          .width(24)
          .height(24)
          .fillColor($r('app.color.text_primary'))
          .onClick(() => {
            router.back();
          })

        Text(this.threadTitle.length > 0 ? this.threadTitle : getResourceString($r('app.string.thread_detail_title')))
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Start)

        Blank()
          .width(24)
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .alignItems(VerticalAlign.Center)
      .backgroundColor($r('app.color.background'))

      if (this.errorMessage.length > 0 && this.postList.length === 0) {
        ErrorView({
          message: this.errorMessage,
          onRetryClick: () => this.loadPosts(true)
        })
          .layoutWeight(1)
      } else {
        List() {
          ForEach(this.postList, (post: PostInfo, index: number) => {
            ListItem() {
              this.PostItemBuilder(post, index === 0)
            }
          }, (post: PostInfo) => post.pid.toString())

          if (this.isLoading && this.postList.length > 0) {
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
        .onReachEnd(() => this.onReachEnd())
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  PostItemBuilder(post: PostInfo, isFirst: boolean) {
    Column() {
      Row() {
        Image(post.author.avatar)
          .width(40)
          .height(40)
          .borderRadius(20)
          .objectFit(ImageFit.Cover)

        Column() {
          Text(post.author.name)
            .fontSize(15)
            .fontColor($r('app.color.text_primary'))
            .fontWeight(FontWeight.Medium)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text($r('app.string.floor_label', post.floor))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
        }
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 12 })
        .layoutWeight(1)

        if (isFirst) {
          Text($r('app.string.author_label'))
            .fontSize(11)
            .fontColor($r('app.color.primary'))
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .border({ width: 0.5, color: $r('app.color.primary'), radius: 4 })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Text(post.content)
        .fontSize(15)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: 12 })
        .width('100%')

      if (post.mediaList.length > 0) {
        Row() {
          ForEach(post.mediaList.slice(0, 3), (media: MediaInfo, index: number) => {
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
                    urls: post.mediaList.map((m: MediaInfo) => m.url),
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
              .opacity(post.isAgreed ? 1.0 : 0.6)
            Text(post.agreeNum.toString())
              .fontSize(13)
              .fontColor(post.isAgreed ? $r('app.color.primary') : $r('app.color.text_secondary'))
              .margin({ left: 4 })
          }
          .alignItems(VerticalAlign.Center)
          .onClick(() => {
            this.handleAgree(post).catch((err: Error) => {
              console.error(`[ThreadPage] handleAgree failed: ${err.message}`);
            });
          })

          // 踩按钮
          Row() {
            Text('👎')
              .fontSize(14)
              .opacity(post.isDisagreed ? 1.0 : 0.6)
            Text(post.disagreeNum.toString())
              .fontSize(13)
              .fontColor(post.isDisagreed ? $r('app.color.error') : $r('app.color.text_secondary'))
              .margin({ left: 4 })
          }
          .alignItems(VerticalAlign.Center)
          .margin({ left: 16 })
          .onClick(() => {
            this.handleDisagree(post).catch((err: Error) => {
              console.error(`[ThreadPage] handleDisagree failed: ${err.message}`);
            });
          })
        }
        .alignItems(VerticalAlign.Center)

        Blank()

        // 右侧：评论按钮
        Row() {
          Text('💬')
            .fontSize(14)
          Text(post.replyNum.toString())
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .margin({ left: 4 })
        }
        .alignItems(VerticalAlign.Center)
        .onClick(() => this.showCommentToast())
      }
      .width('100%')
      .margin({ top: 12 })
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(isFirst ? 0 : 8)
    .margin({ left: isFirst ? 0 : 12, right: isFirst ? 0 : 12, top: isFirst ? 0 : 8 })
  }
}
