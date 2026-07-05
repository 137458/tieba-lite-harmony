import { router } from '@kit.ArkUI';
import { ThreadInfo, MediaInfo } from '../model/ForumModels';
import { formatRelativeTime } from '../utils/TimeUtil';
import { getMediaImageUrl, getAvatarImageUrl } from '../utils/ImageLoadUtil';

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

  // 图片加载模式（0=智能原图 1=智能无图 2=始终原图 3=始终无图），由 EntryAbility 预读写入 AppStorage
  @StorageProp('imageLoadType') imageLoadType: number = 0;
  // 当前是否 WiFi 网络，由 EntryAbility 预读写入 AppStorage（切片 5 接入网络变化监听）
  @StorageProp('isWifi') isWifi: boolean = false;

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
      // #92 HitTestMode.Transparent：让 Image 既响应 onClick 跳转，又让触控穿透到父 List
      // 解决 fling 期间手指碰到图片时 List 收不到 Down 事件导致触控丢失
      .hitTestBehavior(HitTestMode.Transparent)
      .onClick(() => {
        router.pushUrl({
          url: 'pages/viewer/ImageViewerPage',
          params: {
            urls: this.thread.mediaList.map((m: MediaInfo) => m.url),
            index: 0
          }
        }).catch((err: Error) => {
          console.error(`[ThreadCard] navigate to ImageViewer failed: ${err.message}`);
        });
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
      .margin({ right: isLast ? 0 : 4 })
      // #92 HitTestMode.Transparent：让 Image 既响应 onClick 跳转，又让触控穿透到父 List
      .hitTestBehavior(HitTestMode.Transparent)
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
      // 用户行：36px 头像 + 14px 用户名 + 12px 时间，gap 10
      Row() {
        Image(getAvatarImageUrl(this.thread.author.avatar, this.imageLoadType, this.isWifi))
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

      // 图片：1 张占满宽度（aspectRatio 2.25），2-3 张用 Row + layoutWeight 1 + 1:1
      if (this.thread.mediaList.length > 0) {
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
            .fillColor(this.thread.isAgreed ? $r('app.color.primary') : $r('app.color.text_caption'))
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
        .alignItems(VerticalAlign.Center)
        .margin({ left: 20 })
        .hitTestBehavior(HitTestMode.Block)
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
        .alignItems(VerticalAlign.Center)
        .margin({ left: 20 })
        .hitTestBehavior(HitTestMode.Block)
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
    // #92 移除按压动画（onTouch + animateTo + isPressed）
    // 原因：快速 fling 时手指划过多个卡片，每个都触发 Down/Up → animateTo 动画堆积阻塞主线程
    // 用户反馈按压反馈"屁用没有"，直接移除换取滑动流畅性
    // 保留 renderGroup(true) 和 onClick 跳转
    .onClick(() => {
      if (this.onCardClick) {
        this.onCardClick();
      }
    })
  }
}
