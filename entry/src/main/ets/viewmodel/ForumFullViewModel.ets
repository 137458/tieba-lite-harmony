// 完整版吧内页面 ViewModel（M02 自 ForumPageFull.ets 迁入，导出以便独立单测）
// 最新/精品走 getThreads（cmd=301001），通用 Tab 走 getGeneralTabList（cmd=309622）

import { TiebaAPI } from '../api/TiebaAPI';
import { ThreadInfo, ForumInfo, NavTabInfo, FrsTabInfo } from '../model/ForumModels';
import { FrsPageResult } from '../proto/FrsPageProto';
import { GeneralTabListResult } from '../proto/GeneralTabListProto';
import { BaseViewModel, FetchDataResult } from './BaseViewModel';

const SORT_REPLY: number = 6;   // 按回复时间（默认）

/**
 * 完整版吧内页面 ViewModel
 * 复用 ForumPage 的 ForumViewModel 结构，额外暴露 navTabInfo 给 UI 层渲染 Tab 栏
 */
export class ForumFullViewModel extends BaseViewModel<ThreadInfo> {
  private forumName: string = '';
  private sortType: number = SORT_REPLY;
  private isGood: boolean = false;
  // 吧信息（含 fid），从 getThreads 响应的 forum 字段提取
  private forumInfo: ForumInfo = new ForumInfo();
  // 吧内 Tab 信息（FrsPage field 37），用于渲染 Tab 栏
  private navTabInfo: NavTabInfo = new NavTabInfo();
  // 当前选中的通用 Tab（null=最新/精品，走 getThreads；非 null=通用 Tab，走 getGeneralTabList）
  // 对齐安卓版 ForumPage.kt：切换到通用 Tab 时使用独立接口 /c/f/frs/generalTabList?cmd=309622
  private currentTabInfo: FrsTabInfo | null = null;

  setForumName(name: string): void {
    this.forumName = name;
  }

  setSortType(type: number): void {
    this.sortType = type;
  }

  setIsGood(good: boolean): void {
    this.isGood = good;
  }

  /**
   * 设置当前 Tab
   * @param tab null=最新/精品（走 getThreads），非 null=通用 Tab（走 getGeneralTabList）
   */
  setCurrentTab(tab: FrsTabInfo | null): void {
    this.currentTabInfo = tab;
  }

  /** 当前是否在通用 Tab（用于 syncState 跳过 forumInfo/navTabInfo 同步，避免覆盖首次 FrsPage 数据） */
  isOnGeneralTab(): boolean {
    return this.currentTabInfo !== null;
  }

  getForumInfo(): ForumInfo {
    return this.forumInfo;
  }

  getNavTabInfo(): NavTabInfo {
    return this.navTabInfo;
  }

  protected async fetchData(page: number, isRefresh: boolean): Promise<FetchDataResult<ThreadInfo>> {
    if (this.currentTabInfo !== null) {
      // 通用 Tab：调用 /c/f/frs/generalTabList?cmd=309622（与 FrsPage 是独立接口）
      // lastThreadId：翻页时取上一页最后一帖 tid，首页传 0
      const lastThreadId: number = isRefresh ? 0 : this.getLastThreadId();
      const result: GeneralTabListResult = await TiebaAPI.getGeneralTabList(
        this.currentTabInfo,
        this.forumInfo.id,
        page,
        this.sortType,
        lastThreadId
      );
      // 通用 Tab 不更新 forumInfo / navTabInfo（已在首次 FrsPage 加载时填充）
      return result.threads;
    }
    // 普通 Tab（最新/精品）：调用 /c/f/frs/page?cmd=301001
    const result: FrsPageResult = await TiebaAPI.getThreads(
      this.forumName,
      page,
      this.sortType,
      this.isGood
    );
    this.forumInfo = result.forum;
    this.navTabInfo = result.navTabInfo;
    return result.threads;
  }

  /** 获取当前列表最后一帖 tid，用于通用 Tab 翻页 */
  private getLastThreadId(): number {
    const list: ThreadInfo[] = this.paginationState.dataList;
    if (list.length === 0) {
      return 0;
    }
    return list[list.length - 1].tid;
  }
}
