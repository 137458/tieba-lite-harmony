export interface LoadingState {
  isLoading: boolean;
  isRefreshing: boolean;
  error: string;
}

export interface PaginationState<T> {
  dataList: T[];
  hasMore: boolean;
  currentPage: number;
}

export interface FetchDataResult<T> {
  list: T[];
  hasMore: boolean;
  currentPage: number;
}

/**
 * loadMore 去重 + 分页终止判定（issue #45）。
 *
 * 上游 API（如 getPersonalized）的 hasMore 通常由原始返回数量判定（>=rn 即 true），
 * 去重后即便新帖归零，hasMore 仍为 true，会导致 onReachEnd 持续触发空 loadMore，
 * 主页陷入无限加载循环。此处对齐原版 distinctById 的终止语义：一页全为旧帖即视为无更多新内容。
 *
 * @param existing 当前已加载列表（dataList）
 * @param incoming 本次 API 返回的列表
 * @param hasMore API 返回的原始 hasMore
 * @param keyOf 提取去重键（如 tid）
 * @returns 去重后的列表与修正后的 hasMore
 */
export function dedupByKey<T>(
  existing: T[],
  incoming: T[],
  hasMore: boolean,
  keyOf: (item: T) => number
): { list: T[]; hasMore: boolean } {
  if (existing.length === 0) {
    return { list: incoming, hasMore: hasMore };
  }
  const existingKeys: Set<number> = new Set<number>();
  for (let i = 0; i < existing.length; i++) {
    existingKeys.add(keyOf(existing[i]));
  }
  const deduped: T[] = [];
  for (let i = 0; i < incoming.length; i++) {
    if (!existingKeys.has(keyOf(incoming[i]))) {
      deduped.push(incoming[i]);
    }
  }
  // 全部重复时停止分页，根治 hasMore 恒 true 导致的空 loadMore 循环
  if (deduped.length === 0) {
    return { list: deduped, hasMore: false };
  }
  return { list: deduped, hasMore: hasMore };
}

export abstract class BaseViewModel<T> {
  protected state: LoadingState = {
    isLoading: false,
    isRefreshing: false,
    error: ''
  };

  protected paginationState: PaginationState<T> = {
    dataList: [],
    hasMore: true,
    currentPage: 1
  };

  protected abstract fetchData(page: number, isRefresh: boolean): Promise<FetchDataResult<T>>;

  async loadData(isRefresh: boolean = false): Promise<void> {
    // isRefresh 和 loadMore 都会检查 isLoading，避免并发
    if (this.state.isLoading || this.state.isRefreshing) {
      return;
    }

    if (isRefresh) {
      this.paginationState.currentPage = 1;
      this.state.isRefreshing = true;
      // isRefresh 期间也设 isLoading，防止 canLoadMore 返回 true 导致并发 loadMore
      this.state.isLoading = true;
    } else {
      this.state.isLoading = true;
    }

    this.state.error = '';

    try {
      const result = await this.fetchData(this.paginationState.currentPage, isRefresh);

      if (isRefresh) {
        this.paginationState.dataList = result.list;
      } else {
        this.paginationState.dataList = this.paginationState.dataList.concat(result.list);
      }

      this.paginationState.hasMore = result.hasMore;
      this.paginationState.currentPage = result.currentPage + 1;
    } catch (err) {
      const error = err as Error;
      // 输出错误日志便于诊断（之前静默吞错导致白屏无日志）
      console.error(`[BaseViewModel] loadData failed: ${error.message}`, err);
      this.state.error = error.message || '加载失败';
    } finally {
      this.state.isLoading = false;
      this.state.isRefreshing = false;
    }
  }

  canLoadMore(): boolean {
    // 同时检查 isRefreshing，防止刷新期间触发 loadMore
    return this.paginationState.hasMore && !this.state.isLoading && !this.state.isRefreshing;
  }

  get loadingState(): LoadingState {
    return this.state;
  }

  get paginationData(): PaginationState<T> {
    return this.paginationState;
  }
}
