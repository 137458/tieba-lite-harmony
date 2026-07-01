// 时间格式化工具函数（issue #28）
// 提取 ThreadCard.formatTime 与 SearchPage.formatTime 的公共实现
// 相对时间格式化：刚刚 / X 分钟前 / X 小时前 / X 天前 / YYYY-MM-DD

import { getResourceString } from './ResourceUtil';

/**
 * 格式化相对时间
 * 必须在组件 build() 或生命周期内调用（依赖 getContext() 解析 $r 资源）
 *
 * @param timestamp Unix 时间戳（秒）
 * @returns 格式化后的时间字符串；timestamp <= 0 时返回空串
 */
export function formatRelativeTime(timestamp: number): string {
  if (timestamp <= 0) {
    return '';
  }

  const now: number = Date.now() / 1000;
  const diff: number = now - timestamp;

  if (diff < 60) {
    return getResourceString($r('app.string.just_now'));
  } else if (diff < 3600) {
    return Math.floor(diff / 60) + getResourceString($r('app.string.minutes_ago'));
  } else if (diff < 86400) {
    return Math.floor(diff / 3600) + getResourceString($r('app.string.hours_ago'));
  } else if (diff < 604800) {
    return Math.floor(diff / 86400) + getResourceString($r('app.string.days_ago'));
  } else {
    const date = new Date(timestamp * 1000);
    return `${date.getFullYear()}-${(date.getMonth() + 1).toString().padStart(2, '0')}-${date.getDate().toString().padStart(2, '0')}`;
  }
}
