// 帖子交互工具函数（issue #30）
// 提取 HomePage/ForumPage 的 handleAgree/handleDisagree 公共实现
// 乐观更新 + 调用 TiebaAPI + 失败 Toast 提示
// issue #31: 改为接收 CommonDataSource，靠 @Observed+@ObjectLink 自动局部刷新，无需 slice()

import { promptAction } from '@kit.ArkUI';
import { TiebaAPI } from '../api/TiebaAPI';
import { ThreadInfo } from '../model/ForumModels';
import { CommonDataSource } from './CommonDataSource';
import { getResourceString } from './ResourceUtil';

/**
 * 点赞/取消赞（主题帖 pid=0）
 * 乐观更新：先修改本地状态，API 失败时 Toast 提示（不回滚，与原实现一致）
 *
 * ThreadInfo 已 @Observed，ThreadCard 用 @ObjectLink，
 * LazyForEach 传入的 item 与 dataSource 内部数组为同一引用，
 * 修改 target 字段会自动触发 ThreadCard 局部刷新，无需 notifyDataReload。
 *
 * @param dataSource 帖子数据源（getAllData 查找原对象）
 * @param thread 点击的帖子（ThreadCard 的 @ObjectLink 引用，tid 用于查找原对象）
 */
export async function handleThreadAgree(
  dataSource: CommonDataSource<ThreadInfo>,
  thread: ThreadInfo
): Promise<void> {
  const target: ThreadInfo | undefined =
    dataSource.getAllData().find((t: ThreadInfo) => t.tid === thread.tid);
  if (!target) {
    return;
  }
  try {
    if (target.isAgreed) {
      await TiebaAPI.unagree(target.tid, 0, false);
      target.isAgreed = false;
      target.agreeNum = Math.max(0, target.agreeNum - 1);
    } else {
      await TiebaAPI.agree(target.tid, 0, false);
      target.isAgreed = true;
      target.agreeNum += 1;
    }
    // @Observed + @ObjectLink 自动局部刷新，无需手动触发 reload
  } catch (err) {
    promptAction.showToast({
      message: (err as Error).message || getResourceString($r('app.string.follow_operation_failed'))
    });
  }
}

/**
 * 点踩/取消点踩（主题帖 pid=0）
 * 乐观更新：先修改本地状态，API 失败时 Toast 提示（不回滚，与原实现一致）
 *
 * @param dataSource 帖子数据源（getAllData 查找原对象）
 * @param thread 点击的帖子
 */
export async function handleThreadDisagree(
  dataSource: CommonDataSource<ThreadInfo>,
  thread: ThreadInfo
): Promise<void> {
  const target: ThreadInfo | undefined =
    dataSource.getAllData().find((t: ThreadInfo) => t.tid === thread.tid);
  if (!target) {
    return;
  }
  try {
    if (target.isDisagreed) {
      await TiebaAPI.undisagree(target.tid, 0, false);
      target.isDisagreed = false;
      target.disagreeNum = Math.max(0, target.disagreeNum - 1);
    } else {
      await TiebaAPI.disagree(target.tid, 0, false);
      target.isDisagreed = true;
      target.disagreeNum += 1;
    }
    // @Observed + @ObjectLink 自动局部刷新
  } catch (err) {
    promptAction.showToast({
      message: (err as Error).message || getResourceString($r('app.string.follow_operation_failed'))
    });
  }
}
