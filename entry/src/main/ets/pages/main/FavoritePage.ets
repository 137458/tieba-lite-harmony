// 动态页 3-Tab（Phase B Issue #67）
// 替代原单 Tab FavoritePage 实现，对齐 Android ExplorePage.kt：
//   - 关注 Tab（仅登录后显示）：TiebaAPI.getUserLikeFlow（/c/f/concern/userlike?cmd=309474）
//   - 推荐 Tab：TiebaAPI.getPersonalized（/c/f/excellent/personalized?cmd=309264）
//   - 热榜 Tab：TiebaAPI.getHotThreadList（/c/f/forum/hotThreadList?cmd=309661）
// 默认初始页：推荐（对齐原 app initialPage = if (account != null) 1 else 0）

import { router, promptAction } from '@kit.ArkUI';
import { TiebaAPI } from '../../api/TiebaAPI';
import {
  ThreadInfo,
  UserLikeResult,
  HotThreadListResult,
  HotTopicInfo,
  HotTabInfo
} from '../../model/ForumModels';
import { ThreadCard } from '../../components/ThreadCard';
import { LoadingView } from '../../components/LoadingView';
import { ErrorView } from '../../components/ErrorView';
import { getResourceString } from '../../utils/ResourceUtil';
import { getStatusBarHeight } from '../../utils/StatusBarUtil';
import { handleThreadAgree, handleThreadDisagree } from '../../utils/ThreadInteractionHelper';
import { BaseViewModel, FetchDataResult } from '../../viewmodel/BaseViewModel';
import { CommonDataSource } from '../../utils/CommonDataSource';
import { AppStorageManager } from '../../data/AppStorage';

// ==================== ViewModel ====================

/**
 * 关注 Tab ViewModel（沿用 pageTag 游标分页）
 * - isRefresh=true: pageTag="" + loadType=1
 * - isRefresh=false: pageTag=nextPageTag + loadType=2
 */
class UserLikeViewModel extends BaseViewModel<ThreadInfo> {
  private nextPageTag: string = '';

  protected async fetchData(page: number, isRefresh: boolean): Promise<FetchDataResult<ThreadInfo>> {
    const pageTag: string = isRefresh ? '' : this.nextPageTag;
    const loadType: number = isRefresh ? 1 : 2;
    const result: UserLikeResult = await TiebaAPI.getUserLikeFlow(pageTag, loadType);
    this.nextPageTag = result.pageTag;
    return {
      list: result.threadList,
      hasMore: result.hasMore,
      currentPage: page
    };
  }
}

/**
 * 推荐 Tab ViewModel（pn 数字分页，对齐原 app PersonalizedViewModel）
 * - page=1: loadType=1（刷新）
 * - page>1: loadType=2（加载更多）
 */
class PersonalizedViewModel extends BaseViewModel<ThreadInfo> {
  protected async fetchData(page: number, isRefresh: boolean): Promise<FetchDataResult<ThreadInfo>> {
    // getPersonalized 内部根据 page===1 自动决定 loadType
    const result = await TiebaAPI.getPersonalized(page, 11);
    return {
      list: result.list,
      hasMore: result.hasMore,
      currentPage: page
    };
  }
}

/**
 * 热榜 Tab ViewModel（无分页，一次拉全量，切换子 Tab 仅更新 threadList）
 * 对齐原 app HotViewModel：load() 拉全量 / refreshThreadList(tabCode) 切换子 Tab
 */
class HotThreadListViewModel {
  private topicList: HotTopicInfo[] = [];
  private tabList: HotTabInfo[] = [];
  private threadDataSource: CommonDataSource<ThreadInfo> = new CommonDataSource<ThreadInfo>();
  private currentTabCode: string = 'all';

  isLoading: boolean = false;
  errorMessage: string = '';
  isLoaded: boolean = false;  // 是否已加载过（避免重复加载）

  getDataSource(): CommonDataSource<ThreadInfo> {
    return this.threadDataSource;
  }

  getTopicList(): HotTopicInfo[] {
    return this.topicList;
  }

  getTabList(): HotTabInfo[] {
    return this.tabList;
  }

