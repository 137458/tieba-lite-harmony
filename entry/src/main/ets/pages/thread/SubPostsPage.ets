import { router } from '@kit.ArkUI';
import { inputMethod } from '@kit.IMEKit';
import { TiebaAPI } from '../../api/TiebaAPI';
import { SubPostInfo, ContentFragment, ContentFragmentType, UserInfo } from '../../model/ForumModels';
import { LoadingView } from '../../components/LoadingView';
import { ErrorView } from '../../components/ErrorView';
import { ReplyBox, ReplyTarget } from '../../components/ReplyBox';
import { getResourceString } from '../../utils/ResourceUtil';
import { getStatusBarHeight } from '../../utils/StatusBarUtil';
import { formatRelativeTime } from '../../utils/TimeUtil';
import { EmoticonManager } from '../../utils/EmoticonManager';
import { CommonDataSource } from '../../utils/CommonDataSource';
import { getAvatarImageUrl } from '../../utils/ImageLoadUtil';

/** SubPostsPage 路由参数 */
interface SubPostsPageParams {
  // ArkUI router.pushUrl params 跨页面传递时 number 可能被序列化为 string
  // （特别是 int64 tid/pid 可能超过 Number.MAX_SAFE_INTEGER）
  // 用 string | number 联合类型 + Number() 转换兼容两种情况
  tid?: string | number;
  pid?: string | number;
  floor?: string | number;
}

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
  // #79 图片加载策略：通过 AppStorage 共享，SettingsPage 修改后自动响应
  @StorageProp('imageLoadType') imageLoadType: number = 0;
  @StorageProp('isWifi') isWifi: boolean = false;

  // Toast 提示 helper（API 12+ 推荐用 UIContext.getPromptAction() 替代全局 promptAction）
  private showToast(message: string): void {
    this.getUIContext().getPromptAction().showToast({ message });
  }

  build() {
    Column() {
      // 作者行
      Row() {
        // #79 接入图片加载策略：shouldLoad=false 时返回空串，Image 组件显示 alt 占位图
        Image(getAvatarImageUrl(this.post.author.avatar, this.imageLoadType, this.isWifi))
          .width(28)
          .height(28)
          .borderRadius(14)
          .objectFit(ImageFit.Cover)
          .backgroundColor($r('app.color.input_background'))
          .alt($r('app.media.startIcon'))
          // #92 HitTestMode.Transparent：让触控穿透到父 List，避免 fling 期间碰到图片导致触控丢失
          .hitTestBehavior(HitTestMode.Transparent)

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
      // #92 HitTestMode.Transparent：让触控穿透到父 List，避免 fling 期间碰到用户行导致触控丢失
      .hitTestBehavior(HitTestMode.Transparent)
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
            // #92 HitTestMode.Transparent：让触控穿透到父 List，避免 fling 期间碰到图片导致触控丢失
            .hitTestBehavior(HitTestMode.Transparent)
          Text(getResourceString($r('app.string.reply_button_label')))
            .fontSize(11)
            .fontColor($r('app.color.text_caption'))
            .margin({ left: 3 })
        }
        .alignItems(VerticalAlign.Center)
        // #93 HitTestMode.Block：与 ThreadPage 保持一致，确保 onClick 触发
        // 之前误用 Transparent 导致点击穿透到父 List，onClick 不触发
        .hitTestBehavior(HitTestMode.Block)
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
            // #92 HitTestMode.Transparent：让触控穿透到父 List，避免 fling 期间碰到图片导致触控丢失
            .hitTestBehavior(HitTestMode.Transparent)
          if (this.post.agreeNum > 0) {
            Text(this.post.agreeNum.toString())
              .fontSize(11)
              .fontColor(this.post.isAgreed ? $r('app.color.primary') : $r('app.color.text_caption'))
              .margin({ left: 3 })
          }
        }
        .alignItems(VerticalAlign.Center)
        .margin({ left: 'auto' })
        // #93 HitTestMode.Block：与 ThreadPage 保持一致，确保 onClick 触发（修复"评论不能点赞"）
        // 之前误用 Transparent 导致点击穿透到父 List，onClick 不触发
        .hitTestBehavior(HitTestMode.Block)
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
  @StorageProp('safeBottom') safeBottom: number = 0;
  // #88 楼中楼点赞防重复点击标志位，请求 in-flight 期间拒绝再次点击
  // 改为 private 字段：点赞状态变化无需触发整页 build，仅作为防抖锁，
  // 避免 @State 变化引起 SubPostsPage build 重新执行（包含 LazyForEach 重建风险）
  private isProcessingSubPostAgree: boolean = false;
  // 内嵌回复框（bindSheet 半模态）：showReplySheet 控制显隐，replyTarget 持有回复目标参数
  @State showReplySheet: boolean = false;
  @State replyTarget: ReplyTarget = new ReplyTarget();
  // #84 bindSheet onAppear 中 setTimeout 句柄，aboutToDisappear 时清理避免页面销毁后回调 requestFocus 报错
  private replyFocusTimer: number = -1;

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
    const params = router.getParams() as SubPostsPageParams;
    if (params) {
      // #93 修复"参数无效无法加载楼中楼"：
      // router.pushUrl params 跨页面传递时 number 可能被序列化为 string
      // 用 Number() 转换兼容两种情况，参考 ThreadPage.ets 路由参数处理
      const tidVal: number = Number(params.tid);
      const pidVal: number = Number(params.pid);
      const floorVal: number = Number(params.floor);
      if (!Number.isNaN(tidVal) && tidVal > 0) {
        this.tid = tidVal;
      }
      if (!Number.isNaN(pidVal) && pidVal > 0) {
        this.pid = pidVal;
      }
      if (!Number.isNaN(floorVal) && floorVal >= 0) {
        this.floor = floorVal;
      }
    }
    this.loadSubPosts(true).catch((err: Error) => {
      console.error(`[SubPostsPage] loadSubPosts failed: ${err.message}`);
    });
  }

  // #84 aboutToDisappear：清理 setTimeout 句柄 + 关闭 sheet，避免页面销毁后回调引用已销毁组件
  aboutToDisappear(): void {
    if (this.replyFocusTimer >= 0) {
      clearTimeout(this.replyFocusTimer);
      this.replyFocusTimer = -1;
    }
    // 关闭回复 sheet，避免 sheet 内 ReplyBox 闭包引用已销毁组件
    this.showReplySheet = false;
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

  /** 楼中楼点赞 toggle。复用 TiebaAPI.agree/unagree(tid, spid, true)，乐观更新 + 失败回滚 */
  async toggleSubPostAgree(post: SubPostInfo): Promise<void> {
    // 防御：未登录提示
    if (post.spid <= 0) {
      return;
    }
    // 防重复点击：上一次点赞请求未完成时拒绝再次触发
    if (this.isProcessingSubPostAgree) {
      return;
    }
    this.isProcessingSubPostAgree = true;
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
    } finally {
      this.isProcessingSubPostAgree = false;
    }
  }

  /** 点击作者跳转用户主页 */
  navigateToUserProfile(portrait: string, userName: string, uid: number): void {
    // 防御：uid<=0 且 portrait 为空时无法查询用户资料，跳过跳转
    if (uid <= 0 && portrait.length === 0) {
      console.warn(`[SubPostsPage] navigateToUserProfile skipped: uid=${uid}, portrait empty`);
      return;
    }
    router.pushUrl({
      url: 'pages/user/UserProfilePage',
      params: { portrait: portrait, userName: userName, uid: uid }
    }).catch((err: Error) => {
      console.error(`[SubPostsPage] navigate to user profile failed: ${err.message}`);
    });
  }

  /**
   * 打开内嵌回复框（bindSheet 半模态）
   * 替代原 navigateToReply 跳转 ReplyPage 方案
   * 楼中楼的楼中楼：subPostId 传 spid，被回复者为该楼中楼作者
   * 普通楼中楼回复（不带 spid）：subPostId 不传，回复的是该楼层
   */
  openReplyBox(replyTargetSubPost?: SubPostInfo): void {
    const newTarget: ReplyTarget = new ReplyTarget();
    newTarget.tid = this.tid;
    newTarget.fid = 0;  // 楼中楼回复时 fid 非必传（v_fid/v_fname 留空）
    newTarget.forumName = '';
    newTarget.postId = this.pid;  // 被回复楼层 pid
    if (replyTargetSubPost !== undefined) {
      newTarget.subPostId = replyTargetSubPost.spid;
      newTarget.replyUid = replyTargetSubPost.author.uid;
      newTarget.replyUserName = replyTargetSubPost.author.name;
      newTarget.replyUserPortrait = replyTargetSubPost.author.portrait;
      newTarget.floor = replyTargetSubPost.floor;
    }
    // 重新赋值整个 ReplyTarget 实例触发 @State 刷新
    this.replyTarget = newTarget;
    this.showReplySheet = true;
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
        // 楼中楼回复成功后刷新当前列表
        this.loadSubPosts(true).catch((err: Error) => {
          console.error(`[SubPostsPage] refresh after reply failed: ${err.message}`);
        });
      },
      onClose: () => {
        this.showReplySheet = false;
      }
    })
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
          onRetryClick: () => this.loadSubPosts(true).catch((err: Error) => {
            console.error(`[SubPostsPage] loadSubPosts retry failed: ${err.message}`);
          })
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
                  this.toggleSubPostAgree(p).catch((err: Error) => {
                    console.error(`[SubPostsPage] toggleSubPostAgree failed: ${err.message}`);
                  });
                },
                onReplyClick: (p: SubPostInfo) => {
                  this.openReplyBox(p);
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
          }, (post: SubPostInfo, index: number) => `${post.spid}`)

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
        .padding({ left: 12, right: 12, bottom: this.safeBottom + 16 })
        .backgroundColor($r('app.color.page_background'))
        .cachedCount(5)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
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
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    // 内嵌回复框（bindSheet 半模态）
    // #93 修复回复工具栏不跟键盘上移（对齐 ThreadPage 修复）：
    // bindSheet 是半模态浮层，不受全局 setKeyboardAvoidMode 影响
    // 改用 TRANSLATE_AND_RESIZE：sheet 自身响应键盘上移
    .bindSheet($$this.showReplySheet, this.ReplySheetBuilder(), {
      height: SheetSize.MEDIUM,
      dragBar: true,
      showClose: true,
      keyboardAvoidMode: SheetKeyboardAvoidMode.TRANSLATE_AND_RESIZE,
      title: { title: getResourceString($r('app.string.reply_subpost_title')) },
      onAppear: () => {
        // #88 键盘避让：sheet 出现后主动让 TextArea 获焦，触发输入法弹出
        // setTimeout(0) 让出当前任务队列，等 sheet 布局完成后再 requestFocus，
        // 避免在 sheet 未完成挂载时 requestFocus 找不到 key 导致焦点失效
        // try-catch 包裹：防御 sheet 销毁竞态下 requestFocus 抛错导致崩溃
        this.replyFocusTimer = setTimeout(() => {
          this.replyFocusTimer = -1;
          try {
            this.getUIContext().getFocusController().requestFocus('replyTextArea');
          } catch (err) {
            console.warn(`[SubPostsPage] requestFocus failed: ${(err as Error).message}`);
          }
        }, 0);
      },
      onWillDismiss: ((dismissAction: DismissSheetAction) => {
        // 关闭前主动收起键盘 + 清理焦点
        try {
          inputMethod.getController().stopInputSession();
        } catch (err) {
          console.warn(`[SubPostsPage] stopInputSession failed: ${(err as Error).message}`);
        }
        this.getUIContext().getFocusController().clearFocus();
        dismissAction.dismiss();
      })
    })
  }
}
