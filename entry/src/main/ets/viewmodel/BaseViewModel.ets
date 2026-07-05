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

  // 最近一次 fetchData 返回的列表（issue #39）：
  // - isRefresh=true 时：全量数据
  // - isRefresh=false 时：本次新增的数据（用于 appendData 增量更新）
  protected lastFetchList: T[] = [];
  // 最近一次操作是否为刷新（issue #39）
  protected lastOpIsRefresh: boolean = false;

  protected abstract fetchData(page: number, isRefresh: boolean): Promise<FetchDataResult<T>>;

  async loadData(isRefresh: boolean = false): Promise<void> {
    // isRefresh 和 loadMore 都会检查 isLoading，避免并发
    if (this.state.isLoading || this.state.isRefreshing) {
      return;
    }

    // 保存刷新前的 currentPage，fetchData 抛错时回滚（P0 修复）：
    // 否则刷新失败后 currentPage 仍为 1，下次 loadMore 会用 page=1 拉取并 concat 到旧列表，造成数据重复
    const prevPage: number = this.paginationState.currentPage;

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
      const requestPage: number = this.paginationState.currentPage;
      const result = await this.fetchData(requestPage, isRefresh);

      if (isRefresh) {
        this.paginationState.dataList = result.list;
      } else {
        this.paginationState.dataList = this.paginationState.dataList.concat(result.list);
      }

      this.paginationState.hasMore = result.hasMore;
      // 不依赖服务器返回的 current_page（服务器可能返回 0 导致 proto3 省略字段，
      // PageData 默认值 1 会导致每次 loadMore 都计算 currentPage=2，反复请求第2页）
      // 改用客户端管理的页码：请求页 + 1
      this.paginationState.currentPage = requestPage + 1;

      // 记录本次新增数据，供调用方 appendData 使用（避免全量 setData）
      this.lastFetchList = result.list;
      this.lastOpIsRefresh = isRefresh;
    } catch (err) {
      const error = err as Error;
      // #87 P1：error.message 可能为 undefined（throw 非 Error 时），
      // 提取为局部变量并兜底，避免日志和 state.error 出现 "undefined" 字样
      const errMsg: string = error.message && error.message.length > 0 ? error.message : '加载失败';
      // 刷新/加载失败时回滚 currentPage，保证下次重试从正确页码拉取
      this.paginationState.currentPage = prevPage;
      // 输出错误日志便于诊断（之前静默吞错导致白屏无日志）
      console.error(`[BaseViewModel] loadData failed: ${errMsg}`);
      this.state.error = errMsg;
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

  /** 最近一次 fetchData 返回的新增列表（isRefresh=true 时为全量） */
  get lastAddedList(): T[] {
    return this.lastFetchList;
  }

  /** 最近一次操作是否为刷新 */
  get lastOpWasRefresh(): boolean {
    return this.lastOpIsRefresh;
  }
}
