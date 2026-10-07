import { AppStorageManager } from '../data/AppStorage';

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

const RECENT_FORUMS_KEY: string = 'recentForums';
const RECENT_FORUMS_LIMIT: number = 8;

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
    for (let i = 0; i < stored.length && i < limit; i++) {
      const item: StoredRecentForumItem = stored[i] as StoredRecentForumItem;
      if (item.name !== undefined && item.name.length > 0) {
        result.push(new RecentForumItem(item.fid, item.name, item.avatar === undefined ? '' : item.avatar));
      }
    }
  } catch (err) {
    return [];
  }
  return result;
}

export class RecentForumHistory {
  static async load(): Promise<RecentForumItem[]> {
    const storage: AppStorageManager = AppStorageManager.getInstance();
    const raw: string = await storage.getString(RECENT_FORUMS_KEY, '[]');
    // M32：解析/防御规则提取为 parseRecentForums 纯函数
    return parseRecentForums(raw, RECENT_FORUMS_LIMIT);
  }

  static async save(item: RecentForumItem): Promise<void> {
    const current: RecentForumItem[] = await RecentForumHistory.load();
    const next: RecentForumItem[] = [item];
    for (let i = 0; i < current.length; i++) {
      if (current[i].name !== item.name) {
        next.push(current[i]);
      }
      if (next.length >= RECENT_FORUMS_LIMIT) {
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
    const current: RecentForumItem[] = await RecentForumHistory.load();
    const next: RecentForumItem[] = [];
    for (let i = 0; i < current.length; i++) {
      if (current[i].name !== forumName) {
        next.push(current[i]);
      }
    }
    await AppStorageManager.getInstance().setString(RECENT_FORUMS_KEY, JSON.stringify(next));
  }
}
