// 状态栏高度工具（P1 重构）
// 提取各页面 aboutToAppear 中重复的 getWindowAvoidArea 逻辑，避免 8 处重复代码
// 默认值 36vp，获取失败时保留默认值并记录警告日志

import { UIContext, window } from '@kit.ArkUI';

/** 默认状态栏高度（vp），getWindowAvoidArea 失败时兜底 */
const DEFAULT_STATUS_BAR_HEIGHT: number = 36;

/**
 * 获取状态栏高度（vp），用于沉浸式避让。
 *
 * 使用调用方 UIContext 获取宿主 Context 和像素密度，避免依赖已弃用的全局
 * getContext/px2vp API。获取失败时返回默认值，调用方无需重复 try-catch。
 */
export async function getStatusBarHeight(uiContext: UIContext): Promise<number> {
  try {
    const hostContext: Context | undefined = uiContext.getHostContext();
    if (hostContext === undefined) {
      return DEFAULT_STATUS_BAR_HEIGHT;
    }
    const mainWindow: window.Window = await window.getLastWindow(hostContext);
    const avoidArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
    return uiContext.px2vp(avoidArea.topRect.height);
  } catch (err) {
    console.warn(`[StatusBarUtil] getStatusBarHeight failed: ${(err as Error).message || err}, fallback to ${DEFAULT_STATUS_BAR_HEIGHT}`);
    return DEFAULT_STATUS_BAR_HEIGHT;
  }
}
