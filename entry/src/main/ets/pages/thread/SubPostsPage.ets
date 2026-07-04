import { router } from '@kit.ArkUI';
import { TiebaAPI } from '../../api/TiebaAPI';
import { SubPostInfo, ContentFragment, ContentFragmentType, UserInfo } from '../../model/ForumModels';
import { LoadingView } from '../../components/LoadingView';
import { ErrorView } from '../../components/ErrorView';
import { getResourceString } from '../../utils/ResourceUtil';
import { getStatusBarHeight } from '../../utils/StatusBarUtil';
import { getAvatarUrl } from '../../utils/AvatarUtil';
import { formatRelativeTime } from '../../utils/TimeUtil';
import { EmoticonManager } from '../../utils/EmoticonManager';
import { CommonDataSource } from '../../utils/CommonDataSource';

/**
 * #73 楼中楼列表页
 *
 * 路由参数（router.pushUrl params）：
 *   - tid:    number  必需，主题帖 id
 *   - pid:    number  必需，楼层 id（要查询楼中楼的楼层）
 *   - floor:  number  可选，楼层号（用于标题显示，从 0 开始）
 *
 * 实现：
 *   - 调用 TiebaAPI.getComments(tid, pid, pn) 获取楼中楼列表
 *   - 分页：onReachEnd 触发 loadMore，pn 递增
 *   - 点赞：复用 TiebaAPI.agree(tid, spid, true)（isComment=true 走 obj_type=2 楼中楼）
 *   - 富文本渲染复用 PostItem 的 Text+Span+ImageSpan 模式（#71）
 */
/**
 * 单条楼中楼卡片（独立 @Component + @ObjectLink）
 * 用 @ObjectLink 响应 SubPostInfo（@Observed）的字段变化，
 * 点赞时 isAgreed/agreeNum 变化会自动局部刷新，无需 slice() 触发重建
 */
@Component
struct SubPostItemView {
  @ObjectLink post: SubPostInfo;
  /** 点赞回调（父组件传入，乐观更新 + 失败回滚） */
  onAgreeClick?: (post: SubPostInfo) => void;
  /** 回复按钮回调（跳转 ReplyPage） */
  onReplyClick?: (post: SubPostInfo) => void;
  /** 点击作者头像/名字回调（跳转用户主页） */
  onAuthorClick?: (portrait: string, name: string, uid: number) => void;
  /** 点击 @用户 回调（跳转被@用户主页，仅 uid + 昵称） */
  onAtClick?: (uid: number, name: string) => void;

