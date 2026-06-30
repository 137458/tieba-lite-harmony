import { ThreadInfo, MediaInfo } from '../model/ForumModels';

@Preview
@Component
export struct ThreadCard {
  @Prop thread: ThreadInfo;
  onCardClick?: () => void;
  /** 点击作者区域（头像/名字）回调。设置后用 HitTestMode.Block 阻断冒泡到卡片 onClick */
  onAuthorClick?: () => void;

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

          Text(this.formatTime(this.thread.createTime))
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
          }, (media: MediaInfo) => media.url)
        }
        .width('100%')
        .margin({ top: 8 })
      }

      Row() {
        Row() {
          Image('')
            .width(14)
            .height(14)
            .fillColor($r('app.color.text_secondary'))

          Text(this.thread.replyNum.toString())
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .margin({ left: 4 })
        }

        Row() {
          Image('')
            .width(14)
            .height(14)
            .fillColor($r('app.color.text_secondary'))

          Text(this.thread.viewNum.toString())
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .margin({ left: 4 })
        }
        .margin({ left: 16 })
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

  private formatTime(timestamp: number): string {
    if (timestamp <= 0) {
      return '';
    }

    const now: number = Date.now() / 1000;
    const diff: number = now - timestamp;

    if (diff < 60) {
      return $r('app.string.just_now').toString();
    } else if (diff < 3600) {
      return Math.floor(diff / 60) + $r('app.string.minutes_ago').toString();
    } else if (diff < 86400) {
      return Math.floor(diff / 3600) + $r('app.string.hours_ago').toString();
    } else if (diff < 604800) {
      return Math.floor(diff / 86400) + $r('app.string.days_ago').toString();
    } else {
      const date = new Date(timestamp * 1000);
      return `${date.getFullYear()}-${(date.getMonth() + 1).toString().padStart(2, '0')}-${date.getDate().toString().padStart(2, '0')}`;
    }
  }
}
