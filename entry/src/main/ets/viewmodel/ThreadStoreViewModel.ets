// 收藏帖子列表 ViewModel（M02 自 ThreadStorePage.ets 迁入，导出以便独立单测）
// 数据来源：TiebaAPI.getThreadStore（/c/f/post/threadstore）

import { TiebaAPI } from '../api/TiebaAPI';
import { ThreadInfo } from '../model/ForumModels';
import { BaseViewModel, FetchDataResult } from './BaseViewModel';

/**
 * 收藏列表 ViewModel
 * 调用 TiebaAPI.getThreadStore（/c/f/post/threadstore，offset 分页）
 */
export class ThreadStoreViewModel extends BaseViewModel<ThreadInfo> {
  // 每页收藏数（对齐原 app 默认 res_num）
  private static readonly PAGE_SIZE: number = 20;

  protected async fetchData(page: number, isRefresh: boolean): Promise<FetchDataResult<ThreadInfo>> {
    // BaseViewModel currentPage 从 1 开始，getThreadStore page 从 0 开始（对齐 Android），需 -1
    return await TiebaAPI.getThreadStore(page - 1, ThreadStoreViewModel.PAGE_SIZE);
  }
}
