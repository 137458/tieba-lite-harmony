import { router } from '@kit.ArkUI';
import { TiebaAPI, SearchType, ISearchExactParams } from '../../api/TiebaAPI';
import { ExactSearch, ForumInfo, SearchForumResult } from '../../model/ForumModels';
import { LoadingView } from '../../components/LoadingView';
import { ErrorView } from '../../components/ErrorView';
import { BaseViewModel, FetchDataResult } from '../../viewmodel/BaseViewModel';
import { getAvatarImageUrl } from '../../utils/ImageLoadUtil';
import { getResourceString } from '../../utils/ResourceUtil';
import { formatRelativeTime } from '../../utils/TimeUtil';
import { CommonDataSource } from '../../utils/CommonDataSource';
import { getStatusBarHeight } from '../../utils/StatusBarUtil';

// 搜索分页大小（对齐 Android POST_SIZE=30）
const SEARCH_PAGE_SIZE: number = 30;

/** SearchPage 路由参数（吧内搜索 fname 非空，全吧搜索 fname 为空） */
interface SearchPageParams {
  fname?: string;
  keyword?: string;
}

/**
 * 吧内精确搜索 ViewModel
 * 调用 TiebaAPI.searchExact（POST /c/s/searchpost）
 */
class SearchViewModel extends BaseViewModel<ExactSearch> {
  private fname: string = '';
  private keyword: string = '';
  private searchType: SearchType = SearchType.ALL;

  setQuery(fname: string, keyword: string, searchType: SearchType = SearchType.ALL): void {
    this.fname = fname;
    this.keyword = keyword;
    this.searchType = searchType;
  }

  protected async fetchData(page: number, isRefresh: boolean): Promise<FetchDataResult<ExactSearch>> {
    const searchParams: ISearchExactParams = {
      fname: this.fname,
      keyword: this.keyword,
      page: page,
      pageSize: SEARCH_PAGE_SIZE,
      searchType: this.searchType,
      onlyThread: true
    };
    return await TiebaAPI.searchExact(searchParams);
  }
}

/**
 * 搜索帖子结果卡片（issue #31 拆为独立 @Component）
 * ExactSearch 已 @Observed，用 @ObjectLink 引用 dataSource 内部对象
 */
@Component
struct SearchPostCard {
  @ObjectLink item: ExactSearch;

