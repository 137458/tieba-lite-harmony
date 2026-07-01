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

  build() {
    Column() {
      Row() {
        Image(this.thread.author.avatar)
          .width(36)
          .height(36)
          .borderRadius(18)
          .objectFit(ImageFit.Cover)

        Column() {
          Text(this.thread.author.name)
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text(formatRelativeTime(this.thread.createTime))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
        }
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 8 })
        .layoutWeight(1)

        if (this.thread.isTop) {
          Text($r('app.string.top_label'))
            .fontSize(11)
            .fontColor($r('app.color.tag_top'))
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .border({ width: 0.5, color: $r('app.color.tag_top'), radius: 4 })
        }

        if (this.thread.isGood) {
          Text($r('app.string.good_label'))
            .fontSize(11)
            .fontColor($r('app.color.tag_good'))
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .border({ width: 0.5, color: $r('app.color.tag_good'), radius: 4 })
            .margin({ left: 4 })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .hitTestBehavior(this.onAuthorClick ? HitTestMode.Block : HitTestMode.Default)
      .onClick(() => {
        if (this.onAuthorClick) {
          this.onAuthorClick();
        }
      })

      Text(this.thread.title)
        .fontSize(16)
        .fontColor($r('app.color.text_primary'))
        .fontWeight(FontWeight.Medium)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 8 })

      if (this.thread.content.length > 0) {
        Text(this.thread.content)
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 4 })
      }

      if (this.thread.mediaList.length > 0) {
        Row() {
          ForEach(this.thread.mediaList.slice(0, 3), (media: MediaInfo, index: number) => {
            Image(media.thumbnail.length > 0 ? media.thumbnail : media.url)
              .width(100)
              .height(100)
              .objectFit(ImageFit.Cover)
              .borderRadius(4)
              .margin({ right: index < 2 ? 4 : 0 })
              .onClick(() => {
                // 打开图片查看器（issue #15）
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
          }, (media: MediaInfo) => media.url)
        }
        .width('100%')
        .margin({ top: 8 })
        // 阻断图片 Row 的点击冒泡到卡片 onClick（避免点图片同时跳转帖子详情）
        .hitTestBehavior(HitTestMode.Block)
      }

      // 底部操作栏：左[👍数字][踩数字] 右[评论数字]（issue #17）
      Row() {
        // 左侧：赞 + 踩
        Row() {
          // 赞按钮
          Row() {
            Text('👍')
              .fontSize(13)
              .opacity(this.thread.isAgreed ? 1.0 : 0.6)
            Text(this.thread.agreeNum.toString())
              .fontSize(12)
              .fontColor(this.thread.isAgreed ? $r('app.color.primary') : $r('app.color.text_secondary'))
              .margin({ left: 4 })
          }
          .alignItems(VerticalAlign.Center)
          .hitTestBehavior(HitTestMode.Block)  // 阻断冒泡到卡片 onClick，避免点赞触发跳转
          .onClick(() => {
            if (this.onAgreeClick) {
              this.onAgreeClick(this.thread);
            }
          })

          // 踩按钮
          Row() {
            Text('👎')
              .fontSize(13)
              .opacity(this.thread.isDisagreed ? 1.0 : 0.6)
            Text(this.thread.disagreeNum.toString())
              .fontSize(12)
              .fontColor(this.thread.isDisagreed ? $r('app.color.error') : $r('app.color.text_secondary'))
              .margin({ left: 4 })
          }
          .alignItems(VerticalAlign.Center)
          .hitTestBehavior(HitTestMode.Block)  // 阻断冒泡到卡片 onClick
          .margin({ left: 16 })
          .onClick(() => {
            if (this.onDisagreeClick) {
              this.onDisagreeClick(this.thread);
            }
          })
        }
        .alignItems(VerticalAlign.Center)

        Blank()

        // 右侧：评论按钮
        Row() {
          Text('💬')
            .fontSize(13)
          Text(this.thread.replyNum.toString())
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .margin({ left: 4 })
        }
        .alignItems(VerticalAlign.Center)
        .hitTestBehavior(HitTestMode.Block)  // 阻断冒泡到卡片 onClick
        .onClick(() => {
          if (this.onCommentClick) {
            this.onCommentClick(this.thread);
          }
        })
      }
      .width('100%')
      .margin({ top: 8 })
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(8)
    .onClick(() => {
      if (this.onCardClick) {
        this.onCardClick();
      }
    })
  }

}
