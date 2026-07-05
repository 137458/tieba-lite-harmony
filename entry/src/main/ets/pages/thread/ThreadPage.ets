import { router } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { inputMethod } from '@kit.IMEKit';
import { TiebaAPI } from '../../api/TiebaAPI';
import { PostInfo, MediaInfo, ContentFragment, ContentFragmentType } from '../../model/ForumModels';
import { LoadingView } from '../../components/LoadingView';
import { ErrorView } from '../../components/ErrorView';
import { ReplyBox, ReplyTarget } from '../../components/ReplyBox';
import { BaseViewModel, FetchDataResult } from '../../viewmodel/BaseViewModel';
import { getResourceString } from '../../utils/ResourceUtil';
import { CommonDataSource } from '../../utils/CommonDataSource';
import { getStatusBarHeight } from '../../utils/StatusBarUtil';
import { formatRelativeTime } from '../../utils/TimeUtil';
import { formatCount } from '../../utils/FormatUtil';
import { getMediaImageUrl, getAvatarImageUrl } from '../../utils/ImageLoadUtil';

// loadPreviousPage 加载成功后滚动到首条回复的延迟（ms），等待 LazyForEach 渲染就绪
const SCROLL_TO_FIRST_REPLY_DELAY_MS: number = 100;

/** ThreadPage 路由参数（tid 字符串形式，调用方 router.pushUrl params） */
interface ThreadPageParams {
  tid?: string;
}

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
  /** #74 贴吧 id（回帖 API 必传字段） */
  forumId: number = 0;
  // #72 加载上一页相关状态
  hasPrev: boolean = false;           // 服务端返回的 has_prev
  totalPage: number = 1;              // 服务端返回的 total_page
  currentPageMin: number = 1;         // 当前列表最小页码（加载上一页后递减）
  currentPageMax: number = 1;         // 当前列表最大页码（loadMore 后递增）
  isLoadingPrevious: boolean = false; // 正在加载上一页
  lastPrevList: PostInfo[] = [];      // 最近一次加载上一页返回的列表（前置插入用）
  // 楼主楼层（floor==1）的正文 fragments 和图片 mediaList
  // 信息栏合并显示标题 + 楼主正文 + 楼主图片，避免标题与内容分开
  firstPostFragments: ContentFragment[] = [];
  firstPostMediaList: MediaInfo[] = [];

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
      this.forumId = result.forumId;  // #74 回帖 API 必传字段
      // #72 刷新时重置页码范围
      this.hasPrev = result.posts.hasPrev;
      this.totalPage = result.posts.totalPage;
      this.currentPageMin = result.posts.currentPage;
      this.currentPageMax = result.posts.currentPage;
    } else {
      // loadMore 时更新最大页码和 hasPrev/totalPage
      this.hasPrev = result.posts.hasPrev;
      this.totalPage = result.posts.totalPage;
      this.currentPageMax = result.posts.currentPage;
    }
    // 恢复 floor==1 过滤：从 floor==1 楼主楼层提取 fragments + mediaList 到信息栏合并显示
    // 列表中过滤掉 floor==1，避免正文和图片在列表第一项重复显示
    // 信息栏渲染：标题 + 楼主正文 fragments + 楼主图片 mediaList（合并显示，不分页）
    const filteredList: PostInfo[] = [];
    for (let i = 0; i < result.posts.list.length; i++) {
      const p: PostInfo = result.posts.list[i];
      if (p.floor === 1) {
        // 楼主楼层：提取 fragments + mediaList，供信息栏合并显示
        this.firstPostFragments = p.fragments;
        this.firstPostMediaList = p.mediaList;
      } else {
        filteredList.push(p);
      }
    }
    return {
      list: filteredList,
      hasMore: result.posts.hasMore,
      currentPage: result.posts.currentPage
    };
  }

  /**
   * #72 加载上一页（对齐 Android ThreadViewModel.LoadPrevious）
   * 请求 pn = currentPageMin - 1，传 back=true + lastPostId（当前列表首条 pid）
   * 结果前置插入到 dataList 头部，更新 currentPageMin
   * @returns 是否加载成功（失败时 error 已写入 state.error）
   */
  async loadPrevious(): Promise<boolean> {
    if (this.isLoadingPrevious || this.state.isLoading || this.state.isRefreshing) {
      return false;
    }
    if (this.currentPageMin <= 1 || !this.hasPrev) {
      return false;
    }
    this.isLoadingPrevious = true;
    this.state.error = '';
    try {
      const prevPage: number = this.currentPageMin - 1;
      // 锚点 pid：当前列表首条 post 的 pid（对齐 Android postId = data.first().post.id）
      const firstPost: PostInfo | undefined = this.paginationState.dataList[0];
      const lastPostId: number = firstPost !== undefined ? firstPost.pid : 0;
      const result = await TiebaAPI.getPosts(
        this.tid, prevPage, this.onlyAuthor, this.sort, true, lastPostId
      );
      // 过滤掉 floor==1（楼主楼层，已在列表中显示）和已存在的 pid（避免重复）
      const existingPids: Set<number> = new Set<number>();
      for (let i = 0; i < this.paginationState.dataList.length; i++) {
        existingPids.add(this.paginationState.dataList[i].pid);
      }
      const newPosts: PostInfo[] = [];
      for (let i = 0; i < result.posts.list.length; i++) {
        const p: PostInfo = result.posts.list[i];
        if (p.floor !== 1 && !existingPids.has(p.pid)) {
          newPosts.push(p);
        }
      }
      // 前置插入：newPosts + oldDataList
      this.paginationState.dataList = newPosts.concat(this.paginationState.dataList);
      this.currentPageMin = prevPage;
      this.hasPrev = result.posts.hasPrev;
      this.totalPage = result.posts.totalPage;
      this.lastPrevList = newPosts;
      this.lastOpIsRefresh = false;
      return true;
    } catch (err) {
      const error = err as Error;
      console.error(`[ThreadViewModel] loadPrevious failed: ${error.message}`);
      this.state.error = error.message || '加载上一页失败';
      return false;
    } finally {
      this.isLoadingPrevious = false;
    }
  }

  /**
   * #72 跳转到指定页码（对齐 Android ThreadUiIntent.Load）
   * 整页替换 dataList，重置 currentPageMin/currentPageMax
   * @param page 目标页码
   * @returns 是否跳转成功
   */
  async jumpToPage(page: number): Promise<boolean> {
    if (this.state.isLoading || this.state.isRefreshing) {
      return false;
    }
    if (page < 1 || (this.totalPage > 0 && page > this.totalPage)) {
      return false;
    }
    this.state.isLoading = true;
    this.state.error = '';
    try {
      const result = await TiebaAPI.getPosts(this.tid, page, this.onlyAuthor, this.sort);
      this.threadTitle = result.thread.title;
      this.threadAuthorUid = result.thread.author.uid;
      this.threadReplyNum = result.thread.replyNum;
      this.threadAgreeNum = result.thread.agreeNum;
      this.threadIsAgreed = result.thread.isAgreed;
      this.threadForumName = result.thread.forumName;
      this.threadViewNum = result.thread.viewNum;
      this.threadCreateTime = result.thread.createTime;
      this.forumId = result.forumId;  // #74 回帖 API 必传字段
      // 恢复 floor==1 过滤（对齐 fetchData 逻辑）：
      // 从 floor==1 楼主楼层提取 fragments + mediaList 到信息栏合并显示
      // 列表中过滤掉 floor==1，避免正文和图片在列表第一项重复显示
      const filteredList: PostInfo[] = [];
      for (let i = 0; i < result.posts.list.length; i++) {
        const p: PostInfo = result.posts.list[i];
        if (p.floor === 1) {
          this.firstPostFragments = p.fragments;
          this.firstPostMediaList = p.mediaList;
        } else {
          filteredList.push(p);
        }
      }
      this.paginationState.dataList = filteredList;
      this.paginationState.hasMore = result.posts.hasMore;
      this.paginationState.currentPage = page + 1;
      this.hasPrev = result.posts.hasPrev;
      this.totalPage = result.posts.totalPage;
      this.currentPageMin = result.posts.currentPage;
      this.currentPageMax = result.posts.currentPage;
      this.lastFetchList = result.posts.list;
      this.lastOpIsRefresh = true;
      return true;
    } catch (err) {
      const error = err as Error;
      console.error(`[ThreadViewModel] jumpToPage failed: ${error.message}`);
      this.state.error = error.message || '跳转失败';
      return false;
    } finally {
      this.state.isLoading = false;
    }
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
  // #72 沉浸模式（纯净阅读）：隐藏头像区，仅显示内容+操作按钮
  @Prop immersiveMode: boolean = false;
  // #79 图片加载策略：通过 AppStorage 共享，SettingsPage 修改后自动响应
  @StorageProp('imageLoadType') imageLoadType: number = 0;
  @StorageProp('isWifi') isWifi: boolean = false;
  onAgreeClick?: (post: PostInfo) => void;
  onDisagreeClick?: (post: PostInfo) => void;
  onCommentClick?: () => void;
  // 点击作者区域（头像/名字）回调，跳转用户主页
  onAuthorClick?: () => void;
  // #71 点击 @用户 回调，跳转被@用户的主页（uid + 昵称）
  onAtClick?: (uid: number, name: string) => void;

  // Toast 提示 helper（API 12+ 推荐用 UIContext.getPromptAction() 替代全局 promptAction）
  private showToast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message });
  }

  @Builder
  MediaImage(index: number, isSingle: boolean) {
    // #79 接入图片加载策略：shouldLoad=false 时返回空串，Image 组件显示 alt 占位图
    Image(getMediaImageUrl(
      this.post.mediaList[index].thumbnail,
      this.post.mediaList[index].url,
      this.imageLoadType,
      this.isWifi
    ))
      .objectFit(ImageFit.Cover)
      .borderRadius(8)
      .backgroundColor($r('app.color.input_background'))
      .alt($r('app.media.startIcon'))
      .width('100%')
      .aspectRatio(isSingle ? 4 / 3 : 1)
      // #92 HitTestMode.Transparent：让触控穿透到父 List，避免 fling 期间碰到图片导致触控丢失
      .hitTestBehavior(HitTestMode.Transparent)
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
      // #72 沉浸模式隐藏头像区（对齐 Android ThreadPage immersiveMode 逻辑）
      if (!this.immersiveMode) {
        Row() {
          // #79 接入图片加载策略：shouldLoad=false 时返回空串，Image 组件显示 alt 占位图
          Image(getAvatarImageUrl(this.post.author.avatar, this.imageLoadType, this.isWifi))
            .width(36)
            .height(36)
            .borderRadius(18)
            .objectFit(ImageFit.Cover)
            .backgroundColor($r('app.color.input_background'))
            .alt($r('app.media.startIcon'))
            .border(this.isAuthor ? { width: 2, color: $r('app.color.primary') } : { width: 0 })
            // #92 HitTestMode.Transparent：让触控穿透到父 List，避免 fling 期间碰到图片导致触控丢失
            .hitTestBehavior(HitTestMode.Transparent)

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
      // #92 HitTestMode.Transparent：让触控穿透到父 List，避免 fling 期间碰到用户行导致触控丢失
      .hitTestBehavior(HitTestMode.Transparent)
      .onClick(() => {
        if (this.onAuthorClick) {
          this.onAuthorClick();
        }
      })
      } else {
        // 沉浸模式下仅显示楼层时间（简化版，对齐 Android 隐藏头像但保留楼层信息）
        Text(getResourceString($r('app.string.floor_time_label', this.post.floor + 1, formatRelativeTime(this.post.createTime))))
          .fontSize(12)
          .fontColor($r('app.color.text_caption'))
          .margin({ bottom: 6 })
      }

      // #71 富文本渲染：优先用 fragments（Text+Span+ImageSpan），为空时 fallback 到纯 content
      if (this.post.fragments.length > 0) {
        Text() {
          ForEach(this.post.fragments, (frag: ContentFragment, idx: number) => {
            if (frag.type === ContentFragmentType.LINK) {
              // 链接：主色高亮 + 点击显示链接URL（跳转功能后续实现）
              Span(frag.text)
                .fontColor($r('app.color.primary'))
                .onClick(() => {
                  this.showToast(frag.link);
                })
            } else if (frag.type === ContentFragmentType.AT) {
              // @用户：主色高亮 + 点击跳转被@用户主页
              Span(frag.text)
                .fontColor($r('app.color.primary'))
                .onClick(() => {
                  if (this.onAtClick && frag.uid > 0) {
                    this.onAtClick(frag.uid, frag.text);
                  }
                })
            } else if (frag.type === ContentFragmentType.EMOJI) {
              // 表情：ImageSpan 内联显示（URL 对齐 TiebaLite EmoticonManager.kt:300）
              // 协议用 https：贴吧 CDN 支持，避免 http 明文传输风险
              ImageSpan('https://static.tieba.baidu.com/tb/editor/images/client/' + frag.text + '.png')
                .width(20)
                .height(20)
                .verticalAlign(ImageSpanAlignment.CENTER)
            } else {
              // 纯文本（TEXT类型）
              Span(frag.text)
            }
          }, (frag: ContentFragment, idx: number) => `${idx}_${frag.type}_${frag.text}`)
        }
        .fontSize(15)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: 10 })
        .width('100%')
        .lineHeight(24)
      } else {
        // fallback：fragments 为空时用纯 content（兼容旧数据）
        Text(this.post.content)
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
          .margin({ top: 10 })
          .width('100%')
          .lineHeight(24)
      }

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
            // #92 HitTestMode.Transparent：让触控穿透到父 List，避免 fling 期间碰到图片导致触控丢失
            .hitTestBehavior(HitTestMode.Transparent)
          Text(this.post.agreeNum.toString())
            .fontSize(12)
            .fontColor(this.post.isAgreed ? $r('app.color.primary') : $r('app.color.text_caption'))
            .margin({ left: 4 })
        }
        .padding({ left: 0, right: 8, top: 8, bottom: 8 })
        .alignItems(VerticalAlign.Center)
        // #92 点赞按钮需响应 onClick：用 Block 阻断事件向父 List 穿透，避免点击被 List 滚动手势消费
        // （之前误用 Transparent 导致点击穿透到 List，onClick 不触发）
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
            // #92 HitTestMode.Transparent：让触控穿透到父 List，避免 fling 期间碰到图片导致触控丢失
            .hitTestBehavior(HitTestMode.Transparent)
          Text(this.post.disagreeNum.toString())
            .fontSize(12)
            .fontColor(this.post.isDisagreed ? $r('app.color.error') : $r('app.color.text_caption'))
            .margin({ left: 4 })
        }
        .padding({ left: 0, right: 8, top: 8, bottom: 8 })
        .alignItems(VerticalAlign.Center)
        // #92 踩按钮需响应 onClick：用 Block 阻断事件向父 List 穿透（同点赞按钮）
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
            // #92 HitTestMode.Transparent：让触控穿透到父 List，避免 fling 期间碰到图片导致触控丢失
            .hitTestBehavior(HitTestMode.Transparent)
          Text(this.post.replyNum.toString())
            .fontSize(12)
            .fontColor($r('app.color.text_caption'))
            .margin({ left: 4 })
        }
        .padding({ left: 0, right: 8, top: 8, bottom: 8 })
        .alignItems(VerticalAlign.Center)
        // #92 评论按钮需响应 onClick：用 Block 阻断事件向父 List 穿透（同点赞按钮）
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
  // #72 Scroller 用于跳转楼层后滚动到列表顶部
  private scroller: Scroller = new Scroller();
  // #72 跳转楼层对话框控制器
  private jumpPageDialogController: CustomDialogController | null = null;
  // loadPreviousPage 中 setTimeout 句柄，aboutToDisappear 时清理避免页面销毁后回调报错
  private scrollTimer: number = -1;
  // #84 bindSheet onAppear 中 setTimeout 句柄，aboutToDisappear 时清理避免页面销毁后回调 requestFocus 报错
  private replyFocusTimer: number = -1;
  // #84 handleThreadShare 防抖锁，避免重复点击触发多个分享面板
  private isSharing: boolean = false;

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
  // #72 加载上一页 + 跳转楼层 + 沉浸模式
  @State hasPrev: boolean = false;        // 是否有上一页（控制"加载上一页"按钮显示）
  @State isLoadingPrevious: boolean = false;
  @State totalPage: number = 1;           // 总页数（跳转楼层校验用）
  @State currentPageMax: number = 1;      // 当前最大页码（跳转楼层提示用）
  @State isImmersiveMode: boolean = false; // 沉浸模式（纯净阅读，隐藏顶部栏/底部栏/头像区）
  // 内嵌回复框（bindSheet 半模态）：showReplySheet 控制显隐，replyTarget 持有回复目标参数
  @State showReplySheet: boolean = false;
  @State replyTarget: ReplyTarget = new ReplyTarget();
  // 楼主楼层（floor==1）的正文 fragments 和图片 mediaList（信息栏合并显示用）
  // 从 viewModel.firstPostFragments/firstPostMediaList 同步，避免标题与内容分开
  @State firstPostFragments: ContentFragment[] = [];
  @State firstPostMediaList: MediaInfo[] = [];
  // #79 图片加载策略：通过 AppStorage 共享，SettingsPage 修改后自动响应
  @StorageProp('imageLoadType') imageLoadType: number = 0;
  @StorageProp('isWifi') isWifi: boolean = false;

  // Toast 提示 helper（API 12+ 推荐用 UIContext.getPromptAction() 替代全局 promptAction）
  private showToast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message });
  }

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
    const params = router.getParams() as ThreadPageParams;
    if (params && params.tid) {
      const parsedTid: number = Number(params.tid);
      // NaN 校验：Number('abc') 返回 NaN，NaN 与任何数比较都为 false
      // 不校验会导致 viewModel.setTid(NaN) 后 API 请求带 NaN tid，服务端返回错误或空数据
      if (!Number.isNaN(parsedTid) && parsedTid > 0) {
        this.tid = parsedTid;
        this.viewModel.setTid(this.tid);
        this.loadPosts(true).catch((err: Error) => {
          console.error(`[ThreadPage] loadPosts failed: ${err.message}`);
        });
      } else {
        console.error(`[ThreadPage] invalid tid from params: ${params.tid}`);
        this.errorMessage = getResourceString($r('app.string.error_invalid_params'));
      }
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
    // #72 同步加载上一页/跳转楼层/总页数状态
    this.hasPrev = this.viewModel.hasPrev;
    this.isLoadingPrevious = this.viewModel.isLoadingPrevious;
    this.totalPage = this.viewModel.totalPage;
    this.currentPageMax = this.viewModel.currentPageMax;
    // 同步楼主楼层的 fragments + mediaList（信息栏合并显示标题 + 正文 + 图片）
    if (this.viewModel.lastOpWasRefresh) {
      this.firstPostFragments = this.viewModel.firstPostFragments;
      this.firstPostMediaList = this.viewModel.firstPostMediaList;
    }
  }

  onReachEnd(): void {
    if (this.viewModel.canLoadMore()) {
      // onReachEnd 回调不处理 async 返回值，需 catch 避免 unhandled rejection
      this.loadPosts(false).catch((err: Error) => {
        console.error(`[ThreadPage] onReachEnd loadPosts failed: ${err.message}`);
      });
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
    // 防抖：请求进行中时禁用点击，避免连点导致赞数错乱（3280003 不能重复取消/3280004 操作太频繁）
    if (post.isAgreeing) {
      return;
    }
    post.isAgreeing = true;
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
      this.showToast((err as Error).message || getResourceString($r('app.string.follow_operation_failed')));
    } finally {
      post.isAgreeing = false;
    }
  }

  /**
   * 点踩/取消点踩（issue #17，#31 改 LazyForEach）
   * 乐观更新 + 失败回滚（对齐原 APP，保证 UI 与服务端一致）
   */
  async handleDisagree(post: PostInfo): Promise<void> {
    // 防抖：请求进行中时禁用点击（同 handleAgree）
    if (post.isAgreeing) {
      return;
    }
    post.isAgreeing = true;
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
      this.showToast((err as Error).message || getResourceString($r('app.string.follow_operation_failed')));
    } finally {
      post.isAgreeing = false;
    }
  }

  /** #73 评论按钮点击：跳转到楼中楼列表页（SubPostsPage） */
  navigateToSubPosts(post: PostInfo): void {
    if (post.pid <= 0) {
      this.showToast(getResourceString($r('app.string.subposts_invalid_params')));
      return;
    }
    router.pushUrl({
      url: 'pages/thread/SubPostsPage',
      params: {
        tid: post.tid,
        pid: post.pid,
        floor: post.floor
      }
    }).catch((err: Error) => {
      console.error(`[ThreadPage] navigate to SubPostsPage failed: ${err.message}`);
    });
  }

  /**
   * 打开内嵌回复框（bindSheet 半模态）
   * 替代原 navigateToReply 跳转 ReplyPage 方案，回复框往上抬即可，不离开当前页面
   * 普通回帖：仅传 tid/fid/forumName
   * 楼中楼回复：额外传 postId/replyUid/replyUserName/replyUserPortrait/floor
   */
  openReplyBox(post?: PostInfo): void {
    if (this.tid <= 0 || this.viewModel.forumId <= 0 || this.threadForumName.length === 0) {
      this.showToast(getResourceString($r('app.string.reply_invalid_params')));
      return;
    }
    const target: ReplyTarget = new ReplyTarget();
    target.tid = this.tid;
    target.fid = this.viewModel.forumId;
    target.forumName = this.threadForumName;
    if (post !== undefined && post.pid > 0) {
      target.postId = post.pid;
      target.replyUid = post.author.uid;
      target.replyUserName = post.author.name;
      target.replyUserPortrait = post.author.portrait;
      target.floor = post.floor;
    }
    // 重新赋值整个 ReplyTarget 实例触发 @State 刷新（非 @Observed 类字段级监听）
    this.replyTarget = target;
    this.showReplySheet = true;
  }

  /**
   * 信息栏楼主图片 Builder（参考 PostItem.MediaImage 渲染逻辑）
   * 单图全宽 4:3，多图 1:1，点击跳转 ImageViewerPage
   */
  @Builder
  FirstPostMediaImage(index: number, isSingle: boolean) {
    Image(getMediaImageUrl(
      this.firstPostMediaList[index].thumbnail,
      this.firstPostMediaList[index].url,
      this.imageLoadType,
      this.isWifi
    ))
      .objectFit(ImageFit.Cover)
      .borderRadius(8)
      .backgroundColor($r('app.color.input_background'))
      .alt($r('app.media.startIcon'))
      .width('100%')
      .aspectRatio(isSingle ? 4 / 3 : 1)
      // #92 HitTestMode.Transparent：让触控穿透到父 List，避免 fling 期间碰到图片导致触控丢失
      .hitTestBehavior(HitTestMode.Transparent)
      .onClick(() => {
        router.pushUrl({
          url: 'pages/viewer/ImageViewerPage',
          params: {
            urls: this.firstPostMediaList.map((m: MediaInfo) => m.url),
            index: index
          }
        }).catch((err: Error) => {
          console.error(`[ThreadPage] navigate to ImageViewer failed: ${err.message}`);
        });
      })
  }

  /** 回复框 builder：通过 bindSheet 半模态弹出，ReplyBox 内部管理状态 */
  @Builder
  ReplySheetBuilder() {
    ReplyBox({
      tid: this.replyTarget.tid,
      fid: this.replyTarget.fid,
      forumName: this.replyTarget.forumName,
      postId: this.replyTarget.postId,
      subPostId: this.replyTarget.subPostId,
      replyUid: this.replyTarget.replyUid,
      replyUserName: this.replyTarget.replyUserName,
      replyUserPortrait: this.replyTarget.replyUserPortrait,
      floor: this.replyTarget.floor,
      onSentSuccess: () => {
        this.showReplySheet = false;
        // 普通回帖成功后刷新当前列表（楼中楼回复不影响楼层列表，不刷新）
        if (this.replyTarget.postId <= 0) {
          this.loadPosts(true).catch((err: Error) => {
            console.error(`[ThreadPage] refresh after reply failed: ${err.message}`);
          });
        }
      },
      onClose: () => {
        this.showReplySheet = false;
      }
    })
  }

  /** 底部输入栏按钮（图片/@/表情）提示开发中（#74 回帖页面后续实现） */
  showCommentToast(): void {
    this.showToast(getResourceString($r('app.string.page_developing')));
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
      this.showToast((err as Error).message || getResourceString($r('app.string.follow_operation_failed')));
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
        this.showToast(getResourceString($r('app.string.favorite_removed')));
      } else {
        await TiebaAPI.addStore(this.tid, 0);
        this.isFavorited = true;
        this.showToast(getResourceString($r('app.string.favorite_added')));
      }
    } catch (err) {
      console.error('[ThreadPage] handleThreadFavorite failed: ' + (err as Error).message);
      this.showToast((err as Error).message || getResourceString($r('app.string.follow_operation_failed')));
    } finally {
      this.isProcessingFavorite = false;
    }
  }

  /**
   * 分享按钮：调用系统分享面板（@kit.ShareKit systemShare）
   * 分享贴吧帖子链接 https://tieba.baidu.com/p/{tid}，UTD=HYPERLINK 直达浏览器
   * anchor='threadShareButton' 让面板锚定到分享按钮位置以 Popup 形式展示
   */
  handleThreadShare(): void {
    if (this.tid <= 0) {
      this.showToast(getResourceString($r('app.string.share_developing')));
      return;
    }
    // #84 防抖锁：避免重复点击触发多个分享面板
    if (this.isSharing) {
      return;
    }
    this.isSharing = true;

    const shareUrl: string = `https://tieba.baidu.com/p/${this.tid}`;
    const threadTitle: string = this.viewModel.threadTitle.length > 0
      ? this.viewModel.threadTitle
      : getResourceString($r('app.string.app_name'));
    const description: string = this.viewModel.threadForumName.length > 0
      ? `${this.viewModel.threadForumName} - ${threadTitle}`
      : threadTitle;

    try {
      // 构造分享数据：HYPERLINK 类型，content=URL，title/description 用于生成分享卡片预览
      const shareData: systemShare.SharedData = new systemShare.SharedData({
        utd: utd.UniformDataType.HYPERLINK,
        content: shareUrl,
        title: threadTitle,
        description: description
      });
      const controller: systemShare.ShareController = new systemShare.ShareController(shareData);
      // 获取 UIAbility 上下文（systemShare.show 要求 common.UIAbilityContext）
      // #84 判空：getHostContext 理论上返回 UIAbilityContext，但防御性判空避免强转 null 引发 NPE
      const uiContext: UIContext = this.getUIContext();
      const hostContext: common.UIAbilityContext | undefined = uiContext.getHostContext() as common.UIAbilityContext;
      if (hostContext === null || hostContext === undefined) {
        this.showToast(getResourceString($r('app.string.share_developing')));
        return;
      }
      controller.on('dismiss', () => {
        console.info('[ThreadPage] share panel closed');
        this.isSharing = false;
      });
      controller.show(hostContext, {
        anchor: 'threadShareButton',
        previewMode: systemShare.SharePreviewMode.DEFAULT,
        selectionMode: systemShare.SelectionMode.SINGLE
      }).catch((err: Error) => {
        console.error(`[ThreadPage] share show failed: ${err.message}`);
        this.showToast(err.message);
      }).finally(() => {
        this.isSharing = false;
      });
    } catch (err) {
      console.error(`[ThreadPage] share error: ${(err as Error).message}`);
      this.showToast((err as Error).message);
      this.isSharing = false;
    }
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

  /**
   * #72 加载上一页
   * 调用 ViewModel.loadPrevious，成功后前置插入数据并滚动到第一条回复
   */
  loadPreviousPage(): void {
    this.viewModel.loadPrevious().then((success: boolean) => {
      if (success) {
        // 前置插入新数据到 dataSource 头部
        this.dataSource.prependData(this.viewModel.lastPrevList);
        this.postCount = this.dataSource.totalCount();
        this.hasPrev = this.viewModel.hasPrev;
        this.isLoadingPrevious = this.viewModel.isLoadingPrevious;
        // 滚动到第一条新加载的回复（跳过 LoadPreviousBtn 本身，index=1）
        // 保存句柄，aboutToDisappear 时清理避免页面销毁后回调报错
        this.scrollTimer = setTimeout(() => {
          this.scroller.scrollToIndex(1, false);
          this.scrollTimer = -1;
        }, SCROLL_TO_FIRST_REPLY_DELAY_MS);
      } else {
        this.errorMessage = this.viewModel.loadingState.error;
        this.isLoadingPrevious = this.viewModel.isLoadingPrevious;
      }
    }).catch((err: Error) => {
      console.error(`[ThreadPage] loadPreviousPage failed: ${err.message}`);
    });
  }

  /**
   * #72 跳转到指定页码
   * @param page 目标页码（1-based）
   */
  jumpToPage(page: number): void {
    if (page < 1) {
      this.showToast(getResourceString($r('app.string.jump_page_invalid')));
      return;
    }
    if (this.totalPage > 0 && page > this.totalPage) {
      this.showToast(getResourceString($r('app.string.jump_page_exceed', this.totalPage)));
      return;
    }
    this.viewModel.jumpToPage(page).then((success: boolean) => {
      if (success) {
        this.syncState();
        // 滚动到列表顶部
        this.scroller.scrollToIndex(0, false);
      } else {
        this.errorMessage = this.viewModel.loadingState.error;
      }
    }).catch((err: Error) => {
      console.error(`[ThreadPage] jumpToPage failed: ${err.message}`);
    });
  }

  /**
   * #72 切换沉浸模式（纯净阅读，对齐 Android ThreadPage onImmersiveModeClick）
   * 进入沉浸模式时如果当前不是"只看楼主"，强制切换到只看楼主
   */
  toggleImmersiveMode(): void {
    if (!this.isImmersiveMode && !this.onlyAuthorMode) {
      // 进入沉浸模式前强制切换到只看楼主（对齐 Android 原版）
      this.onlyAuthorMode = true;
      this.viewModel.setOnlyAuthor(true);
      this.loadPosts(true).catch((err: Error) => {
        console.error(`[ThreadPage] immersiveMode reload failed: ${err.message}`);
      });
    }
    this.isImmersiveMode = !this.isImmersiveMode;
  }

  /**
   * #72 显示跳转楼层对话框
   * 对齐 Android PromptDialog，输入页码后跳转
   */
  showJumpPageDialog(): void {
    // 每次打开时重新构造 controller，传入最新 currentPage/totalPage，避免 aboutToAppear 时快照过期
    this.jumpPageDialogController = new CustomDialogController({
      builder: JumpPageDialog({
        currentPage: this.currentPageMax,
        totalPage: this.totalPage,
        onConfirm: (page: number) => {
          this.jumpToPage(page);
        }
      }),
      autoCancel: true,
      alignment: DialogAlignment.Center
    });
    this.jumpPageDialogController.open();
  }

  aboutToDisappear(): void {
    // #84 清理 setTimeout 句柄，避免页面销毁后回调触发 scroller.scrollToIndex / requestFocus 报错
    if (this.scrollTimer >= 0) {
      clearTimeout(this.scrollTimer);
      this.scrollTimer = -1;
    }
    if (this.replyFocusTimer >= 0) {
      clearTimeout(this.replyFocusTimer);
      this.replyFocusTimer = -1;
    }
    // #84 关闭跳页对话框，避免页面销毁后 CustomDialog 持有已销毁组件引用导致内存泄漏
    if (this.jumpPageDialogController !== null) {
      this.jumpPageDialogController.close();
      this.jumpPageDialogController = null;
    }
    // #84 关闭回复 sheet，避免 sheet 内 ReplyBox 闭包引用已销毁组件
    this.showReplySheet = false;
  }

  build() {
    Column() {
      // 顶部导航栏：返回 + 吧名(居中) + 分享 + 更多（按原型 detail-nav）
      // #72 沉浸模式下隐藏顶部栏
      if (!this.isImmersiveMode) {
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
            .constraintSize({ maxWidth: '50%' })
            .layoutWeight(1)
            .margin({ left: 50, right: 50 })

          // #69 收藏按钮（在分享按钮前，对齐 issue 要求 nav-actions 添加收藏图标）
          Row() {
            Image($r('app.media.ic_star'))
              .width(20)
              .height(20)
              .fillColor(this.isFavorited ? $r('app.color.primary') : $r('app.color.text_secondary'))
          }
          .width(30)
          .height(30)
          .borderRadius(15)
          .justifyContent(FlexAlign.Center)
          .hitTestBehavior(HitTestMode.Block)
          .onClick(() => {
            this.handleThreadFavorite();
          })

          // 分享按钮
          // .key('threadShareButton')：systemShare.ShareController.show 的 anchor，
          // 分享面板以 Popup 形式锚定到此按钮位置展示
          Row() {
            Image($r('app.media.ic_share'))
              .width(20)
              .height(20)
              .fillColor($r('app.color.text_secondary'))
          }
          .key('threadShareButton')
          .width(30)
          .height(30)
          .borderRadius(15)
          .justifyContent(FlexAlign.Center)
          .margin({ left: 12 })
          .hitTestBehavior(HitTestMode.Block)
          .onClick(() => {
            this.handleThreadShare();
          })

          // 更多按钮（#70 改为 bindMenu：只看楼主 + 回复排序 + #72 跳转楼层 + 沉浸模式）
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
            },
            {
              value: getResourceString($r('app.string.menu_jump_page')),
              action: () => this.showJumpPageDialog()
            },
            {
              value: (this.isImmersiveMode ? '✓ ' : '') + getResourceString($r('app.string.menu_immersive')),
              action: () => this.toggleImmersiveMode()
            }
          ])
        }
        .width('100%')
        .height(44 + this.statusBarHeight)
        .padding({ left: 16, right: 16, top: this.statusBarHeight })
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
        .alignItems(VerticalAlign.Center)
        .backgroundColor($r('app.color.page_background'))
      }

      if (this.errorMessage.length > 0 && this.postCount === 0) {
        ErrorView({
          message: this.errorMessage,
          onRetryClick: () => this.loadPosts(true).catch((err: Error) => {
            console.error(`[ThreadPage] loadPosts retry failed: ${err.message}`);
          })
        })
          .layoutWeight(1)
      } else {
        List({ scroller: this.scroller }) {
          // 帖子信息栏（标题 + 楼主正文 fragments + 楼主图片 mediaList + 浏览/评论/日期/点赞）
          // 标题与楼主正文/图片合并显示在信息栏，避免分页后标题与内容分开
          if (this.threadTitle.length > 0) {
            ListItem() {
              Column() {
                Text(this.threadTitle)
                  .fontSize(17)
                  .fontWeight(600)
                  .fontColor($r('app.color.text_primary'))
                  .lineHeight(24)

                // 楼主正文 fragments（TEXT/LINK/AT/EMOJI），与 PostItem 渲染逻辑一致
                if (this.firstPostFragments.length > 0) {
                  Text() {
                    ForEach(this.firstPostFragments, (frag: ContentFragment, idx: number) => {
                      if (frag.type === ContentFragmentType.LINK) {
                        Span(frag.text)
                          .fontColor($r('app.color.primary'))
                          .onClick(() => {
                            this.showToast(frag.link);
                          })
                      } else if (frag.type === ContentFragmentType.AT) {
                        Span(frag.text)
                          .fontColor($r('app.color.primary'))
                          .onClick(() => {
                            this.navigateToUserProfile('', frag.text, frag.uid);
                          })
                      } else if (frag.type === ContentFragmentType.EMOJI) {
                        ImageSpan('https://static.tieba.baidu.com/tb/editor/images/client/' + frag.text + '.png')
                          .width(20)
                          .height(20)
                          .verticalAlign(ImageSpanAlignment.CENTER)
                      } else {
                        Span(frag.text)
                      }
                    }, (frag: ContentFragment, idx: number) => `${idx}_${frag.type}_${frag.text}`)
                  }
                  .fontSize(15)
                  .fontColor($r('app.color.text_primary'))
                  .margin({ top: 10 })
                  .width('100%')
                  .lineHeight(24)
                }

                // 楼主图片 mediaList（缩略图，点击跳转 ImageViewerPage）
                if (this.firstPostMediaList.length > 0) {
                  Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
                    ForEach(this.firstPostMediaList, (media: MediaInfo, index: number) => {
                      Row() {
                        this.FirstPostMediaImage(index, this.firstPostMediaList.length === 1)
                      }
                      .width(this.firstPostMediaList.length === 1 ? '100%' : '48%')
                      .margin({ right: index % 2 === 0 && this.firstPostMediaList.length > 1 ? '4%' : 0, bottom: 4 })
                    }, (media: MediaInfo, idx: number) => `${media.url}_${idx}`)
                  }
                  .width('100%')
                  .margin({ top: 10 })
                }

                Row() {
                  if (this.threadViewNum > 0) {
                    Row() {
                      Image($r('app.media.ic_eye'))
                        .width(14)
                        .height(14)
                        .fillColor($r('app.color.text_caption'))
                        // #92 HitTestMode.Transparent：让触控穿透到父 List，避免 fling 期间碰到图片导致触控丢失
                        .hitTestBehavior(HitTestMode.Transparent)
                      Text(formatCount(this.threadViewNum))
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
                      // #92 HitTestMode.Transparent：让触控穿透到父 List，避免 fling 期间碰到图片导致触控丢失
                      .hitTestBehavior(HitTestMode.Transparent)
                    Text(formatCount(this.threadReplyNum))
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

                  // #69 主题帖点赞按钮（meta 行右侧，对齐 issue 要求"信息栏添加点赞按钮"）
                  // 乐观更新 + 失败回滚，调用 handleThreadAgree(objType=3, pid=0)
                  Row() {
                    Image($r('app.media.ic_like'))
                      .width(14)
                      .height(14)
                      .fillColor(this.threadIsAgreed ? $r('app.color.primary') : $r('app.color.text_caption'))
                      // #92 HitTestMode.Transparent：让触控穿透到父 List，避免 fling 期间碰到图片导致触控丢失
                      .hitTestBehavior(HitTestMode.Transparent)
                    if (this.threadAgreeNum > 0) {
                      Text(formatCount(this.threadAgreeNum))
                        .fontSize(12)
                        .fontColor(this.threadIsAgreed ? $r('app.color.primary') : $r('app.color.text_caption'))
                        .margin({ left: 3 })
                    }
                  }
                  .alignItems(VerticalAlign.Center)
                  .margin({ left: 'auto' })
                  .hitTestBehavior(HitTestMode.Block)
                  .onClick(() => {
                    this.handleThreadAgree();
                  })
                }
                .margin({ top: 8 })
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 12, bottom: 12 })
              .backgroundColor($r('app.color.card_background'))
              .borderRadius(10)
              .alignItems(HorizontalAlign.Start)
            }
            .margin({ top: 0, bottom: 12 })
          }

          // #72 加载上一页按钮（hasPrev=true 时显示在列表头部）
          if (this.hasPrev) {
            ListItem() {
              Row() {
                if (this.isLoadingPrevious) {
                  LoadingView({ message: getResourceString($r('app.string.loading_previous')) })
                    .height(40)
                } else {
                  Text(getResourceString($r('app.string.btn_load_previous')))
                    .fontSize(14)
                    .fontColor($r('app.color.primary'))
                }
              }
              .width('100%')
              .height(44)
              .justifyContent(FlexAlign.Center)
              .alignItems(VerticalAlign.Center)
              .hitTestBehavior(HitTestMode.Block)
              .onClick(() => {
                if (!this.isLoadingPrevious) {
                  this.loadPreviousPage();
                }
              })
            }
            .margin({ top: 0, bottom: 10 })
          }

          // 楼层列表
          LazyForEach(this.dataSource, (post: PostInfo, index: number) => {
            ListItem() {
              PostItem({
                post: post,
                isAuthor: post.author.uid === this.threadAuthorUid && this.threadAuthorUid > 0,
                immersiveMode: this.isImmersiveMode,
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
                onCommentClick: () => this.navigateToSubPosts(post),
                onAuthorClick: () => this.navigateToUserProfile(
                  post.author.portrait,
                  post.author.name,
                  post.author.uid
                ),
                onAtClick: (uid: number, name: string) => this.navigateToUserProfile('', name, uid)
              })
            }
            .margin({ top: 0, bottom: 10 })
          }, (post: PostInfo) => `${post.pid}`)

          if (this.isLoading && this.postCount > 0) {
            ListItem() {
              LoadingView({ message: getResourceString($r('app.string.loading_more')) })
                .height(60)
                .margin({ left: 0, right: 0 })
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

      // 底部回复栏：输入框 + 图片/@/表情
      // #72 沉浸模式下隐藏底部回复栏
      // #74 点击任意按钮均跳转到 ReplyPage（独立回帖页面，对齐 Android ReplyPage.kt）
      if (!this.isImmersiveMode) {
        Row() {
          // focusable(false)：底部 TextInput 仅作回复入口触发 bindSheet，
          // 不可获焦避免 sheet 关闭后焦点回落在 TextInput 上导致页面滚动到底部回复栏
          TextInput({ placeholder: $r('app.string.reply_hint'), text: $$this.replyText })
          .layoutWeight(1)
          .height(36)
          .borderRadius(18)
          .backgroundColor($r('app.color.input_background'))
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .placeholderColor($r('app.color.text_caption'))
          .padding({ left: 14, right: 14 })
          .focusable(false)
          .hitTestBehavior(HitTestMode.Block)
          .onClick(() => {
            this.openReplyBox();
          })
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
          this.openReplyBox();
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
          this.openReplyBox();
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
          this.openReplyBox();
        })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
      .backgroundColor($r('app.color.card_background'))
      .border({ width: { top: 0.5 }, color: $r('app.color.divider') })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
    // 内嵌回复框（bindSheet 半模态）
    // keyboardAvoidMode 用 NONE：sheet 自身不做键盘避让，依赖 EntryAbility 全局
    // setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE) 压缩窗口布局。
    // 之前用 TRANSLATE_AND_RESIZE 实测无效（用户反馈工具栏完全不上移），
    // 改用 NONE + 全局 RESIZE 后，键盘弹出时 sheet 内容区域被压缩，
    // TextArea 的 layoutWeight(1) 自动缩小，底部工具栏（图片/表情/发送按钮）随之上移到键盘上方。
    .bindSheet($$this.showReplySheet, this.ReplySheetBuilder(), {
      height: SheetSize.MEDIUM,
      dragBar: true,
      showClose: true,
      keyboardAvoidMode: SheetKeyboardAvoidMode.NONE,
      // 楼中楼回复（postId > 0）显示"回复楼层"，否则显示"回复主题"
      title: { title: this.replyTarget.postId > 0
        ? getResourceString($r('app.string.reply_subpost_title'))
        : getResourceString($r('app.string.reply_thread_title')) },
      onAppear: () => {
        // #84 sheet 出现后主动让 TextArea 获焦，触发输入法弹出
        // 保存 setTimeout 句柄到 replyFocusTimer，aboutToDisappear 时清理避免页面销毁后回调报错
        this.replyFocusTimer = setTimeout(() => {
          this.replyFocusTimer = -1;
          this.getUIContext().getFocusController().requestFocus('replyTextArea');
        }, 100);
      },
      onWillDismiss: ((dismissAction: DismissSheetAction) => {
        // 关闭前主动收起键盘 + 清理焦点，避免退出后键盘仍弹着导致帖子页回复栏被抬起
        try {
          inputMethod.getController().stopInputSession();
        } catch (err) {
          console.warn(`[ThreadPage] stopInputSession failed: ${(err as Error).message}`);
        }
        this.getUIContext().getFocusController().clearFocus();
        dismissAction.dismiss();
      })
    })
  }
}

/**
 * #72 跳转楼层对话框（对齐 Android PromptDialog）
 * 输入页码后调用 onConfirm 回调跳转
 */
@CustomDialog
struct JumpPageDialog {
  currentPage: number = 1;
  totalPage: number = 1;
  onConfirm: (page: number) => void = () => {};
  @State inputPage: string = '';
  controller: CustomDialogController;

  build() {
    Column() {
      Text(getResourceString($r('app.string.title_jump_page')))
        .fontSize(18)
        .fontWeight(600)
        .fontColor($r('app.color.text_primary'))
        .margin({ bottom: 12 })

      Text(getResourceString($r('app.string.tip_jump_page', this.currentPage, this.totalPage)))
        .fontSize(14)
        .fontColor($r('app.color.text_caption'))
        .margin({ bottom: 16 })

      TextInput({ placeholder: getResourceString($r('app.string.jump_page_hint')), text: $$this.inputPage })
        .type(InputType.Number)
        .height(40)
        .borderRadius(8)
        .backgroundColor($r('app.color.input_background'))
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
        .placeholderColor($r('app.color.text_caption'))
        .padding({ left: 12, right: 12 })
        .margin({ bottom: 20 })

      Row() {
        Button(getResourceString($r('app.string.cancel_button')))
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .backgroundColor($r('app.color.input_background'))
          .layoutWeight(1)
          .height(38)
          .borderRadius(8)
          .onClick(() => {
            this.controller.close();
          })
          .margin({ right: 8 })

        Button(getResourceString($r('app.string.confirm')))
          .fontSize(14)
          .fontColor($r('app.color.white'))
          .backgroundColor($r('app.color.primary'))
          .layoutWeight(1)
          .height(38)
          .borderRadius(8)
          .onClick(() => {
            const page: number = Number(this.inputPage);
            if (page > 0) {
              this.onConfirm(page);
            }
            this.controller.close();
          })
      }
      .width('100%')
    }
    .padding({ left: 24, right: 24, top: 20, bottom: 20 })
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(16)
  }
}
