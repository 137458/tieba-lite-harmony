/**
 * #151 [Video-1] 端到端最小播放
 * #152 [Video-2] 自定义控制层
 * #153 [Video-3] 全屏播放（横屏旋转 + 全屏覆盖层 + 返回键 + 不重建 Controller）
 * #154 [Video-4] 健壮性（错误重试 + 无图模式封面占位 + 播放完成重置）
 *
 * 功能：
 * - 未播放：显示封面图 + 中央播放按钮（无图模式下封面不加载，显示占位图）
 * - 点击播放按钮：切换到 Video 组件，autoPlay=true 开始播放
 * - 播放中：自定义控制层（底部进度条 + 时长 + 播放/暂停按钮 + 全屏按钮），3秒自动隐藏
 * - 点击视频区域：切换控制条显隐
 * - 缓冲中（onPrepared 前）：显示 LoadingProgress 指示器
 * - 全屏：点击全屏按钮 → 横屏旋转 + 全屏覆盖层（bindContentCover）+ 隐藏系统栏
 * - 退出全屏：返回按钮 / 物理返回键 → 恢复竖屏 + 恢复系统栏 + 进度恢复
 * - #154 错误处理：URL 为空/播放失败 → 错误占位 + 重试按钮（上限 3 次）
 * - #154 播放完成：显示重新播放按钮，点击从头播放
 * - #154 无图模式：封面图根据 shouldLoad 判断，无图模式显示占位图
 * - aboutToDisappear：停止播放 + 清理定时器 + 恢复竖屏
 *
 * 依赖 ArkUI Video 组件 + VideoController + window 方向控制（API 7+）+ ImageLoadUtil
 */
import { window, AppStorageV2 } from '@kit.ArkUI';
import { shouldLoad } from '../utils/ImageLoadUtil';
import { ImageLoadTypeState, IsWifiState } from '../model/AppStorageV2Models';
import { connectTheme, ThemeState } from '../theme/ThemeManager';

