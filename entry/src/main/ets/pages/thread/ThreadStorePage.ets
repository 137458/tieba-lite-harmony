// 收藏帖子列表页（issue #49 切片2）
// 数据来源：TiebaAPI.getThreadStore（/c/f/post/threadstore）
// 入口：ProfilePage "我的收藏" 菜单项
// 展示已收藏的帖子，点击跳转 ThreadPage

import { AppStorageV2 } from '@kit.ArkUI';
import { HdsNavDestination, ScrollEffectType, hdsMaterial } from '@kit.UIDesignKit';
import { TiebaAPI } from '../../api/TiebaAPI';
import { ThreadInfo } from '../../model/ForumModels';
import { ImageLoadTypeState, IsWifiState } from '../../model/AppStorageV2Models';
import { ThreadCard } from '../../components/ThreadCard';
import { LoadingView } from '../../components/LoadingView';
import { ErrorView } from '../../components/ErrorView';
import { getResourceString } from '../../utils/ResourceUtil';
import { handleThreadAgree, handleThreadDisagree } from '../../utils/ThreadInteractionHelper';
import { BaseViewModel, FetchDataResult } from '../../viewmodel/BaseViewModel';
import { CommonDataSource } from '../../utils/CommonDataSource';
import { connectTheme, ThemeState } from '../../theme/ThemeManager';
import { RouterUtil, ThreadNavParams, UserProfileNavParams } from '../../utils/RouterUtil';

// #163 [A4-S3] Navigation 路由表 @Builder：供 router_map.json 的 buildFunction 引用
@Builder
export function ThreadStorePageBuilder() {
  ThreadStorePage()
}

/**
 * 收藏列表 ViewModel
 * 调用 TiebaAPI.getThreadStore（/c/f/post/threadstore，offset 分页）
 */
class ThreadStoreViewModel extends BaseViewModel<ThreadInfo> {
  // 每页收藏数（对齐原 app 默认 res_num）
  private static readonly PAGE_SIZE: number = 20;

  protected async fetchData(page: number, isRefresh: boolean): Promise<FetchDataResult<ThreadInfo>> {
    // BaseViewModel currentPage 从 1 开始，getThreadStore page 从 0 开始（对齐 Android），需 -1
    return await TiebaAPI.getThreadStore(page - 1, ThreadStoreViewModel.PAGE_SIZE);
  }
}

@ComponentV2
export struct ThreadStorePage {
  private viewModel: ThreadStoreViewModel = new ThreadStoreViewModel();
  private dataSource: CommonDataSource<ThreadInfo> = new CommonDataSource<ThreadInfo>();
  // #163 滚动器，绑定到 HdsNavDestination.bindToScrollable 实现标题栏滚动动态模糊
  private scroller: Scroller = new Scroller();
  // 组件是否已销毁标志位：aboutToDisappear 置 true，所有 async 任务完成后检查，
  // 避免页面销毁后修改 @Local 触发警告或操作已销毁的 dataSource
  // 用 private 而非 @Local：标志位变化无需触发 UI 重渲染（对齐 ThreadPage.ets / SubPostsPage isProcessingSubPostAgree 惯例）
  private isDestroyed: boolean = false;

  @Local threadCount: number = 0;
  @Local isLoading: boolean = false;
  @Local isRefreshing: boolean = false;
  @Local hasMore: boolean = true;
  @Local errorMessage: string = '';
  // 图片加载策略 + 网络状态，传给 ThreadCard 子组件（子组件不再自行 connect）
  @Local imageLoadTypeState: ImageLoadTypeState = AppStorageV2.connect(ImageLoadTypeState, 'imageLoadType', () => new ImageLoadTypeState())!;
  @Local isWifiState: IsWifiState = AppStorageV2.connect(IsWifiState, 'isWifi', () => new IsWifiState())!;
  @Local themeState: ThemeState = connectTheme();

