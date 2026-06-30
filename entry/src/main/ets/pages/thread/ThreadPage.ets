import { router } from '@kit.ArkUI';
import { TiebaAPI } from '../../api/TiebaAPI';
import { PostInfo, MediaInfo } from '../../model/ForumModels';
import { LoadingView } from '../../components/LoadingView';
import { ErrorView } from '../../components/ErrorView';
import { BaseViewModel, FetchDataResult } from '../../viewmodel/BaseViewModel';
import { getResourceString } from '../../utils/ResourceUtil';

class ThreadViewModel extends BaseViewModel<PostInfo> {
  private tid: number = 0;

  setTid(id: number): void {
    this.tid = id;
  }

  protected async fetchData(page: number, isRefresh: boolean): Promise<FetchDataResult<PostInfo>> {
    return await TiebaAPI.getPosts(
      this.tid,
      page,
      false
    );
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
  }

  onReachEnd(): void {
    if (this.viewModel.canLoadMore()) {
      this.loadPosts(false);
    }
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

        Text($r('app.string.thread_detail_title'))
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
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
          }, (media: MediaInfo) => media.url)
        }
        .width('100%')
        .margin({ top: 8 })
      }

      Row() {
        Row() {
          Image('')
            .width(16)
            .height(16)
            .fillColor($r('app.color.text_secondary'))

          Text(post.agreeNum.toString())
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .margin({ left: 4 })
        }

        Row() {
          Image('')
            .width(16)
            .height(16)
            .fillColor($r('app.color.text_secondary'))

          Text(post.replyNum.toString())
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .margin({ left: 4 })
        }
        .margin({ left: 16 })
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
