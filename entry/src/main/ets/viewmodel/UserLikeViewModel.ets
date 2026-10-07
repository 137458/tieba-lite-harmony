// 关注 Tab（用户_like 流）ViewModel（M02 自 FavoritePage.ets 迁入，导出以便独立单测）
// 沿用 pageTag 游标分页（与 pn 数字分页的 ThreadStoreViewModel 不同构，评估后不合并）

import { TiebaAPI } from '../api/TiebaAPI';
import { ThreadInfo, UserLikeResult } from '../model/ForumModels';
import { BaseViewModel, FetchDataResult } from './BaseViewModel';

/**
 * 关注 Tab ViewModel（沿用 pageTag 游标分页）
 * - isRefresh=true: pageTag="" + loadType=1
 * - isRefresh=false: pageTag=nextPageTag + loadType=2
 */
export class UserLikeViewModel extends BaseViewModel<ThreadInfo> {
  private nextPageTag: string = '';

  protected async fetchData(page: number, isRefresh: boolean): Promise<FetchDataResult<ThreadInfo>> {
    const pageTag: string = isRefresh ? '' : this.nextPageTag;
    const loadType: number = isRefresh ? 1 : 2;
    const result: UserLikeResult = await TiebaAPI.getUserLikeFlow(pageTag, loadType);
    this.nextPageTag = result.pageTag;
    return {
      list: result.threadList,
      hasMore: result.hasMore,
      currentPage: page
    };
  }
}
