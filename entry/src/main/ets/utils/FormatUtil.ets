// 数字格式化工具函数
// 提取 HomePage.formatCount 与 ThreadPage.formatCount 的公共实现（消除重复）
// 中文计数单位（万/亿），防御 NaN/Infinity/负数（服务器脏数据）

/**
 * 数字格式化为中文计数单位（万/亿）
 * <1万：原数；1万~1亿：X.X万；>=1亿：X.X亿；整数时去掉小数部分
 * 防御 NaN/Infinity/负数，异常时统一返回 '0'
 *
 * @param count 原始数值（可能来自服务端脏数据）
 * @returns 格式化后的字符串（如 '328万'、'12.6亿'、'9527'、'0'）
 */
export function formatCount(count: number): string {
  // 防御 NaN/Infinity/负数（服务器脏数据），统一显示 0
  if (!Number.isFinite(count) || count < 0) {
    return '0';
  }
  if (count < 10000) {
    return count.toString();
  } else if (count < 100000000) {
    const wan: number = count / 10000;
    const wanStr: string = wan.toFixed(1);
    return wanStr.endsWith('.0') ? `${wanStr.substring(0, wanStr.length - 2)}万` : `${wanStr}万`;
  } else {
    const yi: number = count / 100000000;
    const yiStr: string = yi.toFixed(1);
    return yiStr.endsWith('.0') ? `${yiStr.substring(0, yiStr.length - 2)}亿` : `${yiStr}亿`;
  }
}
