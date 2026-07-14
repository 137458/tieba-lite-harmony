import { ThreadInfo, MediaInfo } from '../model/ForumModels';
import { formatRelativeTime } from '../utils/TimeUtil';
import { getMediaImageUrl, getAvatarImageUrl } from '../utils/ImageLoadUtil';
import { connectTheme, ThemeState } from '../theme/ThemeManager';
import { curves } from '@kit.ArkUI';
import { connectImageViewer, ImageViewerState } from '../model/AppStorageV2Models';

// 按压/松开动画时长（ms），Down/Up 两侧保持一致
const CARD_PRESS_ANIM_DURATION_MS: number = 100;

@Preview
@ReusableV2
@ComponentV2
export struct ThreadCard {
  @Require @Param thread: ThreadInfo;
  @Event onCardClick?: () => void;
  /** 点击作者区域（头像/名字）回调。设置后用 HitTestMode.Block 阻断冒泡到卡片 onClick */
  @Event onAuthorClick?: () => void;
  /** 点赞/取消赞回调（issue #17），由父组件调 TiebaAPI.agree/unagree 并刷新 threadList */
  @Event onAgreeClick?: (thread: ThreadInfo) => void;
  /** 点踩/取消点踩回调（issue #17） */
  @Event onDisagreeClick?: (thread: ThreadInfo) => void;
  /** 评论按钮回调（issue #17），父组件弹输入框或提示开发中 */
  @Event onCommentClick?: (thread: ThreadInfo) => void;

  /** 卡片按下态（对齐 iOS 原型 :active 缩放 0.98 + 透明度 0.85） */
  @Local isPressed: boolean = false;
  @Local themeState: ThemeState = connectTheme();
  // #132 图片查看器全局模态状态（onClick 时写入 urls/index/shareId/thumbnailUrl 触发模态）
  @Local imageViewerState: ImageViewerState = connectImageViewer();
  // 图片加载模式（0=智能原图 1=智能无图 2=始终原图 3=始终无图），由父组件从 AppStorageV2 传入
  @Param imageLoadType: number = 0;
  // 当前是否 WiFi 网络，由父组件从 AppStorageV2 传入
  @Param isWifi: boolean = false;

  // A11 GlobalReuse：组件被复用时重置按压态，避免上次卡片在按压状态被回收后残留
  aboutToReuse(params: Object): void {
    this.isPressed = false;
  }

  // 单张图片：占满宽度，aspectRatio 2.25（宽幅横图）
  @Builder
  SingleMedia() {
    Image(getMediaImageUrl(
      this.thread.mediaList[0].thumbnail,
      this.thread.mediaList[0].url,
      this.imageLoadType,
      this.isWifi
    ))
      .width('100%')
      .aspectRatio(2.25)
      .objectFit(ImageFit.Cover)
      .borderRadius(8)
      .backgroundColor($r('app.color.input_background'))
      .alt($r('app.media.startIcon'))
      // A5 图片优化：网络大图异步加载避免阻塞 UI + 高质量插值缓解锯齿 + 自动降采样减少内存
      .syncLoad(false)
      .interpolation(ImageInterpolation.High)
      .autoResize(true)
      .onError(() => {
        // 媒体图加载失败静默处理：alt 占位图会自动显示
      })
      // #92 HitTestMode.Transparent：让 Image 既响应 onClick 跳转，又让触控穿透到父 List
      // 解决 fling 期间手指碰到图片时 List 收不到 Down 事件导致触控丢失
      .hitTestBehavior(HitTestMode.Transparent)
      // #132 共享元素转场：源端 Image 绑定 shareId，与模态目标端 Image 配对
      .geometryTransition(`card_${this.thread.tid}_0`, { follow: true })
      .onClick(() => {
        this.openImageViewer(0);
      })
  }

