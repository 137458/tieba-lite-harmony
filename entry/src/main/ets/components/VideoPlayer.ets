/**
 * #151 [Video-1] 视频贴内联播放组件（端到端最小播放）
 *
 * 功能：
 * - 未播放：显示封面图 + 中央播放按钮（对齐 Android VideoPlayer.kt 封面+PlayArrow 设计）
 * - 点击播放按钮：切换到 Video 组件，autoPlay=true 开始播放
 * - aboutToDisappear：停止播放释放资源，避免后台继续播放音频
 *
 * 依赖 ArkUI 内置 Video 组件 + VideoController（API 7+）
 * slice 2 将替换为自定义控制层，slice 3 将增加全屏
 */
@ComponentV2
export struct VideoPlayer {
  /** 视频 URL（PbContent type5 field 3=link） */
  @Param videoUrl: string = '';
  /** 封面 URL（PbContent type5 field 4=src） */
  @Param coverUrl: string = '';
  /** 视频宽度（从 bsize 解析，用于计算宽高比） */
  @Param videoWidth: number = 0;
  /** 视频高度（从 bsize 解析，用于计算宽高比） */
  @Param videoHeight: number = 0;

  /** 是否已开始播放（控制封面/Video 切换） */
  @Local isPlaying: boolean = false;
  /** 是否发生错误（slice 4 将扩展为错误占位+重试） */
  @Local hasError: boolean = false;

  /** Video 控制器（start/pause/stop/reset/setCurrentTime） */
  private controller: VideoController = new VideoController();
  /** #93 isDestroyed 生命周期守护：aboutToDisappear 后禁止操作状态 */
  private isDestroyed: boolean = false;

  build() {
    Stack() {
      if (this.isPlaying) {
        // 播放中：显示 Video 组件
        Video({
          src: this.videoUrl,
          previewUri: this.coverUrl,
          controller: this.controller
        })
          .controls(true)
          .autoPlay(true)
          .objectFit(ImageFit.Contain)
          .width('100%')
          .aspectRatio(this.computeAspectRatio())
          .onError(() => {
            if (this.isDestroyed) return;
            this.hasError = true;
          })
      } else {
        // 未播放：显示封面图 + 中央播放按钮
        Image(this.coverUrl)
          .objectFit(ImageFit.Cover)
          .width('100%')
          .aspectRatio(this.computeAspectRatio())
          .backgroundColor($r('app.color.input_background'))
          .alt($r('app.media.startIcon'))
          .syncLoad(false)
          .interpolation(ImageInterpolation.High)
          .autoResize(true)
          .onError(() => { /* 封面加载失败静默处理，仍显示播放按钮 */ })

        // 中央播放按钮（对齐 Android VideoPlayer.kt: 48dp PlayArrow）
        // 用半透明圆形背景 + SymbolGlyph 播放图标，避免新增媒体资源
        Stack() {
          Circle({ width: 56, height: 56 })
            .fill('rgba(0, 0, 0, 0.5)')
          SymbolGlyph($r('sys.symbol.play_fill'))
            .fontSize(28)
            .fontColor([Color.White])
            .onClick(() => {
              this.startPlayback();
            })
        }
        .width(56)
        .height(56)
      }
    }
    .width('100%')
    .alignContent(Alignment.Center)
  }

  /**
   * 计算视频宽高比
   * 有有效宽高时用实际值，否则默认 16:9（对齐 Android FeedCard: max(封面宽高比, 16/9)）
   */
  private computeAspectRatio(): number {
    if (this.videoWidth > 0 && this.videoHeight > 0) {
      return this.videoWidth / this.videoHeight;
    }
    return 16 / 9;
  }

  /** 点击播放按钮：切换到播放状态 */
  private startPlayback(): void {
    if (this.isDestroyed) return;
    this.isPlaying = true;
  }

  aboutToDisappear(): void {
    this.isDestroyed = true;
    // 停止播放释放资源，避免视频贴滚出屏后后台继续播放音频
    try {
      this.controller.stop();
    } catch (e) {
      // 组件已销毁时 stop 可能抛异常，忽略
    }
  }
}
