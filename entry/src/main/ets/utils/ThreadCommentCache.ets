// 吧内帖子评论预览缓存（issue: 吧内帖子评论预览功能）
// FrsPage API 不返回楼层列表，需额外调用 PbPage API 获取前几楼回复
// 用全局 LRU 缓存避免重复请求，控制内存占用
//
// 设计：
// - 容量限制 50 个帖子的评论预览，超出淘汰最久未访问
// - 用 Set<number> 跟踪正在加载的 tid，避免重复请求
// - 用并发令牌限流（最大 MAX_CONCURRENT_FETCHES 路同时请求），避免列表滚动时
//   每张卡片同时发起 PbPage 请求造成网络/解析突发、页面卡顿
// - 失败静默处理，不阻塞 UI
//
// 性能优化说明（2026-09）：
// 原 ThreadCard 内联在 aboutToAppear/aboutToReuse 时对每张可见卡片直接发起
// TiebaAPI.getPosts，滚动时并发请求数不受限。现将获取逻辑收拢到本模块，
// 通过 pendingQueue + activeFetches 令牌桶排队，同一时刻最多 MAX_CONCURRENT_FETCHES
// 个请求在途，其余等待，缓解请求突发。
import { TiebaAPI } from '../api/TiebaAPI';
import { SubPostInfo } from '../model/ForumModels';

const CACHE_MAX_SIZE: number = 50;
// 每个帖子预览最多取几条楼中楼
const SUB_POST_PREVIEW_MAX: number = 3;
// 评论预览请求最大并发数（同时请求太多会加重网络/解析负载，页面滚动卡顿）
const MAX_CONCURRENT_FETCHES: number = 2;

// 模块级变量（ArkTS 禁止在静态方法中使用 this，改用模块级变量 + 独立函数）
const cache: Map<number, SubPostInfo[]> = new Map<number, SubPostInfo[]>();
const loadingTids: Set<number> = new Set<number>();
const listeners: Map<number, Array<(posts: SubPostInfo[]) => void>> =
  new Map<number, Array<(posts: SubPostInfo[]) => void>>();
// 并发限流状态
let activeFetches: number = 0;
const pendingQueue: number[] = [];

/**
 * 查询缓存命中
 * 命中时会刷新 LRU 顺序（先 delete 再 set 把元素移到 Map 末尾，Map 迭代顺序=插入顺序）
 */
export function getCachedCommentPreview(tid: number): SubPostInfo[] | undefined {
  const posts: SubPostInfo[] | undefined = cache.get(tid);
  if (posts !== undefined) {
    cache.delete(tid);
    cache.set(tid, posts);
  }
  return posts;
}

/**
 * 写入缓存，超出容量时淘汰最旧条目
 */
export function setCachedCommentPreview(tid: number, posts: SubPostInfo[]): void {
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
  const callbacks: Array<(posts: SubPostInfo[]) => void> | undefined = listeners.get(tid);
  if (callbacks !== undefined) {
    listeners.delete(tid);
    for (let i = 0; i < callbacks.length; i++) {
      callbacks[i](posts);
    }
  }
}

export function subscribeCommentPreview(tid: number, callback: (posts: SubPostInfo[]) => void): void {
  const callbacks: Array<(posts: SubPostInfo[]) => void> = listeners.get(tid) ?? [];
  callbacks.push(callback);
  listeners.set(tid, callbacks);
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
  listeners.delete(tid);
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
  listeners.clear();
  pendingQueue.length = 0;
  activeFetches = 0;
}

/**
 * 请求评论预览（带并发限流 + LRU 缓存 + 去重）
 *
 * 入口统一在这里路由：
 * - 缓存命中：立即回调返回缓存数据
 * - 已在加载中：订阅监听，等首次请求完成时统一回调（去重）
 * - 否则：入队待请求，由令牌桶并发限流依次发起
 *
 * @param tid      帖子 tid
 * @param onResult 结果回调（命中缓存时同步调用，否则在加载完成后回调）
 * @returns true=本次请求进入加载流程（订阅等待）；false=直接命中缓存返回
 */
export function requestCommentPreview(tid: number, onResult: (posts: SubPostInfo[]) => void): boolean {
  if (tid <= 0) {
    onResult([]);
    return false;
  }
  // 缓存命中直接返回
  const cached: SubPostInfo[] | undefined = getCachedCommentPreview(tid);
  if (cached !== undefined) {
    onResult(cached);
    return false;
  }
  // 已在加载中：订阅等待首个请求完成回调（去重，避免重复请求）
  if (isCommentPreviewLoading(tid)) {
    subscribeCommentPreview(tid, onResult);
    return true;
  }
  markCommentPreviewLoading(tid);
  // 发起者也订阅回调：否则完成/失败时不会回到发起方，卡片会一直处于加载态
  subscribeCommentPreview(tid, onResult);
  pendingQueue.push(tid);
  pumpCommentPreviewQueue();
  return true;
}

/**
 * 令牌桶：在并发额度内依次取出排队 tid 发起请求
 */
function pumpCommentPreviewQueue(): void {
  while (activeFetches < MAX_CONCURRENT_FETCHES && pendingQueue.length > 0) {
    const tid: number | undefined = pendingQueue.shift();
    if (tid === undefined) {
      break;
    }
    activeFetches++;
    fetchCommentPreview(tid).finally(() => {
      activeFetches--;
      pumpCommentPreviewQueue();
    });
  }
}

/**
 * 单个 tid 的评论预览请求 + 入缓存 + 通知订阅方
 */
async function fetchCommentPreview(tid: number): Promise<void> {
  try {
    const result = await TiebaAPI.getPosts({ threadId: tid, page: 1, onlyAuthor: false, sort: 0 });
    // 取前几楼（跳过楼主首楼，楼主首楼内容已在卡片摘要显示）
    const posts: SubPostInfo[] = [];
    for (let i = 0; i < result.posts.list.length; i++) {
      const post = result.posts.list[i];
      for (let j = 0; j < post.subPostList.length; j++) {
        posts.push(post.subPostList[j]);
      }
    }
    posts.sort((left: SubPostInfo, right: SubPostInfo) => {
      if (left.createTime !== right.createTime) {
        return right.createTime - left.createTime;
      }
      return right.spid - left.spid;
    });
    const preview: SubPostInfo[] = posts.slice(0, SUB_POST_PREVIEW_MAX);
    // setCachedCommentPreview 会同步通知所有订阅方
    setCachedCommentPreview(tid, preview);
  } catch (err) {
    // 失败静默处理：通知订阅方空数组，避免卡片一直停留在加载态
    console.warn(`[ThreadCommentCache] loadCommentPreview tid=${tid} failed: ${(err as Error).message}`);
    const callbacks: Array<(posts: SubPostInfo[]) => void> | undefined = listeners.get(tid);
    if (callbacks !== undefined) {
      listeners.delete(tid);
      for (let i = 0; i < callbacks.length; i++) {
        callbacks[i]([]);
      }
    }
  } finally {
    clearCommentPreviewLoading(tid);
  }
}