// 全局日志门面（H15：统一 console.* 与 hilog 双轨制）
// console.* 无 domain/tag，真机 hdc hilog 排障时无法过滤，核心协议层关键日志
// 混在海量 JSAPP 输出中；本门面提供独立 domain + 模块 TAG + 级别路由。
import { hilog } from '@kit.PerformanceAnalysisKit';

/** 全局日志独立 domain（与模板遗留 0x0000 区分，真机过滤：hdc shell hilog | grep 0xC001） */
export const LOG_DOMAIN: number = 0xC001;

/**
 * 日志门面：调用方传模块 TAG 与模板字符串，消息整体以 %{public}s 单参输出。
 * 单参封装保证调用方模板串中的 % 字符不会破坏 hilog 格式解析，
 * 输出可见性与原 console 行为一致（console 输出同样以 public 落 hilog）。
 * 约束：不得输出凭证明文（BDUSS/STOKEN 等），由调用方模板串保证。
 */
export class Logger {
  static info(tag: string, msg: string): void {
    hilog.info(LOG_DOMAIN, tag, '%{public}s', msg);
  }

  static warn(tag: string, msg: string): void {
    hilog.warn(LOG_DOMAIN, tag, '%{public}s', msg);
  }

  static error(tag: string, msg: string): void {
    hilog.error(LOG_DOMAIN, tag, '%{public}s', msg);
  }
}