  getCurrentTabCode(): string {
    return this.currentTabCode;
  }

  /** 取话题榜前 4 项用于 2x2 Grid 展示（封装 slice 避免在 build() 中创建新数组） */
  getTopTopics(): HotTopicInfo[] {
    return this.topicList.length > 4 ? this.topicList.slice(0, 4) : this.topicList;
  }

  /** 首次加载或刷新：拉取全量（话题榜 + 子 Tab + 帖子列表） */
  async load(): Promise<void> {
    if (this.isLoading) {
      return;
    }
    this.isLoading = true;
    this.errorMessage = '';
    try {
      const result: HotThreadListResult = await TiebaAPI.getHotThreadList('all');
      this.topicList = result.topicList;
      this.tabList = result.tabList;
      this.currentTabCode = 'all';
      this.threadDataSource.setData(result.threadList);
      this.isLoaded = true;
    } catch (err) {
      this.errorMessage = (err as Error).message || '获取热榜失败';
    } finally {
      this.isLoading = false;
    }
  }

  /** 切换子 Tab：仅更新帖子列表，不更新话题榜和 Tab 列表 */
  async refreshThreadList(tabCode: string): Promise<void> {
    if (this.isLoading || tabCode === this.currentTabCode) {
      return;
    }
    this.isLoading = true;
    this.errorMessage = '';
    try {
      const result: HotThreadListResult = await TiebaAPI.getHotThreadList(tabCode);
      this.currentTabCode = tabCode;
      this.threadDataSource.setData(result.threadList);
    } catch (err) {
      this.errorMessage = (err as Error).message || '获取热榜失败';
    } finally {
      this.isLoading = false;
    }
  }
}

// ==================== 关注 Tab ====================

/**
 * 关注 Tab（仅登录后显示）
 * 数据源：UserLikeViewModel（pageTag 游标分页）
 */
@Component
struct ConcernTab {
  private viewModel: UserLikeViewModel = new UserLikeViewModel();
  private dataSource: CommonDataSource<ThreadInfo> = new CommonDataSource<ThreadInfo>();

  @State threadCount: number = 0;
  @State isLoading: boolean = false;
  @State hasMore: boolean = true;
  @State errorMessage: string = '';
  @State bduss: string = '';
  @State isLoaded: boolean = false;

  async aboutToAppear() {
    try {
      const storage: AppStorageManager = AppStorageManager.getInstance();
      await storage.ensureReady();
      this.bduss = await storage.getString('bduss', '');
    } catch (err) {
      console.error(`[ConcernTab] storage init failed: ${(err as Error).message}`);
    }
    if (this.bduss.length > 0 && !this.isLoaded) {
      this.isLoaded = true;
      this.loadThreads(true).catch((err: Error) => {
        console.error(`[ConcernTab] loadThreads failed: ${err.message}`);
      });
    }
  }

  async loadThreads(isRefresh: boolean = false): Promise<void> {
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
    this.threadCount = this.dataSource.totalCount();
    this.hasMore = paginationData.hasMore;
    this.isLoading = loadingState.isLoading;
    this.errorMessage = loadingState.error;
  }

  onReachEnd(): void {
    if (this.viewModel.canLoadMore()) {
      this.loadThreads(false);
    }
  }

  navigateToThread(tid: number): void {
    if (tid <= 0) {
      console.warn(`[ConcernTab] invalid tid: ${tid}, skip navigation`);
      return;
    }
    router.pushUrl({
      url: 'pages/thread/ThreadPage',
      params: { tid: tid.toString() }
    }).catch((err: Error) => {
      console.error(`[ConcernTab] navigate to thread failed: ${err.message}`);
    });
  }

  navigateToUserProfile(portrait: string, userName: string, uid: number): void {
    router.pushUrl({
      url: 'pages/user/UserProfilePage',
      params: { portrait: portrait, userName: userName, uid: uid }
    }).catch((err: Error) => {
      console.error(`[ConcernTab] navigate to userProfile failed: ${err.message}`);
    });
  }

  async handleAgree(thread: ThreadInfo): Promise<void> {
    await handleThreadAgree(this.dataSource, thread);
  }

