import { AppStorageV2 } from '@kit.ArkUI';
import { HdsNavDestination, ScrollEffectType, hdsMaterial } from '@kit.UIDesignKit';
import { common } from '@kit.AbilityKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { inputMethod } from '@kit.IMEKit';
import { TiebaAPI } from '../../api/TiebaAPI';
import { PostInfo, MediaInfo, ContentFragment, ContentFragmentType } from '../../model/ForumModels';
import { PbPageResult } from '../../proto/PbPageProto';
import { ImageLoadTypeState, IsWifiState, SafeBottomState } from '../../model/AppStorageV2Models';
import { LoadingView } from '../../components/LoadingView';
import { ErrorView } from '../../components/ErrorView';
import { ReplyBox, ReplyTarget } from '../../components/ReplyBox';
import { BaseViewModel, FetchDataResult } from '../../viewmodel/BaseViewModel';
import { getResourceString } from '../../utils/ResourceUtil';
import { getStatusBarHeight } from '../../utils/StatusBarUtil';
import { CommonDataSource } from '../../utils/CommonDataSource';
import { formatRelativeTime } from '../../utils/TimeUtil';
import { formatCount } from '../../utils/FormatUtil';
import { getMediaImageUrl, getAvatarImageUrl } from '../../utils/ImageLoadUtil';
import { generateAppLinkingUrl, buildThreadShareUrl } from '../../utils/AppLinkingUtil';
import { VideoCoverPlaceholder } from '../../components/VideoPlayer';
import { connectTheme, ThemeState } from '../../theme/ThemeManager';
import { VibratorUtil } from '../../utils/VibratorUtil';
import { RouterUtil, ThreadNavParams, SubPostsNavParams, UserProfileNavParams, ImageViewerNavParams } from '../../utils/RouterUtil';