  // 视频帖封面：显示视频缩略图 + 中央播放图标，点击跳转帖子详情页（ThreadPage）而非图片查看器
  // 视频帖通过 thread.videoInfo.videoUrl 非空识别（ThreadInfo.proto field 79 = video_info）
  @Builder
  VideoMedia() {
    Stack() {
      Image(getMediaImageUrl(
        this.thread.videoInfo.thumbnailUrl,
        this.thread.videoInfo.thumbnailUrl,
        this.imageLoadType,
        this.isWifi
      ))
        .width('100%')
        .aspectRatio(this.computeVideoAspectRatio())
        .objectFit(ImageFit.Cover)
        .borderRadius(8)
        .backgroundColor($r('app.color.input_background'))
        .alt($r('app.media.startIcon'))
        .syncLoad(false)
        .interpolation(ImageInterpolation.High)
        .autoResize(true)
        .onError(() => { /* 视频封面加载失败静默处理 */ })

      // 中央播放图标（半透明圆形背景 + play_fill）
      Stack() {
        Circle({ width: 56, height: 56 })
          .fill('rgba(0, 0, 0, 0.5)')
        SymbolGlyph($r('sys.symbol.play_fill'))
          .fontSize(28)
          .fontColor([Color.White])
      }
      .width(56)
      .height(56)
    }
    .width('100%')
    .hitTestBehavior(HitTestMode.Transparent)
    .onClick(() => {
      // 视频帖点击跳转帖子详情页，不跳图片查看器
      if (this.onCardClick) {
        this.onCardClick();
      }
    })
  }

  // 多图网格项：layoutWeight 1 + 1:1 宽高比，最后一项无右侧间距
  @Builder
  GridMedia(index: number, isLast: boolean) {
    Image(getMediaImageUrl(
      this.thread.mediaList[index].thumbnail,
      this.thread.mediaList[index].url,
      this.imageLoadType,
      this.isWifi
    ))
      .layoutWeight(1)
      .aspectRatio(1)
      .objectFit(ImageFit.Cover)
      .borderRadius(8)
      .backgroundColor($r('app.color.input_background'))
      .alt($r('app.media.startIcon'))
      // A5 图片优化：网格缩略图异步加载避免阻塞滑动 + 自动降采样减少内存 + 错误兜底
      .syncLoad(false)
      .interpolation(ImageInterpolation.Medium)
      .autoResize(true)
      .onError(() => {
        // 缩略图加载失败静默处理：alt 占位图会自动显示
      })
      .margin({ right: isLast ? 0 : 4 })
      // #92 HitTestMode.Transparent：让 Image 既响应 onClick 跳转，又让触控穿透到父 List
      .hitTestBehavior(HitTestMode.Transparent)
      // #132 共享元素转场：源端 Image 绑定 shareId，与模态目标端 Image 配对
      .geometryTransition(`card_${this.thread.tid}_${index}`, { follow: true })
      .onClick(() => {
        this.openImageViewer(index);
      })
  }

  /** 计算视频封面宽高比（videoWidth/videoHeight 有效时用实际比例，否则默认 16:9） */
  private computeVideoAspectRatio(): number {
    if (this.thread.videoInfo.videoWidth > 0 && this.thread.videoInfo.videoHeight > 0) {
      return this.thread.videoInfo.videoWidth / this.thread.videoInfo.videoHeight;
    }
    return 16 / 9;
  }

  /**
   * #132 打开图片查看器模态（共享元素转场）
   * 写入 ImageViewerState 触发 Index.ets 的 bindContentCover 显示模态
   * springMotion 弹性回弹曲线驱动转场动画
   */
  private openImageViewer(index: number): void {
    const urls: string[] = this.thread.mediaList.map((m: MediaInfo) => m.url);
    // thumbnailUrl 用源端 Image 实际显示的 URL，确保转场期间两端图片一致避免闪烁
    const thumbnailUrl: string = getMediaImageUrl(
      this.thread.mediaList[index].thumbnail,
      this.thread.mediaList[index].url,
      this.imageLoadType,
      this.isWifi
    );
    const shareId: string = `card_${this.thread.tid}_${index}`;
    this.imageViewerState.urls = urls;
    this.imageViewerState.index = index;
    this.imageViewerState.shareId = shareId;
    this.imageViewerState.thumbnailUrl = thumbnailUrl;
    this.getUIContext()?.animateTo({
      duration: 350,
      curve: curves.springMotion()
    }, () => {
      this.imageViewerState.isVisible = true;
    });
  }

