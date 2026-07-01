// 状态栏高度工具（P1 重构）
// 提取各页面 aboutToAppear 中重复的 getWindowAvoidArea 逻辑，避免 8 处重复代码
// 默认值 36vp，获取失败时保留默认值并记录警告日志

import { window } from '@kit.ArkUI';

/** 默认状态栏高度（vp），getWindowAvoidArea 失败时兜底 */
const DEFAULT_STATUS_BAR_HEIGHT: number = 36;

/**
 * 获取状态栏高度（vp），用于沉浸式避让
 *
 * 必须在组件生命周期内调用（依赖 context 的 windowStage）。
 * 获取失败时返回默认值 36，不抛错，调用方无需 try-catch。
 *
 * @param context 组件 getContext(this) 返回值
 * @returns 状态栏高度（vp）
 */
export async function getStatusBarHeight(context: Context): Promise<number> {
  try {
    const mainWindow = await window.getLastWindow(context);
    const avoidArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
    return px2vp(avoidArea.topRect.height);
  } catch (err) {
    // 获取失败保留默认值，记录警告日志便于排查
    console.warn(`[StatusBarUtil] getStatusBarHeight failed: ${(err as Error).message || err}, fallback to ${DEFAULT_STATUS_BAR_HEIGHT}`);
    return DEFAULT_STATUS_BAR_HEIGHT;
  }
}
