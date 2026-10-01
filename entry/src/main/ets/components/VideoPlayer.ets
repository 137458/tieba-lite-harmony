/**
 * #151 [Video-1] 端到端最小播放
 * #152 [Video-2] 自定义控制层
 * #153 [Video-3] 全屏播放（横屏旋转 + 全屏覆盖层 + 返回键 + 不重建播放器）
 * #154 [Video-4] 健壮性（错误重试 + 无图模式封面占位 + 播放完成重置）
 * #115 [A8] 视频手势（迁移 @seagazer/ccplayer：左半屏竖滑亮度 / 右半屏竖滑音量 / 横滑进度）
 *
 * 播放内核：@seagazer/ccplayer（CcPlayer + CcPlayerViewV2），替代系统 Video 组件。
 * 选型理由（2026-10-01 决策）：
 *   - CcPlayerViewV2 内置手势识别（左亮右音中进度的区域划分 + 阻尼换算 + 双击事件），
 *     系统组件需自写 PanGesture 组合并处理与列表滚动的手势冲突
 *   - CcPlayer 与 UI 解耦（实例持有播放状态，View 只绑定 surface 渲染），
 *     播控中心绑定（bindAvSession）与画中画（enablePip）能力后续可白送，帖内短视频暂不启用
 *
 * surface 生命周期（真机回归修正）：surface 重绑后库不会自动恢复画面（黑屏有声），
 * 因此 onSurfaceCreated 总是重新 setMediaSource 并从上次进度恢复（startTo），
 * 对齐旧 Video 组件"视图重建后 seek 恢复"语义。
 *
 * 手势生效模型（对齐官方 Sample"用户自己手动处理手势事件"）：
 *   CcPlayerViewV2.onGestureAction 只上报手势类型与百分比，实际生效由本组件实现：
 *   - PROGRESS：isTouchUp 时 seekTo（松手生效，拖动中只更新气泡）
 *   - BRIGHTNESS：实时 window.setWindowBrightness
 *   - VOLUME：实时 player.setVolume（媒体流音量）
 *   手势 UI 用轻量自绘气泡（与自绘控制条体系一致，不引入 NodeContainer overlay）
 *
 * 功能保留（对齐 #151-154）：
 * - 未播放：封面图 + 中央播放按钮（无图模式封面不加载）
 * - 点击播放：懒激活渲染 CcPlayerViewV2，onSurfaceCreated 后 setMediaSource + start
 * - 控制条：底部进度条 + 时长 + 播放/暂停 + 全屏，3 秒自动隐藏
 * - 全屏：横屏视频旋转横屏 + bindContentCover 覆盖层 + 返回恢复（同一 CcPlayer 实例，重设源恢复进度）
 * - 错误：错误占位 + 重试（上限 3 次，重试走"卸载 view 重挂 surface"的干净路径）
 * - 完成：重新播放按钮（seekTo(0) + start）
 * - aboutToDisappear：release 播放器 + 清定时器 + 恢复竖屏
 *
 * 对外 @Param 与 VideoCoverPlaceholder 懒激活契约保持不变。
 * 依赖 @seagazer/ccplayer ^1.3.3（API 12+）+ window 方向控制 + ImageLoadUtil
 */
import { window } from '@kit.ArkUI';
import { shouldLoad } from '../utils/ImageLoadUtil';
import { ThemeState } from '../theme/ThemeManager';
import {
  AspectRatio,
  CcPlayer,
  CcPlayerViewV2,
  GestureType,
  MediaSourceFactory,
  PlayerState
} from '@seagazer/ccplayer';

/** #154 最大重试次数（避免无限重试循环） */
const MAX_RETRY: number = 3;
/** 控制条自动隐藏延时（毫秒，对齐原实现） */
const CONTROL_AUTO_HIDE_MS: number = 3000;

// ==================== 文件级工具函数（VideoPlayer 与 VideoCoverPlaceholder 共用） ====================
// P2 #6 抽取：避免两个 struct 各自重复实现 computeAspectRatio / getDisplayCoverUrl