  build() {
    Column() {
      // 用户行：36px 头像 + 14px 用户名 + 12px 时间，gap 10
      Row() {
        Image(getAvatarImageUrl(this.thread.author.avatar, this.imageLoadType, this.isWifi))
          .width(36)
          .height(36)
          .borderRadius(18)
          .objectFit(ImageFit.Cover)
          .backgroundColor($r('app.color.input_background'))
          .alt($r('app.media.startIcon'))
          // #166 滑动卡顿优化：头像异步解码避免阻塞主线程（参考 PostItem 优化经验）
          // loadMore 加载 30 个新 ThreadCard 时，syncLoad(true) 同步解码会阻塞主线程约 1 秒
          .syncLoad(false)
          .interpolation(ImageInterpolation.Low)
          .onError(() => {
            // 头像加载失败静默处理：alt 占位图会自动显示
          })

        Column() {
          Text(this.thread.author.name)
            .fontSize(14)
            .fontWeight(600)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text(formatRelativeTime(this.thread.createTime))
            .fontSize(12)
            .fontColor($r('app.color.text_caption'))
        }
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 10 })
        .layoutWeight(1)
      }
      .width('100%')
      .margin({ bottom: 8 })
      .alignItems(VerticalAlign.Center)
      // #92 HitTestMode.Transparent：让触控穿透到父 List，避免 fling 期间碰到用户行导致触控丢失
      // onAuthorClick 仍能触发（Transparent 自身响应事件，但不阻止兄弟组件）
      .hitTestBehavior(HitTestMode.Transparent)
      .onClick(() => {
        if (this.onAuthorClick) {
          this.onAuthorClick();
        }
      })

      // 标签独立一行（置顶/精华，位于 user-row 之后、title 之前，gap 6）
      if (this.thread.isTop || this.thread.isGood) {
        Row() {
          if (this.thread.isTop) {
            Text($r('app.string.top_label'))
              .fontSize(11)
              .fontWeight(600)
              .fontColor($r('app.color.tag_top'))
              .backgroundColor($r('app.color.tag_top_light'))
              .padding({ left: 8, right: 8, top: 2, bottom: 2 })
              .borderRadius(6)
          }
          if (this.thread.isGood) {
            Text($r('app.string.good_label'))
              .fontSize(11)
              .fontWeight(600)
              .fontColor($r('app.color.tag_good'))
              .backgroundColor($r('app.color.tag_good_light'))
              .padding({ left: 8, right: 8, top: 2, bottom: 2 })
              .borderRadius(6)
              .margin({ left: this.thread.isTop ? 6 : 0 })
          }
        }
        .margin({ bottom: 6 })
      }

