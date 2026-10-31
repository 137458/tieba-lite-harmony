import { AppStorageManager } from '../data/AppStorage';
import { StringPrefs } from '../data/PreferenceKeys';

export class RecentForumItem {
  fid: number = 0;
  name: string = '';
  avatar: string = '';

  constructor(fid: number, name: string, avatar: string) {
    this.fid = fid;
    this.name = name;
    this.avatar = avatar;
  }
}

class StoredRecentForumItem {
  fid: number = 0;
  name: string = '';
  avatar: string = '';
}

const RECENT_FORUMS_KEY: string = StringPrefs.RECENT_FORUMS.key;
/** 默认展示数量上限（收起/滚动模式） */
export const RECENT_FORUMS_DEFAULT_LIMIT: number = 8;
/** 持久化存储深度上限（避免过滤已关注贴吧时由于全被已关注覆盖而无剩余贴吧） */
export const RECENT_FORUMS_MAX_STORED: number = 32;

/**
 * 最近浏览列表 JSON 解析纯函数（M32：损坏数据防御规则独立于 preferences，可确定性测试）
 * 规则：JSON.parse 抛错（损坏 JSON）→ 空数组；name 空串/缺失项过滤；limit 截断；
 * avatar 缺失兜底空串
 *
 * @param raw 持久化的列表 JSON 串
 * @param limit 列表上限
 * @returns 解析结果（损坏数据返回空数组）
 */
export function parseRecentForums(raw: string, limit: number): RecentForumItem[] {
  const result: RecentForumItem[] = [];
  try {
    const stored: Object[] = JSON.parse(raw) as Object[];
    for (let i = 0; i < stored.length; i++) {
      const item: StoredRecentForumItem = stored[i] as StoredRecentForumItem;
      if (item.name !== undefined && item.name.length > 0) {
        result.push(new RecentForumItem(item.fid, item.name, item.avatar === undefined ? '' : item.avatar));
        if (limit > 0 && result.length >= limit) {
          break;
        }
      }
    }
  } catch (err) {
    return [];
  }
  return result;
}

/**
 * 根据是否过滤已关注贴吧以及限制数量筛选最近浏览列表（#295 纯函数，易于单元测试）
 * @param items 最近浏览全量列表
 * @param followedNames 已关注贴吧名称集合（Set<string> 或 string[]）
 * @param filterFollowed 是否过滤已关注贴吧
 * @param limit 返回条数上限（小于等于0时不截断）
 */
export function filterRecentForums(
  items: RecentForumItem[],
  followedNames: Set<string> | string[],
  filterFollowed: boolean,
  limit: number = RECENT_FORUMS_DEFAULT_LIMIT
): RecentForumItem[] {
  if (!items || items.length === 0) {
    return [];
  }
  let filtered: RecentForumItem[] = items;
  if (filterFollowed) {
    const set: Set<string> = followedNames instanceof Set ? followedNames : new Set<string>(followedNames);
    filtered = items.filter((item: RecentForumItem) => !set.has(item.name));
  }
  if (limit > 0 && filtered.length > limit) {
    return filtered.slice(0, limit);
  }
  return filtered;
}

export class RecentForumHistory {
  static async load(limit: number = RECENT_FORUMS_MAX_STORED): Promise<RecentForumItem[]> {
    const storage: AppStorageManager = AppStorageManager.getInstance();
    const raw: string = await storage.getString(RECENT_FORUMS_KEY, '[]');
    // M32：解析/防御规则提取为 parseRecentForums 纯函数
    return parseRecentForums(raw, limit);
  }

  static async save(item: RecentForumItem): Promise<void> {
    const current: RecentForumItem[] = await RecentForumHistory.load(RECENT_FORUMS_MAX_STORED);
    const next: RecentForumItem[] = [item];
    for (let i = 0; i < current.length; i++) {
      if (current[i].name !== item.name) {
        next.push(current[i]);
      }
      if (next.length >= RECENT_FORUMS_MAX_STORED) {
        break;
      }
    }
    await AppStorageManager.getInstance().setString(RECENT_FORUMS_KEY, JSON.stringify(next));
  }

  /**
   * 删除指定贴吧的最近浏览记录
   * @param forumName 贴吧名
   */
  static async remove(forumName: string): Promise<void> {
    const current: RecentForumItem[] = await RecentForumHistory.load(RECENT_FORUMS_MAX_STORED);
    const next: RecentForumItem[] = [];
    for (let i = 0; i < current.length; i++) {
      if (current[i].name !== forumName) {
        next.push(current[i]);
      }
    }
    await AppStorageManager.getInstance().setString(RECENT_FORUMS_KEY, JSON.stringify(next));
  }
}
