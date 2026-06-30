import { preferences } from '@kit.ArkData';
import { Context } from '@kit.AbilityKit';

export class AppStorageManager {
  private static instance: AppStorageManager;
  private pref: preferences.Preferences | null = null;
  private context: Context | null = null;
  // 跟踪初始化进度的Promise，供ensureReady等待
  // 解决UIAbility生命周期async可能不被系统等待的竞态问题（P0修复）
  private readyPromise: Promise<void> | null = null;

  private constructor() {
  }

  static getInstance(): AppStorageManager {
    if (!AppStorageManager.instance) {
      AppStorageManager.instance = new AppStorageManager();
    }
    return AppStorageManager.instance;
  }

  async init(context: Context): Promise<void> {
    this.context = context;
    // 将真实初始化逻辑封装到Promise中，使ensureReady可等待
    this.readyPromise = this.doInit(context);
    await this.readyPromise;
  }

  private async doInit(context: Context): Promise<void> {
    this.pref = await preferences.getPreferences(context, 'tieba_settings');
  }

  /**
   * 等待初始化完成。页面aboutToAppear中读取preferences前必须调用此方法，
   * 防止EntryAbility.onCreate的async未被系统等待时出现pref为null的竞态
   */
  async ensureReady(): Promise<void> {
    if (this.readyPromise) {
      await this.readyPromise;
    }
  }

  async setString(key: string, value: string): Promise<void> {
    if (!this.pref) {
      throw new Error('AppStorage not initialized');
    }
    await this.pref.put(key, value);
    await this.pref.flush();
  }

  async getString(key: string, defaultValue: string = ''): Promise<string> {
    if (!this.pref) {
      return defaultValue;
    }
    return await this.pref.get(key, defaultValue) as string;
  }

  async setNumber(key: string, value: number): Promise<void> {
    if (!this.pref) {
      throw new Error('AppStorage not initialized');
    }
    await this.pref.put(key, value);
    await this.pref.flush();
  }

  async getNumber(key: string, defaultValue: number = 0): Promise<number> {
    if (!this.pref) {
      return defaultValue;
    }
    return await this.pref.get(key, defaultValue) as number;
  }

  async setBoolean(key: string, value: boolean): Promise<void> {
    if (!this.pref) {
      throw new Error('AppStorage not initialized');
    }
    await this.pref.put(key, value);
    await this.pref.flush();
  }

  async getBoolean(key: string, defaultValue: boolean = false): Promise<boolean> {
    if (!this.pref) {
      return defaultValue;
    }
    return await this.pref.get(key, defaultValue) as boolean;
  }

  async remove(key: string): Promise<void> {
    if (!this.pref) {
      throw new Error('AppStorage not initialized');
    }
    await this.pref.delete(key);
    await this.pref.flush();
  }

  async clear(): Promise<void> {
    if (!this.pref) {
      throw new Error('AppStorage not initialized');
    }
    await this.pref.clear();
    await this.pref.flush();
  }
}
