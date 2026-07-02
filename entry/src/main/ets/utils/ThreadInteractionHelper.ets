// 帖子交互工具函数（issue #30）
// 提取 HomePage/ForumPage 的 handleAgree/handleDisagree 公共实现
// 乐观更新 + 调用 TiebaAPI + 失败 Toast 提示
// issue #31: 改为接收 CommonDataSource，靠 @Observed+@ObjectLink 自动局部刷新，无需 slice()
// issue #38: 抽取 handleThreadOp 消除 agree/disagree 重复代码

import { promptAction } from '@kit.ArkUI';
import { TiebaAPI } from '../api/TiebaAPI';
import { ThreadInfo } from '../model/ForumModels';
import { CommonDataSource } from './CommonDataSource';
import { getResourceString } from './ResourceUtil';

/**
 * 帖子赞/踩通用操作（主题帖 pid=0）
 * 乐观更新 + 失败回滚（对齐原 APP ConcernViewModel.kt:83-88）：
 * API 失败时回滚 isAgreed/agreeNum/isDisagreed/disagreeNum 到原值，保证 UI 与服务端一致
 *
 * ThreadInfo 已 @Observed，ThreadCard 用 @ObjectLink，
 * LazyForEach 传入的 item 与 dataSource 内部数组为同一引用，
 * 修改 target 字段会自动触发 ThreadCard 局部刷新，无需 notifyDataReload。
 *
 * @param dataSource 帖子数据源（getAllData 查找原对象）
 * @param thread 点击的帖子（ThreadCard 的 @ObjectLink 引用，tid 用于查找原对象）
 * @param isDisagreeOp true=踩操作，false=赞操作
 */
async function handleThreadOp(
  dataSource: CommonDataSource<ThreadInfo>,
  thread: ThreadInfo,
  isDisagreeOp: boolean
): Promise<void> {
  const target: ThreadInfo | undefined =
    dataSource.getAllData().find((t: ThreadInfo) => t.tid === thread.tid);
  if (!target) {
    return;
  }
  // 保存原状态用于失败回滚（对齐原 APP，避免 UI 与服务端状态分离）
  const prevIsAgreed: boolean = target.isAgreed;
  const prevAgreeNum: number = target.agreeNum;
  const prevIsDisagreed: boolean = target.isDisagreed;
  const prevDisagreeNum: number = target.disagreeNum;
  try {
    if (isDisagreeOp) {
      // 踩操作
      if (target.isDisagreed) {
        await TiebaAPI.undisagree(target.tid, 0, false);
        target.isDisagreed = false;
        target.disagreeNum = Math.max(0, target.disagreeNum - 1);
      } else {
        await TiebaAPI.disagree(target.tid, 0, false);
        target.isDisagreed = true;
        target.disagreeNum += 1;
      }
    } else {
      // 赞操作
      if (target.isAgreed) {
        await TiebaAPI.unagree(target.tid, 0, false);
        target.isAgreed = false;
        target.agreeNum = Math.max(0, target.agreeNum - 1);
      } else {
        await TiebaAPI.agree(target.tid, 0, false);
        target.isAgreed = true;
        target.agreeNum += 1;
      }
    }
    // @Observed + @ObjectLink 自动局部刷新，无需手动触发 reload
  } catch (err) {
    // 失败回滚到原状态（对齐原 APP，保证 UI 与服务端一致）
    target.isAgreed = prevIsAgreed;
    target.agreeNum = prevAgreeNum;
    target.isDisagreed = prevIsDisagreed;
    target.disagreeNum = prevDisagreeNum;
    promptAction.showToast({
      message: (err as Error).message || getResourceString($r('app.string.follow_operation_failed'))
    });
  }
}

/** 点赞/取消赞（主题帖 pid=0） */
export function handleThreadAgree(
  dataSource: CommonDataSource<ThreadInfo>,
  thread: ThreadInfo
): Promise<void> {
  return handleThreadOp(dataSource, thread, false);
}

/** 点踩/取消点踩（主题帖 pid=0） */
export function handleThreadDisagree(
  dataSource: CommonDataSource<ThreadInfo>,
  thread: ThreadInfo
): Promise<void> {
  return handleThreadOp(dataSource, thread, true);
}
