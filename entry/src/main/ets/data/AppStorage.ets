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
    // #87 P1 防重复初始化：若已存在进行中的 readyPromise，复用之，避免并发 init
    // 重复调用 doInit 会导致 pref 实例被覆盖，期间 getString 等读取可能命中 null
    if (this.readyPromise !== null) {
      try {
        await this.readyPromise;
        return;
      } catch (e) {
        // 之前的初始化失败，清除引用允许重试
        this.readyPromise = null;
      }
    }
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
   *
   * 失败恢复机制：若 readyPromise 已 rejected，清除引用允许后续调用重试，
   * 避免 pref 永久不可用；当 context 已存在时自动尝试重新初始化
   */
  async ensureReady(): Promise<void> {
    if (this.readyPromise !== null) {
      try {
        await this.readyPromise;
        return;
      } catch (e) {
        // 失败时清除引用，允许后续调用重试，避免永久拒绝
        this.readyPromise = null;
        // ArkTS 严格模式禁止 throw e（e 是无类型 catch 变量），包装为 Error 抛出
        throw new Error((e as Error).message);
      }
    }
    // readyPromise 为 null：可能是尚未 init，也可能是之前 init 失败被清除
    // 若 context 已存在，自动尝试重新初始化
    if (this.context !== null) {
      this.readyPromise = this.doInit(this.context);
      try {
        await this.readyPromise;
      } catch (e) {
        this.readyPromise = null;
        throw new Error((e as Error).message);
      }
    }
  }

  async setString(key: string, value: string): Promise<void> {
    if (!this.pref) {
      // 与 setNumber/setBoolean/remove/clear 保持一致：未初始化抛错，避免调用方误以为已保存
      throw new Error('AppStorage not initialized');
    }
    await this.pref.put(key, value);
    await this.pref.flush();
  }

  async getString(key: string, defaultValue: string = ''): Promise<string> {
    if (!this.pref) {
      return defaultValue;
    }
    // #87 P1：preferences 在跨调用迁移/类型不一致场景下可能返回非 string，
    // 用 typeof 严格校验，类型不符回退 defaultValue 避免 as 断言后解引用崩溃
    // 注意：必须用 Object（大写）接收，小写 object 不接受 string 赋值
    const val: Object = await this.pref.get(key, defaultValue);
    if (typeof val === 'string') {
      return val as string;
    }
    return defaultValue;
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
    // #87 P1：跨调用类型不一致场景下可能返回 string/bool，as number 断言不报错但运行时为脏值
    // 注意：必须用 Object（大写）接收，小写 object 不接受 number 赋值
    const val: Object = await this.pref.get(key, defaultValue);
    if (typeof val === 'number') {
      return val as number;
    }
    return defaultValue;
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
    // #87 P1：跨调用类型不一致场景下可能返回 number/string，as boolean 断言后逻辑判断会出错
    // 注意：必须用 Object（大写）接收，小写 object 不接受 boolean 赋值
    const val: Object = await this.pref.get(key, defaultValue);
    if (typeof val === 'boolean') {
      return val as boolean;
    }
    return defaultValue;
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
