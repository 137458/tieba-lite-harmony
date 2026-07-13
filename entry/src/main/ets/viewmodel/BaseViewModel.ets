import { getResourceString } from '../utils/ResourceUtil';
import { MemoryPressureState, MEMORY_LEVEL_NORMAL, MEMORY_LEVEL_CRITICAL, connectMemoryPressure } from '../model/AppStorageV2Models';
import { CommonDataSource } from '../utils/CommonDataSource';

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

@ObservedV2
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

  // #203 内存压力状态（AppStorageV2 全局共享，EntryAbility.onMemoryLevel 写入）
  // @Monitor 监听 level 变化，CRITICAL 时自动 clearCache
  @Trace memoryPressureState: MemoryPressureState = connectMemoryPressure();

  // #203 页面注入的 DataSource 引用，clearCache 时同步清空 dataArray
  private dataSource: CommonDataSource<T> | null = null;

  // #203 clearCache 时的 fetch 序号，用于 loadData 检测中断后丢弃结果
  // 每次 clearCache 递增，loadData 在 fetchData 返回后比对 epoch，
  // 不一致则说明 clearCache 在 fetchData 进行中触发过，丢弃结果避免脏数据写入
  private fetchEpoch: number = 0;

  protected abstract fetchData(page: number, isRefresh: boolean): Promise<FetchDataResult<T>>;

  /**
   * #203 系统内存压力变化回调
   * MEMORY_LEVEL_CRITICAL 时清空 dataList + DataSource.dataArray，释放内存
   * 清理后若有数据则自动 reload 首屏，避免用户回到前台看到空白列表
   * 处理后重置 level=NORMAL，使下次 CRITICAL 能再次触发 @Monitor
   * （@Monitor 仅在值变化时通知，CRITICAL→CRITICAL 不会触发）
   */
  @Monitor('memoryPressureState.level')
  onMemoryPressureChange(monitor: IMonitor): void {
    if (this.memoryPressureState.level === MEMORY_LEVEL_CRITICAL) {
      const hadData: boolean = this.paginationState.dataList.length > 0;
      this.clearCache();
      console.info('[BaseViewModel] memory pressure CRITICAL, cache cleared');
      // 清理前有数据则自动重新加载首屏，避免用户回到前台看到空白列表
      // hadData=false 时不需要加载（页面本来就空）
      if (hadData && this.dataSource !== null) {
        this.loadData(true).catch((err: Error) => {
          console.error(`[BaseViewModel] auto reload after clearCache failed: ${err.message}`);
        });
      }
      // 消费后重置 level，使下次 CRITICAL 能再次触发 @Monitor
      // 避免 level 持续 CRITICAL 时第二次内存压力事件被吞掉
      this.memoryPressureState.level = MEMORY_LEVEL_NORMAL;
    }
  }

  /**
   * #203 页面注入 DataSource 引用，供 clearCache 同步清空
   * 页面 aboutToAppear 中调用 this.viewModel.setDataSource(this.dataSource)
   * 页面 aboutToDisappear 中调用 this.viewModel.setDataSource(null) 清理引用
   */
  setDataSource(ds: CommonDataSource<T> | null): void {
    this.dataSource = ds;
  }

  /**
   * #203 清空缓存（dataList + DataSource.dataArray + 分页状态重置）
   * 由 onMemoryPressureChange(CRITICAL) 触发，或页面主动调用
   * 注意：会递增 fetchEpoch，正在进行的 loadData 完成后会检测到并丢弃结果
   */
  clearCache(): void {
    // 递增 epoch，正在进行的 loadData 完成后会检测到 epoch 变化并丢弃结果
    this.fetchEpoch++;
    this.paginationState.dataList = [];
    this.paginationState.hasMore = true;
    this.paginationState.currentPage = 1;
    this.lastFetchList = [];
    this.lastOpIsRefresh = false;
    this.state.error = '';
    // 重置加载标志，否则 isLoading 卡死导致 canLoadMore 永远 false
    this.state.isLoading = false;
    this.state.isRefreshing = false;
    if (this.dataSource !== null) {
      this.dataSource.setData([]);
    }
  }

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

    // #203 记录 fetch 开始时的 epoch，clearCache 会递增 epoch
    // fetchData 完成后若 epoch 不一致，说明 clearCache 在期间触发过，丢弃结果
    const epochAtStart: number = this.fetchEpoch;

    try {
      const requestPage: number = this.paginationState.currentPage;
      const result = await this.fetchData(requestPage, isRefresh);

      // clearCache 在 fetchData 进行中触发时丢弃结果，避免脏数据写入
      if (epochAtStart !== this.fetchEpoch) {
        console.info('[BaseViewModel] loadData result discarded due to clearCache');
        return;
      }

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
      // clearCache 已触发时跳过错误处理，避免覆盖 state.error 和回滚 currentPage
      if (epochAtStart !== this.fetchEpoch) {
        return;
      }
      const error = err as Error;
      // #87 P1：error.message 可能为 undefined（throw 非 Error 时），
      // 提取为局部变量并兜底，避免日志和 state.error 出现 "undefined" 字样
      const errMsg: string = error.message && error.message.length > 0 ? error.message : getResourceString($r('app.string.base_load_failed'));
      // 刷新/加载失败时回滚 currentPage，保证下次重试从正确页码拉取
      this.paginationState.currentPage = prevPage;
      // 失败时重置 lastFetchList 和 lastOpIsRefresh，避免 syncState 用上一次成功的旧值
      // 调用 appendData 导致数据重复（如 loadMore 成功后 refresh 失败，旧 lastFetchList
      // 会被再次 append 进 dataSource，造成列表项重复）
      this.lastFetchList = [];
      this.lastOpIsRefresh = false;
      // 输出错误日志便于诊断（之前静默吞错导致白屏无日志）
      console.error(`[BaseViewModel] loadData failed: ${errMsg}`);
      this.state.error = errMsg;
    } finally {
      // 仅当 epoch 未变时才重置 isLoading，避免 clearCache 已重置后被这里再次覆盖
      if (epochAtStart === this.fetchEpoch) {
        this.state.isLoading = false;
        this.state.isRefreshing = false;
      }
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
