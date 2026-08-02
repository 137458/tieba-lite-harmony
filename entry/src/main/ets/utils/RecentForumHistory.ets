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

export class RecentForumHistory {
  static async load(): Promise<RecentForumItem[]> {
    const storage: AppStorageManager = AppStorageManager.getInstance();
    const raw: string = await storage.getString(RECENT_FORUMS_KEY, '[]');
    try {
      const stored: Object[] = JSON.parse(raw) as Object[];
      const result: RecentForumItem[] = [];
      for (let i = 0; i < stored.length && i < RECENT_FORUMS_LIMIT; i++) {
        const item: StoredRecentForumItem = stored[i] as StoredRecentForumItem;
        if (item.name !== undefined && item.name.length > 0) {
          result.push(new RecentForumItem(item.fid, item.name, item.avatar === undefined ? '' : item.avatar));
        }
      }
      return result;
    } catch (err) {
      return [];
    }
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
