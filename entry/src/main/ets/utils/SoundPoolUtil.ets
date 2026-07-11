// #123 消息提示音工具类
// 封装 media.SoundPool API，实现一次加载、多次低时延播放
// 受设置开关控制（soundEnabled 偏好），关闭时不播放
//
// 音频资源：entry/src/main/resources/rawfile/message.ogg
//   - 用户需自行提供该文件（短促提示音，建议 <1秒，Ogg Vorbis 格式）
//   - 文件缺失时 init() 会 log 警告，不影响应用运行
//
// API：@kit.MediaKit 的 media.createSoundPool(maxStreams, audioRendererInfo)
//   - soundPool.load(fd, offset, length) 加载音频返回 soundId
//   - soundPool.play(soundId, playParameters, callback) 播放返回 streamId
//   - soundPool.on('loadComplete' | 'error') 监听事件
//   - soundPool.release() 释放资源

import { media } from '@kit.MediaKit';
import { audio } from '@kit.AudioKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppStorageManager } from '../data/AppStorage';

/** 提示音偏好 key */
const PREF_KEY_SOUND_ENABLED: string = 'soundEnabled';
/** rawfile 中提示音文件名（用户需提供此文件） */
const RAWFILE_NAME: string = 'message.ogg';

/**
 * 消息提示音工具类
 *
 * 使用方式：
 *   1. 应用启动时调用 SoundPoolUtil.init(context) 创建实例并加载音频
 *   2. 设置页 Toggle 调用 SoundPoolUtil.setEnabled()
 *   3. 消息场景调用 SoundPoolUtil.playMessage()
 *
 * 音频文件缺失时所有调用静默跳过，不抛异常
 */
export class SoundPoolUtil {
  /** SoundPool 实例（创建失败时为 null） */
  private static soundPool: media.SoundPool | null = null;
  /** 已加载的音频 soundId（加载完成回调中更新） */
  private static soundId: number = -1;
  /** 音频是否已加载完成（loadComplete 回调后置 true） */
  private static loaded: boolean = false;
  /** 是否启用提示音（内存缓存，避免每次播放都读 preferences） */
  private static enabled: boolean = true;
  /** 初始化进行中标记（防止重复初始化） */
  private static initializing: boolean = false;

  /**
   * 初始化：创建 SoundPool 实例 + 加载 rawfile 音频
   * 应在应用启动时（EntryAbility.onCreate 或 StartupTask）调用
   * @param context AbilityContext，用于获取 resourceManager
   */
  static async init(context: common.Context): Promise<void> {
    // 防止重复初始化
    if (SoundPoolUtil.initializing || SoundPoolUtil.soundPool !== null) {
      return;
    }
    SoundPoolUtil.initializing = true;
    try {
      // 1. 读取偏好
      const storage: AppStorageManager = AppStorageManager.getInstance();
      await storage.ensureReady();
      SoundPoolUtil.enabled = await storage.getBoolean(PREF_KEY_SOUND_ENABLED, true);

      // 2. 创建 SoundPool 实例（maxStreams=5，STREAM_USAGE_NOTIFICATION 通知音类型）
      const audioRendererInfo: audio.AudioRendererInfo = {
        usage: audio.StreamUsage.STREAM_USAGE_NOTIFICATION,
        rendererFlags: 0
      };
      SoundPoolUtil.soundPool = await media.createSoundPool(5, audioRendererInfo);

      // 3. 监听加载完成事件
      SoundPoolUtil.soundPool.on('loadComplete', (soundId: number) => {
        SoundPoolUtil.soundId = soundId;
        SoundPoolUtil.loaded = true;
        console.info('[SoundPoolUtil] audio loaded successfully');
      });
      SoundPoolUtil.soundPool.on('error', (err: BusinessError) => {
        console.error(`[SoundPoolUtil] soundPool error: ${err.code} ${err.message}`);
      });

      // 4. 加载 rawfile 音频（文件缺失会抛异常，catch 后不阻塞应用）
      const fd = await context.resourceManager.getRawFd(RAWFILE_NAME);
      SoundPoolUtil.soundId = await SoundPoolUtil.soundPool.load(fd.fd, fd.offset, fd.length);
      console.info(`[SoundPoolUtil] load called, soundId: ${SoundPoolUtil.soundId}`);
    } catch (err) {
      // 音频文件缺失或加载失败：置空 soundPool，所有播放调用将静默跳过
      console.warn(`[SoundPoolUtil] init failed (rawfile/${RAWFILE_NAME} may be missing): ${(err as Error).message}`);
      SoundPoolUtil.soundPool = null;
    } finally {
      SoundPoolUtil.initializing = false;
    }
  }

  /**
   * 设置开关状态（设置页 Toggle onChange 调用）
   * @param enabled true=开启 false=关闭
   */
  static async setEnabled(enabled: boolean): Promise<void> {
    SoundPoolUtil.enabled = enabled;
    try {
      await AppStorageManager.getInstance().setBoolean(PREF_KEY_SOUND_ENABLED, enabled);
    } catch (err) {
      console.error(`[SoundPoolUtil] setEnabled failed: ${(err as Error).message}`);
    }
  }

  /**
   * 获取当前开关状态
   * @returns true=开启 false=关闭
   */
  static isEnabled(): boolean {
    return SoundPoolUtil.enabled;
  }

  /**
   * 播放消息提示音
   * 关闭/未加载/未初始化时静默跳过，不抛异常
   */
  static playMessage(): void {
    if (!SoundPoolUtil.enabled) {
      return;
    }
    if (!SoundPoolUtil.loaded || SoundPoolUtil.soundPool === null || SoundPoolUtil.soundId < 0) {
      return;
    }
    try {
      const playParameters: media.PlayParameters = {
        loop: 0,           // 不循环
        rate: 1,           // 正常倍速
        leftVolume: 1.0,   // 左声道音量
        rightVolume: 1.0,  // 右声道音量
        priority: 0,       // 最低优先级
      };
      SoundPoolUtil.soundPool.play(SoundPoolUtil.soundId, playParameters, (err: BusinessError | null, streamId: number) => {
        if (err) {
          console.error(`[SoundPoolUtil] play failed: ${err.code} ${err.message}`);
        }
      });
    } catch (err) {
      console.error(`[SoundPoolUtil] playMessage failed: ${(err as Error).message}`);
    }
  }
}
