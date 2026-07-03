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

        // 置顶/精华 pill 标签（11px Medium，iOS tint 背景色，对齐 design-spec.md 第6节）
        if (this.thread.isTop) {
          Text($r('app.string.top_label'))
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.tag_top'))
            .backgroundColor($r('app.color.tag_top_light'))
            .padding({ left: 8, right: 8, top: 2, bottom: 2 })
            .borderRadius(6)
        }

        if (this.thread.isGood) {
          Text($r('app.string.good_label'))
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.tag_good'))
            .backgroundColor($r('app.color.tag_good_light'))
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
        .fontWeight(600)
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
        Row() {
          Image($r('app.media.ic_like'))
            .width(18)
            .height(18)
            .fillColor(this.thread.isAgreed ? $r('app.color.primary') : $r('app.color.text_caption'))
          Text(this.thread.agreeNum.toString())
            .fontSize(13)
            .fontColor(this.thread.isAgreed ? $r('app.color.primary') : $r('app.color.text_caption'))
            .margin({ left: 4 })
        }
        .padding({ left: 0, right: 8, top: 8, bottom: 8 })
        .alignItems(VerticalAlign.Center)
        .hitTestBehavior(HitTestMode.Block)
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
          Text(this.thread.disagreeNum.toString())
            .fontSize(13)
            .fontColor(this.thread.isDisagreed ? $r('app.color.error') : $r('app.color.text_caption'))
            .margin({ left: 4 })
        }
        .padding({ left: 0, right: 8, top: 8, bottom: 8 })
        .alignItems(VerticalAlign.Center)
        .hitTestBehavior(HitTestMode.Block)
        .margin({ left: 20 })
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
          Text(this.thread.replyNum.toString())
            .fontSize(13)
            .fontColor($r('app.color.text_caption'))
            .margin({ left: 4 })
        }
        .padding({ left: 8, right: 0, top: 8, bottom: 8 })
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
      .padding({ top: 0, bottom: 6, left: 16, right: 16 })
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