  build() {
    Column() {
      // 标题
      if (this.item.title.length > 0) {
        Text(this.item.title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }

      // 内容摘要
      if (this.item.text.length > 0) {
        Text(this.item.text)
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .margin({ top: this.item.title.length > 0 ? 6 : 0 })
      }

      // 底部元信息：作者 + 吧名 + 楼中楼标记 + 时间
      Row() {
        if (this.item.showName.length > 0) {
          Text(this.item.showName)
            .fontSize(11)
            .fontColor($r('app.color.primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }

        if (this.item.fname.length > 0) {
          Text(this.item.fname)
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ left: this.item.showName.length > 0 ? 8 : 0 })
        }

        if (this.item.isComment) {
          Text($r('app.string.comment_label'))
            .fontSize(10)
            .fontColor($r('app.color.text_secondary'))
            .padding({ left: 4, right: 4, top: 1, bottom: 1 })
            .borderRadius(3)
            .backgroundColor($r('app.color.input_background'))
            .margin({ left: 8 })
        }

        Text(formatRelativeTime(this.item.createTime))
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .margin({ left: 8 })
      }
      .width('100%')
      .margin({ top: 8 })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(10)
  }
}

@Entry
@Component
struct SearchPage {
  // 帖子搜索 ViewModel + 数据源
  private postViewModel: SearchViewModel = new SearchViewModel();
  private postDataSource: CommonDataSource<ExactSearch> = new CommonDataSource<ExactSearch>();

  @State keyword: string = '';
  @State fname: string = '';
  // 搜索模式：0=帖子，1=贴吧
  @State searchMode: number = 0;
  // 是否显示贴吧 Tab（fname 为空时才显示，吧内搜索不需要搜吧）
  @State showForumTab: boolean = false;

  // 帖子搜索状态
  @State postCount: number = 0;
  @State postIsLoading: boolean = false;
  @State postHasMore: boolean = true;
  @State postErrorMessage: string = '';
  @State postHasSearched: boolean = false;

  // 贴吧搜索状态（不分页，直接用 @State 存结果）
  @State forumResult: SearchForumResult = new SearchForumResult();
  @State forumIsLoading: boolean = false;
  @State forumErrorMessage: string = '';
  @State forumHasSearched: boolean = false;

  // 状态栏高度（vp），沉浸式避让状态栏，默认 36，aboutToAppear 动态获取
  @State statusBarHeight: number = 36;
  // #93 底部安全高度，避让系统手势条
  @StorageProp('safeBottom') safeBottom: number = 0;
  // #79 图片加载策略：0=智能原图 1=智能无图 2=始终原图 3=始终无图（EntryAbility 启动时写入）
  @StorageProp('imageLoadType') imageLoadType: number = 0;
  // 网络类型（EntryAbility 网络监听写入，控制 SMART_NO 模式下是否加载图片）
  @StorageProp('isWifi') isWifi: boolean = false;

  async aboutToAppear() {
    // 获取状态栏高度（沉浸式，P1 重构提取为 StatusBarUtil），失败不阻塞搜索页加载，保留默认值 36
    try {
      this.statusBarHeight = await getStatusBarHeight(getContext(this));
    } catch (err) {
      console.error(`[SearchPage] getStatusBarHeight failed: ${(err as Error).message}`);
    }
    // 默认全吧搜索场景：显示贴吧 Tab（showForumTab=true）
    // 仅当吧内搜索（fname 非空）时才隐藏贴吧 Tab
    this.showForumTab = true;
    const params = router.getParams() as SearchPageParams;
    if (params) {
      // 支持吧内搜索（fname 非空）和全吧搜索（fname 为空）
      this.fname = params.fname || '';
      this.keyword = params.keyword || '';
      // 吧内搜索（fname 非空）不显示贴吧 Tab（吧内搜索无需搜吧）
      this.showForumTab = this.fname.length === 0;
      if (this.keyword.length > 0) {
        this.performSearch().catch((err: Error) => {
          console.error(`[SearchPage] performSearch failed: ${err.message}`);
        });
      }
    }
  }

  /**
   * 执行搜索（根据当前 searchMode 调用对应 API）
   * Tab 切换或点击搜索按钮时调用此方法
   */
  async performSearch(): Promise<void> {
    if (this.keyword.length === 0) {
      return;
    }

    if (this.searchMode === 0) {
      // 帖子搜索
      this.postHasSearched = true;
      this.postViewModel.setQuery(this.fname, this.keyword);
      await this.postViewModel.loadData(true);
      this.syncPostState();
    } else {
      // 贴吧搜索（不分页，直接调用 API 存结果到 @State）
      this.forumHasSearched = true;
      this.forumIsLoading = true;
      this.forumErrorMessage = '';
      try {
        this.forumResult = await TiebaAPI.searchForum(this.keyword);
      } catch (err) {
        this.forumErrorMessage = (err as Error).message;
        this.forumResult = new SearchForumResult();
      } finally {
        this.forumIsLoading = false;
      }
    }
  }

  async loadMorePosts(): Promise<void> {
    if (this.postViewModel.canLoadMore()) {
      await this.postViewModel.loadData(false);
      this.syncPostState();
    }
  }

  private syncPostState(): void {
    const paginationData = this.postViewModel.paginationData;
    const loadingState = this.postViewModel.loadingState;

    // issue #39：刷新用 setData 全量替换，loadMore 用 appendData 增量追加
    if (this.postViewModel.lastOpWasRefresh) {
      this.postDataSource.setData(paginationData.dataList);
    } else {
      this.postDataSource.appendData(this.postViewModel.lastAddedList);
    }
    this.postCount = this.postDataSource.totalCount();
    this.postHasMore = paginationData.hasMore;
    this.postIsLoading = loadingState.isLoading;
    this.postErrorMessage = loadingState.error;
  }

  /**
   * 切换搜索模式（Tab 切换）
   * 切换后如果已有搜索关键词且该模式尚未搜索过，自动触发对应模式的搜索
   *
   * 防御性清理：切换到帖子 Tab 时，若当前无关键词或尚未搜索，清理 postErrorMessage，
   * 避免上一次失败搜索的"搜索失败"残留显示（用户反馈：切到帖子 Tab 不搜任何东西却显示搜索失败）
   */
  switchSearchMode(mode: number): void {
    if (this.searchMode === mode) {
      return;
    }
    this.searchMode = mode;
    if (this.keyword.length > 0) {
      if (mode === 0 && !this.postHasSearched) {
        this.performSearch().catch((err: Error) => {
          console.error(`[SearchPage] switchSearchMode(0) performSearch failed: ${err.message}`);
        });
      } else if (mode === 1 && !this.forumHasSearched) {
        this.performSearch().catch((err: Error) => {
          console.error(`[SearchPage] switchSearchMode(1) performSearch failed: ${err.message}`);
        });
      }
    } else {
      // 无关键词时清理错误状态，避免残留的"搜索失败"显示
      if (mode === 0) {
        this.postErrorMessage = '';
      } else {
        this.forumErrorMessage = '';
      }
    }
  }

  /**
   * 重置两个模式的搜索状态（用户输入新关键词或点击搜索按钮时调用）
   * 这样切换 Tab 会重新触发搜索，保证结果与新关键词一致
   */
  resetSearchState(): void {
    this.postHasSearched = false;
    this.forumHasSearched = false;
    this.postCount = 0;
    this.postErrorMessage = '';
    this.forumResult = new SearchForumResult();
    this.forumErrorMessage = '';
  }

  navigateToThread(tid: number): void {
    if (tid <= 0) {
      console.warn(`[SearchPage] invalid tid: ${tid}, skip navigation`);
      return;
    }
    router.pushUrl({
      url: 'pages/thread/ThreadPage',
      params: { tid: tid.toString() }
    }).catch((err: Error) => {
      console.error(`[SearchPage] navigate to thread failed: ${err.message}`);
    });
  }

  navigateToForum(forumName: string): void {
    if (forumName.length === 0) {
      console.warn(`[SearchPage] invalid forumName, skip navigation`);
      return;
    }
    router.pushUrl({
      url: 'pages/forum/ForumPage',
      params: { forumName: forumName }
    }).catch((err: Error) => {
      console.error(`[SearchPage] navigate to forum failed: ${err.message}`);
    });
  }

  @Builder
  TabBar() {
    Row() {
      Text($r('app.string.search_tab_post'))
        .fontSize(this.searchMode === 0 ? 15 : 14)
        .fontWeight(this.searchMode === 0 ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.searchMode === 0 ? $r('app.color.primary') : $r('app.color.text_secondary'))
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .onClick(() => this.switchSearchMode(0))

      if (this.showForumTab) {
        Text($r('app.string.search_tab_forum'))
          .fontSize(this.searchMode === 1 ? 15 : 14)
          .fontWeight(this.searchMode === 1 ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(this.searchMode === 1 ? $r('app.color.primary') : $r('app.color.text_secondary'))
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .onClick(() => this.switchSearchMode(1))
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 4, bottom: 4 })
    .backgroundColor($r('app.color.page_background'))
  }

  /**
   * 贴吧搜索结果卡片（@Builder 内联渲染，避免 @Prop/@ObjectLink 对非 @Observed class 的限制）
   * @param forum 吧信息
   * @param showExactMatchBadge 是否显示"精确匹配"标签
   */
  @Builder
  ForumCard(forum: ForumInfo, showExactMatchBadge: boolean) {
    Row() {
      // 吧头像（avatar 字段为完整 URL，对齐 TiebaLite SearchForumBean.ForumInfoBean.avatar）
      // #79 接入图片加载策略：shouldLoad=false 时返回空字符串，Image 显示 alt 占位图
      Image(getAvatarImageUrl(forum.avatar, this.imageLoadType, this.isWifi))
        .width(56)
        .height(56)
        .borderRadius(28)
        .objectFit(ImageFit.Cover)
        .backgroundColor($r('app.color.input_background'))
        .alt($r('app.media.startIcon'))
        // #92 HitTestMode.Transparent：让触控穿透到父 List，避免 fling 期间碰到图片导致触控丢失
        .hitTestBehavior(HitTestMode.Transparent)

      Column() {
        // 顶部：吧名 + 精确匹配标签 + 已关注标签
        Row() {
          Text(forum.name)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)

          if (showExactMatchBadge) {
            Text($r('app.string.search_forum_exact_match'))
              .fontSize(10)
              .fontColor($r('app.color.primary'))
              .padding({ left: 4, right: 4, top: 1, bottom: 1 })
              .borderRadius(3)
              .backgroundColor($r('app.color.input_background'))
              .margin({ left: 8 })
          }

          if (forum.isFollowed) {
            Text($r('app.string.following_button'))
              .fontSize(10)
              .fontColor($r('app.color.text_secondary'))
              .padding({ left: 4, right: 4, top: 1, bottom: 1 })
              .borderRadius(3)
              .backgroundColor($r('app.color.input_background'))
              .margin({ left: 8 })
          }
        }
        .width('100%')

        // slogan（吧宣言）
        if (forum.slogan.length > 0) {
          Text(forum.slogan)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .margin({ top: 4 })
        }

        // 底部元信息：关注数 + 帖子数
        Row() {
          Text(`${getResourceString($r('app.string.search_forum_member_count'))} ${forum.memberCount}`)
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))

          Text(`${getResourceString($r('app.string.search_forum_post_count'))} ${forum.postCount}`)
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
            .margin({ left: 12 })
        }
        .width('100%')
        .margin({ top: 4 })
      }
      .layoutWeight(1)
      .margin({ left: 12 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(10)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  PostContent() {
    if (this.postIsLoading && this.postCount === 0) {
      LoadingView({ message: getResourceString($r('app.string.loading')) })
        .layoutWeight(1)
    } else if (this.postErrorMessage.length > 0 && this.postCount === 0) {
      ErrorView({
        message: this.postErrorMessage,
        onRetryClick: () => {
          this.performSearch().catch((err: Error) => {
            console.error(`[SearchPage] performSearch(onRetryClick) failed: ${err.message}`);
          });
        }
      })
        .layoutWeight(1)
    } else if (this.postHasSearched && this.postCount === 0) {
      Column() {
        Text($r('app.string.search_no_result'))
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 12 })
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    } else {
      List({ space: 8 }) {
        LazyForEach(this.postDataSource, (item: ExactSearch) => {
          ListItem() {
            SearchPostCard({ item: item })
          }
          .onClick(() => this.navigateToThread(item.tid))
        }, (item: ExactSearch, index: number) => `${item.tid}_${item.pid}`)

        if (this.postIsLoading && this.postCount > 0) {
          ListItem() {
            LoadingView({ message: getResourceString($r('app.string.loading_more')) })
              .height(60)
          }
        }
      }
      .width('100%')
      .layoutWeight(1)
      .divider({ strokeWidth: 0 })
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .cachedCount(5)
      // #93 padding bottom = safeBottom + 16：避让系统手势条，backgroundColor 与外层一致消除遮罩
      .padding({ left: 16, right: 16, bottom: this.safeBottom + 16 })
      .backgroundColor($r('app.color.page_background'))
      .onReachEnd(() => {
        // onReachEnd 回调不处理 async 返回值，需 catch 避免 unhandled rejection
        this.loadMorePosts().catch((err: Error) => {
          console.error(`[SearchPage] loadMore failed: ${err.message}`);
        });
      })
    }
  }

  @Builder
  ForumContent() {
    if (this.forumIsLoading) {
      LoadingView({ message: getResourceString($r('app.string.loading')) })
        .layoutWeight(1)
    } else if (this.forumErrorMessage.length > 0) {
      ErrorView({
        message: this.forumErrorMessage,
        onRetryClick: () => {
          this.performSearch().catch((err: Error) => {
            console.error(`[SearchPage] performSearch(onRetryClick) failed: ${err.message}`);
          });
        }
      })
        .layoutWeight(1)
    } else if (this.forumHasSearched && !this.forumResult.hasExactMatch && this.forumResult.fuzzyMatch.length === 0) {
      Column() {
        Text($r('app.string.search_forum_no_result'))
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 12 })
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    } else {
      List({ space: 8 }) {
        // 精确匹配（exactMatch，单个）
        if (this.forumResult.hasExactMatch) {
          ListItem() {
            this.ForumCard(this.forumResult.exactMatch, true)
          }
          .onClick(() => this.navigateToForum(this.forumResult.exactMatch.name))
        }

        // 模糊匹配（fuzzyMatch，列表）
        if (this.forumResult.fuzzyMatch.length > 0) {
          // 有精确匹配时显示分组标题
          if (this.forumResult.hasExactMatch) {
            ListItem() {
              Text($r('app.string.search_forum_fuzzy_match'))
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
                .margin({ top: 8, bottom: 4 })
            }
          }
          ForEach(this.forumResult.fuzzyMatch, (forum: ForumInfo, index: number) => {
            ListItem() {
              this.ForumCard(forum, false)
            }
            .onClick(() => this.navigateToForum(forum.name))
          }, (forum: ForumInfo, index: number) => `${forum.id}_${index}`)
        }
      }
      .width('100%')
      .layoutWeight(1)
      .divider({ strokeWidth: 0 })
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      // #93 padding bottom = safeBottom + 16：避让系统手势条，backgroundColor 与外层一致消除遮罩
      .padding({ left: 16, right: 16, bottom: this.safeBottom + 16 })
      .backgroundColor($r('app.color.page_background'))
    }
  }

  build() {
    Column() {
      // 顶部搜索栏（对齐原型导航栏 44px + 搜索框 36px/10px 圆角）
      Row() {
        Image($r('app.media.ic_back'))
          .width(20)
          .height(20)
          .fillColor($r('app.color.primary'))
          .onClick(() => {
            router.back();
          })

        Row() {
          TextInput({ placeholder: $r('app.string.search_hint'), text: $$this.keyword })
            .width('100%')
            .height(36)
            .fontSize(14)
            .backgroundColor(Color.Transparent)
            .padding({ left: 8 })
            .onSubmit(() => {
              // 新关键词搜索：重置两模式状态，保证切换 Tab 时重新搜索
              this.resetSearchState();
              this.performSearch().catch((err: Error) => {
                console.error(`[SearchPage] performSearch(onSubmit) failed: ${err.message}`);
              });
            })
        }
        .width('100%')
        .height(36)
        .padding({ left: 10, right: 8 })
        .backgroundColor($r('app.color.input_background'))
        .borderRadius(10)
        .layoutWeight(1)
        .margin({ left: 12 })

        Text($r('app.string.search_button'))
          .fontSize(15)
          .fontColor($r('app.color.primary'))
          .margin({ left: 12 })
          .onClick(() => {
            // 新关键词搜索：重置两模式状态，保证切换 Tab 时重新搜索
            this.resetSearchState();
            this.performSearch().catch((err: Error) => {
              console.error(`[SearchPage] performSearch(onClick) failed: ${err.message}`);
            });
          })
      }
      .width('100%')
      .height(44 + this.statusBarHeight)
      .padding({ left: 16, right: 16, top: this.statusBarHeight })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
      .alignItems(VerticalAlign.Center)
      .backgroundColor($r('app.color.page_background'))

      // Tab 切换栏（仅全吧搜索时显示，吧内搜索只搜帖子）
      if (this.showForumTab) {
        this.TabBar()
      }

      // 内容区（根据 searchMode 切换）
      if (this.searchMode === 0) {
        this.PostContent()
      } else {
        this.ForumContent()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
    // #93 背景延伸到系统手势条区域，消除底部遮罩
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }
}