  // Toast 提示 helper（API 12+ 推荐用 UIContext.getPromptAction() 替代全局 promptAction）
  private showToast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message });
  }

  async aboutToAppear() {
    this.loadThreads(true).catch((err: Error) => {
      console.error(`[ThreadStorePage] loadThreads failed: ${err.message}`);
    });
  }

  aboutToDisappear(): void {
    // 标记组件已销毁，所有进行中的 async 任务完成后检查此标志，
    // 避免修改已销毁组件的 @Local 或操作已销毁的 dataSource
    this.isDestroyed = true;
  }

  async loadThreads(isRefresh: boolean = false): Promise<void> {
    await this.viewModel.loadData(isRefresh);
    // 页面可能在 await 期间销毁，检查标志位避免修改已销毁组件的 @Local
    if (this.isDestroyed) {
      return;
    }
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
    this.threadCount = this.dataSource.totalCount();
    this.hasMore = paginationData.hasMore;
    this.isLoading = loadingState.isLoading;
    this.isRefreshing = loadingState.isRefreshing;
    this.errorMessage = loadingState.error;
  }

  onReachEnd(): void {
    if (this.viewModel.canLoadMore()) {
      this.loadThreads(false).catch((err: Error) => {
        console.error(`[ThreadStorePage] loadThreads more failed: ${err.message}`);
      });
    }
  }

  navigateToThread(tid: number): void {
    if (tid <= 0) {
      console.warn(`[ThreadStorePage] invalid tid: ${tid}, skip navigation`);
      return;
    }
    // #163 路由迁移：router.pushUrl → RouterUtil.push
    RouterUtil.push(RouterUtil.ROUTE_THREAD_PAGE, new ThreadNavParams(tid));
  }

  navigateToUserProfile(portrait: string, userName: string, uid: number): void {
    // #165 路由迁移：router.pushUrl → RouterUtil.push
    RouterUtil.push(RouterUtil.ROUTE_USER_PROFILE_PAGE,
      new UserProfileNavParams(portrait, userName, uid));
  }

  /** 点赞（issue #17） */
  async handleAgree(thread: ThreadInfo): Promise<void> {
    await handleThreadAgree(this.dataSource, thread, this.getUIContext());
    // 页面可能在 await 期间销毁，检查标志位避免后续操作已销毁组件
    if (this.isDestroyed) {
      return;
    }
  }

  async handleDisagree(thread: ThreadInfo): Promise<void> {
    await handleThreadDisagree(this.dataSource, thread, this.getUIContext());
    // 页面可能在 await 期间销毁，检查标志位避免后续操作已销毁组件
    if (this.isDestroyed) {
      return;
    }
  }

  /** 评论按钮点击：提示功能开发中 */
  showCommentToast(): void {
    this.showToast(getResourceString($r('app.string.page_developing')));
  }

  build() {
    // #163 [A4-S3] HdsNavDestination 包装：titleBar 沉浸光感材质 + GRADIENT_BLUR 滚动模糊
    HdsNavDestination() {
      Column() {
        // 内容区
        if (this.errorMessage.length > 0 && this.threadCount === 0) {
          ErrorView({
            message: this.errorMessage,
            onRetryClick: () => this.loadThreads(true).catch((err: Error) => {
              console.error(`[ThreadStorePage] loadThreads retry failed: ${err.message}`);
            })
          })
            .layoutWeight(1)
        } else if (this.threadCount === 0 && !this.isLoading) {
          // 空状态
          Column() {
            Text($r('app.string.thread_store_empty'))
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          List({ scroller: this.scroller }) {
            LazyForEach(this.dataSource, (thread: ThreadInfo) => {
              ListItem() {
                ThreadCard({
                  thread: thread,
                  imageLoadType: this.imageLoadTypeState.value,
                  isWifi: this.isWifiState.value,
                  onCardClick: () => this.navigateToThread(thread.tid),
                  onAuthorClick: () => this.navigateToUserProfile(
                    thread.author.portrait,
                    thread.author.name,
                    thread.author.uid
                  ),
                  onAgreeClick: (t: ThreadInfo) => {
                    this.handleAgree(t).catch((err: Error) => {
                      console.error(`[ThreadStorePage] handleAgree failed: ${err.message}`);
                    });
                  },
                  onDisagreeClick: (t: ThreadInfo) => {
                    this.handleDisagree(t).catch((err: Error) => {
                      console.error(`[ThreadStorePage] handleDisagree failed: ${err.message}`);
                    });
                  },
                  onCommentClick: () => this.showCommentToast()
                })
                  .margin({ top: 4, bottom: 4 })
              }
            }, (thread: ThreadInfo, index: number) => `${thread.tid}`)

            if (this.isLoading && this.threadCount > 0) {
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
          .padding({ left: 16, right: 16 })
          .backgroundColor($r('app.color.page_background'))
          .onReachEnd(() => this.onReachEnd())
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.page_background'))
    }
    .titleBar({
      content: {
        title: {
          mainTitle: $r('app.string.thread_store_title')
        }
      },
      style: {
        scrollEffectOpts: {
          enableScrollEffect: true,
          scrollEffectType: ScrollEffectType.GRADIENT_BLUR
        },
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        }
      },
      // 避让状态栏：setWindowLayoutFullScreen(true) 全屏模式下 titleBar 默认不避让状态栏，
      // 需显式设置 avoidLayoutSafeArea: true 让 titleBar 内容（标题/按钮）避让状态栏
      avoidLayoutSafeArea: true
    })
    .bindToScrollable([this.scroller])
    .backgroundColor($r('app.color.page_background'))
  }
}
