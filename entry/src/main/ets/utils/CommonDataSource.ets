// 通用 IDataSource 实现（issue #31）
// 配合 LazyForEach 实现列表懒加载，cachedCount(5) 控制可视区域外缓存数量
// 用法：class ThreadDataSource extends CommonDataSource<ThreadInfo> { ... }
// 或直接实例化：new CommonDataSource<ThreadInfo>()

/**
 * IDataSource 通用实现
 * - setData 触发整体刷新（onDataReloaded）
 * - getAllData 返回内部数组引用，用于查找原对象（如点赞时用 tid 查找）
 * - 配合 @Observed/@ObjectLink 可实现局部刷新（子组件感知字段变化）
 */
export class CommonDataSource<T> implements IDataSource {
  private listeners: DataChangeListener[] = [];
  private dataArray: T[] = [];

  totalCount(): number {
    return this.dataArray.length;
  }

  getData(index: number): T {
    // 越界保护（issue #36）：LazyForEach 在 onDataReloaded 后可能用旧索引访问
    // 抛错会导致子组件渲染中断白屏，改为返回 dataArray 最后一项兜底
    // 并记录警告日志便于排查，保证渲染连续性
    if (index < 0 || index >= this.dataArray.length) {
      console.warn(`[CommonDataSource] getData index out of range: ${index}/${this.dataArray.length}, fallback to last`);
      if (this.dataArray.length > 0) {
        return this.dataArray[this.dataArray.length - 1];
      }
      // 空数组兜底（#87 P0）：totalCount=0 时 LazyForEach 不应调用 getData，
      // 此处属于上游 bug。抛错而非返回 undefined，避免下游解引用 NPE 静默失败，
      // 让上游调用链立即暴露问题便于排查
      throw new Error(`[CommonDataSource] getData called on empty array at index ${index}`);
    }
    return this.dataArray[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const pos: number = this.listeners.indexOf(listener);
    if (pos >= 0) {
      this.listeners.splice(pos, 1);
    }
  }

  /** 设置全部数据并触发整体刷新（用于首次加载/刷新） */
  setData(data: T[]): void {
    this.dataArray = data;
    this.notifyDataReload();
  }

  /**
   * 追加数据并通知 LazyForEach 增量更新（issue #39）
   * loadMore 场景调用，避免 setData 触发全量 reload 引起整列 diff
   * DataChangeListener.onDataAdd 仅通知新增区域，已渲染的 item 不重新构建
   */
  appendData(items: T[]): void {
    if (items.length === 0) {
      return;
    }
    const startIndex: number = this.dataArray.length;
    for (let i: number = 0; i < items.length; i++) {
      this.dataArray.push(items[i]);
    }
    this.listeners.forEach((listener: DataChangeListener) => {
      // onDataAdd 单条触发，循环通知每条新增
      for (let i: number = 0; i < items.length; i++) {
        listener.onDataAdd(startIndex + i);
      }
    });
  }

  /** 获取内部数组引用（用于查找原对象，如点赞时用 tid 查找） */
  getAllData(): T[] {
    return this.dataArray;
  }

  /**
   * #72 前置插入数据（加载上一页场景）
   * 将新数据插入到数组头部，并通知 LazyForEach 增量更新
   * 由于 LazyForEach 不支持 onDataAdd 在头部插入（索引会错乱），
   * 这里用 notifyDataReload 触发整体刷新，保证索引正确
   */
  prependData(items: T[]): void {
    if (items.length === 0) {
      return;
    }
    // 在数组头部插入新数据
    const newItems: T[] = items.slice();
    this.dataArray = newItems.concat(this.dataArray);
    // 头部插入会改变所有索引，必须用 onDataReloaded 触发整体刷新
    this.notifyDataReload();
  }

  /** 通知 LazyForEach 数据整体重载（按 key 比对复用缓存） */
  notifyDataReload(): void {
    this.listeners.forEach((listener: DataChangeListener) => {
      listener.onDataReloaded();
    });
  }
}
