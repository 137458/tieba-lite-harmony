// 吧内帖子评论预览缓存（issue: 吧内帖子评论预览功能）
// FrsPage API 不返回楼层列表，需额外调用 PbPage API 获取前几楼回复
// 用全局 LRU 缓存避免重复请求，控制内存占用
//
// 设计：
// - 容量限制 50 个帖子的评论预览，超出淘汰最久未访问
// - 用 Set<number> 跟踪正在加载的 tid，避免重复请求
// - 失败静默处理，不阻塞 UI
import { PostInfo } from '../model/ForumModels';

const CACHE_MAX_SIZE: number = 50;

// 模块级变量（ArkTS 禁止在静态方法中使用 this，改用模块级变量 + 独立函数）
const cache: Map<number, PostInfo[]> = new Map<number, PostInfo[]>();
const loadingTids: Set<number> = new Set<number>();

/**
 * 查询缓存命中
 * 命中时会刷新 LRU 顺序（先 delete 再 set 把元素移到 Map 末尾，Map 迭代顺序=插入顺序）
 */
export function getCachedCommentPreview(tid: number): PostInfo[] | undefined {
  const posts: PostInfo[] | undefined = cache.get(tid);
  if (posts !== undefined) {
    cache.delete(tid);
    cache.set(tid, posts);
  }
  return posts;
}

/**
 * 写入缓存，超出容量时淘汰最旧条目
 */
export function setCachedCommentPreview(tid: number, posts: PostInfo[]): void {
  if (cache.has(tid)) {
    cache.delete(tid);
  } else if (cache.size >= CACHE_MAX_SIZE) {
    // 淘汰 Map 第一个元素（最久未访问）
    const firstKey: number | undefined = cache.keys().next().value;
    if (firstKey !== undefined) {
      cache.delete(firstKey);
    }
  }
  cache.set(tid, posts);
}

/**
 * 标记 tid 正在加载（避免重复请求）
 */
export function markCommentPreviewLoading(tid: number): void {
  loadingTids.add(tid);
}

/**
 * 清除加载标记
 */
export function clearCommentPreviewLoading(tid: number): void {
  loadingTids.delete(tid);
}

/**
 * 查询 tid 是否正在加载
 */
export function isCommentPreviewLoading(tid: number): boolean {
  return loadingTids.has(tid);
}

/**
 * 清空缓存（切换吧或退出页面时可调用）
 */
export function clearCommentPreviewCache(): void {
  cache.clear();
  loadingTids.clear();
}
