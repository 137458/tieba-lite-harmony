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

/**
 * 按 key 去重合并：从 incoming 中剔除 key 已存在于 existing 的项，保持 incoming 原有顺序
 * 用于列表 loadMore 追加时防止服务端重复返回（同 fid 帖子/吧）导致 LazyForEach key 冲突
 *
 * @param existing 已有列表（其 key 全部视为已存在）
 * @param incoming 待追加列表
 * @param keyOf 提取唯一 key（如 forum.fid）
 * @returns incoming 中 key 不与 existing/前序项重复的子集
 */
export function dedupeByKey<T>(existing: T[], incoming: T[], keyOf: (item: T) => number): T[] {
  const seen: Set<number> = new Set<number>();
  for (let i: number = 0; i < existing.length; i++) {
    seen.add(keyOf(existing[i]));
  }
  const result: T[] = [];
  for (let i: number = 0; i < incoming.length; i++) {
    const key: number = keyOf(incoming[i]);
    if (!seen.has(key)) {
      seen.add(key);
      result.push(incoming[i]);
    }
  }
  return result;
}
