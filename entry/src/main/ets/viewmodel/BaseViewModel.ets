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
    if (this.state.isLoading) {
      return;
    }

    if (isRefresh) {
      this.paginationState.currentPage = 1;
      this.state.isRefreshing = true;
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
    return this.paginationState.hasMore && !this.state.isLoading;
  }

  get loadingState(): LoadingState {
    return this.state;
  }

  get paginationData(): PaginationState<T> {
    return this.paginationState;
  }
}