/** #154 最大重试次数（避免无限重试循环） */
const MAX_RETRY: number = 3;

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
  /** #154 是否发生错误（onError 触发，显示错误占位 + 重试按钮） */
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
  /** #154 是否播放完成（onFinish 触发，显示重新播放按钮） */
  @Local isFinished: boolean = false;
  /** #154 已重试次数（超过 MAX_RETRY 后禁用重试按钮） */
  @Local retryCount: number = 0;
  @Local themeState: ThemeState = connectTheme();

  /** #154 图片加载模式（0/1/2/3），无图模式下封面不加载 */
  @Local imageLoadTypeState: ImageLoadTypeState =
    AppStorageV2.connect(ImageLoadTypeState, 'imageLoadType', () => new ImageLoadTypeState())!;
  /** #154 是否 WiFi 网络（配合 imageLoadType 判断无图模式） */
  @Local isWifiState: IsWifiState =
    AppStorageV2.connect(IsWifiState, 'isWifi', () => new IsWifiState())!;

  /** Video 控制器（start/pause/stop/reset/setCurrentTime），全屏前后复用同一实例 */
  private controller: VideoController = new VideoController();
  /** #93 isDestroyed 生命周期守护：aboutToDisappear 后禁止操作状态 */
  private isDestroyed: boolean = false;
  /** #152 控制条3秒自动隐藏定时器 ID（-1 表示无定时器） */
  private hideControlsTimerId: number = -1;

  build() {
    Stack() {
      // #154 URL 为空：直接显示错误占位，不创建 Video 组件
      if (this.videoUrl.length === 0) {
        this.ErrorPlaceholder($r('app.string.video_url_invalid'), false)
      } else if (this.hasError) {
        // #154 播放失败：错误占位 + 重试按钮（达到上限后禁用）
        this.ErrorPlaceholder($r('app.string.video_play_failed'), this.retryCount < MAX_RETRY)
      } else if (this.isPlaying) {
        // #153 全屏时不渲染非全屏 Video（避免 controller 绑定两个 Video 实例）
        // 全屏 Video 在 bindContentCover 的 FullscreenLayer builder 中渲染
        if (!this.isFullscreen) {
          Video({
            src: this.videoUrl,
            previewUri: this.coverUrl,
            controller: this.controller
          })
            .controls(false)
            // autoPlay=false：onPrepared 中手动 start，以便退出全屏重建时先 seek 恢复进度再 start
            .autoPlay(false)
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
              // 退出全屏后重建非全屏 Video：先 seek 到之前的进度，再 start
              // 第一次创建时 currentTime=0，不 seek，直接 start（行为同 autoPlay=true）
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
              this.onPlaybackFinish();
            })
            .onError(() => {
              if (this.isDestroyed) return;
              this.hasError = true;
              this.isBuffering = false;
            })

          // 缓冲指示器（居中，onPrepared 前显示）
          if (this.isBuffering) {
            LoadingProgress()
              .width(48)
              .height(48)
              .color(Color.White)
              .hitTestBehavior(HitTestMode.None)
          }

          // #154 播放完成遮罩 + 重新播放按钮
          if (this.isFinished) {
            this.ReplayOverlay()
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
        // #154 无图模式下 getDisplayCoverUrl 返回空字符串，Image 显示 alt 占位图
        Image(this.getDisplayCoverUrl())
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
          // #154 播放完成后显示重新播放图标，否则显示播放图标
          if (this.isFinished) {
            SymbolGlyph($r('sys.symbol.arrow_clockwise'))
              .fontSize(28)
              .fontColor([Color.White])
              .onClick(() => {
                this.replayFromStart();
              })
          } else {
            SymbolGlyph($r('sys.symbol.play_fill'))
              .fontSize(28)
              .fontColor([Color.White])
              .onClick(() => {
                this.startPlayback();
              })
          }
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

  /** #154 错误占位 Builder（错误图标 + 错误信息 + 可选重试按钮） */
  @Builder
  ErrorPlaceholder(msg: Resource, showRetry: boolean) {
    Column() {
      SymbolGlyph($r('sys.symbol.exclamationmark_triangle'))
        .fontSize(32)
        .fontColor([$r('app.color.text_secondary')])
        .margin({ bottom: 8 })

      Text(msg)
        .fontColor($r('app.color.text_secondary'))
        .fontSize(12)

      if (showRetry) {
        Text($r('app.string.retry'))
          .fontColor(this.themeState.primary)
          .fontSize(12)
          .margin({ top: 8 })
          .onClick(() => {
            this.retryPlayback();
          })
      } else if (this.retryCount >= MAX_RETRY) {
        // 达到重试上限：显示 video_retry_limit 提示
        Text($r('app.string.video_retry_limit'))
          .fontColor($r('app.color.text_secondary'))
          .fontSize(12)
          .margin({ top: 8 })
      }
    }
    .width('100%')
    .aspectRatio(this.computeAspectRatio())
    .backgroundColor($r('app.color.input_background'))
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  /** #154 播放完成遮罩 Builder（半透明背景 + 重新播放按钮） */
  @Builder
  ReplayOverlay() {
    Column() {
      SymbolGlyph($r('sys.symbol.arrow_clockwise'))
        .fontSize(40)
        .fontColor([Color.White])
        .margin({ bottom: 4 })
      Text($r('app.string.video_replay'))
        .fontColor(Color.White)
        .fontSize(12)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('rgba(0, 0, 0, 0.5)')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .onClick(() => {
      this.replayFromStart();
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
      // 全屏 Video（复用 controller，onPrepared 恢复进度后手动 start）
      // autoPlay=false 避免 onPrepared 前从头播放导致进度恢复失效
      Video({
        src: this.videoUrl,
        controller: this.controller
      })
        .controls(false)
        .autoPlay(false)
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
          // #153 恢复播放进度（全屏 Video 重建后先 seek 到之前的进度，再 start）
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
          this.onPlaybackFinish();
        })
        .onError(() => {
          if (this.isDestroyed) return;
          this.hasError = true;
          this.isBuffering = false;
        })

      // 缓冲指示器
      if (this.isBuffering) {
        LoadingProgress()
          .width(48)
          .height(48)
          .color(Color.White)
          .hitTestBehavior(HitTestMode.None)
      }

      // #154 播放完成遮罩 + 重新播放按钮（全屏）
      if (this.isFinished) {
        this.ReplayOverlay()
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

  /** #154 获取封面图 URL（无图模式下返回空字符串，Image 显示 alt 占位图） */
  private getDisplayCoverUrl(): string {
    if (!shouldLoad(this.imageLoadTypeState.value, this.isWifiState.value)) {
      return '';
    }
    return this.coverUrl;
  }

  /** 点击播放按钮：切换到播放状态 */
  private startPlayback(): void {
    if (this.isDestroyed) return;
    // #154 播放完成后点击播放按钮 → 重新播放
    if (this.isFinished) {
      this.replayFromStart();
      return;
    }
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

  /** #154 播放完成回调（onFinish）：重置进度 + 显示重新播放按钮 + 常显控制层 */
  private onPlaybackFinish(): void {
    this.isPaused = true;
    this.isFinished = true;
    this.currentTime = 0;
    this.clearAutoHide();
    this.showControls = true;
  }

  /** #154 重新播放（从头开始）：重置完成状态 + seek 到开头 + start */
  private replayFromStart(): void {
    if (this.isDestroyed) return;
    this.isFinished = false;
    this.currentTime = 0;
    this.isPaused = false;
    try {
      this.controller.setCurrentTime(0);
      this.controller.start();
      this.scheduleAutoHide();
    } catch (e) {
      console.error(`[VideoPlayer] replay failed: ${(e as Error).message}`);
    }
  }

  /** #154 错误重试：reset + start 重新发起播放（受 MAX_RETRY 限制） */
  private retryPlayback(): void {
    if (this.isDestroyed) return;
    if (this.retryCount >= MAX_RETRY) return;
    this.retryCount++;
    this.hasError = false;
    this.isBuffering = true;
    this.isFinished = false;
    this.currentTime = 0;
    try {
      this.controller.reset();
      this.controller.start();
    } catch (e) {
      console.error(`[VideoPlayer] retry failed: ${(e as Error).message}`);
    }
  }

  /** #153 进入全屏：横屏视频旋转横屏 + 隐藏系统栏 + 弹出覆盖层
   * 竖屏视频（videoWidth <= videoHeight）保持竖屏全屏，避免横屏后两边大量黑边 */
  private enterFullscreen(): void {
    if (this.isDestroyed || this.isFullscreen) return;
    // #154 进入全屏时重置完成状态（全屏 Video 重建后 autoPlay 会重新播放）
    this.isFinished = false;
    this.isFullscreen = true;
    // 仅横屏视频旋转横屏，竖屏视频保持竖屏全屏
    if (this.isLandscapeVideo()) {
      this.applyLandscapeOrientation();
    }
  }

  /** #153 退出全屏：恢复竖屏（仅横屏视频旋转过）+ 恢复系统栏 + 关闭覆盖层 */
  private exitFullscreen(): void {
    if (this.isDestroyed || !this.isFullscreen) return;
    this.isFullscreen = false;
    // 仅横屏视频需要恢复竖屏，竖屏视频从未旋转无需恢复
    if (this.isLandscapeVideo()) {
      this.applyPortraitOrientation();
    }
  }

  /** 判断是否为横屏视频（videoWidth > videoHeight），用于决定全屏时是否旋转 */
  private isLandscapeVideo(): boolean {
    return this.videoWidth > 0 && this.videoHeight > 0 && this.videoWidth > this.videoHeight;
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
    // #153 退出页面时若仍处于全屏且为横屏视频，恢复竖屏避免影响其他页面
    // 竖屏视频全屏未旋转过方向，无需恢复
    if (this.isFullscreen && this.isLandscapeVideo()) {
      this.applyPortraitOrientation();
    }
    // #154 停止播放释放资源（停止音频）
    try {
      this.controller.stop();
    } catch (e) {
      // 组件已销毁时 stop 可能抛异常，忽略
    }
  }
}

/**
 * 视频封面占位组件（性能优化：列表中懒创建 VideoPlayer）
 *
 * 问题背景：
 * 直接在列表项中渲染 VideoPlayer 会导致每个含视频回复都创建 VideoPlayer 实例，
 * 即使不播放也会产生重资源开销：
 * - new VideoController() 初始化解码器
 * - 3 次 AppStorageV2.connect（themeState/imageLoadType/isWifi）
 * - bindContentCover 全屏覆盖层绑定
 * 滚动到视频回复时卡顿，多个视频回复累积卡顿严重
 *
 * 优化策略：
 * - 默认只渲染封面图 + 播放按钮（轻量 Image + SymbolGlyph）
 * - 点击播放按钮才 isActivated=true，用 VideoPlayer 替换占位
 * - @Monitor('videoUrl') 监听 URL 变化（@ReusableV2 PostItem 复用时触发），
 *   重置 isActivated=false，避免复用后旧激活状态错误保留
 */
@ComponentV2
export struct VideoCoverPlaceholder {
  /** 视频 URL */
  @Param videoUrl: string = '';
  /** 封面 URL */
  @Param coverUrl: string = '';
  /** 视频宽度（计算宽高比） */
  @Param videoWidth: number = 0;
  /** 视频高度（计算宽高比） */
  @Param videoHeight: number = 0;
  /** 图片加载策略（0/1/2/3），无图模式下封面不加载 */
  @Param imageLoadType: number = 0;
  /** 是否 WiFi 网络（配合 imageLoadType 判断无图模式） */
  @Param isWifi: boolean = false;

  /** 是否已激活（点击播放按钮后 true，渲染完整 VideoPlayer） */
  @Local isActivated: boolean = false;

  /**
   * 监听 videoUrl 变化：@ReusableV2 PostItem 复用时新 post 的视频 URL 传入，
   * 重置 isActivated=false，避免复用后旧激活状态错误显示 VideoPlayer。
   * 极端情况：新旧 videoUrl 相同时不触发（两个回复引用同一视频，罕见，可忽略）
   */
  @Monitor('videoUrl')
  onVideoUrlChange(monitor: IMonitor): void {
    this.isActivated = false;
  }

  build() {
    if (this.isActivated) {
      // 点击播放后：渲染完整 VideoPlayer 组件（此时才创建 VideoController 等重资源）
      VideoPlayer({
        videoUrl: this.videoUrl,
        coverUrl: this.coverUrl,
        videoWidth: this.videoWidth,
        videoHeight: this.videoHeight
      })
        .width('100%')
        .margin({ top: 10 })
    } else {
      // 默认：封面图 + 播放按钮（轻量，不创建 VideoController）
      Stack({ alignContent: Alignment.Center }) {
        Image(this.getDisplayCoverUrl())
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
        }
        .width(56)
        .height(56)
        .hitTestBehavior(HitTestMode.Block)
        .onClick(() => {
          this.isActivated = true;
        })
      }
      .width('100%')
      .margin({ top: 10 })
    }
  }

  /** 计算视频宽高比（对齐 VideoPlayer.computeAspectRatio） */
  private computeAspectRatio(): number {
    if (this.videoWidth > 0 && this.videoHeight > 0) {
      return this.videoWidth / this.videoHeight;
    }
    return 16 / 9;
  }

  /** 获取封面图 URL（无图模式下返回空字符串，Image 显示 alt 占位图） */
  private getDisplayCoverUrl(): string {
    if (!shouldLoad(this.imageLoadType, this.isWifi)) {
      return '';
    }
    return this.coverUrl;
  }
}
