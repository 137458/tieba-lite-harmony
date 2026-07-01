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

  /** 设置全部数据并触发整体刷新 */
  setData(data: T[]): void {
    this.dataArray = data;
    this.notifyDataReload();
  }

  /** 获取内部数组引用（用于查找原对象，如点赞时用 tid 查找） */
  getAllData(): T[] {
    return this.dataArray;
  }

  /** 通知 LazyForEach 数据整体重载（按 key 比对复用缓存） */
  notifyDataReload(): void {
    this.listeners.forEach((listener: DataChangeListener) => {
      listener.onDataReloaded();
    });
  }
}