  // Toast 提示 helper（API 12+ 推荐用 UIContext.getPromptAction() 替代全局 promptAction）
  private showToast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message });
  }

  build() {
    Column() {
      // 作者行
      Row() {
        Image(this.post.author.avatar)
          .width(28)
          .height(28)
          .borderRadius(14)
          .objectFit(ImageFit.Cover)
          .backgroundColor($r('app.color.input_background'))
          .alt($r('app.media.startIcon'))

        Column() {
          Text(this.post.author.nickname.length > 0 ? this.post.author.nickname : this.post.author.name)
            .fontSize(13)
            .fontColor($r('app.color.text_primary'))
            .fontWeight(600)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(formatRelativeTime(this.post.createTime))
            .fontSize(11)
            .fontColor($r('app.color.text_caption'))
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 8 })
        .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .hitTestBehavior(this.onAuthorClick ? HitTestMode.Block : HitTestMode.Default)
      .onClick(() => {
        if (this.onAuthorClick) {
          this.onAuthorClick(this.post.author.portrait, this.post.author.name, this.post.author.uid);
        }
      })

      // 富文本内容（复用 PostItem 渲染方案）
      if (this.post.fragments.length > 0) {
        Text() {
          ForEach(this.post.fragments, (frag: ContentFragment, idx: number) => {
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
                  if (this.onAtClick) {
                    this.onAtClick(frag.uid, frag.text);
                  }
                })
            } else if (frag.type === ContentFragmentType.EMOJI) {
              // 复用 EmoticonManager 构造 CDN URL，统一 URL 构造逻辑
              ImageSpan(EmoticonManager.getEmoticonUrl(frag.text))
                .width(18)
                .height(18)
                .verticalAlign(ImageSpanAlignment.CENTER)
            } else {
              Span(frag.text)
            }
          }, (frag: ContentFragment, idx: number) => `${idx}_${frag.type}_${frag.text}`)
        }
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: 8 })
        .width('100%')
        .lineHeight(22)
      } else {
        // fallback：fragments 为空时用纯 content
        Text(this.post.content)
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .margin({ top: 8 })
          .width('100%')
          .lineHeight(22)
      }

      // 操作行：回复按钮 + 点赞按钮（右对齐）
      Row() {
        // #74 回复按钮：跳转 ReplyPage 回复该楼中楼
        Row() {
          Image($r('app.media.ic_chat_bubble'))
            .width(14)
            .height(14)
            .fillColor($r('app.color.text_caption'))
          Text(getResourceString($r('app.string.reply_button_label')))
            .fontSize(11)
            .fontColor($r('app.color.text_caption'))
            .margin({ left: 3 })
        }
        .alignItems(VerticalAlign.Center)
        .hitTestBehavior(this.onReplyClick ? HitTestMode.Block : HitTestMode.Default)
        .onClick(() => {
          if (this.onReplyClick) {
            this.onReplyClick(this.post);
          }
        })

        Row() {
          Image($r('app.media.ic_like'))
            .width(14)
            .height(14)
            .fillColor(this.post.isAgreed ? $r('app.color.primary') : $r('app.color.text_caption'))
          if (this.post.agreeNum > 0) {
            Text(this.post.agreeNum.toString())
              .fontSize(11)
              .fontColor(this.post.isAgreed ? $r('app.color.primary') : $r('app.color.text_caption'))
              .margin({ left: 3 })
          }
        }
        .alignItems(VerticalAlign.Center)
        .margin({ left: 'auto' })
        .hitTestBehavior(this.onAgreeClick ? HitTestMode.Block : HitTestMode.Default)
        .onClick(() => {
          if (this.onAgreeClick) {
            this.onAgreeClick(this.post);
          }
        })
      }
      .width('100%')
      .margin({ top: 8 })
    }
    .width('100%')
    .padding(12)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(8)
  }
}

@Entry
@Component
struct SubPostsPage {
  @State tid: number = 0;
  @State pid: number = 0;
  @State floor: number = 0;
  /** 楼中楼列表数据源（LazyForEach + CommonDataSource，长列表性能优化） */
  subPostsDataSource: CommonDataSource<SubPostInfo> = new CommonDataSource<SubPostInfo>();
  @State isLoading: boolean = false;
  @State isLoadingMore: boolean = false;
  @State errorMessage: string = '';
  @State hasMore: boolean = true;
  @State currentPage: number = 1;
  @State totalPages: number = 1;
  @State statusBarHeight: number = 36;

