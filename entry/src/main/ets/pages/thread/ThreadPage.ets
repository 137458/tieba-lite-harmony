import { router, promptAction } from '@kit.ArkUI';
import { TiebaAPI } from '../../api/TiebaAPI';
import { PostInfo, MediaInfo } from '../../model/ForumModels';
import { LoadingView } from '../../components/LoadingView';
import { ErrorView } from '../../components/ErrorView';
import { BaseViewModel, FetchDataResult } from '../../viewmodel/BaseViewModel';
import { getResourceString } from '../../utils/ResourceUtil';
import { CommonDataSource } from '../../utils/CommonDataSource';
import { getStatusBarHeight } from '../../utils/StatusBarUtil';
import { formatRelativeTime } from '../../utils/TimeUtil';

class ThreadViewModel extends BaseViewModel<PostInfo> {
  private tid: number = 0;
  // #70 只看楼主 + 回复排序（0=正序ASC, 1=倒序DESC, 2=热门HOT，对齐 Android ThreadSortType）
  private onlyAuthor: boolean = false;
  private sort: number = 0;
  threadTitle: string = '';
  threadReplyNum: number = 0;
  threadAuthorUid: number = 0;
  threadAgreeNum: number = 0;
  threadIsAgreed: boolean = false;
  threadForumName: string = '';
  threadViewNum: number = 0;
  threadCreateTime: number = 0;

  setTid(id: number): void {
    this.tid = id;
  }

  setOnlyAuthor(onlyAuthor: boolean): void {
    this.onlyAuthor = onlyAuthor;
  }

  setSort(sort: number): void {
    this.sort = sort;
  }