      // 标题（16px SemiBold，lineHeight 1.35）
      Text(this.thread.title)
        .fontSize(16)
        .fontWeight(600)
        .fontColor($r('app.color.text_primary'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .lineHeight(16 * 1.35)
        .margin({ bottom: 6 })

      // 摘要（14px，3 行截断，lineHeight 1.5）
      if (this.thread.content.length > 0) {
        Text(this.thread.content)
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .lineHeight(14 * 1.5)
          .margin({ bottom: 10 })
      }

      // 媒体区域：视频帖优先渲染 VideoMedia（封面+播放图标，点击跳帖子详情）
      // 非视频帖走 mediaList 图片渲染（1 张占满宽度 aspectRatio 2.25，2-3 张用 Row + layoutWeight 1 + 1:1）
      if (this.thread.videoInfo.videoUrl.length > 0) {
        this.VideoMedia()
      } else if (this.thread.mediaList.length > 0) {
        if (this.thread.mediaList.length === 1) {
          this.SingleMedia()
        } else {
          Row() {
            this.GridMedia(0, false)
            if (this.thread.mediaList.length > 1) {
              this.GridMedia(1, this.thread.mediaList.length === 2)
            }
            if (this.thread.mediaList.length > 2) {
              this.GridMedia(2, true)
            }
          }
          .width('100%')
          // #92 HitTestMode.Transparent：让触控穿透到父 List
          .hitTestBehavior(HitTestMode.Transparent)
        }
      }

      // 操作栏：顶部 0.5px 分割线，gap 20，左[赞][踩] 右[评论]
      Row() {
        Row() {
          Image($r('app.media.ic_like'))
            .width(18)
            .height(18)
            .fillColor(this.thread.isAgreed ? this.themeState.primary : $r('app.color.text_caption'))
            // A5 图片优化：本地 SVG 小图同步加载避免闪烁
            .syncLoad(true)
            .interpolation(ImageInterpolation.Low)
            // #92 HitTestMode.Transparent：让触控穿透到父 List
            .hitTestBehavior(HitTestMode.Transparent)
          Text(this.thread.agreeNum.toString())
            .fontSize(13)
            .fontColor(this.thread.isAgreed ? this.themeState.primary : $r('app.color.text_caption'))
            .margin({ left: 4 })
        }
        .alignItems(VerticalAlign.Center)
        // #92 HitTestMode.Transparent：点赞按钮仍响应 onClick，同时让触控穿透到父 List
        .hitTestBehavior(HitTestMode.Transparent)
        .onClick(() => {
          if (this.onAgreeClick) {
            this.onAgreeClick(this.thread);
          }
        })

        Row() {
          Image($r('app.media.ic_dislike'))
            .width(18)
            .height(18)
            .fillColor(this.thread.isDisagreed ? $r('app.color.error') : $r('app.color.text_caption'))
            // A5 图片优化：本地 SVG 小图同步加载避免闪烁
            .syncLoad(true)
            .interpolation(ImageInterpolation.Low)
            // #92 HitTestMode.Transparent：让触控穿透到父 List
            .hitTestBehavior(HitTestMode.Transparent)
          Text(this.thread.disagreeNum.toString())
            .fontSize(13)
            .fontColor(this.thread.isDisagreed ? $r('app.color.error') : $r('app.color.text_caption'))
            .margin({ left: 4 })
        }
        .alignItems(VerticalAlign.Center)
        .margin({ left: 20 })
        // #92 HitTestMode.Transparent：踩按钮仍响应 onClick，同时让触控穿透到父 List
        .hitTestBehavior(HitTestMode.Transparent)
        .onClick(() => {
          if (this.onDisagreeClick) {
            this.onDisagreeClick(this.thread);
          }
        })

        Blank()

        Row() {
          Image($r('app.media.ic_message'))
            .width(18)
            .height(18)
            .fillColor($r('app.color.text_caption'))
            // A5 图片优化：本地 SVG 小图同步加载避免闪烁
            .syncLoad(true)
            .interpolation(ImageInterpolation.Low)
            // #92 HitTestMode.Transparent：让触控穿透到父 List
            .hitTestBehavior(HitTestMode.Transparent)
          Text(this.thread.replyNum.toString())
            .fontSize(13)
            .fontColor($r('app.color.text_caption'))
            .margin({ left: 4 })
        }
        .alignItems(VerticalAlign.Center)
        .margin({ left: 20 })
        // #92 HitTestMode.Transparent：评论按钮仍响应 onClick，同时让触控穿透到父 List
        .hitTestBehavior(HitTestMode.Transparent)
        .onClick(() => {
          if (this.onCommentClick) {
            this.onCommentClick(this.thread);
          }
        })
      }
      .width('100%')
      .margin({ top: 10 })
      .padding({ top: 10, bottom: 0, left: 0, right: 0 })
      .border({ width: { top: 0.5 }, color: $r('app.color.divider') })
    }
    .width('100%')
    .padding({ top: 14, bottom: 14, left: 16, right: 16 })
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(10)
    .renderGroup(true)
    .alignItems(HorizontalAlign.Start)
    // #93 HitTestMode.Transparent：让卡片 onClick 仍能触发，同时让触控穿透到父 List
    // 修复热榜/关注/推荐 Tab 滑动被拦截问题（对齐 ThreadPage PostItem 实现）
    // 之前默认 Auto + onClick 会阻止事件向父 List 传播，List 无法滚动
    .hitTestBehavior(HitTestMode.Transparent)
    .scale({ x: this.isPressed ? 0.98 : 1, y: this.isPressed ? 0.98 : 1 })
    .opacity(this.isPressed ? 0.85 : 1)
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        animateTo({ duration: CARD_PRESS_ANIM_DURATION_MS, curve: Curve.EaseInOut }, () => {
          this.isPressed = true;
        });
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        animateTo({ duration: CARD_PRESS_ANIM_DURATION_MS, curve: Curve.EaseInOut }, () => {
          this.isPressed = false;
        });
      }
    })
    .onClick(() => {
      if (this.onCardClick) {
        this.onCardClick();
      }
    })
  }
}