// loadPreviousPage 加载成功后滚动到首条回复的延迟（ms），等待 LazyForEach 渲染就绪
const SCROLL_TO_FIRST_REPLY_DELAY_MS: number = 100;
// P2 #7：bindSheet onAppear 后延迟聚焦回复输入框（ms），等待 sheet 弹出动画完成
// 原 L1757 误用 SCROLL_TO_FIRST_REPLY_DELAY_MS（语义不符），拆分为独立常量
const REPLY_FOCUS_DELAY_MS: number = 100;
// 楼主楼层号（floor==1 表示楼主首楼，对齐服务端 protobuf 字段）
const FIRST_FLOOR_NUMBER: number = 1;
// 加载上一页成功后滚动到首条新回复的索引（跳过 LoadPreviousBtn 本身）
const SCROLL_TO_NEW_REPLY_INDEX: number = 1;
// #194 HdsNavDestination titleBar 高度（mini 模式约 48vp），用于内容区顶部占位避让
const TITLE_BAR_HEIGHT: number = 48;

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

  getTid(): number {
    return this.tid;
  }

  setOnlyAuthor(onlyAuthor: boolean): void {
    this.onlyAuthor = onlyAuthor;
  }

  setSort(sort: number): void {
    this.sort = sort;
  }

  protected async fetchData(page: number, isRefresh: boolean): Promise<FetchDataResult<PostInfo>> {
    const result = await TiebaAPI.getPosts({
      threadId: this.tid,
      page: page,
      onlyAuthor: this.onlyAuthor,
      sort: this.sort
    });
    this.threadTitle = result.thread.title;
    if (isRefresh) {
      this.updateThreadInfo(result);
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
    const filteredList: PostInfo[] = this.filterFirstPostAndBuildFallback(result);
    return {
      list: filteredList,
      hasMore: result.posts.hasMore,
      currentPage: result.posts.currentPage
    };
  }

  /**
   * 更新主题帖字段（标题/作者/回复数/点赞数/吧名/浏览数/创建时间/forumId）
   * fetchData(isRefresh) 和 jumpToPage 共用，避免字段同步逻辑重复
   */
  private updateThreadInfo(result: PbPageResult): void {
    this.threadTitle = result.thread.title;
    this.threadAuthorUid = result.thread.author.uid;
    this.threadReplyNum = result.thread.replyNum;
    this.threadAgreeNum = result.thread.agreeNum;
    this.threadIsAgreed = result.thread.isAgreed;
    this.threadForumName = result.thread.forumName;
    this.threadViewNum = result.thread.viewNum;
    this.threadCreateTime = result.thread.createTime;
    this.forumId = result.forumId;  // #74 回帖 API 必传字段
  }

  /**
   * 过滤楼主楼层（floor==1）并构造正文 fallback
   * 楼主楼层提取 fragments + mediaList 到信息栏合并显示，列表中过滤掉 floor==1 避免重复
   * fallback：floor==1 不在当前页时用 thread.content 纯文本构造 TEXT fragment 兜底，保证正文不丢
   * fetchData 和 jumpToPage 共用此逻辑
   */
  private filterFirstPostAndBuildFallback(result: PbPageResult): PostInfo[] {
    const filteredList: PostInfo[] = [];
    for (let i = 0; i < result.posts.list.length; i++) {
      const post: PostInfo = result.posts.list[i];
      if (post.floor === FIRST_FLOOR_NUMBER) {
        // 楼主楼层：提取 fragments + mediaList，供信息栏合并显示
        this.firstPostFragments = post.fragments;
        this.firstPostMediaList = post.mediaList;
      } else {
        filteredList.push(post);
      }
    }
    // #93 fallback：floor==1 不在当前页（DESC/onlyAuthor/跳转非首页）时，
    // firstPostFragments 为空，信息栏只显示标题不显示正文（用户反馈"标题和帖子内容分开"）
    // 用 result.thread.content 纯文本构造 TEXT fragment 兜底，保证正文不丢
    if (this.firstPostFragments.length === 0 && result.thread.content.length > 0) {
      const fallbackFrag: ContentFragment = new ContentFragment();
      fallbackFrag.type = ContentFragmentType.TEXT;
      fallbackFrag.text = result.thread.content;
      this.firstPostFragments = [fallbackFrag];
    }
    return filteredList;
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
      const result = await TiebaAPI.getPrevPosts(
        this.tid, prevPage, this.onlyAuthor, this.sort, lastPostId
      );
      // 过滤掉 floor==1（楼主楼层，已在列表中显示）和已存在的 pid（避免重复）
      const existingPids: Set<number> = new Set<number>();
      for (let i = 0; i < this.paginationState.dataList.length; i++) {
        existingPids.add(this.paginationState.dataList[i].pid);
      }
      const newPosts: PostInfo[] = [];
      for (let i = 0; i < result.posts.list.length; i++) {
        const p: PostInfo = result.posts.list[i];
        if (p.floor !== FIRST_FLOOR_NUMBER && !existingPids.has(p.pid)) {
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
      const result = await TiebaAPI.getPosts({
        threadId: this.tid,
        page: page,
        onlyAuthor: this.onlyAuthor,
        sort: this.sort
      });
      this.updateThreadInfo(result);
      // floor==1 过滤 + fallback 构造（对齐 fetchData 逻辑）
      const filteredList: PostInfo[] = this.filterFirstPostAndBuildFallback(result);
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
 * 楼层卡片（issue #31 拆为独立 @ComponentV2）
 * PostInfo 已 @ObservedV2 + @Trace，用 @Require @Param 引用 dataSource 内部对象，
 * 修改 post.isAgreed/agreeNum 等字段会自动局部刷新，无需 slice() 触发重建
 * A11 GlobalReuse：加 @ReusableV2，长列表滚动时复用减少创建/销毁开销（无 @Local 字段，无需 aboutToReuse）
 */
@ReusableV2
@ComponentV2
struct PostItem {
  @Require @Param post: PostInfo;
  // 是否为楼主楼层（用 post.author.uid === thread.author.uid 判断，对齐原 APP，分页后仍正确）
  @Param isAuthor: boolean = false;
  // #72 沉浸模式（纯净阅读）：隐藏头像区，仅显示内容+操作按钮
  @Param immersiveMode: boolean = false;
  // #79 图片加载策略：由父组件从 AppStorageV2 传入
  @Param imageLoadType: number = 0;
  @Param isWifi: boolean = false;
  @Event onAgreeClick?: (post: PostInfo) => void;
  @Event onDisagreeClick?: (post: PostInfo) => void;
  @Event onCommentClick?: () => void;
  // 点击作者区域（头像/名字）回调，跳转用户主页
  @Event onAuthorClick?: () => void;
  // #71 点击 @用户 回调，跳转被@用户的主页（uid + 昵称）
  @Event onAtClick?: (uid: number, name: string) => void;
  @Local themeState: ThemeState = connectTheme();

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
      // A5 图片优化：帖子媒体图场景
      .syncLoad(false)
      .interpolation(ImageInterpolation.High)
      .autoResize(true)
      .onError(() => { /* 帖子媒体图加载失败静默处理 */ })
      // #92 HitTestMode.Transparent：让触控穿透到父 List，避免 fling 期间碰到图片导致触控丢失
      .hitTestBehavior(HitTestMode.Transparent)
      .onClick(() => {
        // #165 路由迁移：router.pushUrl → RouterUtil.push
        RouterUtil.push(RouterUtil.ROUTE_IMAGE_VIEWER_PAGE,
          new ImageViewerNavParams(this.post.mediaList.map((m: MediaInfo) => m.url), index));
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
            .border(this.isAuthor ? { width: 2, color: this.themeState.primary } : { width: 0 })
            // A5 图片优化：头像场景
            .syncLoad(true)
            .interpolation(ImageInterpolation.Low)
            .onError(() => { /* 头像加载失败静默处理 */ })
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
                  .fontColor(this.themeState.primary)
                  .padding({ left: 6, right: 6, top: 1, bottom: 1 })
                  .backgroundColor(this.themeState.primary_light)
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
                .fontColor(this.themeState.primary)
                .onClick(() => {
                  this.showToast(frag.link);
                })
            } else if (frag.type === ContentFragmentType.AT) {
              // @用户：主色高亮 + 点击跳转被@用户主页
              Span(frag.text)
                .fontColor(this.themeState.primary)
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
            } else if (frag.type === ContentFragmentType.VIDEO) {
              // #151 视频碎片不内联渲染（VideoPlayer 是块级组件，无法内联到 Text）
              // 独立块在下方 videoFragments 区渲染，这里用空 Span 占位避免 webUrl 当文本显示
              Span('')
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

      // #151 视频碎片渲染：VIDEO 类型用 VideoCoverPlaceholder 懒创建（性能优化）
      // 列表中只渲染封面图+播放按钮，点击才创建 VideoPlayer，避免每个视频回复实例化 VideoController
      ForEach(this.post.fragments, (frag: ContentFragment, idx: number) => {
        if (frag.type === ContentFragmentType.VIDEO && frag.videoUrl.length > 0) {
          VideoCoverPlaceholder({
            videoUrl: frag.videoUrl,
            coverUrl: frag.coverUrl,
            videoWidth: frag.videoWidth,
            videoHeight: frag.videoHeight,
            imageLoadType: this.imageLoadType,
            isWifi: this.isWifi
          })
        }
      }, (frag: ContentFragment, idx: number) => `video_${idx}_${frag.videoUrl}`)

      // #93 "查看全部 N 条回复"入口：replyNum > 0 时显示，点击跳转楼中楼（对齐 Android open_all_sub_posts）
      // 之前只有评论图标可跳转楼中楼，用户反馈不够明显
      if (this.post.replyNum > 0) {
        Text($r('app.string.view_all_sub_posts', this.post.replyNum))
          .fontSize(13)
          .fontColor(this.themeState.primary)
          .margin({ top: 10 })
          .hitTestBehavior(HitTestMode.Block)
          .onClick(() => {
            if (this.onCommentClick) {
              this.onCommentClick();
            }
          })
      }

      Row() {
        Row() {
          Image($r('app.media.ic_like'))
            .width(16)
            .height(16)
            .fillColor(this.post.isAgreed ? this.themeState.primary : $r('app.color.text_caption'))
            // A5 图片优化：本地 SVG 图标
            .syncLoad(true)
            .interpolation(ImageInterpolation.Low)
            // #92 HitTestMode.Transparent：让触控穿透到父 List，避免 fling 期间碰到图片导致触控丢失
            .hitTestBehavior(HitTestMode.Transparent)
          Text(this.post.agreeNum.toString())
            .fontSize(12)
            .fontColor(this.post.isAgreed ? this.themeState.primary : $r('app.color.text_caption'))
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
            // A5 图片优化：本地 SVG 图标
            .syncLoad(true)
            .interpolation(ImageInterpolation.Low)
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
            // A5 图片优化：本地 SVG 图标
            .syncLoad(true)
            .interpolation(ImageInterpolation.Low)
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

// #163 [A4-S3] Navigation 路由表 @Builder：供 router_map.json 的 buildFunction 引用
@Builder
export function ThreadPageBuilder() {
  ThreadPage()
}

@ComponentV2
export struct ThreadPage {
  private viewModel: ThreadViewModel = new ThreadViewModel();
  private dataSource: CommonDataSource<PostInfo> = new CommonDataSource<PostInfo>();
  // #72 Scroller 用于跳转楼层后滚动到列表顶部 + #163 bindToScrollable 标题栏滚动模糊
  private scroller: Scroller = new Scroller();
  // #72 跳转楼层对话框控制器
  private jumpPageDialogController: CustomDialogController | null = null;
  // loadPreviousPage 中 setTimeout 句柄，aboutToDisappear 时清理避免页面销毁后回调报错
  private scrollTimer: number = -1;
  // #84 bindSheet onAppear 中 setTimeout 句柄，aboutToDisappear 时清理避免页面销毁后回调 requestFocus 报错
  private replyFocusTimer: number = -1;
  // #84 handleThreadShare 防抖锁，避免重复点击触发多个分享面板
  private isSharing: boolean = false;
  // 组件是否已销毁标志位：aboutToDisappear 置 true，所有 async 任务完成后检查，
  // 避免页面销毁后修改 @Local 触发警告或操作已销毁的 dataSource
  private isDestroyed: boolean = false;

  @Local tid: number = 0;
  @Local postCount: number = 0;
  @Local isLoading: boolean = false;
  @Local isRefreshing: boolean = false;
  @Local hasMore: boolean = true;
  @Local errorMessage: string = '';
  @Local threadTitle: string = '';
  @Local threadReplyNum: number = 0;
  @Local threadAuthorUid: number = 0;
  @Local threadAgreeNum: number = 0;
  @Local threadIsAgreed: boolean = false;
  @Local isFavorited: boolean = false;
  @Local isProcessingFavorite: boolean = false;
  @Local isProcessingAgree: boolean = false;
  @Local threadForumName: string = '';
  @Local threadViewNum: number = 0;
  @Local threadCreateTime: number = 0;
  @Local replyText: string = '';
  // #70 只看楼主 + 回复排序（持久化 sort 偏好到 AppStorage）
  @Local onlyAuthorMode: boolean = false;
  @Local sortOrder: number = 0;
  // #72 加载上一页 + 跳转楼层 + 沉浸模式
  @Local hasPrev: boolean = false;        // 是否有上一页（控制"加载上一页"按钮显示）
  @Local isLoadingPrevious: boolean = false;
  @Local totalPage: number = 1;           // 总页数（跳转楼层校验用）
  @Local currentPageMax: number = 1;      // 当前最大页码（跳转楼层提示用）
  @Local isImmersiveMode: boolean = false; // 沉浸模式（纯净阅读，隐藏顶部栏/底部栏/头像区）
  // 状态栏高度（vp），沉浸式避让状态栏，默认 36，aboutToAppear 动态获取
  @Local statusBarHeight: number = 36;
  // 内嵌回复框（bindSheet 半模态）：showReplySheet 控制显隐，replyTarget 持有回复目标参数
  @Local showReplySheet: boolean = false;
  @Local replyTarget: ReplyTarget = new ReplyTarget();
  // 楼主楼层（floor==1）的正文 fragments 和图片 mediaList（信息栏合并显示用）
  // 从 viewModel.firstPostFragments/firstPostMediaList 同步，避免标题与内容分开
  @Local firstPostFragments: ContentFragment[] = [];
  @Local firstPostMediaList: MediaInfo[] = [];
  // #79 图片加载策略：通过 AppStorageV2 共享，SettingsPage 修改后自动响应
  @Local imageLoadTypeState: ImageLoadTypeState = AppStorageV2.connect(ImageLoadTypeState, 'imageLoadType', () => new ImageLoadTypeState())!;
  @Local isWifiState: IsWifiState = AppStorageV2.connect(IsWifiState, 'isWifi', () => new IsWifiState())!;
  @Local safeBottomState: SafeBottomState = AppStorageV2.connect(SafeBottomState, 'safeBottom', () => new SafeBottomState())!;
  @Local themeState: ThemeState = connectTheme();

  // Toast 提示 helper（API 12+ 推荐用 UIContext.getPromptAction() 替代全局 promptAction）
  private showToast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message });
  }

  async aboutToAppear() {
    // #203 注入 DataSource 引用，供 BaseViewModel 内存压力时自动 clearCache
    this.viewModel.setDataSource(this.dataSource);
    // #163 路由迁移：router.getParams() → NavPathStack.getParamByName()
    // NavPathStack.getParamByName 返回所有同名页面参数数组，取最后一个（栈顶=当前页面）
    // SDK 返回 Array<unknown>，ArkTS 不支持 unknown，用 as Object[] 断言
    // 注意：参数读取必须在任何 await 之前，避免 await 挂起期间其他代码用默认 tid=0 发请求
    // （对齐 ForumPage 的正确做法，修复 350004 首次失败 bug）
    const paramsStack: Object[] = RouterUtil.getStack().getParamByName(RouterUtil.ROUTE_THREAD_PAGE) as Object[];
    if (paramsStack && paramsStack.length > 0) {
      const params = paramsStack[paramsStack.length - 1] as ThreadNavParams;
      if (params && params.tid) {
        const parsedTid: number = Number(params.tid);
        // NaN 校验：Number('abc') 返回 NaN，NaN 与任何数比较都为 false
        // 不校验会导致 viewModel.setTid(NaN) 后 API 请求带 NaN tid，服务端返回错误或空数据
        if (!Number.isNaN(parsedTid) && parsedTid > 0) {
          this.tid = parsedTid;
          this.viewModel.setTid(this.tid);
          // #109 A1 AppLinking：通过外部链接 see_lz=1 拉起时启用只看楼主模式
          // 对齐 Android 原版 onCopyLinkClick 行为：https://tieba.baidu.com/p/{tid}?see_lz=1
          if (params.seeLz === true) {
            this.onlyAuthorMode = true;
            this.viewModel.setOnlyAuthor(true);
          }
          // 参数就绪后立即触发加载，不等待 getStatusBarHeight（避免 await 时序竞态）
          this.loadPosts(true).catch((err: Error) => {
            console.error(`[ThreadPage] loadPosts failed: ${err.message}`);
          });
        } else {
          console.error(`[ThreadPage] invalid tid from params: ${params.tid}`);
          this.errorMessage = getResourceString($r('app.string.error_invalid_params'));
        }
      }
    }
    // #70 从 AppStorage 读取排序偏好（key: thread_default_sort，默认 0=正序）
    const savedSort = AppStorage.get<number>('thread_default_sort');
    if (savedSort !== null && savedSort !== undefined) {
      this.sortOrder = savedSort;
      this.viewModel.setSort(savedSort);
    }
    // 获取状态栏高度（沉浸式避让状态栏，对齐 HomePage/MessagePage 等页面做法）
    // 失败不阻塞后续加载，保留默认值 36
    // 放在参数读取+loadPosts 之后，避免 await 挂起期间参数未就绪
    try {
      this.statusBarHeight = await getStatusBarHeight(getContext(this));
    } catch (err) {
      console.error(`[ThreadPage] getStatusBarHeight failed: ${(err as Error).message}`);
    }
  }

  async loadPosts(isRefresh: boolean = false): Promise<void> {
    // 守卫：tid 未就绪时不发请求，避免 350004（对齐 aboutToAppear 参数读取前置的修复）
    if (this.viewModel.getTid() <= 0) {
      console.warn(`[ThreadPage] loadPosts skipped: tid not ready (tid=${this.viewModel.getTid()})`);
      return;
    }
    await this.viewModel.loadData(isRefresh);
    // 页面可能在 await 期间销毁，检查标志位避免修改已销毁组件的 @State
    if (this.isDestroyed) {
      return;
    }
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
    // #93 去掉 lastOpWasRefresh 条件：loadMore 时 viewModel.firstPostFragments 保留旧值，
    // 同步到 @State 也是同样的值，不会有副作用；避免 refresh 失败后 @State 不同步
    this.firstPostFragments = this.viewModel.firstPostFragments;
    this.firstPostMediaList = this.viewModel.firstPostMediaList;
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
   * PostInfo 已 @ObservedV2 + @Trace，PostItem 用 @Require @Param，
   * 修改 post 字段会自动局部刷新，无需 slice() 触发重建
   */
  async handleAgree(post: PostInfo): Promise<void> {
    // 防抖：请求进行中时禁用点击，避免连点导致赞数错乱（3280003 不能重复取消/3280004 操作太频繁）
    if (post.isAgreeing) {
      return;
    }
    post.isAgreeing = true;
    // #121 触感反馈：楼层点赞属于强调交互，触发重震动
    VibratorUtil.heavy();
    // 保存原状态用于失败回滚（对齐原 APP）
    const prevIsAgreed: boolean = post.isAgreed;
    const prevAgreeNum: number = post.agreeNum;
    try {
      if (post.isAgreed) {
        await TiebaAPI.unagree(post.tid, post.pid, false);
      } else {
        await TiebaAPI.agree(post.tid, post.pid, false);
      }
      // 页面可能在 await 期间销毁，检查标志位避免修改已销毁组件的 @State
      if (this.isDestroyed) {
        return;
      }
      if (post.isAgreed) {
        post.isAgreed = false;
        post.agreeNum = Math.max(0, post.agreeNum - 1);
      } else {
        post.isAgreed = true;
        post.agreeNum += 1;
      }
      // @ObservedV2 + @Trace + @Require @Param 自动局部刷新，无需 slice()
    } catch (err) {
      // 页面可能在 await 期间销毁，检查标志位避免修改已销毁组件的 @Local
      if (this.isDestroyed) {
        return;
      }
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
    // #121 触感反馈：楼层点踩属于强调交互，触发重震动
    VibratorUtil.heavy();
    // 保存原状态用于失败回滚（对齐原 APP）
    const prevIsDisagreed: boolean = post.isDisagreed;
    const prevDisagreeNum: number = post.disagreeNum;
    try {
      if (post.isDisagreed) {
        await TiebaAPI.undisagree(post.tid, post.pid, false);
      } else {
        await TiebaAPI.disagree(post.tid, post.pid, false);
      }
      // 页面可能在 await 期间销毁，检查标志位避免修改已销毁组件的 @State
      if (this.isDestroyed) {
        return;
      }
      if (post.isDisagreed) {
        post.isDisagreed = false;
        post.disagreeNum = Math.max(0, post.disagreeNum - 1);
      } else {
        post.isDisagreed = true;
        post.disagreeNum += 1;
      }
      // @ObservedV2 + @Trace + @Require @Param 自动局部刷新
    } catch (err) {
      // 页面可能在 await 期间销毁，检查标志位避免修改已销毁组件的 @Local
      if (this.isDestroyed) {
        return;
      }
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
    // #93 修复 tid=0 bug：post.tid 从 protobuf threadTid 解析，但日志显示为 0
    // 直接用 this.tid（从路由参数获取，必定有效）
    // #163 路由迁移：router.pushUrl → RouterUtil.push
    RouterUtil.push(RouterUtil.ROUTE_SUB_POSTS_PAGE,
      new SubPostsNavParams(this.tid, post.pid, post.floor));
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
    // 重新赋值整个 ReplyTarget 实例触发 @Local 刷新（非 @ObservedV2 类字段级监听）
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
      this.imageLoadTypeState.value,
      this.isWifiState.value
    ))
      .objectFit(ImageFit.Cover)
      .borderRadius(8)
      .backgroundColor($r('app.color.input_background'))
      .alt($r('app.media.startIcon'))
      .width('100%')
      .aspectRatio(isSingle ? 4 / 3 : 1)
      // A5 图片优化：帖子媒体图场景
      .syncLoad(false)
      .interpolation(ImageInterpolation.High)
      .autoResize(true)
      .onError(() => { /* 帖子媒体图加载失败静默处理 */ })
      // #92 HitTestMode.Transparent：让触控穿透到父 List，避免 fling 期间碰到图片导致触控丢失
      .hitTestBehavior(HitTestMode.Transparent)
      .onClick(() => {
        // #165 路由迁移：router.pushUrl → RouterUtil.push
        RouterUtil.push(RouterUtil.ROUTE_IMAGE_VIEWER_PAGE,
          new ImageViewerNavParams(this.firstPostMediaList.map((m: MediaInfo) => m.url), index));
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
   * 注意：主题帖不是 PostInfo，不在 dataSource 中，直接操作 @Local 变量
   */
  async handleThreadAgree(): Promise<void> {
    if (this.isProcessingAgree) {
      return;
    }
    this.isProcessingAgree = true;
    // #121 触感反馈：主题首楼点赞属于强调交互，触发重震动
    VibratorUtil.heavy();
    const prevIsAgreed: boolean = this.threadIsAgreed;
    const prevAgreeNum: number = this.threadAgreeNum;
    try {
      if (this.threadIsAgreed) {
        await TiebaAPI.unagree(this.tid, 0, false);
      } else {
        await TiebaAPI.agree(this.tid, 0, false);
      }
      // 页面可能在 await 期间销毁，检查标志位避免修改已销毁组件的 @State
      if (this.isDestroyed) {
        return;
      }
      if (this.threadIsAgreed) {
        this.threadIsAgreed = false;
        this.threadAgreeNum = Math.max(0, this.threadAgreeNum - 1);
      } else {
        this.threadIsAgreed = true;
        this.threadAgreeNum += 1;
      }
    } catch (err) {
      console.error('[ThreadPage] handleThreadAgree failed: ' + (err as Error).message);
      // 页面可能在 await 期间销毁，检查标志位避免修改已销毁组件的 @State
      if (this.isDestroyed) {
        return;
      }
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
    // #121 触感反馈：收藏/取消收藏属于强调交互，触发重震动
    VibratorUtil.heavy();
    try {
      if (this.isFavorited) {
        await TiebaAPI.removeStore(this.tid);
      } else {
        await TiebaAPI.addStore(this.tid, 0);
      }
      // 页面可能在 await 期间销毁，检查标志位避免修改已销毁组件的 @State
      if (this.isDestroyed) {
        return;
      }
      if (this.isFavorited) {
        this.isFavorited = false;
        this.showToast(getResourceString($r('app.string.favorite_removed')));
      } else {
        this.isFavorited = true;
        this.showToast(getResourceString($r('app.string.favorite_added')));
      }
    } catch (err) {
      console.error('[ThreadPage] handleThreadFavorite failed: ' + (err as Error).message);
      // 页面可能在 await 期间销毁，检查标志位避免修改已销毁组件的 @State
      if (this.isDestroyed) {
        return;
      }
      this.showToast((err as Error).message || getResourceString($r('app.string.follow_operation_failed')));
    } finally {
      this.isProcessingFavorite = false;
    }
  }

  /**
   * 分享按钮：调用系统分享面板（@kit.ShareKit systemShare）
   * 分享贴吧帖子链接 https://tieba.baidu.com/p/{tid}，UTD=HYPERLINK 直达浏览器
   * #194 分享按钮迁移到 titleBar menu 后无 anchor 节点，移除 anchor 参数，面板居中展示
   *
   * #109 A1 AppLinking：预留 generateAppLinkingUrl 入口
   * 当前 AGC 未开通 AppLinking 服务，generateAppLinkingUrl 会抛错自动降级使用 https URL
   * 后续在 AGC 控制台开通 AppLinking 并配置 domain 后，此处自动使用 AppLinking 短链
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
    // #121 触感反馈：分享属于常规交互，触发轻震动
    VibratorUtil.light();

    const threadTitle: string = this.viewModel.threadTitle.length > 0
      ? this.viewModel.threadTitle
      : getResourceString($r('app.string.app_name'));
    const description: string = this.viewModel.threadForumName.length > 0
      ? `${this.viewModel.threadForumName} - ${threadTitle}`
      : threadTitle;

    // #109 A1 AppLinking：优先尝试 AppLinking 短链，AGC 未开通时降级 https URL
    // generateAppLinkingUrl 同步抛错，try-catch 降级到 buildThreadShareUrl
    let shareUrl: string;
    try {
      shareUrl = generateAppLinkingUrl(this.tid, threadTitle);
      console.info('[ThreadPage] share using AppLinking url');
    } catch (err) {
      // AGC 未开通预期路径：降级使用标准 https URL
      shareUrl = buildThreadShareUrl(this.tid, this.onlyAuthorMode);
      console.info(`[ThreadPage] share fallback to https url: ${(err as Error).message}`);
    }

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
        this.isSharing = false;
        return;
      }
      controller.on('dismiss', () => {
        console.info('[ThreadPage] share panel closed');
        this.isSharing = false;
      });
      controller.show(hostContext, {
        previewMode: systemShare.SharePreviewMode.DEFAULT,
        selectionMode: systemShare.SelectionMode.SINGLE
      }).catch((err: Error) => {
        // show 失败时重置防抖锁，允许用户重试；成功时保持锁定，等 dismiss 回调重置
        console.error(`[ThreadPage] share show failed: ${err.message}`);
        this.showToast(err.message);
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
    // #165 路由迁移：router.pushUrl → RouterUtil.push
    RouterUtil.push(RouterUtil.ROUTE_USER_PROFILE_PAGE,
      new UserProfileNavParams(portrait, userName, uid));
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
      // 页面可能在 await 期间销毁，检查标志位避免操作已销毁组件的 dataSource 和 @State
      if (this.isDestroyed) {
        return;
      }
      if (success) {
        // 前置插入新数据到 dataSource 头部
        this.dataSource.prependData(this.viewModel.lastPrevList);
        this.postCount = this.dataSource.totalCount();
        this.hasPrev = this.viewModel.hasPrev;
        this.isLoadingPrevious = this.viewModel.isLoadingPrevious;
        // 滚动到第一条新加载的回复（跳过 LoadPreviousBtn 本身，index=1）
        // 保存句柄，aboutToDisappear 时清理避免页面销毁后回调报错
        this.scrollTimer = setTimeout(() => {
          if (!this.isDestroyed) {
            this.scroller.scrollToIndex(SCROLL_TO_NEW_REPLY_INDEX, false);
          }
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
      // 页面可能在 await 期间销毁，检查标志位避免操作已销毁组件的 dataSource 和 @State
      if (this.isDestroyed) {
        return;
      }
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

  /**
   * #194 titleBar menu "更多"按钮：弹出 ActionMenu 显示二级菜单选项
   * 替代原 bindMenu（menu action 不支持 bindMenu），保留全部 6 项功能：
   * 只看楼主 / 排序(正序/倒序/热门) / 跳转楼层 / 沉浸模式
   */
  showMoreMenu(): void {
    this.getUIContext().getPromptAction().showActionMenu({
      title: getResourceString($r('app.string.thread_detail_title')),
      buttons: [
        { text: (this.onlyAuthorMode ? '✓ ' : '') + getResourceString($r('app.string.menu_see_lz')),
          color: $r('app.color.text_primary') },
        { text: (this.sortOrder === 0 ? '✓ ' : '') + getResourceString($r('app.string.menu_sort_asc')),
          color: $r('app.color.text_primary') },
        { text: (this.sortOrder === 1 ? '✓ ' : '') + getResourceString($r('app.string.menu_sort_desc')),
          color: $r('app.color.text_primary') },
        { text: (this.sortOrder === 2 ? '✓ ' : '') + getResourceString($r('app.string.menu_sort_hot')),
          color: $r('app.color.text_primary') },
        { text: getResourceString($r('app.string.menu_jump_page')),
          color: $r('app.color.text_primary') },
        { text: (this.isImmersiveMode ? '✓ ' : '') + getResourceString($r('app.string.menu_immersive')),
          color: $r('app.color.text_primary') }
      ]
    }).then((result) => {
      switch (result.index) {
        case 0: this.toggleOnlyAuthor(); break;
        case 1: this.changeSort(0); break;
        case 2: this.changeSort(1); break;
        case 3: this.changeSort(2); break;
        case 4: this.showJumpPageDialog(); break;
        case 5: this.toggleImmersiveMode(); break;
        default: break;
      }
    }).catch((err: Error) => {
      console.error(`[ThreadPage] showMoreMenu failed: ${err.message}`);
    });
  }

  aboutToDisappear(): void {
    // 标记组件已销毁，所有进行中的 async 任务完成后检查此标志，避免修改已销毁组件的 @State
    this.isDestroyed = true;
    // #84 清理 setTimeout 句柄，避免页面销毁后回调触发 scroller.scrollToIndex / requestFocus 报错
    if (this.scrollTimer >= 0) {
      clearTimeout(this.scrollTimer);
      this.scrollTimer = -1;
    }
    if (this.replyFocusTimer >= 0) {
      clearTimeout(this.replyFocusTimer);
      this.replyFocusTimer = -1;
    }
    // #203 清理 ViewModel 持有的 DataSource 引用，防止 ViewModel 被全局缓存时引用泄漏
    this.viewModel.setDataSource(null);
    // #84 关闭跳页对话框，避免页面销毁后 CustomDialog 持有已销毁组件引用导致内存泄漏
    if (this.jumpPageDialogController !== null) {
      this.jumpPageDialogController.close();
      this.jumpPageDialogController = null;
    }
    // #84 关闭回复 sheet，避免 sheet 内 ReplyBox 闭包引用已销毁组件
    this.showReplySheet = false;
    // 重置状态锁，避免异步任务在组件销毁后仍持有锁导致后续逻辑异常
    this.isProcessingAgree = false;
    this.isProcessingFavorite = false;
    this.isSharing = false;
    this.isLoading = false;
    this.isRefreshing = false;
    this.isLoadingPrevious = false;
  }

  build() {
    // #194 HdsNavDestination titleBar 穿透式（Mode 2）：参考 HomePage
    // - titleBar 提供：返回按钮 + 帖子标题（mainTitle）+ menu（收藏/分享/更多）
    // - "更多"按钮用 showMoreMenu() 弹 ActionMenu 实现 6 项二级菜单（titleBar menu action 不支持 bindMenu）
    // - 分享按钮迁移到 menu 后无 anchor 节点，ShareController.show 移除 anchor 参数
    // - List clip(false) + cachedCount(_, true) 让内容穿透到 titleBar 下方做模糊
    // - #72 沉浸模式下 hideTitleBar(true) 隐藏 titleBar，保留纯净阅读
    HdsNavDestination() {
    Column() {
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
                          .fontColor(this.themeState.primary)
                          .onClick(() => {
                            this.showToast(frag.link);
                          })
                      } else if (frag.type === ContentFragmentType.AT) {
                        Span(frag.text)
                          .fontColor(this.themeState.primary)
                          .onClick(() => {
                            this.navigateToUserProfile('', frag.text, frag.uid);
                          })
                      } else if (frag.type === ContentFragmentType.EMOJI) {
                        ImageSpan('https://static.tieba.baidu.com/tb/editor/images/client/' + frag.text + '.png')
                          .width(20)
                          .height(20)
                          .verticalAlign(ImageSpanAlignment.CENTER)
                      } else if (frag.type === ContentFragmentType.VIDEO) {
                        // #151 视频碎片不内联渲染，独立块在下方渲染，空 Span 占位避免 webUrl 当文本显示
                        Span('')
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

                // #151 楼主帖视频碎片渲染：VIDEO 类型用 VideoCoverPlaceholder 懒创建（性能优化）
                ForEach(this.firstPostFragments, (frag: ContentFragment, idx: number) => {
                  if (frag.type === ContentFragmentType.VIDEO && frag.videoUrl.length > 0) {
                    VideoCoverPlaceholder({
                      videoUrl: frag.videoUrl,
                      coverUrl: frag.coverUrl,
                      videoWidth: frag.videoWidth,
                      videoHeight: frag.videoHeight,
                      imageLoadType: this.imageLoadTypeState.value,
                      isWifi: this.isWifiState.value
                    })
                  }
                }, (frag: ContentFragment, idx: number) => `firstpost_video_${idx}_${frag.videoUrl}`)

                Row() {
                  if (this.threadViewNum > 0) {
                    Row() {
                      Image($r('app.media.ic_eye'))
                        .width(14)
                        .height(14)
                        .fillColor($r('app.color.text_caption'))
                        // A5 图片优化：本地 SVG 图标
                        .syncLoad(true)
                        .interpolation(ImageInterpolation.Low)
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
                      // A5 图片优化：本地 SVG 图标
                      .syncLoad(true)
                      .interpolation(ImageInterpolation.Low)
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
                      .fillColor(this.threadIsAgreed ? this.themeState.primary : $r('app.color.text_caption'))
                      // A5 图片优化：本地 SVG 图标
                      .syncLoad(true)
                      .interpolation(ImageInterpolation.Low)
                      // #92 HitTestMode.Transparent：让触控穿透到父 List，避免 fling 期间碰到图片导致触控丢失
                      .hitTestBehavior(HitTestMode.Transparent)
                    if (this.threadAgreeNum > 0) {
                      Text(formatCount(this.threadAgreeNum))
                        .fontSize(12)
                        .fontColor(this.threadIsAgreed ? this.themeState.primary : $r('app.color.text_caption'))
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
                    .fontColor(this.themeState.primary)
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
                imageLoadType: this.imageLoadTypeState.value,
                isWifi: this.isWifiState.value,
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
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .cachedCount(8, true)
        // #194 clip(false) + cachedCount(_, true) 让内容穿透到 titleBar 下方做模糊（对齐 HomePage 混合式）
        .clip(false)
        // #194 混合式：padding top 移到外层 Column，List 仅留小间距
        .padding({ left: 16, right: 16, top: 8 })
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
            // A5 图片优化：本地 SVG 图标
            .syncLoad(true)
            .interpolation(ImageInterpolation.Low)
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
            // A5 图片优化：本地 SVG 图标
            .syncLoad(true)
            .interpolation(ImageInterpolation.Low)
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
            // A5 图片优化：本地 SVG 图标
            .syncLoad(true)
            .interpolation(ImageInterpolation.Low)
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
      }
    }
    .width('100%')
    .height('100%')
    // #194 混合式：外层 Column padding top 避让状态栏 + titleBar（沉浸模式仅避让状态栏）
    .padding({ top: this.isImmersiveMode ? this.statusBarHeight : this.statusBarHeight + TITLE_BAR_HEIGHT })
    .backgroundColor($r('app.color.page_background'))
    }
    .titleBar({
      // #194 不设 enableComponentSafeArea，让内容穿透到 titleBar 下方（配合 clip(false) + cachedCount）
      // titleBar 的 GRADIENT_BLUR + ADAPTIVE 对穿透内容做模糊，避免不透明背景板遮挡
      content: {
        // 标题显示帖子标题（可能很长，titleBar 自动省略），无标题时用默认占位
        title: {
          mainTitle: this.threadTitle.length > 0
            ? this.threadTitle
            : getResourceString($r('app.string.thread_detail_title'))
        },
        // menu：收藏 + 分享 + 更多（替代原自定义顶部栏按钮）
        menu: {
          value: [{
            content: {
              icon: $r('app.media.ic_star'),
              isEnabled: true,
              action: () => this.handleThreadFavorite()
            }
          }, {
            content: {
              icon: $r('app.media.ic_share'),
              isEnabled: true,
              action: () => this.handleThreadShare()
            }
          }, {
            content: {
              icon: $r('app.media.ic_more'),
              isEnabled: true,
              action: () => this.showMoreMenu()
            }
          }]
        }
      },
      style: {
        // GRADIENT_BLUR 渐变模糊：标题栏顶部模糊→底部清晰，无硬边
        scrollEffectOpts: {
          enableScrollEffect: true,
          scrollEffectType: ScrollEffectType.GRADIENT_BLUR
        },
        // ADAPTIVE 沉浸光感材质：系统自适应模糊，不依赖下层内容（不会因内容滚出屏幕而变白）
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.ADAPTIVE,
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
        },
        // #194 originalStyle：滚动效果生效前的初始样式，图标颜色跟随主题色（标题用默认黑色）
        originalStyle: {
          contentStyle: {
            menuStyle: { iconColor: this.themeState.primary }
          }
        },
        // #194 scrollEffectStyle：滚动效果生效后的样式，图标颜色跟随主题色（标题用默认黑色）
        scrollEffectStyle: {
          contentStyle: {
            menuStyle: { iconColor: this.themeState.primary }
          }
        }
      },
      // 避让状态栏：setWindowLayoutFullScreen(true) 全屏模式下 titleBar 默认不避让状态栏
      avoidLayoutSafeArea: true
    })
    .bindToScrollable([this.scroller])
    // #72 沉浸模式隐藏 titleBar，保留纯净阅读（动态绑定 isImmersiveMode）
    .hideTitleBar(this.isImmersiveMode)
    .backgroundColor($r('app.color.page_background'))
    // 内嵌回复框（bindSheet 半模态）
    // #93 修复回复工具栏不跟键盘上移：
    // bindSheet 是半模态浮层，独立于页面根节点，不受全局 setKeyboardAvoidMode(RESIZE) 影响
    // 之前用 NONE 依赖全局 RESIZE 是错误判断，sheet 内容高度固定不变，工具栏被键盘遮挡
    // 改用 TRANSLATE_AND_RESIZE：sheet 自身响应键盘，键盘弹出时 sheet 整体上移 + 内容区域缩小，
    // 底部工具栏（图片/表情/发送按钮）随之上移到键盘上方
    // 同时全局改为 OFFSET（避免双套避让机制冲突，见 EntryAbility.ets）
    .bindSheet($$this.showReplySheet, this.ReplySheetBuilder(), {
      height: SheetSize.MEDIUM,
      dragBar: true,
      showClose: true,
      keyboardAvoidMode: SheetKeyboardAvoidMode.TRANSLATE_AND_RESIZE,
      // 楼中楼回复（postId > 0）显示"回复楼层"，否则显示"回复主题"
      title: { title: this.replyTarget.postId > 0
        ? getResourceString($r('app.string.reply_subpost_title'))
        : getResourceString($r('app.string.reply_thread_title')) },
      onAppear: () => {
        // #84 sheet 出现后主动让 TextArea 获焦，触发输入法弹出
        // 保存 setTimeout 句柄到 replyFocusTimer，aboutToDisappear 时清理避免页面销毁后回调报错
        this.replyFocusTimer = setTimeout(() => {
          this.replyFocusTimer = -1;
          // 组件未完全初始化时 requestFocus 可能抛异常，包裹 try-catch 避免中断 sheet onAppear
          try {
            this.getUIContext().getFocusController().requestFocus('replyTextArea');
          } catch (err) {
            console.warn(`[ThreadPage] requestFocus failed: ${(err as Error).message}`);
          }
        }, REPLY_FOCUS_DELAY_MS);
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
