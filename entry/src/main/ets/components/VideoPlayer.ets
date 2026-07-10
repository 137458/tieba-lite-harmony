/**
 * #151 [Video-1] 端到端最小播放 + #152 [Video-2] 自定义控制层
 *
 * 功能：
 * - 未播放：显示封面图 + 中央播放按钮（对齐 Android VideoPlayer.kt 封面+PlayArrow 设计）
 * - 点击播放按钮：切换到 Video 组件，autoPlay=true 开始播放
 * - 播放中：自定义控制层（底部进度条 + 时长 + 播放/暂停按钮），3秒自动隐藏
 * - 点击视频区域：切换控制条显隐
 * - 缓冲中（onPrepared 前）：显示 LoadingProgress 指示器
 * - aboutToDisappear：停止播放 + 清理定时器，避免后台继续播放音频和内存泄漏
 *
 * 依赖 ArkUI 内置 Video 组件 + VideoController（API 7+）
 * slice 3 将增加全屏播放，slice 4 将增加错误重试
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
  /** 是否暂停（控制播放/暂停按钮图标，onStart/onPause/onFinish 同步） */
  @Local isPaused: boolean = false;
  /** 是否发生错误（slice 4 将扩展为错误占位+重试） */
  @Local hasError: boolean = false;
  /** 是否缓冲中（onPrepared 前为 true，onPrepared 后为 false） */
  @Local isBuffering: boolean = true;
  /** 当前播放时间（秒，onUpdate 回调更新） */
  @Local currentTime: number = 0;
  /** 视频总时长（秒，onPrepared 回调更新） */
  @Local duration: number = 0;
  /** 控制条是否显示（点击视频区域切换 + 3秒自动隐藏） */
  @Local showControls: boolean = true;

  /** Video 控制器（start/pause/stop/setCurrentTime） */
  private controller: VideoController = new VideoController();
  /** #93 isDestroyed 生命周期守护：aboutToDisappear 后禁止操作状态 */
  private isDestroyed: boolean = false;
  /** #152 控制条3秒自动隐藏定时器 ID（-1 表示无定时器） */
  private hideControlsTimerId: number = -1;

  build() {
    Stack() {
      if (this.isPlaying) {
        // 播放中：Video 组件 + 缓冲指示 + 控制层
        Video({
          src: this.videoUrl,
          previewUri: this.coverUrl,
          controller: this.controller
        })
          // #152 隐藏内置控制栏，用自定义控制层
          .controls(false)
          .autoPlay(true)
          .objectFit(ImageFit.Contain)
          .width('100%')
          .aspectRatio(this.computeAspectRatio())
          // 点击视频区域：切换控制条显隐（非切换播放/暂停，对齐 issue #152 验收标准）
          .onClick(() => {
            this.toggleControls();
          })
          .onPrepared((e: PreparedInfo) => {
            if (this.isDestroyed) return;
            this.duration = e.duration;
            this.isBuffering = false;
            this.showControls = true;
            this.scheduleAutoHide();
          })
          .onUpdate((e: PlaybackInfo) => {
            if (this.isDestroyed) return;
            this.currentTime = e.time;
          })
          .onStart(() => {
            if (this.isDestroyed) return;
            this.isPaused = false;
          })
          .onPause(() => {
            if (this.isDestroyed) return;
            this.isPaused = true;
          })
          .onFinish(() => {
            if (this.isDestroyed) return;
            this.isPaused = true;
          })
          .onError(() => {
            if (this.isDestroyed) return;
            this.hasError = true;
          })

        // #152 缓冲指示器（居中，onPrepared 前显示）
        if (this.isBuffering) {
          LoadingProgress()
            .width(48)
            .height(48)
            .color(Color.White)
            // 不拦截点击，让点击穿透到 Video
            .hitTestBehavior(HitTestMode.None)
        }

        // #152 控制层（底部进度条 + 时长 + 播放/暂停按钮）
        // 用 opacity 动画控制显隐，不改 layout 属性（对齐验收标准）
        Column() {
          Row() {
            // 播放/暂停按钮：根据 isPaused 状态切换图标
            if (this.isPaused) {
              SymbolGlyph($r('sys.symbol.play_fill'))
                .fontSize(20)
                .fontColor([Color.White])
                .onClick(() => {
                  if (this.isDestroyed) return;
                  this.controller.start();
                  this.scheduleAutoHide();
                })
            } else {
              SymbolGlyph($r('sys.symbol.pause_fill'))
                .fontSize(20)
                .fontColor([Color.White])
                .onClick(() => {
                  if (this.isDestroyed) return;
                  this.controller.pause();
                  this.scheduleAutoHide();
                })
            }

            // 当前时长（mm:ss 格式）
            Text(this.formatTime(this.currentTime))
              .fontColor(Color.White)
              .fontSize(12)
              .margin({ left: 8 })

            // 进度条（拖拽 seek + 拖拽期间不隐藏）
            Slider({
              value: this.currentTime,
              min: 0,
              max: this.duration > 0 ? this.duration : 1
            })
              .layoutWeight(1)
              .selectedColor(Color.White)
              .trackColor('rgba(255, 255, 255, 0.3)')
              .blockColor(Color.White)
              .onChange((value: number, mode: SliderChangeMode) => {
                this.onSliderChange(value, mode);
              })

            // 总时长（mm:ss 格式）
            Text(this.formatTime(this.duration))
              .fontColor(Color.White)
              .fontSize(12)
              .margin({ left: 8 })
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 8, bottom: 8 })
          .backgroundColor('rgba(0, 0, 0, 0.5)')
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.End)
        // Column 空白区域不拦截点击（穿透到 Video），控制条 Row 内按钮正常响应
        .hitTestBehavior(HitTestMode.None)
        // 透明度动画控制显隐（不改 layout 属性，对齐验收标准）
        .opacity(this.showControls ? 1 : 0)
        .animation({ duration: 300, curve: Curve.EaseInOut })
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

  /** #152 点击视频区域：切换控制条显隐 */
  private toggleControls(): void {
    if (this.isDestroyed) return;
    this.showControls = !this.showControls;
    if (this.showControls) {
      this.scheduleAutoHide();
    } else {
      this.clearAutoHide();
    }
  }

  /** #152 安排3秒后自动隐藏控制条 */
  private scheduleAutoHide(): void {
    if (this.isDestroyed) return;
    this.clearAutoHide();
    this.hideControlsTimerId = setTimeout(() => {
      if (this.isDestroyed) return;
      this.showControls = false;
      this.hideControlsTimerId = -1;
    }, 3000);
  }

  /** #152 清除自动隐藏定时器 */
  private clearAutoHide(): void {
    if (this.hideControlsTimerId !== -1) {
      clearTimeout(this.hideControlsTimerId);
      this.hideControlsTimerId = -1;
    }
  }

  /** #152 进度条拖拽回调：Moving 更新显示+保持显示，End/Click seek+重新计时 */
  private onSliderChange(value: number, mode: SliderChangeMode): void {
    if (this.isDestroyed) return;
    if (mode === SliderChangeMode.Moving) {
      // 拖拽中：更新显示时间，清除自动隐藏（控制条保持显示）
      this.currentTime = value;
      this.clearAutoHide();
    } else if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
      // 松手/点击：seek 到目标位置 + 重新安排自动隐藏
      this.controller.setCurrentTime(value);
      this.scheduleAutoHide();
    }
  }

  /** #152 格式化时间秒→mm:ss */
  private formatTime(seconds: number): string {
    const totalSeconds: number = Math.floor(seconds);
    const m: number = Math.floor(totalSeconds / 60);
    const s: number = totalSeconds % 60;
    const mStr: string = m < 10 ? '0' + m.toString() : m.toString();
    const sStr: string = s < 10 ? '0' + s.toString() : s.toString();
    return mStr + ':' + sStr;
  }

  aboutToDisappear(): void {
    this.isDestroyed = true;
    // #152 清理自动隐藏定时器，避免内存泄漏
    this.clearAutoHide();
    // 停止播放释放资源，避免视频贴滚出屏后后台继续播放音频
    try {
      this.controller.stop();
    } catch (e) {
      // 组件已销毁时 stop 可能抛异常，忽略
    }
  }
}