  async handleDisagree(thread: ThreadInfo): Promise<void> {
    await handleThreadDisagree(this.dataSource, thread);
  }

  showCommentToast(): void {
    promptAction.showToast({ message: getResourceString($r('app.string.page_developing')) });
  }

  navigateToLogin(): void {
    router.pushUrl({ url: 'pages/main/LoginPage' }).catch((err: Error) => {
      console.error(`[ConcernTab] navigate to login failed: ${err.message}`);
    });
  }

  build() {
    if (this.bduss.length === 0) {
      // 未登录：登录引导
      Column() {
        Text($r('app.string.favorite_login_required'))
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .margin({ bottom: 12 })
        Text($r('app.string.login_button'))
          .fontSize(14)
          .fontColor($r('app.color.primary'))
          .padding({ left: 24, right: 24, top: 8, bottom: 8 })
          .border({ width: 1, color: $r('app.color.primary'), radius: 20 })
          .onClick(() => this.navigateToLogin())
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    } else if (this.errorMessage.length > 0 && this.threadCount === 0) {
      ErrorView({
        message: this.errorMessage,
        onRetryClick: () => this.loadThreads(true).catch((err: Error) => {
          console.error(`[ConcernTab] retry failed: ${err.message}`);
        })
      })
        .width('100%')
        .height('100%')
    } else if (this.threadCount === 0 && !this.isLoading) {
      Column() {
        Text($r('app.string.concern_empty'))
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    } else {
      List() {
        LazyForEach(this.dataSource, (thread: ThreadInfo) => {
          ListItem() {
            ThreadCard({
              thread: thread,
              onCardClick: () => this.navigateToThread(thread.tid),
              onAuthorClick: () => this.navigateToUserProfile(
                thread.author.portrait,
                thread.author.name,
                thread.author.uid
              ),
              onAgreeClick: (t: ThreadInfo) => {
                this.handleAgree(t).catch((err: Error) => {
                  console.error(`[ConcernTab] handleAgree failed: ${err.message}`);
                });
              },
              onDisagreeClick: (t: ThreadInfo) => {
                this.handleDisagree(t).catch((err: Error) => {
                  console.error(`[ConcernTab] handleDisagree failed: ${err.message}`);
                });
              },
              onCommentClick: () => this.showCommentToast()
            })
          }
          .margin({ top: 4, bottom: 4 })
        }, (thread: ThreadInfo) => thread.tid.toString())

        if (this.isLoading && this.threadCount > 0) {
          ListItem() {
            LoadingView({ message: getResourceString($r('app.string.loading_more')) })
              .height(60)
          }
        }
      }
      .width('100%')
      .height('100%')
      .divider({ strokeWidth: 0 })
      .padding({ left: 16, right: 16 })
      .edgeEffect(EdgeEffect.Spring)
      .cachedCount(5)
      .onReachEnd(() => this.onReachEnd())
    }
  }
}

// ==================== 推荐 Tab ====================

/**
 * 推荐 Tab（默认初始页）
 * 数据源：PersonalizedViewModel（pn 数字分页，page 从 1 开始）
 */
@Component
struct PersonalizedTab {
  private viewModel: PersonalizedViewModel = new PersonalizedViewModel();
  private dataSource: CommonDataSource<ThreadInfo> = new CommonDataSource<ThreadInfo>();

  @State threadCount: number = 0;
  @State isLoading: boolean = false;
  @State hasMore: boolean = true;
  @State errorMessage: string = '';
  @State isLoaded: boolean = false;

  async aboutToAppear() {
    if (!this.isLoaded) {
      this.isLoaded = true;
      this.loadThreads(true).catch((err: Error) => {
        console.error(`[PersonalizedTab] loadThreads failed: ${err.message}`);
      });
    }
  }

  async loadThreads(isRefresh: boolean = false): Promise<void> {
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
    this.threadCount = this.dataSource.totalCount();
    this.hasMore = paginationData.hasMore;
    this.isLoading = loadingState.isLoading;
    this.errorMessage = loadingState.error;
  }

  onReachEnd(): void {
    if (this.viewModel.canLoadMore()) {
      this.loadThreads(false);
    }
  }

  navigateToThread(tid: number): void {
    if (tid <= 0) {
      console.warn(`[PersonalizedTab] invalid tid: ${tid}, skip navigation`);
      return;
    }
    router.pushUrl({
      url: 'pages/thread/ThreadPage',
      params: { tid: tid.toString() }
    }).catch((err: Error) => {
      console.error(`[PersonalizedTab] navigate to thread failed: ${err.message}`);
    });
  }

  navigateToUserProfile(portrait: string, userName: string, uid: number): void {
    router.pushUrl({
      url: 'pages/user/UserProfilePage',
      params: { portrait: portrait, userName: userName, uid: uid }
    }).catch((err: Error) => {
      console.error(`[PersonalizedTab] navigate to userProfile failed: ${err.message}`);
    });
  }

  async handleAgree(thread: ThreadInfo): Promise<void> {
    await handleThreadAgree(this.dataSource, thread);
  }

  async handleDisagree(thread: ThreadInfo): Promise<void> {
    await handleThreadDisagree(this.dataSource, thread);
  }

  showCommentToast(): void {
    promptAction.showToast({ message: getResourceString($r('app.string.page_developing')) });
  }

  build() {
    if (this.errorMessage.length > 0 && this.threadCount === 0) {
      ErrorView({
        message: this.errorMessage,
        onRetryClick: () => this.loadThreads(true).catch((err: Error) => {
          console.error(`[PersonalizedTab] retry failed: ${err.message}`);
        })
      })
        .width('100%')
        .height('100%')
    } else if (this.threadCount === 0 && !this.isLoading) {
      Column() {
        Text($r('app.string.personalized_empty'))
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    } else {
      List() {
        LazyForEach(this.dataSource, (thread: ThreadInfo) => {
          ListItem() {
            ThreadCard({
              thread: thread,
              onCardClick: () => this.navigateToThread(thread.tid),
              onAuthorClick: () => this.navigateToUserProfile(
                thread.author.portrait,
                thread.author.name,
                thread.author.uid
              ),
              onAgreeClick: (t: ThreadInfo) => {
                this.handleAgree(t).catch((err: Error) => {
                  console.error(`[PersonalizedTab] handleAgree failed: ${err.message}`);
                });
              },
              onDisagreeClick: (t: ThreadInfo) => {
                this.handleDisagree(t).catch((err: Error) => {
                  console.error(`[PersonalizedTab] handleDisagree failed: ${err.message}`);
                });
              },
              onCommentClick: () => this.showCommentToast()
            })
          }
          .margin({ top: 4, bottom: 4 })
        }, (thread: ThreadInfo) => thread.tid.toString())

        if (this.isLoading && this.threadCount > 0) {
          ListItem() {
            LoadingView({ message: getResourceString($r('app.string.loading_more')) })
              .height(60)
          }
        }
      }
      .width('100%')
      .height('100%')
      .divider({ strokeWidth: 0 })
      .padding({ left: 16, right: 16 })
      .edgeEffect(EdgeEffect.Spring)
      .cachedCount(5)
      .onReachEnd(() => this.onReachEnd())
    }
  }
}

// ==================== 热榜 Tab ====================

/**
 * 热榜 Tab（3 段式：话题榜 + 子 Tab 切换 + 帖子列表）
 * 数据源：HotThreadListViewModel（无分页，一次拉全量，切换子 Tab 仅更新帖子列表）
 */
@Component
struct HotTab {
  private viewModel: HotThreadListViewModel = new HotThreadListViewModel();
  @State isLoading: boolean = false;
  @State errorMessage: string = '';
  @State isLoaded: boolean = false;
  // P0-2 优化：将 viewModel 内部字段提升为 @State，移除 refreshTick 强制刷新
  // @State 变化自动触发 build()，无需手动递增计数器
  @State topicList: HotTopicInfo[] = [];
  @State tabList: HotTabInfo[] = [];
  @State currentTabCode: string = 'all';
  @State threadCount: number = 0;
  // P2 优化：缓存 getTopTopics() 的 slice 结果，避免每次 build 都创建新数组
  @State topTopics: HotTopicInfo[] = [];

  async aboutToAppear() {
    if (!this.isLoaded) {
      this.isLoaded = true;
      this.loadHot().catch((err: Error) => {
        console.error(`[HotTab] loadHot failed: ${err.message}`);
      });
    }
  }

  async loadHot(): Promise<void> {
    await this.viewModel.load();
    this.syncViewModelState();
  }

  async switchTab(tabCode: string): Promise<void> {
    await this.viewModel.refreshThreadList(tabCode);
    this.syncViewModelState();
  }

  /** 同步 viewModel 状态到 @State，触发 build 刷新 */
  private syncViewModelState(): void {
    this.isLoading = this.viewModel.isLoading;
    this.errorMessage = this.viewModel.errorMessage;
    this.topicList = this.viewModel.getTopicList();
    this.tabList = this.viewModel.getTabList();
    this.currentTabCode = this.viewModel.getCurrentTabCode();
    this.threadCount = this.viewModel.getDataSource().totalCount();
    // 缓存 slice 结果，build() 直接读取
    this.topTopics = this.topicList.length > 4 ? this.topicList.slice(0, 4) : this.topicList;
  }

  navigateToThread(tid: number): void {
    if (tid <= 0) {
      console.warn(`[HotTab] invalid tid: ${tid}, skip navigation`);
      return;
    }
    router.pushUrl({
      url: 'pages/thread/ThreadPage',
      params: { tid: tid.toString() }
    }).catch((err: Error) => {
      console.error(`[HotTab] navigate to thread failed: ${err.message}`);
    });
  }

  navigateToUserProfile(portrait: string, userName: string, uid: number): void {
    router.pushUrl({
      url: 'pages/user/UserProfilePage',
      params: { portrait: portrait, userName: userName, uid: uid }
    }).catch((err: Error) => {
      console.error(`[HotTab] navigate to userProfile failed: ${err.message}`);
    });
  }

  async handleAgree(thread: ThreadInfo): Promise<void> {
    await handleThreadAgree(this.viewModel.getDataSource(), thread);
  }

  async handleDisagree(thread: ThreadInfo): Promise<void> {
    await handleThreadDisagree(this.viewModel.getDataSource(), thread);
  }

  showCommentToast(): void {
    promptAction.showToast({ message: getResourceString($r('app.string.page_developing')) });
  }

  /** 获取排名颜色（Top1 红 / Top2 橙 / Top3 黄 / 其他 text_secondary） */
  private getRankColor(index: number): Resource {
    if (index === 0) {
      return $r('app.color.hot_rank_1');
    } else if (index === 1) {
      return $r('app.color.hot_rank_2');
    } else if (index === 2) {
      return $r('app.color.hot_rank_3');
    }
    return $r('app.color.text_secondary');
  }

  build() {
    if (this.errorMessage.length > 0 && this.threadCount === 0) {
      ErrorView({
        message: this.errorMessage,
        onRetryClick: () => this.loadHot().catch((err: Error) => {
          console.error(`[HotTab] retry failed: ${err.message}`);
        })
      })
        .width('100%')
        .height('100%')
    } else if (this.threadCount === 0 && !this.isLoading) {
      Column() {
        Text($r('app.string.hot_thread_empty'))
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    } else {
      // 用 List 统一承载话题榜 + 子 Tab + 帖子列表，避免 LazyForEach 嵌套滚动问题
      List() {
        // 1. 话题榜区（仅当有话题数据时显示，最多展示前 4 个 2x2 Grid）
        if (this.topicList.length > 0) {
          ListItem() {
            this.HotTopicSection()
          }
        }

        // 2. 子 Tab 切换区（仅当有子 Tab 时显示，固定首项"全部"）
        if (this.tabList.length > 0) {
          ListItem() {
            this.HotTabSection()
          }
        }

        // 3. 帖子列表（LazyForEach 必须在 List 内，带排名 + 热度信息）
        LazyForEach(this.viewModel.getDataSource(), (thread: ThreadInfo, index: number) => {
          ListItem() {
            Column() {
              ThreadCard({
                thread: thread,
                onCardClick: () => this.navigateToThread(thread.tid),
                onAuthorClick: () => this.navigateToUserProfile(
                  thread.author.portrait,
                  thread.author.name,
                  thread.author.uid
                ),
                onAgreeClick: (t: ThreadInfo) => {
                  this.handleAgree(t).catch((err: Error) => {
                    console.error(`[HotTab] handleAgree failed: ${err.message}`);
                  });
                },
                onDisagreeClick: (t: ThreadInfo) => {
                  this.handleDisagree(t).catch((err: Error) => {
                    console.error(`[HotTab] handleDisagree failed: ${err.message}`);
                  });
                },
                onCommentClick: () => this.showCommentToast()
              })
              // 排名 + 热度信息（位于卡片下方右侧，对齐原 app FeedCard dislikeAction 槽位）
              Row() {
                Text((index + 1).toString())
                  .fontSize(16)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.getRankColor(index))
                Text(getResourceString($r('app.string.hot_num_label')) + ' ' + thread.hotNum.toString())
                  .fontSize(11)
                  .fontColor($r('app.color.text_secondary'))
                  .margin({ left: 8 })
              }
              .width('100%')
              .justifyContent(FlexAlign.End)
              .padding({ right: 16, bottom: 8 })
            }
          }
          .margin({ top: 4, bottom: 4 })
        }, (thread: ThreadInfo) => thread.tid.toString())

        if (this.isLoading) {
          ListItem() {
            LoadingView({ message: getResourceString($r('app.string.loading_more')) })
              .height(60)
          }
        }
      }
      .width('100%')
      .height('100%')
      .divider({ strokeWidth: 0 })
      .padding({ left: 16, right: 16 })
      .edgeEffect(EdgeEffect.Spring)
      .cachedCount(5)
    }
  }

  @Builder
  HotTopicSection() {
    Column() {
      Text($r('app.string.hot_topic_rank'))
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .margin({ left: 16, top: 12, bottom: 8 })
        .width('100%')

      Grid() {
        ForEach(this.topTopics, (topic: HotTopicInfo, index: number) => {
          GridItem() {
            this.HotTopicItem(topic, index)
          }
        }, (topic: HotTopicInfo) => topic.topicId.toString())
      }
      .columnsTemplate('1fr 1fr')
      .columnsGap(8)
      .rowsGap(8)
      .padding({ left: 16, right: 16, bottom: 12 })
      .width('100%')
      .height(160)
    }
    .width('100%')
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(10)
    .margin({ top: 8 })
  }

  @Builder
  HotTopicItem(topic: HotTopicInfo, index: number) {
    Row() {
      // 排名
      Text((index + 1).toString())
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.getRankColor(index))
        .width(28)

      // 话题名 + 讨论数
      Column() {
        Text(topic.topicName)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(topic.discussNum.toString() + ' ' + getResourceString($r('app.string.hot_topic_discuss_label')))
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 8 })
    }
    .width('100%')
    .padding(12)
    .backgroundColor($r('app.color.background'))
    .borderRadius(8)
  }

  @Builder
  HotTabSection() {
    // 横向滚动的子 Tab（包含固定首项"全部"）
    Scroll() {
      Row() {
        // 固定首项"全部"
        this.HotTabItem(getResourceString($r('app.string.tab_all_hot_thread')), 'all')

        // 服务端返回的子 Tab
        ForEach(this.tabList, (tab: HotTabInfo) => {
          this.HotTabItem(tab.tabName, tab.tabCode)
        }, (tab: HotTabInfo) => tab.tabCode)
      }
      .padding({ left: 16, right: 16 })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .height(44)
    .margin({ top: 8, bottom: 8 })
  }

  @Builder
  HotTabItem(tabName: string, tabCode: string) {
    Text(tabName)
      .fontSize(13)
      .fontColor(this.currentTabCode === tabCode ?
        $r('app.color.card_background') : $r('app.color.text_primary'))
      .backgroundColor(this.currentTabCode === tabCode ?
        $r('app.color.primary') : $r('app.color.background'))
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .borderRadius(14)
      .margin({ right: 8 })
      .onClick(() => {
        this.switchTab(tabCode).catch((err: Error) => {
          console.error(`[HotTab] switchTab failed: ${err.message}`);
        });
      })
  }
}

// ==================== 顶层动态页 ====================

/**
 * 动态页顶层容器（Phase B Issue #67）
 * 3-Tab 结构：关注（仅登录后显示）/ 推荐 / 热榜
 * 默认初始页：推荐（对齐原 app initialPage = if (account != null) 1 else 0）
 */
@Component
export struct FavoritePage {
  @State statusBarHeight: number = 36;
  @State bduss: string = '';
  // 当前选中的 Tab 索引：未登录=0（推荐），已登录=1（推荐）
  @State currentTab: number = 0;
  @State isReady: boolean = false;
  // Tabs 控制器：用于编程式切换 Tab（顶部自定义 TabButton 点击时调用 changeIndex）
  private tabsController: TabsController = new TabsController();

  async aboutToAppear() {
    try {
      this.statusBarHeight = await getStatusBarHeight(getContext(this));
    } catch (err) {
      console.error(`[FavoritePage] getStatusBarHeight failed: ${(err as Error).message}`);
    }
    const storage: AppStorageManager = AppStorageManager.getInstance();
    await storage.ensureReady();
    this.bduss = await storage.getString('bduss', '');
    // 已登录时初始页为推荐（索引 1），未登录时为推荐（索引 0）
    this.currentTab = this.bduss.length > 0 ? 1 : 0;
    this.isReady = true;
  }

  build() {
    Column() {
      // iOS Large Title 顶部栏（34px 800，对齐 HomePage/ProfilePage 主页面规范）
      Row() {
        Text($r('app.string.favorite_page_title'))
          .fontSize(34)
          .fontWeight(800)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .textAlign(TextAlign.Start)
      }
      .width('100%')
      .height(56 + this.statusBarHeight)
      .padding({ left: 16, right: 16, top: this.statusBarHeight, bottom: 8 })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
      .alignItems(VerticalAlign.Center)

      // 3-Tab 切换栏（大标题下方，对齐原型 dynamic-header 下的 Tab 语义）
      Row() {
        if (this.bduss.length > 0) {
          // 已登录：3-Tab
          this.TabButton($r('app.string.explore_tab_concern'), 0)
          this.TabButton($r('app.string.explore_tab_personalized'), 1)
          this.TabButton($r('app.string.explore_tab_hot'), 2)
        } else {
          // 未登录：2-Tab（关注 Tab 隐藏）
          this.TabButton($r('app.string.explore_tab_personalized'), 0)
          this.TabButton($r('app.string.explore_tab_hot'), 1)
        }
      }
      .width('100%')
      .height(44)
      .padding({ left: 16, right: 16 })

      // Tab 内容区（#68 P0 重构：用 Tabs + TabContent 代替 Stack + Visibility.None）
      // 由 Tabs 内部保持所有子页面状态，切换 Tab 不销毁组件，保留数据/滚动位置
      if (this.isReady) {
        Tabs({
          barPosition: BarPosition.Start,
          index: this.currentTab,
          controller: this.tabsController
        }) {
          // 关注 Tab（仅登录后渲染）
          if (this.bduss.length > 0) {
            TabContent() {
              ConcernTab()
            }
            .tabBar('')
          }

          // 推荐 Tab
          TabContent() {
            PersonalizedTab()
          }
          .tabBar('')

          // 热榜 Tab
          TabContent() {
            HotTab()
          }
          .tabBar('')
        }
        .barHeight(0)
        .scrollable(true)
        .animationDuration(300)
        .layoutWeight(1)
        .onChange((index: number) => {
          this.currentTab = index;
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }

  @Builder
  TabButton(label: Resource, index: number) {
    Text(label)
      .fontSize(this.currentTab === index ? 16 : 14)
      .fontWeight(this.currentTab === index ? FontWeight.Bold : FontWeight.Normal)
      .fontColor(this.currentTab === index ?
        $r('app.color.text_primary') : $r('app.color.text_secondary'))
      .layoutWeight(1)
      .textAlign(TextAlign.Center)
      .height('100%')
      .onClick(() => {
        // 编程式切换 Tab（带动画），onChange 回调同步 currentTab 状态
        this.tabsController.changeIndex(index);
      })
  }
}
