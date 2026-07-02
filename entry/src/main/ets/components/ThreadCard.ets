import { router } from '@kit.ArkUI';
import { ThreadInfo, MediaInfo } from '../model/ForumModels';
import { formatRelativeTime } from '../utils/TimeUtil';

@Preview
@Component
export struct ThreadCard {
  @ObjectLink thread: ThreadInfo;
  onCardClick?: () => void;
  /** 点击作者区域（头像/名字）回调。设置后用 HitTestMode.Block 阻断冒泡到卡片 onClick */
  onAuthorClick?: () => void;
  /** 点赞/取消赞回调（issue #17），由父组件调 TiebaAPI.agree/unagree 并刷新 threadList */
  onAgreeClick?: (thread: ThreadInfo) => void;
  /** 点踩/取消点踩回调（issue #17） */
  onDisagreeClick?: (thread: ThreadInfo) => void;
  /** 评论按钮回调（issue #17），父组件弹输入框或提示开发中 */
  onCommentClick?: (thread: ThreadInfo) => void;

  /** P1 优化：展开写的图片项，避免 build 中 slice+ForEach 创建新数组 */
  @Builder
  MediaImage(index: number) {
    Image(this.thread.mediaList[index].thumbnail.length > 0 ?
      this.thread.mediaList[index].thumbnail : this.thread.mediaList[index].url)
      .width(100)
      .height(100)
      .objectFit(ImageFit.Cover)
      .borderRadius(8)
      .backgroundColor($r('app.color.input_background'))
      .alt($r('app.media.startIcon'))
      .margin({ right: index < 2 ? 4 : 0 })
      .onClick(() => {
        router.pushUrl({
          url: 'pages/viewer/ImageViewerPage',
          params: {
            urls: this.thread.mediaList.map((m: MediaInfo) => m.url),
            index: index
          }
        }).catch((err: Error) => {
          console.error(`[ThreadCard] navigate to ImageViewer failed: ${err.message}`);
        });
      })
  }