  // Toast 提示 helper（API 12+ 推荐用 UIContext.getPromptAction() 替代全局 promptAction）
  private showToast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message });
  }

  async aboutToAppear() {
    try {
      this.statusBarHeight = await getStatusBarHeight(getContext(this));
    } catch (err) {
      console.warn(`[SubPostsPage] getStatusBarHeight failed: ${(err as Error).message}`);
    }
    const params = router.getParams() as Record<string, number>;
    if (params) {
      const tidVal = params['tid'];
      if (typeof tidVal === 'number') {
        this.tid = tidVal;
      }
      const pidVal = params['pid'];
      if (typeof pidVal === 'number') {
        this.pid = pidVal;
      }
      const floorVal = params['floor'];
      if (typeof floorVal === 'number') {
        this.floor = floorVal;
      }
    }
    this.loadSubPosts(true).catch((err: Error) => {
      console.error(`[SubPostsPage] loadSubPosts failed: ${err.message}`);
    });
  }

  /** 加载楼中楼列表。isRefresh=true 重置 pn=1，false 加载更多 */
  async loadSubPosts(isRefresh: boolean): Promise<void> {
    if (this.tid <= 0 || this.pid <= 0) {
      this.errorMessage = getResourceString($r('app.string.subposts_invalid_params'));
      return;
    }
    if (!isRefresh) {
      if (this.isLoadingMore || !this.hasMore) {
        return;
      }
    }
    if (isRefresh) {
      this.isLoading = true;
      this.isLoadingMore = false;  // refresh 时重置 loadMore 状态，避免状态残留竞态
      this.errorMessage = '';
    } else {
      this.isLoadingMore = true;
    }
    const targetPn: number = isRefresh ? 1 : this.currentPage + 1;
    try {
      const result = await TiebaAPI.getComments(this.tid, this.pid, targetPn);
      if (isRefresh) {
        this.subPostsDataSource.setData(result.subPosts);
      } else {
        // 加载更多：追加到列表末尾（增量通知，避免全量 reload）
        this.subPostsDataSource.appendData(result.subPosts);
      }
      this.currentPage = result.currentPage;
      this.totalPages = result.totalPages;
      this.hasMore = result.hasMore;
    } catch (err) {
      this.errorMessage = (err as Error).message || getResourceString($r('app.string.subposts_load_failed'));
    } finally {
      if (isRefresh) {
        this.isLoading = false;
      } else {
        this.isLoadingMore = false;
      }
    }
  }

  /** 楼中楼点赞。复用 TiebaAPI.agree(tid, spid, true)，乐观更新 + 失败回滚 */
  async handleSubPostAgree(post: SubPostInfo): Promise<void> {
    // 防御：未登录提示
    if (post.spid <= 0) {
      return;
    }
    // 乐观更新
    const prevAgreed: boolean = post.isAgreed;
    const prevAgreeNum: number = post.agreeNum;
    if (post.isAgreed) {
      post.isAgreed = false;
      post.agreeNum = Math.max(0, post.agreeNum - 1);
    } else {
      post.isAgreed = true;
      post.agreeNum = post.agreeNum + 1;
    }
    try {
      if (prevAgreed) {
        await TiebaAPI.unagree(this.tid, post.spid, true);
      } else {
        await TiebaAPI.agree(this.tid, post.spid, true);
      }
    } catch (err) {
      // 回滚
      post.isAgreed = prevAgreed;
      post.agreeNum = prevAgreeNum;
      const msg: string = (err as Error).message || getResourceString($r('app.string.follow_operation_failed'));
      this.showToast(msg);
    }
  }

  /** 点击作者跳转用户主页 */
  navigateToUserProfile(portrait: string, userName: string, uid: number): void {
    router.pushUrl({
      url: 'pages/user/UserProfilePage',
      params: { portrait: portrait, userName: userName, uid: uid }
    }).catch((err: Error) => {
      console.error(`[SubPostsPage] navigate to user profile failed: ${err.message}`);
    });
  }

  /**
   * #74 跳转到 ReplyPage 回复某条楼中楼
   * 楼中楼的楼中楼：subPostId 传 spid，被回复者为该楼中楼作者
   * 普通楼中楼回复（不带 spid）：subPostId 不传，回复的是该楼层
   */
  navigateToReply(target?: SubPostInfo): void {
    const params: Record<string, Object> = {
      'tid': this.tid,
      'fid': 0,  // 楼中楼回复时 fid 非必传（v_fid/v_fname 留空）
      'forumName': '',
      'postId': this.pid  // 被回复楼层 pid
    };
    if (target !== undefined) {
      params['subPostId'] = target.spid;
      params['replyUid'] = target.author.uid;
      params['replyUserName'] = target.author.name;
      params['replyUserPortrait'] = target.author.portrait;
      params['floor'] = target.floor;
    }
    router.pushUrl({
      url: 'pages/thread/ReplyPage',
      params: params
    }).catch((err: Error) => {
      console.error(`[SubPostsPage] navigate to ReplyPage failed: ${err.message}`);
    });
  }

  build() {
    Column() {
      // 顶部导航栏
      Row() {
        Image($r('app.media.ic_back'))
          .width(20)
          .height(20)
          .fillColor($r('app.color.primary'))
          .onClick(() => router.back())

        Text(getResourceString($r('app.string.subposts_title', this.floor + 1)))
          .fontSize(17)
          .fontWeight(600)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .margin({ left: 8, right: 8 })

        Blank().width(20).height(20)
      }
      .width('100%')
      .height(44 + this.statusBarHeight)
      .padding({ left: 16, right: 16, top: this.statusBarHeight })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
      .alignItems(VerticalAlign.Center)
      .backgroundColor($r('app.color.page_background'))

      // 内容区
      if (this.isLoading && this.subPostsDataSource.totalCount() === 0) {
        LoadingView({ message: getResourceString($r('app.string.loading')) })
          .layoutWeight(1)
      } else if (this.errorMessage.length > 0 && this.subPostsDataSource.totalCount() === 0) {
        ErrorView({
          message: this.errorMessage,
          onRetryClick: () => this.loadSubPosts(true)
        })
          .layoutWeight(1)
      } else if (this.subPostsDataSource.totalCount() === 0) {
        Column() {
          Text($r('app.string.subposts_empty'))
            .fontSize(14)
            .fontColor($r('app.color.text_caption'))
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        List() {
          LazyForEach(this.subPostsDataSource, (post: SubPostInfo) => {
            ListItem() {
              SubPostItemView({
                post: post,
                onAgreeClick: (p: SubPostInfo) => {
                  this.handleSubPostAgree(p);
                },
                onReplyClick: (p: SubPostInfo) => {
                  this.navigateToReply(p);
                },
                onAuthorClick: (portrait: string, name: string, uid: number) => {
                  this.navigateToUserProfile(portrait, name, uid);
                },
                onAtClick: (uid: number, name: string) => {
                  // @碎片只含 uid + 昵称，portrait 传空串（getUserProfile 支持 uid-only 查询）
                  this.navigateToUserProfile('', name, uid);
                }
              })
            }
            .margin({ top: 4, bottom: 4 })
          }, (post: SubPostInfo, index: number) => `${post.spid}_${index}`)

          // 加载更多 / 已加载全部
          ListItem() {
            if (this.isLoadingMore) {
              Row() {
                Text($r('app.string.loading_more'))
                  .fontSize(14)
                  .fontColor($r('app.color.text_caption'))
              }
              .width('100%')
              .height(48)
              .justifyContent(FlexAlign.Center)
            } else if (this.hasMore) {
              Row() {
                Text($r('app.string.click_to_load_more'))
                  .fontSize(14)
                  .fontColor($r('app.color.primary'))
              }
              .width('100%')
              .height(48)
              .justifyContent(FlexAlign.Center)
              .onClick(() => {
                this.loadSubPosts(false).catch((err: Error) => {
                  console.error(`[SubPostsPage] loadMore failed: ${err.message}`);
                });
              })
            } else {
              Row() {
                Text($r('app.string.no_more_posts'))
                  .fontSize(12)
                  .fontColor($r('app.color.text_caption'))
              }
              .width('100%')
              .height(48)
              .justifyContent(FlexAlign.Center)
            }
          }
        }
        .layoutWeight(1)
        .padding({ left: 12, right: 12 })
        .cachedCount(10)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .nestedScroll({ scrollForward: NestedScrollMode.PARENT_FIRST, scrollBackward: NestedScrollMode.SELF_FIRST })
        .onReachEnd(() => {
          this.loadSubPosts(false).catch((err: Error) => {
            console.error(`[SubPostsPage] onReachEnd loadMore failed: ${err.message}`);
          });
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_background'))
  }
}