  protected async fetchData(page: number, isRefresh: boolean): Promise<FetchDataResult<PostInfo>> {
    const result = await TiebaAPI.getPosts(this.tid, page, this.onlyAuthor, this.sort);
    this.threadTitle = result.thread.title;
    if (isRefresh) {
      this.threadAuthorUid = result.thread.author.uid;
      this.threadReplyNum = result.thread.replyNum;
      this.threadAgreeNum = result.thread.agreeNum;
      this.threadIsAgreed = result.thread.isAgreed;
      this.threadForumName = result.thread.forumName;
      this.threadViewNum = result.thread.viewNum;
      this.threadCreateTime = result.thread.createTime;
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
  // 点击作者区域（头像/名字）回调，跳转用户主页
  onAuthorClick?: () => void;

  @Builder
  MediaImage(index: number, isSingle: boolean) {
    Image(this.post.mediaList[index].thumbnail.length > 0 ?
      this.post.mediaList[index].thumbnail : this.post.mediaList[index].url)
      .objectFit(ImageFit.Cover)
      .borderRadius(8)
      .backgroundColor($r('app.color.input_background'))
      .alt($r('app.media.startIcon'))
      .width('100%')
      .aspectRatio(isSingle ? 4 / 3 : 1)
      .hitTestBehavior(HitTestMode.Block)
      .onClick(() => {
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
      Row() {
        Image(this.post.author.avatar)
          .width(36)
          .height(36)
          .borderRadius(18)
          .objectFit(ImageFit.Cover)
          .backgroundColor($r('app.color.input_background'))
          .alt($r('app.media.startIcon'))
          .border(this.isAuthor ? { width: 2, color: $r('app.color.primary') } : { width: 0 })

        Column() {
          Row() {
            Text(this.post.author.name)
              .fontSize(14)
              .fontColor($r('app.color.text_primary'))
              .fontWeight(600)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            if (this.isAuthor) {
              Text($r('app.string.author_label'))
                .fontSize(10)
                .fontColor($r('app.color.primary'))
                .padding({ left: 6, right: 6, top: 1, bottom: 1 })
                .backgroundColor($r('app.color.primary_light'))
                .borderRadius(6)
                .margin({ left: 6 })
            }
          }

          Text(getResourceString($r('app.string.floor_time_label', this.post.floor + 1, formatRelativeTime(this.post.createTime))))
            .fontSize(12)
            .fontColor($r('app.color.text_caption'))
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 10 })
        .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .hitTestBehavior(this.onAuthorClick ? HitTestMode.Block : HitTestMode.Default)
      .onClick(() => {
        if (this.onAuthorClick) {
          this.onAuthorClick();
        }
      })

      Text(this.post.content)
        .fontSize(15)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: 10 })
        .width('100%')
        .lineHeight(24)

      if (this.post.mediaList.length > 0) {
        // 2 列 grid 布局（对齐原型 floor-images），单图全宽 4:3，多图 1:1
        Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
          ForEach(this.post.mediaList, (media: MediaInfo, index: number) => {
            Row() {
              this.MediaImage(index, this.post.mediaList.length === 1)
            }
            .width(this.post.mediaList.length === 1 ? '100%' : '48%')
            .margin({ right: index % 2 === 0 && this.post.mediaList.length > 1 ? '4%' : 0, bottom: 4 })
          }, (media: MediaInfo, idx: number) => `${media.url}_${idx}`)
        }
        .width('100%')
        .margin({ top: 10 })
      }

      Row() {
        Row() {
          Image($r('app.media.ic_like'))
            .width(16)
            .height(16)
            .fillColor(this.post.isAgreed ? $r('app.color.primary') : $r('app.color.text_caption'))
          Text(this.post.agreeNum.toString())
            .fontSize(12)
            .fontColor(this.post.isAgreed ? $r('app.color.primary') : $r('app.color.text_caption'))
            .margin({ left: 4 })
        }
        .padding({ left: 0, right: 8, top: 8, bottom: 8 })
        .alignItems(VerticalAlign.Center)
        .hitTestBehavior(HitTestMode.Block)
        .onClick(() => {
          if (this.onAgreeClick) {
            this.onAgreeClick(this.post);
          }
        })

        Row() {
          Image($r('app.media.ic_dislike'))
            .width(16)
            .height(16)
            .fillColor(this.post.isDisagreed ? $r('app.color.error') : $r('app.color.text_caption'))
          Text(this.post.disagreeNum.toString())
            .fontSize(12)
            .fontColor(this.post.isDisagreed ? $r('app.color.error') : $r('app.color.text_caption'))
            .margin({ left: 4 })
        }
        .padding({ left: 0, right: 8, top: 8, bottom: 8 })
        .alignItems(VerticalAlign.Center)
        .hitTestBehavior(HitTestMode.Block)
        .margin({ left: 20 })
        .onClick(() => {
          if (this.onDisagreeClick) {
            this.onDisagreeClick(this.post);
          }
        })

        Row() {
          Image($r('app.media.ic_message'))
            .width(16)
            .height(16)
            .fillColor($r('app.color.text_caption'))
          Text(this.post.replyNum.toString())
            .fontSize(12)
            .fontColor($r('app.color.text_caption'))
            .margin({ left: 4 })
        }
        .padding({ left: 0, right: 8, top: 8, bottom: 8 })
        .alignItems(VerticalAlign.Center)
        .hitTestBehavior(HitTestMode.Block)
        .margin({ left: 20 })
        .onClick(() => {
          if (this.onCommentClick) {
            this.onCommentClick();
          }
        })
      }
      .width('100%')
      .margin({ top: 2 })
      .justifyContent(FlexAlign.Start)
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(10)
    .alignItems(HorizontalAlign.Start)
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
  @State threadAuthorUid: number = 0;
  @State threadAgreeNum: number = 0;
  @State threadIsAgreed: boolean = false;
  @State isFavorited: boolean = false;
  @State isProcessingFavorite: boolean = false;
  @State isProcessingAgree: boolean = false;
  @State statusBarHeight: number = 36;
  @State threadForumName: string = '';
  @State threadViewNum: number = 0;
  @State threadCreateTime: number = 0;
  @State replyText: string = '';
  // #70 只看楼主 + 回复排序（持久化 sort 偏好到 AppStorage）
  @State onlyAuthorMode: boolean = false;
  @State sortOrder: number = 0;

  async aboutToAppear() {
    try {
      this.statusBarHeight = await getStatusBarHeight(getContext(this));
    } catch (err) {
      console.error(`[ThreadPage] getStatusBarHeight failed: ${(err as Error).message}`);
    }
    // #70 从 AppStorage 读取排序偏好（key: thread_default_sort，默认 0=正序）
    const savedSort = AppStorage.get<number>('thread_default_sort');
    if (savedSort !== null && savedSort !== undefined) {
      this.sortOrder = savedSort;
      this.viewModel.setSort(savedSort);
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
    this.threadTitle = this.viewModel.threadTitle;
    this.threadReplyNum = this.viewModel.threadReplyNum;
    this.threadAuthorUid = this.viewModel.threadAuthorUid;
    if (this.viewModel.lastOpWasRefresh) {
      this.threadAgreeNum = this.viewModel.threadAgreeNum;
      this.threadIsAgreed = this.viewModel.threadIsAgreed;
      this.threadForumName = this.viewModel.threadForumName;
      this.threadViewNum = this.viewModel.threadViewNum;
      this.threadCreateTime = this.viewModel.threadCreateTime;
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
      console.error('[ThreadPage] handleThreadAgree failed: ' + (err as Error).message);
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
      console.error('[ThreadPage] handleThreadFavorite failed: ' + (err as Error).message);
      promptAction.showToast({ message: (err as Error).message || getResourceString($r('app.string.follow_operation_failed')) });
    } finally {
      this.isProcessingFavorite = false;
    }
  }

  /**
   * 分享按钮：暂用 Toast 占位（后续可调用系统分享）
   */
  handleThreadShare(): void {
    promptAction.showToast({ message: getResourceString($r('app.string.share_developing')) });
  }

  /**
   * 跳转用户主页（点击楼层头像/名字触发）
   * 参数对齐 ForumPage / FavoritePage 的 navigateToUserProfile
   */
  navigateToUserProfile(portrait: string, userName: string, uid: number): void {
    router.pushUrl({
      url: 'pages/user/UserProfilePage',
      params: { portrait: portrait, userName: userName, uid: uid }
    }).catch((err: Error) => {
      console.error(`[ThreadPage] navigate to userProfile failed: ${err.message}`);
    });
  }

  /**
   * #70 切换"只看楼主"模式
   * 切换后同步到 ViewModel 并重新加载第一页
   */
  toggleOnlyAuthor(): void {
    this.onlyAuthorMode = !this.onlyAuthorMode;
    this.viewModel.setOnlyAuthor(this.onlyAuthorMode);
    this.loadPosts(true).catch((err: Error) => {
      console.error(`[ThreadPage] toggleOnlyAuthor reload failed: ${err.message}`);
    });
  }

  /**
   * #70 切换回复排序（0=正序, 1=倒序, 2=热门）
   * 持久化到 AppStorage，同步到 ViewModel，重新加载第一页
   */
  changeSort(sort: number): void {
    if (sort === this.sortOrder) {
      return;
    }
    this.sortOrder = sort;
    AppStorage.setOrCreate<number>('thread_default_sort', sort);
    this.viewModel.setSort(sort);
    this.loadPosts(true).catch((err: Error) => {
      console.error(`[ThreadPage] changeSort reload failed: ${err.message}`);
    });
  }

  build() {
    Column() {
      // 顶部导航栏：返回 + 吧名(居中) + 分享 + 更多（按原型 detail-nav）
      Row() {
        Row() {
          Image($r('app.media.ic_back'))
            .width(20)
            .height(20)
            .fillColor($r('app.color.primary'))
        }
        .width(30)
        .height(30)
        .borderRadius(15)
        .justifyContent(FlexAlign.Center)
        .hitTestBehavior(HitTestMode.Block)
        .onClick(() => {
          router.back();
        })

        Text(this.threadForumName.length > 0 ? this.threadForumName : getResourceString($r('app.string.thread_detail_title')))
          .fontSize(17)
          .fontWeight(600)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Center)
          .constraintSize({ maxWidth: '60%' })
          .layoutWeight(1)
          .margin({ left: 8, right: 8 })

        // 分享按钮
        Row() {
          Image($r('app.media.ic_share'))
            .width(20)
            .height(20)
            .fillColor($r('app.color.text_secondary'))
        }
        .width(30)
        .height(30)
        .borderRadius(15)
        .justifyContent(FlexAlign.Center)
        .hitTestBehavior(HitTestMode.Block)
        .onClick(() => {
          this.handleThreadShare();
        })

        // 更多按钮（#70 改为 bindMenu：只看楼主 + 回复排序）
        Row() {
          Image($r('app.media.ic_more'))
            .width(20)
            .height(20)
            .fillColor($r('app.color.text_secondary'))
        }
        .width(30)
        .height(30)
        .borderRadius(15)
        .justifyContent(FlexAlign.Center)
        .margin({ left: 12 })
        .hitTestBehavior(HitTestMode.Block)
        .bindMenu([
          {
            value: (this.onlyAuthorMode ? '✓ ' : '') + getResourceString($r('app.string.menu_see_lz')),
            action: () => this.toggleOnlyAuthor()
          },
          {
            value: (this.sortOrder === 0 ? '✓ ' : '') + getResourceString($r('app.string.menu_sort_asc')),
            action: () => this.changeSort(0)
          },
          {
            value: (this.sortOrder === 1 ? '✓ ' : '') + getResourceString($r('app.string.menu_sort_desc')),
            action: () => this.changeSort(1)
          },
          {
            value: (this.sortOrder === 2 ? '✓ ' : '') + getResourceString($r('app.string.menu_sort_hot')),
            action: () => this.changeSort(2)
          }
        ])
      }
      .width('100%')
      .height(44 + this.statusBarHeight)
      .padding({ left: 16, right: 16, top: this.statusBarHeight })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
      .alignItems(VerticalAlign.Center)
      .backgroundColor($r('app.color.page_background'))

      if (this.errorMessage.length > 0 && this.postCount === 0) {
        ErrorView({
          message: this.errorMessage,
          onRetryClick: () => this.loadPosts(true)
        })
          .layoutWeight(1)
      } else {
        List() {
          // 帖子信息栏（标题 + 浏览/评论/日期）
          if (this.threadTitle.length > 0) {
            ListItem() {
              Column() {
                Text(this.threadTitle)
                  .fontSize(17)
                  .fontWeight(600)
                  .fontColor($r('app.color.text_primary'))
                  .lineHeight(24)
                Row() {
                  if (this.threadViewNum > 0) {
                    Row() {
                      Image($r('app.media.ic_eye'))
                        .width(14)
                        .height(14)
                        .fillColor($r('app.color.text_caption'))
                      Text(this.formatCount(this.threadViewNum))
                        .fontSize(12)
                        .fontColor($r('app.color.text_caption'))
                        .margin({ left: 3 })
                    }
                    .alignItems(VerticalAlign.Center)
                  }
                  Row() {
                    Image($r('app.media.ic_message'))
                      .width(14)
                      .height(14)
                      .fillColor($r('app.color.text_caption'))
                    Text(this.formatCount(this.threadReplyNum))
                      .fontSize(12)
                      .fontColor($r('app.color.text_caption'))
                      .margin({ left: 3 })
                  }
                  .alignItems(VerticalAlign.Center)
                  .margin({ left: 8 })
                  if (this.threadCreateTime > 0) {
                    Text(formatRelativeTime(this.threadCreateTime))
                      .fontSize(12)
                      .fontColor($r('app.color.text_caption'))
                      .margin({ left: 8 })
                  }
                }
                .margin({ top: 8 })
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 12, bottom: 12 })
              .backgroundColor($r('app.color.card_background'))
              .borderRadius(10)
              .alignItems(HorizontalAlign.Start)
            }
            .margin({ left: 16, right: 16, top: 0, bottom: 12 })
          }

          // 楼层列表
          LazyForEach(this.dataSource, (post: PostInfo, index: number) => {
            ListItem() {
              PostItem({
                post: post,
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
                onCommentClick: () => this.showCommentToast(),
                onAuthorClick: () => this.navigateToUserProfile(
                  post.author.portrait,
                  post.author.name,
                  post.author.uid
                )
              })
            }
            .margin({ left: 16, right: 16, top: 0, bottom: 10 })
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
        .backgroundColor($r('app.color.page_background'))
        .onReachEnd(() => this.onReachEnd())
      }

      // 底部回复栏：输入框 + 图片/@/表情
      Row() {
        TextInput({ placeholder: $r('app.string.reply_hint'), text: $$this.replyText })
          .layoutWeight(1)
          .height(36)
          .borderRadius(18)
          .backgroundColor($r('app.color.input_background'))
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .placeholderColor($r('app.color.text_caption'))
          .padding({ left: 14, right: 14 })
        Row() {
          Image($r('app.media.ic_image'))
            .width(20)
            .height(20)
            .fillColor($r('app.color.text_secondary'))
        }
        .width(36)
        .height(36)
        .justifyContent(FlexAlign.Center)
        .hitTestBehavior(HitTestMode.Block)
        .margin({ left: 10 })
        .onClick(() => {
          this.showCommentToast();
        })
        Row() {
          Image($r('app.media.ic_mention'))
            .width(20)
            .height(20)
            .fillColor($r('app.color.text_secondary'))
        }
        .width(36)
        .height(36)
        .justifyContent(FlexAlign.Center)
        .hitTestBehavior(HitTestMode.Block)
        .margin({ left: 8 })
        .onClick(() => {
          this.showCommentToast();
        })
        Row() {
          Image($r('app.media.ic_emoji'))
            .width(20)
            .height(20)
            .fillColor($r('app.color.text_secondary'))
        }
        .width(36)
        .height(36)
        .justifyContent(FlexAlign.Center)
        .hitTestBehavior(HitTestMode.Block)
        .margin({ left: 8 })
        .onClick(() => {
          this.showCommentToast();
        })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      .backgroundColor($r('app.color.card_background'))
      .border({ width: { top: 0.5 }, color: $r('app.color.divider') })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  private formatCount(num: number): string {
    if (num >= 10000) {
      return (num / 10000).toFixed(1) + 'w';
    }
    return num.toString();
  }
}