  build() {
    Column() {
      // 用户行：头像 + 用户名 + 时间 + 标签
      Row() {
        Image(this.thread.author.avatar)
          .width(36)
          .height(36)
          .borderRadius(18)
          .objectFit(ImageFit.Cover)
          .backgroundColor($r('app.color.input_background'))
          .alt($r('app.media.startIcon'))

        Column() {
          Text(this.thread.author.name)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
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

        // 置顶/精华 pill 标签（11px Medium，iOS tint 背景色，对齐 design-spec.md 第6节）
        if (this.thread.isTop) {
          Text($r('app.string.top_label'))
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.tag_top'))
            .backgroundColor($r('app.color.primary_light'))
            .padding({ left: 8, right: 8, top: 2, bottom: 2 })
            .borderRadius(6)
        }

        if (this.thread.isGood) {
          Text($r('app.string.good_label'))
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.tag_good'))
            .backgroundColor($r('app.color.primary_light'))
            .padding({ left: 8, right: 8, top: 2, bottom: 2 })
            .borderRadius(6)
            .margin({ left: 6 })
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 14 })
      .alignItems(VerticalAlign.Center)
      .hitTestBehavior(this.onAuthorClick ? HitTestMode.Block : HitTestMode.Default)
      .onClick(() => {
        if (this.onAuthorClick) {
          this.onAuthorClick();
        }
      })

      // 标题（16px SemiBold）
      Text(this.thread.title)
        .fontSize(16)
        .fontColor($r('app.color.text_primary'))
        .fontWeight(FontWeight.Medium)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 8, left: 16, right: 16 })

      // 摘要（14px Regular，3 行截断）
      if (this.thread.content.length > 0) {
        Text(this.thread.content)
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 6, left: 16, right: 16 })
      }

      // 图片网格（圆角 8px，最多 3 张，P1 优化：展开写避免 build 中 slice+ForEach 创建新数组）
      if (this.thread.mediaList.length > 0) {
        Row() {
          this.MediaImage(0)
          if (this.thread.mediaList.length > 1) {
            this.MediaImage(1)
          }
          if (this.thread.mediaList.length > 2) {
            this.MediaImage(2)
          }
        }
        .width('100%')
        .margin({ top: 10, left: 16, right: 16 })
        .hitTestBehavior(HitTestMode.Block)
      }

      // 操作栏：点赞/踩/评论（对齐 design-spec.md 第6节，独立 SVG path，禁止 rotate 翻转）
      // 顶部 0.5px 分割线（贯穿卡片宽度）+ 左[赞数字][踩数字] 右[评论数字]
      Row() {
        // 赞按钮（独立 SVG path）
        Row() {
          Path()
            // 点赞 path（来自 design-prototype.html，hand.thumbsup.fill）
            .commands('M7 11V17H4.5C4.22 17 4 16.78 4 16.5V11.5C4 11.22 4.22 11 4.5 11H7ZM7 11L8.27 6.21C8.43 5.56 9.01 5.1 9.68 5.1C10.4 5.1 11 5.7 11 6.42V9H15.73C16.27 9 16.73 9.4 16.81 9.93L17.5 14.43C17.6 15.08 17.09 15.67 16.43 15.67H9L7 11Z')
            .fill(this.thread.isAgreed ? $r('app.color.primary') : $r('app.color.text_caption'))
            .width(18)
            .height(18)
            .viewPort({ x: 0, y: 0, width: 24, height: 24 })
          Text(this.thread.agreeNum.toString())
            .fontSize(13)
            .fontColor(this.thread.isAgreed ? $r('app.color.primary') : $r('app.color.text_caption'))
            .margin({ left: 4 })
        }
        .alignItems(VerticalAlign.Center)
        .hitTestBehavior(HitTestMode.Block)
        .onClick(() => {
          if (this.onAgreeClick) {
            this.onAgreeClick(this.thread);
          }
        })

        // 踩按钮（独立 SVG path，非 rotate 翻转，对齐设计文档第6节铁律）
        Row() {
          Path()
            // 点踩 path（来自 design-prototype.html，hand.thumbsdown.fill）
            .commands('M7 9V3H4.5C4.22 3 4 3.22 4 3.5V8.5C4 8.78 4.22 9 4.5 9H7ZM7 9L8.27 13.79C8.43 14.44 9.01 14.9 9.68 14.9C10.4 14.9 11 14.3 11 13.58V11H15.73C16.27 11 16.73 10.6 16.81 10.07L17.5 5.57C17.6 4.92 17.09 4.33 16.43 4.33H9L7 9Z')
            .fill(this.thread.isDisagreed ? $r('app.color.error') : $r('app.color.text_caption'))
            .width(18)
            .height(18)
            .viewPort({ x: 0, y: 0, width: 24, height: 24 })
          Text(this.thread.disagreeNum.toString())
            .fontSize(13)
            .fontColor(this.thread.isDisagreed ? $r('app.color.error') : $r('app.color.text_caption'))
            .margin({ left: 4 })
        }
        .alignItems(VerticalAlign.Center)
        .hitTestBehavior(HitTestMode.Block)
        .margin({ left: 20 })
        .onClick(() => {
          if (this.onDisagreeClick) {
            this.onDisagreeClick(this.thread);
          }
        })

        Blank()

        // 评论按钮（bubble.left）
        Row() {
          Path()
            .commands('M20 2H4c-1.1 0-2 .9-2 2v18l4-4h14c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2zm0 14H6l-2 2V4h16v12z')
            .fill($r('app.color.text_caption'))
            .width(18)
            .height(18)
            .viewPort({ x: 0, y: 0, width: 24, height: 24 })
          Text(this.thread.replyNum.toString())
            .fontSize(13)
            .fontColor($r('app.color.text_caption'))
            .margin({ left: 4 })
        }
        .alignItems(VerticalAlign.Center)
        .hitTestBehavior(HitTestMode.Block)
        .onClick(() => {
          if (this.onCommentClick) {
            this.onCommentClick(this.thread);
          }
        })
      }
      .width('100%')
      .margin({ top: 10 })
      .padding({ top: 10, bottom: 14, left: 16, right: 16 })
      .border({ width: { top: 0.5 }, color: $r('app.color.divider') })
    }
    .width('100%')
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(10)
    .renderGroup(true)
    .alignItems(HorizontalAlign.Start)
    .onClick(() => {
      if (this.onCardClick) {
        this.onCardClick();
      }
    })
  }

}