/** 计算视频宽高比（width/height，无效值兜底 16:9） */
function computeVideoAspectRatio(width: number, height: number): number {
  if (width > 0 && height > 0) {
    return width / height;
  }
  return 16 / 9;
}

/** 获取封面图 URL（无图模式下返回空字符串，Image 组件显示 alt 占位图） */
function getDisplayCoverUrl(coverUrl: string, imageLoadType: number, isWifi: boolean): string {
  if (!shouldLoad(imageLoadType, isWifi)) {
    return '';
  }
  return coverUrl;
}

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
  // P1 #3 #4 性能优化：themeState/imageLoadType/isWifi 改为 @Require @Param，
  // 由父组件 VideoCoverPlaceholder 链式传入，避免每次实例化 VideoPlayer 都 3 次 connect
  @Require @Param themeState: ThemeState;
  @Require @Param imageLoadType: number;
  @Require @Param isWifi: boolean;

  /** 是否已开始播放（控制封面/播放视图切换） */
  @Local isPlaying: boolean = false;
  /** 是否暂停（控制播放/暂停按钮图标，状态/完成回调同步） */
  @Local isPaused: boolean = false;
  /** #154 是否发生错误（错误占位 + 重试按钮） */
  @Local hasError: boolean = false;
  /** 是否缓冲中（prepared 前为 true） */
  @Local isBuffering: boolean = true;
  /** 当前播放时间（秒，进度回调毫秒/1000） */
  @Local currentTime: number = 0;
  /** 视频总时长（秒，prepared 回调毫秒/1000） */
  @Local duration: number = 0;
  /** 控制条是否显示（点击视频区域切换 + 3秒自动隐藏） */
  @Local showControls: boolean = true;
  /** #153 是否全屏模式（驱动 bindContentCover + 横屏旋转） */
  @Local isFullscreen: boolean = false;
  /** #154 是否播放完成（完成回调触发，显示重新播放按钮） */
  @Local isFinished: boolean = false;
  /** #154 已重试次数（超过 MAX_RETRY 后禁用重试按钮） */
  @Local retryCount: number = 0;
  /** #115 手势气泡提示文本（如 "亮度 60%"，空串隐藏） */
  @Local gestureHint: string = '';

  /**
   * ccplayer 播放器实例（激活时创建，aboutToDisappear 时 release）。
   * CcPlayer 与 UI 解耦：全屏切换只换渲染 surface，实例与播放状态保持。
   * 可选原因：未激活（封面态）时不存在实例。
   */
  private player?: CcPlayer;
  /** 亮度手势用的宿主窗口（aboutToAppear 缓存） */
  private playerWindow?: window.Window;
  /** #93 isDestroyed 生命周期守护：aboutToDisappear 后禁止操作状态 */
  private isDestroyed: boolean = false;
  /** #152 控制条3秒自动隐藏定时器 ID（-1 表示无定时器） */
  private hideControlsTimerId: number = -1;

  // 播放器 listener（箭头函数属性，保证 remove 时同一引用）
  private preparedListener = (): void => {
    if (this.isDestroyed) {
      return;
    }
    this.duration = this.player!.getDuration() / 1000;
    this.isBuffering = false;
  };
  private progressListener = (positionMs: number): void => {
    if (this.isDestroyed) {
      return;
    }
    this.currentTime = positionMs / 1000;
  };
  private stateListener = (state: PlayerState): void => {
    if (this.isDestroyed) {
      return;
    }
    if (state === PlayerState.STATE_STARTED) {
      this.isPaused = false;
    } else if (state === PlayerState.STATE_PAUSED) {
      this.isPaused = true;
    } else if (state === PlayerState.STATE_COMPLETED) {
      this.onPlaybackFinish();
    }
  };
  private errorListener = (code: number, message: string): void => {
    if (this.isDestroyed) {
      return;
    }
    console.error(`[VideoPlayer] play error: code=${code}, msg=${message}`);
    this.hasError = true;
    this.isBuffering = false;
  };

  aboutToAppear(): void {
    try {
      const context: Context | undefined = this.getUIContext().getHostContext();
      if (context !== undefined) {
        window.getLastWindow(context).then((win: window.Window) => {
          if (!this.isDestroyed) {
            this.playerWindow = win;
          }
        }).catch((err: Error) => {
          console.warn(`[VideoPlayer] getLastWindow failed: ${err.message}`);
        });
      }
    } catch (e) {
      console.warn(`[VideoPlayer] init window failed: ${(e as Error).message}`);
    }
  }

  aboutToDisappear(): void {
    this.isDestroyed = true;
    this.clearAutoHide();
    // #153 退出页面时若仍处于全屏且为横屏视频，恢复竖屏避免影响其他页面
    if (this.isFullscreen && this.isLandscapeVideo()) {
      this.applyPortraitOrientation();
    }
    // 释放播放器（内部含 stop 与资源回收；未激活时无实例）
    if (this.player !== undefined) {
      try {
        this.player.release();
      } catch (e) {
        // 组件销毁竞态下 release 可能抛异常，忽略
      }
      this.player = undefined;
    }
  }

  /**
   * 创建播放器实例并注册 listener（首次激活时调用）
   */
  private ensurePlayer(): void {
    if (this.player !== undefined) {
      return;
    }
    const context: Context | undefined = this.getUIContext().getHostContext();
    if (context === undefined) {
      this.hasError = true;
      return;
    }
    const player: CcPlayer = new CcPlayer(context);
    // 帖内短视频不绑定播控中心（bindAvSession），避免多视频实例的 session 冲突
    player.setKeepScreenOn(this.getUIContext(), true);
    player
      .addOnPreparedListener(this.preparedListener)
      .addOnProgressChangedListener(this.progressListener)
      .addOnStateChangedListener(this.stateListener)
      .addOnErrorListener(this.errorListener);
    this.player = player;
  }

  /**
   * #115 CcPlayerViewV2 surface 就绪回调（首次播放 / 全屏切换 / 错误重试重挂 共用）：
   * 真机回归发现：surface 重绑后库不会自动恢复画面（黑屏但声音在播），
   * 因此每次 surface 就绪都重新 setMediaSource 并从上次进度恢复（对齐旧 Video
   * 组件"视图重建后 seek 恢复"语义）。AVPlayer 重建开销小（本地/短链路视频）。
   * currentTime > 0 时 startTo 恢复进度，否则从头播放。
   */
  private onSurfaceReady(): void {
    if (this.isDestroyed || this.player === undefined) {
      return;
    }
    const seekMs: number = this.currentTime > 0 ? this.currentTime * 1000 : 0;
    const source = MediaSourceFactory.createUrl('', this.videoUrl);
    this.player.setMediaSource(source, () => {
      if (this.isDestroyed || this.player === undefined) {
        return;
      }
      if (seekMs > 0) {
        this.player.startTo(seekMs);
      } else {
        this.player.start();
      }
      this.showControls = true;
      this.scheduleAutoHide();
    });
  }

  /**
   * #115 手势生效处理（对齐官方 Sample handleGestureAction）：
   * - PROGRESS：拖动中更新气泡，松手（isTouchUp）才 seekTo 并清气泡
   * - BRIGHTNESS：实时窗口亮度，拖动中更新气泡，松手延时清气泡
   * - VOLUME：实时媒体音量，气泡同上
   */
  private handleGestureAction(type: GestureType, percent: number, isTouchUp: boolean): void {
    if (this.isDestroyed) {
      return;
    }
    switch (type) {
      case GestureType.PROGRESS:
        if (isTouchUp) {
          const seekMs: number = this.duration * 1000 * percent;
          this.player?.seekTo(seekMs);
          this.gestureHint = '';
        } else {
          this.gestureHint = `${this.formatTime(this.duration * percent)} / ${this.formatTime(this.duration)}`;
        }
        break;
      case GestureType.BRIGHTNESS:
        this.gestureHint = `亮度 ${Math.round(percent * 100)}%`;
        try {
          this.playerWindow?.setWindowBrightness(percent);
        } catch (e) {
          console.warn(`[VideoPlayer] setWindowBrightness failed: ${(e as Error).message}`);
        }
        if (isTouchUp) {
          this.scheduleGestureHintClear();
        }
        break;
      case GestureType.VOLUME:
        this.gestureHint = `音量 ${Math.round(percent * 100)}%`;
        this.player?.setVolume(percent);
        if (isTouchUp) {
          this.scheduleGestureHintClear();
        }
        break;
      default:
        break;
    }
  }

  /** 手势结束（松手或切回普通点击态）后清除气泡；进度手势在 touchUp 已清，亮/音量延时清 */
  private scheduleGestureHintClear(): void {
    setTimeout(() => {
      if (!this.isDestroyed) {
        this.gestureHint = '';
      }
    }, 600);
  }

  build() {
    Stack() {
      // #154 URL 为空：直接显示错误占位，不创建播放器
      if (this.videoUrl.length === 0) {
        this.ErrorPlaceholder($r('app.string.video_url_invalid'), false)
      } else if (this.hasError) {
        // #154 播放失败：错误占位 + 重试按钮（达到上限后禁用）
        this.ErrorPlaceholder($r('app.string.video_play_failed'), this.retryCount < MAX_RETRY)
      } else if (this.isPlaying) {
        // #153 全屏时不渲染非全屏视图（避免双 surface），
        // 全屏视图在 bindContentCover 的 FullscreenLayer builder 中渲染
        if (!this.isFullscreen) {
          CcPlayerViewV2({
            player: this.player!,
            asRatio: AspectRatio.AUTO,
            isSupportGesture: true,
            // #115 手势生效：库只上报事件，实际生效由本组件 handleGestureAction 实现
            onGestureAction: (type: GestureType, percent: number, isTouchUp: boolean) => {
              this.handleGestureAction(type, percent, isTouchUp);
            },
            onSurfaceCreated: () => {
              this.onSurfaceReady();
            }
          })
            .width('100%')
            .aspectRatio(computeVideoAspectRatio(this.videoWidth, this.videoHeight))
            .onClick(() => {
              this.toggleControls();
            })

          // 缓冲指示器（居中，prepared 前显示）
          if (this.isBuffering) {
            LoadingProgress()
              .width(48)
              .height(48)
              .color(Color.White)
              .hitTestBehavior(HitTestMode.None)
          }

          // #115 手势气泡（居中，手势拖动时显示）
          if (this.gestureHint.length > 0) {
            Text(this.gestureHint)
              .fontSize(14)
              .fontColor(Color.White)
              .padding({ left: 14, right: 14, top: 8, bottom: 8 })
              .backgroundColor('rgba(0, 0, 0, 0.6)')
              .borderRadius(20)
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
            .aspectRatio(computeVideoAspectRatio(this.videoWidth, this.videoHeight))
            .backgroundColor($r('app.color.input_background'))
        }
      } else {
        // 未播放：显示封面图 + 中央播放按钮
        // #154 无图模式下 getDisplayCoverUrl 返回空字符串，Image 显示 alt 占位图
        Image(getDisplayCoverUrl(this.coverUrl, this.imageLoadType, this.isWifi))
          .objectFit(ImageFit.Cover)
          .width('100%')
          .aspectRatio(computeVideoAspectRatio(this.videoWidth, this.videoHeight))
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
    .aspectRatio(computeVideoAspectRatio(this.videoWidth, this.videoHeight))
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
              if (this.isDestroyed || this.player === undefined) return;
              this.player.start();
              this.scheduleAutoHide();
            })
        } else {
          SymbolGlyph($r('sys.symbol.pause_fill'))
            .fontSize(20)
            .fontColor([Color.White])
            .onClick(() => {
              if (this.isDestroyed || this.player === undefined) return;
              this.player.pause();
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

  /** #153 全屏覆盖层 Builder（CcPlayerViewV2 + 返回按钮 + 控制层，绑同一播放器实例） */
  @Builder
  FullscreenLayer() {
    Stack() {
      // 全屏渲染视图（绑定同一 CcPlayer：surface 重绑后经 onSurfaceCreated 重设源并恢复进度）
      if (this.player !== undefined) {
        CcPlayerViewV2({
          player: this.player,
          asRatio: AspectRatio.AUTO,
          isSupportGesture: true,
          onGestureAction: (type: GestureType, percent: number, isTouchUp: boolean) => {
            this.handleGestureAction(type, percent, isTouchUp);
          },
          onSurfaceCreated: () => {
            this.onSurfaceReady();
          }
        })
          .width('100%')
          .height('100%')
          .onClick(() => {
            this.toggleControls();
          })
      }

      // 缓冲指示器
      if (this.isBuffering) {
        LoadingProgress()
          .width(48)
          .height(48)
          .color(Color.White)
          .hitTestBehavior(HitTestMode.None)
      }

      // #115 手势气泡（全屏居中）
      if (this.gestureHint.length > 0) {
        Text(this.gestureHint)
          .fontSize(14)
          .fontColor(Color.White)
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
          .backgroundColor('rgba(0, 0, 0, 0.6)')
          .borderRadius(20)
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

      // 全屏控制层（底部进度条，不含全屏按钮）
      Column() {
        Row() {
          if (this.isPaused) {
            SymbolGlyph($r('sys.symbol.play_fill'))
              .fontSize(20)
              .fontColor([Color.White])
              .onClick(() => {
                if (this.isDestroyed || this.player === undefined) return;
                this.player.start();
                this.scheduleAutoHide();
              })
          } else {
            SymbolGlyph($r('sys.symbol.pause_fill'))
              .fontSize(20)
              .fontColor([Color.White])
              .onClick(() => {
                if (this.isDestroyed || this.player === undefined) return;
                this.player.pause();
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

  /** 点击播放按钮：创建播放器并切换到播放视图 */
  private startPlayback(): void {
    if (this.isDestroyed) {
      return;
    }
    // #154 播放完成后点击播放按钮 → 重新播放
    if (this.isFinished) {
      this.replayFromStart();
      return;
    }
    this.ensurePlayer();
    this.isPlaying = true;
  }

  /** 点击视频区域：切换控制条显隐 */
  private toggleControls(): void {
    if (this.isDestroyed) {
      return;
    }
    this.showControls = !this.showControls;
    if (this.showControls) {
      this.scheduleAutoHide();
    } else {
      this.clearAutoHide();
    }
  }

  /** 安排3秒后自动隐藏控制条 */
  private scheduleAutoHide(): void {
    if (this.isDestroyed) {
      return;
    }
    this.clearAutoHide();
    this.hideControlsTimerId = setTimeout(() => {
      if (this.isDestroyed) {
        return;
      }
      this.showControls = false;
      this.hideControlsTimerId = -1;
    }, CONTROL_AUTO_HIDE_MS);
  }

  /** 清除自动隐藏定时器 */
  private clearAutoHide(): void {
    if (this.hideControlsTimerId !== -1) {
      clearTimeout(this.hideControlsTimerId);
      this.hideControlsTimerId = -1;
    }
  }

  /** 进度条拖拽回调（Slider 秒制，seekTo 毫秒制） */
  private onSliderChange(value: number, mode: SliderChangeMode): void {
    if (this.isDestroyed) {
      return;
    }
    if (mode === SliderChangeMode.Moving) {
      this.currentTime = value;
      this.clearAutoHide();
    } else if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
      this.player?.seekTo(value * 1000);
      this.scheduleAutoHide();
    }
  }

  /** 格式化时间秒→mm:ss */
  private formatTime(seconds: number): string {
    const totalSeconds: number = Math.max(0, Math.floor(seconds));
    const m: number = Math.floor(totalSeconds / 60);
    const s: number = totalSeconds % 60;
    const mStr: string = m < 10 ? '0' + m.toString() : m.toString();
    const sStr: string = s < 10 ? '0' + s.toString() : s.toString();
    return mStr + ':' + sStr;
  }

  /** #154 播放完成回调：重置进度 + 显示重新播放按钮 + 常显控制层 */
  private onPlaybackFinish(): void {
    this.isPaused = true;
    this.isFinished = true;
    this.currentTime = 0;
    this.clearAutoHide();
    this.showControls = true;
  }

  /** #154 重新播放（从头开始）：seekTo(0) + start（数据源仍在，无需重设） */
  private replayFromStart(): void {
    if (this.isDestroyed || this.player === undefined) {
      return;
    }
    this.isFinished = false;
    this.currentTime = 0;
    this.isPaused = false;
    try {
      this.player.seekTo(0);
      this.player.start();
      this.scheduleAutoHide();
    } catch (e) {
      console.error(`[VideoPlayer] replay failed: ${(e as Error).message}`);
    }
  }

  /**
   * #154 错误重试：卸载错误占位 → view 重挂触发 onSurfaceCreated → 重新 setMediaSource。
   */
  private retryPlayback(): void {
    if (this.isDestroyed) {
      return;
    }
    if (this.retryCount >= MAX_RETRY) {
      return;
    }
    this.retryCount++;
    this.hasError = false;
    this.isBuffering = true;
    this.isFinished = false;
    this.currentTime = 0;
    this.duration = 0;
  }

  /** #153 进入全屏：横屏视频旋转横屏 + 隐藏系统栏 + 弹出覆盖层
   * 竖屏视频（videoWidth <= videoHeight）保持竖屏全屏，避免横屏后两边大量黑边 */
  private enterFullscreen(): void {
    if (this.isDestroyed || this.isFullscreen) {
      return;
    }
    // #154 进入全屏时重置完成状态
    this.isFinished = false;
    this.isFullscreen = true;
    // 仅横屏视频旋转横屏，竖屏视频保持竖屏全屏
    if (this.isLandscapeVideo()) {
      this.applyLandscapeOrientation();
    }
  }

  /** #153 退出全屏：恢复竖屏（仅横屏视频旋转过）+ 恢复系统栏 + 关闭覆盖层 */
  private exitFullscreen(): void {
    if (this.isDestroyed || !this.isFullscreen) {
      return;
    }
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
      const context: Context = this.getUIContext().getHostContext() as Context;
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
      const context: Context = this.getUIContext().getHostContext() as Context;
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
}

/**
 * 视频封面占位组件（性能优化：列表中懒创建 VideoPlayer）
 *
 * 问题背景：
 * 直接在列表项中渲染 VideoPlayer 会导致每个含视频回复都创建 VideoPlayer 实例，
 * 即使不播放也会产生重资源开销：
 * - ccplayer 场景：CcPlayer 初始化 AVPlayer + surface 管理
 * - bindContentCover 全屏覆盖层绑定
 * 滚动到视频回复时卡顿，多个视频回复累积卡顿严重
 *
 * 优化策略：
 * - 默认只渲染封面图 + 播放按钮（轻量 Image + SymbolGlyph）
 * - 点击播放按钮才 isActivated=true，用 VideoPlayer 替换占位（此时才创建 CcPlayer）
 * - @Monitor('videoUrl') 监听 URL 变化（@ReusableV2 PostItem 复用时触发），
 *   重置 isActivated=false，避免复用后旧激活状态错误保留
 * - P1 #3 #4：themeState/imageLoadType/isWifi 全部由父组件 @Param 传入，
 *   VideoPlayer 也改为 @Require @Param 链式接收，避免每次激活都 connect
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
  /** 主题状态（链式传给 VideoPlayer，避免 VideoPlayer 自己 connect） */
  @Require @Param themeState: ThemeState;

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
      // 点击播放后：渲染完整 VideoPlayer 组件（此时才创建 CcPlayer 等重资源）
      // themeState/imageLoadType/isWifi 链式传入，VideoPlayer 不再自己 connect
      VideoPlayer({
        videoUrl: this.videoUrl,
        coverUrl: this.coverUrl,
        videoWidth: this.videoWidth,
        videoHeight: this.videoHeight,
        themeState: this.themeState,
        imageLoadType: this.imageLoadType,
        isWifi: this.isWifi
      })
        .width('100%')
        .margin({ top: 10 })
    } else {
      // 默认：封面图 + 播放按钮（轻量，不创建 CcPlayer）
      Stack({ alignContent: Alignment.Center }) {
        Image(getDisplayCoverUrl(this.coverUrl, this.imageLoadType, this.isWifi))
          .objectFit(ImageFit.Cover)
          .width('100%')
          .aspectRatio(computeVideoAspectRatio(this.videoWidth, this.videoHeight))
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
}
