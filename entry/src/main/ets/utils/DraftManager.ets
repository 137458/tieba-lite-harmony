// 发帖草稿管理（Phase 4 内容生产）
// 基于 AppStorageManager preferences 持久化，单草稿模型（对齐 Android DraftManager 简化形态）：
// 同一时间只保留最后一篇未发布的帖子草稿，按 JSON 序列化整体存取
// 自动保存策略由调用方（NewThreadPage）控制：输入变化防抖保存 + 页面离开时保存 + 发布成功后清除

import { AppStorageManager } from '../data/AppStorage';

const DRAFT_KEY: string = 'thread_draft';

/** 帖子草稿 */
export class ThreadDraft {
  /** 选中的吧 ID（0 = 未选择） */
  forumId: number = 0;
  /** 选中的吧名 */
  forumName: string = '';
  /** 标题 */
  title: string = '';
  /** 正文 */
  content: string = '';
  /** 保存时间戳（毫秒），用于展示"上次编辑"信息 */
  savedAt: number = 0;
}

export class DraftManager {
  /**
   * 保存草稿（整体覆盖式）
   * preferences 写失败不抛出（草稿丢失可接受，不应阻塞发帖主流程）
   */
  static async save(draft: ThreadDraft): Promise<void> {
    try {
      draft.savedAt = Date.now();
      await AppStorageManager.getInstance().setString(DRAFT_KEY, JSON.stringify(draft));
    } catch (err) {
      console.warn(`[DraftManager] save failed: ${(err as Error).message}`);
    }
  }

  /**
   * 读取草稿
   * @returns 草稿（forumId=0 表示无有效草稿）；损坏 JSON 返回空草稿
   */
  static async load(): Promise<ThreadDraft> {
    const empty: ThreadDraft = new ThreadDraft();
    try {
      const raw: string = await AppStorageManager.getInstance().getString(DRAFT_KEY, '');
      if (raw.length === 0) {
        return empty;
      }
      const parsed: ThreadDraft = JSON.parse(raw) as ThreadDraft;
      if (typeof parsed.title !== 'string' || typeof parsed.content !== 'string') {
        // 结构不完整（类型声明不保证运行时结构），按无草稿处理
        return empty;
      }
      return parsed;
    } catch (err) {
      console.warn(`[DraftManager] load failed: ${(err as Error).message}`);
      return empty;
    }
  }

  /** 清除草稿（发布成功后调用） */
  static async clear(): Promise<void> {
    try {
      await AppStorageManager.getInstance().remove(DRAFT_KEY);
    } catch (err) {
      console.warn(`[DraftManager] clear failed: ${(err as Error).message}`);
    }
  }
}
