// 资源工具函数（issue #10）
// ArkTS 中 $r('app.string.xxx') 返回 Resource 对象，
// .toString() 继承自 Object.prototype.toString() 返回 "[object Object]"
// 通过应用启动时注入的 ResourceManager 同步读取实际字符串。

import { resourceManager } from '@kit.LocalizationKit';
import { Logger } from './Logger';

const TAG: string = 'ResourceUtil';

let applicationResourceManager: resourceManager.ResourceManager | null = null;

/**
 * 注入当前应用的资源管理器。
 * 只保存应用级 ResourceManager，不持有页面或 Ability 对象，适用于整个进程生命周期。
 */
export function setApplicationResourceManager(manager: resourceManager.ResourceManager): void {
  applicationResourceManager = manager;
}

/**
 * 获取 Resource 资源对应的字符串。
 * 资源系统尚未初始化或资源读取失败时返回稳定的空字符串，避免辅助 UI 影响主流程。
 *
 * @param res $r('app.string.xxx') 返回的 Resource 对象
 * @returns 资源字符串值
 */
export function getResourceString(res: Resource): string {
  const manager: resourceManager.ResourceManager | null = applicationResourceManager;
  if (manager === null) {
    Logger.warn(TAG, `[ResourceUtil] resource manager unavailable, resourceId=${res.id}`);
    return '';
  }
  try {
    if (res.params && res.params.length > 0) {
      return manager.getStringSync(res.id, ...res.params);
    }
    return manager.getStringSync(res.id);
  } catch (err) {
    Logger.error(TAG, `[ResourceUtil] get string failed, resourceId=${res.id}, error=${(err as Error).message}`);
    return '';
  }
}

/**
 * 提取异常的可展示消息（M24：统一 catch 点的错误消息提取写法）
 * #87 式双重兜底：非 Error 抛出物（string/number/null）无 message 属性，
 * 或 message 为空串时，返回调用方指定的兜底文案，保证错误对用户可见
 *
 * @param err catch 捕获的异常对象
 * @param fallback message 缺失/为空时的兜底文案（调用方解析既有资源串后传入）
 * @returns 异常消息或兜底文案
 */
export function getErrMessage(err: Error, fallback: string): string {
  if (err && err.message && err.message.length > 0) {
    return err.message;
  }
  return fallback;
}
