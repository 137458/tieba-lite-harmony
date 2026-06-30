import { router, promptAction } from '@kit.ArkUI';
import { TiebaAPI } from '../../api/TiebaAPI';
import { ThreadInfo } from '../../model/ForumModels';
import { ThreadCard } from '../../components/ThreadCard';
import { LoadingView } from '../../components/LoadingView';
import { getResourceString } from '../../utils/ResourceUtil';
import { ErrorView } from '../../components/ErrorView';
import { BaseViewModel, FetchDataResult } from '../../viewmodel/BaseViewModel';

class ForumViewModel extends BaseViewModel<ThreadInfo> {
  private forumName: string = '';
  private sortType: number = 1;
  private isGood: boolean = false;

  setForumName(name: string): void {
    this.forumName = name;
  }

  setSortType(type: number): void {
    this.sortType = type;
  }

  setIsGood(good: boolean): void {
    this.isGood = good;
  }

  protected async fetchData(page: number, isRefresh: boolean): Promise<FetchDataResult<ThreadInfo>> {
    return await TiebaAPI.getThreads(
      this.forumName,
      page,
      this.sortType,
      this.isGood
    );
  }
}

@Entry
@Component
struct ForumPage {
  private viewModel: ForumViewModel = new ForumViewModel();

  @State forumName: string = '';
  @State threadList: ThreadInfo[] = [];
  @State isLoading: boolean = false;
  @State isRefreshing: boolean = false;
  @State hasMore: boolean = true;
  @State errorMessage: string = '';
  @State sortType: number = 1;
  @State isGood: boolean = false;

  aboutToAppear() {
    const params = router.getParams() as Record<string, string>;
    if (params && params['forumName']) {
      this.forumName = params['forumName'];
      this.viewModel.setForumName(this.forumName);
      this.loadThreads(true);
    }
  }

  async loadThreads(isRefresh: boolean = false): Promise<void> {
    this.viewModel.setSortType(this.sortType);
    this.viewModel.setIsGood(this.isGood);
    await this.viewModel.loadData(isRefresh);
    this.syncState();
  }

  private syncState(): void {
    const paginationData = this.viewModel.paginationData;
    const loadingState = this.viewModel.loadingState;

    this.threadList = paginationData.dataList;
    this.hasMore = paginationData.hasMore;
    this.isLoading = loadingState.isLoading;
    this.isRefreshing = loadingState.isRefreshing;
    this.errorMessage = loadingState.error;
  }

  onReachEnd(): void {
    if (this.viewModel.canLoadMore()) {
      this.loadThreads(false);
    }
  }

  navigateToThread(tid: number): void {
    router.pushUrl({
      url: 'pages/thread/ThreadPage',
      params: { tid: tid.toString() }
    });
  }

  /** 点赞/取消赞（issue #17），主题帖 pid=0。@Prop 浅拷贝需用 tid 查原对象 */
  async handleAgree(thread: ThreadInfo): Promise<void> {
    const target = this.threadList.find((t: ThreadInfo) => t.tid === thread.tid);
    if (!target) {
      return;
    }
    try {
      if (target.isAgreed) {
        await TiebaAPI.unagree(target.tid, 0, false);
        target.isAgreed = false;
        target.agreeNum = Math.max(0, target.agreeNum - 1);
      } else {
        await TiebaAPI.agree(target.tid, 0, false);
        target.isAgreed = true;
        target.agreeNum += 1;
      }
      this.threadList = this.threadList.slice();
    } catch (err) {
      promptAction.showToast({ message: (err as Error).message || getResourceString($r('app.string.follow_operation_failed')) });
    }
  }

  /** 点踩/取消点踩（issue #17） */
  async handleDisagree(thread: ThreadInfo): Promise<void> {
    const target = this.threadList.find((t: ThreadInfo) => t.tid === thread.tid);
    if (!target) {
      return;
    }
    try {
      if (target.isDisagreed) {
        await TiebaAPI.undisagree(target.tid, 0, false);
        target.isDisagreed = false;
        target.disagreeNum = Math.max(0, target.disagreeNum - 1);
      } else {
        await TiebaAPI.disagree(target.tid, 0, false);
        target.isDisagreed = true;
        target.disagreeNum += 1;
      }
      this.threadList = this.threadList.slice();
    } catch (err) {
      promptAction.showToast({ message: (err as Error).message || getResourceString($r('app.string.follow_operation_failed')) });
    }
  }

  /** 评论按钮提示开发中（issue #17） */
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

        Text(this.forumName)
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .textAlign(TextAlign.Start)
          .margin({ left: 12 })

        Row() {
          Text(this.sortType === 1 ? $r('app.string.forum_sort_reply') : $r('app.string.forum_sort_post'))
            .fontSize(14)
            .fontColor($r('app.color.primary'))
            .onClick(() => {
              this.sortType = this.sortType === 1 ? 2 : 1;
              this.loadThreads(true);
            })

          Text(this.isGood ? $r('app.string.forum_filter_all') : $r('app.string.forum_filter_good'))
            .fontSize(14)
            .fontColor($r('app.color.primary'))
            .margin({ left: 12 })
            .onClick(() => {
              this.isGood = !this.isGood;
              this.loadThreads(true);
            })
        }
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .alignItems(VerticalAlign.Center)
      .backgroundColor($r('app.color.background'))

      if (this.errorMessage.length > 0 && this.threadList.length === 0) {
        ErrorView({
          message: this.errorMessage,
          onRetryClick: () => this.loadThreads(true)
        })
          .layoutWeight(1)
      } else {
        List() {
          ForEach(this.threadList, (thread: ThreadInfo) => {
            ListItem() {
              ThreadCard({
                thread: thread,
                onCardClick: () => this.navigateToThread(thread.tid),
                onAgreeClick: (t: ThreadInfo) => {
                  this.handleAgree(t).catch((err: Error) => {
                    console.error(`[ForumPage] handleAgree failed: ${err.message}`);
                  });
                },
                onDisagreeClick: (t: ThreadInfo) => {
                  this.handleDisagree(t).catch((err: Error) => {
                    console.error(`[ForumPage] handleDisagree failed: ${err.message}`);
                  });
                },
                onCommentClick: () => this.showCommentToast()
              })
                .margin({ left: 12, right: 12, top: 8 })
            }
          }, (thread: ThreadInfo) => thread.tid.toString())

          if (this.isLoading && this.threadList.length > 0) {
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
}
