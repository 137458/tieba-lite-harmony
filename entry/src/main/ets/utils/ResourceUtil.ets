// 资源工具函数（issue #10）
// ArkTS 中 $r('app.string.xxx') 返回 Resource 对象，
// .toString() 继承自 Object.prototype.toString() 返回 "[object Object]"
// 通过应用启动时注入的 ResourceManager 同步读取实际字符串。

import { resourceManager } from '@kit.LocalizationKit';

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
    console.warn(`[ResourceUtil] resource manager unavailable, resourceId=${res.id}`);
    return '';
  }
  try {
    if (res.params && res.params.length > 0) {
      return manager.getStringSync(res.id, ...res.params);
    }
    return manager.getStringSync(res.id);
  } catch (err) {
    console.error(`[ResourceUtil] get string failed, resourceId=${res.id}, error=${(err as Error).message}`);
    return '';
  }
}
