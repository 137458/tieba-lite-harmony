/**
 * #151 [Video-1] 端到端最小播放
 * #152 [Video-2] 自定义控制层
 * #153 [Video-3] 全屏播放（横屏旋转 + 全屏覆盖层 + 返回键 + 不重建 Controller）
 *
 * 功能：
 * - 未播放：显示封面图 + 中央播放按钮
 * - 点击播放按钮：切换到 Video 组件，autoPlay=true 开始播放
 * - 播放中：自定义控制层（底部进度条 + 时长 + 播放/暂停按钮 + 全屏按钮），3秒自动隐藏
 * - 点击视频区域：切换控制条显隐
 * - 缓冲中（onPrepared 前）：显示 LoadingProgress 指示器
 * - 全屏：点击全屏按钮 → 横屏旋转 + 全屏覆盖层（bindContentCover）+ 隐藏系统栏
 * - 退出全屏：返回按钮 / 物理返回键 → 恢复竖屏 + 恢复系统栏 + 进度恢复
 * - aboutToDisappear：停止播放 + 清理定时器 + 恢复竖屏
 *
 * 依赖 ArkUI Video 组件 + VideoController + window 方向控制（API 7+）
 * slice 4 将增加错误重试 + 无图模式封面占位
 */
import { window } from '@kit.ArkUI';

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
  /** #153 是否全屏模式（驱动 bindContentCover + 横屏旋转） */
  @Local isFullscreen: boolean = false;

  /** Video 控制器（start/pause/stop/setCurrentTime），全屏前后复用同一实例 */
  private controller: VideoController = new VideoController();
  /** #93 isDestroyed 生命周期守护：aboutToDisappear 后禁止操作状态 */
  private isDestroyed: boolean = false;
  /** #152 控制条3秒自动隐藏定时器 ID（-1 表示无定时器） */
  private hideControlsTimerId: number = -1;

  build() {
    Stack() {
      if (this.isPlaying) {
        // #153 全屏时不渲染非全屏 Video（避免 controller 绑定两个 Video 实例）
        // 全屏 Video 在 bindContentCover 的 FullscreenLayer builder 中渲染
        if (!this.isFullscreen) {
          Video({
            src: this.videoUrl,
            previewUri: this.coverUrl,
            controller: this.controller
          })
            .controls(false)
            .autoPlay(true)
            .objectFit(ImageFit.Contain)
            .width('100%')
            .aspectRatio(this.computeAspectRatio())
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

          // 缓冲指示器（居中，onPrepared 前显示）
          if (this.isBuffering) {
            LoadingProgress()
              .width(48)
              .height(48)
              .color(Color.White)
              .hitTestBehavior(HitTestMode.None)
          }

          // 非全屏控制层
          this.ControlBar()
        } else {
          // 全屏时占位（保持非全屏位置的布局高度，避免 List 塌陷）
          Stack()
            .width('100%')
            .aspectRatio(this.computeAspectRatio())
            .backgroundColor($r('app.color.input_background'))
        }
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
          .onError(() => { /* 封面加载失败静默处理 */ })

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
    // #153 全屏覆盖层：isFullscreen=true 时弹出，物理返回键默认关闭模态层
    // 背景黑色由 FullscreenLayer 内 Stack 的 backgroundColor(Color.Black) 提供
    // modalTransition=NONE：立即显示无转场动画（全屏视频场景不需要动画）
    .bindContentCover(this.isFullscreen, this.FullscreenLayer(), {
      modalTransition: ModalTransition.NONE,
      onDisappear: () => {
        // 物理返回键关闭模态层时恢复竖屏（返回按钮退出时由 exitFullscreen 处理）
        if (this.isFullscreen) {
          this.exitFullscreen();
        }
      }
    })
  }

  /** #152 #153 控制层 Builder（底部进度条 + 时长 + 播放/暂停 + 全屏按钮） */
  @Builder
  ControlBar() {
    Column() {
      Row() {
        // 播放/暂停按钮
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

        Text(this.formatTime(this.currentTime))
          .fontColor(Color.White)
          .fontSize(12)
          .margin({ left: 8 })

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

        Text(this.formatTime(this.duration))
          .fontColor(Color.White)
          .fontSize(12)
          .margin({ left: 8 })

        // #153 全屏按钮（点击进入横屏全屏）
        SymbolGlyph($r('sys.symbol.fullscreen'))
          .fontSize(20)
          .fontColor([Color.White])
          .margin({ left: 8 })
          .onClick(() => {
            this.enterFullscreen();
          })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .backgroundColor('rgba(0, 0, 0, 0.5)')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.End)
    .hitTestBehavior(HitTestMode.None)
    .opacity(this.showControls ? 1 : 0)
    .animation({ duration: 300, curve: Curve.EaseInOut })
  }

  /** #153 全屏覆盖层 Builder（Video + 返回按钮 + 控制层） */
  @Builder
  FullscreenLayer() {
    Stack() {
      // 全屏 Video（复用 controller，onPrepared 恢复进度）
      Video({
        src: this.videoUrl,
        controller: this.controller
      })
        .controls(false)
        .autoPlay(true)
        .objectFit(ImageFit.Contain)
        .width('100%')
        .height('100%')
        .onClick(() => {
          this.toggleControls();
        })
        .onPrepared((e: PreparedInfo) => {
          if (this.isDestroyed) return;
          this.duration = e.duration;
          this.isBuffering = false;
          // #153 恢复播放进度（全屏 Video 重建后 seek 到之前的进度）
          if (this.currentTime > 0) {
            this.controller.setCurrentTime(this.currentTime);
          }
          this.controller.start();
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

      // 缓冲指示器
      if (this.isBuffering) {
        LoadingProgress()
          .width(48)
          .height(48)
          .color(Color.White)
          .hitTestBehavior(HitTestMode.None)
      }

      // 返回按钮（左上角）
      Row() {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(24)
          .fontColor([Color.White])
          .onClick(() => {
            this.exitFullscreen();
          })
      }
      .width(40)
      .height(40)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .backgroundColor('rgba(0, 0, 0, 0.5)')
      .borderRadius(20)
      .position({ x: 16, y: 16 })
      .opacity(this.showControls ? 1 : 0)
      .animation({ duration: 300, curve: Curve.EaseInOut })

      // 全屏控制层（底部进度条，复用 ControlBar 但不显示全屏按钮）
      Column() {
        Row() {
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

          Text(this.formatTime(this.currentTime))
            .fontColor(Color.White)
            .fontSize(12)
            .margin({ left: 8 })

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

          Text(this.formatTime(this.duration))
            .fontColor(Color.White)
            .fontSize(12)
            .margin({ left: 8 })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })
        .backgroundColor('rgba(0, 0, 0, 0.5)')
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.End)
      .hitTestBehavior(HitTestMode.None)
      .opacity(this.showControls ? 1 : 0)
      .animation({ duration: 300, curve: Curve.EaseInOut })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
  }

  /** 计算视频宽高比 */
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

  /** 点击视频区域：切换控制条显隐 */
  private toggleControls(): void {
    if (this.isDestroyed) return;
    this.showControls = !this.showControls;
    if (this.showControls) {
      this.scheduleAutoHide();
    } else {
      this.clearAutoHide();
    }
  }

  /** 安排3秒后自动隐藏控制条 */
  private scheduleAutoHide(): void {
    if (this.isDestroyed) return;
    this.clearAutoHide();
    this.hideControlsTimerId = setTimeout(() => {
      if (this.isDestroyed) return;
      this.showControls = false;
      this.hideControlsTimerId = -1;
    }, 3000);
  }

  /** 清除自动隐藏定时器 */
  private clearAutoHide(): void {
    if (this.hideControlsTimerId !== -1) {
      clearTimeout(this.hideControlsTimerId);
      this.hideControlsTimerId = -1;
    }
  }

  /** 进度条拖拽回调 */
  private onSliderChange(value: number, mode: SliderChangeMode): void {
    if (this.isDestroyed) return;
    if (mode === SliderChangeMode.Moving) {
      this.currentTime = value;
      this.clearAutoHide();
    } else if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
      this.controller.setCurrentTime(value);
      this.scheduleAutoHide();
    }
  }

  /** 格式化时间秒→mm:ss */
  private formatTime(seconds: number): string {
    const totalSeconds: number = Math.floor(seconds);
    const m: number = Math.floor(totalSeconds / 60);
    const s: number = totalSeconds % 60;
    const mStr: string = m < 10 ? '0' + m.toString() : m.toString();
    const sStr: string = s < 10 ? '0' + s.toString() : s.toString();
    return mStr + ':' + sStr;
  }

  /** #153 进入全屏：旋转横屏 + 隐藏系统栏 + 弹出覆盖层 */
  private enterFullscreen(): void {
    if (this.isDestroyed || this.isFullscreen) return;
    this.isFullscreen = true;
    this.applyLandscapeOrientation();
  }

  /** #153 退出全屏：恢复竖屏 + 恢复系统栏 + 关闭覆盖层 */
  private exitFullscreen(): void {
    if (this.isDestroyed || !this.isFullscreen) return;
    this.isFullscreen = false;
    this.applyPortraitOrientation();
  }

  /** #153 设置横屏 + 隐藏系统栏 */
  private applyLandscapeOrientation(): void {
    try {
      const context: Context = getContext(this);
      window.getLastWindow(context).then((win: window.Window) => {
        win.setPreferredOrientation(window.Orientation.LANDSCAPE);
        win.setWindowSystemBarEnable([]);
      }).catch((err: Error) => {
        console.error(`[VideoPlayer] set landscape failed: ${err.message}`);
      });
    } catch (e) {
      console.error(`[VideoPlayer] getLastWindow failed: ${(e as Error).message}`);
    }
  }

  /** #153 恢复竖屏 + 恢复系统栏 */
  private applyPortraitOrientation(): void {
    try {
      const context: Context = getContext(this);
      window.getLastWindow(context).then((win: window.Window) => {
        win.setPreferredOrientation(window.Orientation.UNSPECIFIED);
        win.setWindowSystemBarEnable(['status', 'navigation']);
      }).catch((err: Error) => {
        console.error(`[VideoPlayer] set portrait failed: ${err.message}`);
      });
    } catch (e) {
      console.error(`[VideoPlayer] getLastWindow failed: ${(e as Error).message}`);
    }
  }

  aboutToDisappear(): void {
    this.isDestroyed = true;
    this.clearAutoHide();
    // #153 退出页面时若仍处于全屏，恢复竖屏避免影响其他页面
    if (this.isFullscreen) {
      this.applyPortraitOrientation();
    }
    // 停止播放释放资源
    try {
      this.controller.stop();
    } catch (e) {
      // 组件已销毁时 stop 可能抛异常，忽略
    }
  }
}
