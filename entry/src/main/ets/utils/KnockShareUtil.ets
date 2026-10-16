import { harmonyShare, systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { Logger } from './Logger';

const TAG: string = 'KnockShareUtil';

/**
 * 碰一碰分享能力封装（Share Kit harmonyShare）
 *
 * 用法：页面进入可分享界面时 registerKnockShare(provider) 注册监听，
 * 离开界面（含退至后台）时 unregisterKnockShare() 注销。
 * 用户在另一台「亮屏且解锁」的 HarmonyOS 设备上与顶部轻碰时，
 * 系统回调 knockShareCallback，由 provider 现算当前可分享数据并发送。
 *
 * 说明：碰一碰为系统能力（SystemCapability.Collaboration.HarmonyShare），
 * 从 HarmonyOS NEXT Release 起支持；旧设备由 isKnockShareSupported() 拦截，不注册即无副作用。
 */

/** 是否已注册碰一碰监听（防止重复注册） */
let knockRegistered: boolean = false;

/** 当前可分享数据的构造器（由注册页面提供）；返回 null 表示当前无可分享内容 */
let knockProvider: () => systemShare.SharedData | null = (): systemShare.SharedData | null => null;

/**
 * 碰一碰事件回调（模块级函数声明，引用稳定，供 off 精确注销）
 * 系统在轻碰事件触发时回调，此处构造分享数据并发送
 * @param target 分享发送对象，用于完成分享内容发送
 */
function knockShareCallback(target: harmonyShare.SharableTarget): void {
  if (!knockRegistered) {
    return;
  }
  let data: systemShare.SharedData | null = null;
  try {
    data = knockProvider();
  } catch (err) {
    Logger.error(TAG, `build share data failed: ${(err as Error).message}`);
  }
  if (data === null) {
    // 当前无可分享内容：通过碰一碰专有接口引导用户（如 tid 尚未就绪）
    target.clarifyNonShare({ message: '当前页面暂无可分享内容' }).catch((err: Error) => {
      Logger.error(TAG, `clarifyNonShare failed: ${err.message}`);
    });
    return;
  }
  target.share(data).catch((err: Error) => {
    Logger.error(TAG, `knock share failed: ${err.message}`);
  });
}

/**
 * 是否支持碰一碰分享能力
 * @returns true 表示当前系统/设备支持 SystemCapability.Collaboration.HarmonyShare
 */
export function isKnockShareSupported(): boolean {
  try {
    return canIUse('SystemCapability.Collaboration.HarmonyShare');
  } catch (err) {
    Logger.warn(TAG, `canIUse failed: ${(err as Error).message}`);
    return false;
  }
}

/**
 * 注册碰一碰事件监听
 * 重复调用会先注销旧监听，保证同一时刻只有一个活跃 provider
 * @param provider 分享数据构造器（触发碰一碰时调用，返回 null 表示当前无可分享内容）
 */
export function registerKnockShare(provider: () => systemShare.SharedData | null): void {
  if (!isKnockShareSupported()) {
    Logger.info(TAG, 'knock share unsupported, skip register');
    return;
  }
  // 先注销，避免重复注册导致一次轻碰触发多次分享
  unregisterKnockShare();
  knockProvider = provider;
  try {
    harmonyShare.on('knockShare', knockShareCallback);
    knockRegistered = true;
    Logger.info(TAG, 'knock share registered');
  } catch (err) {
    knockRegistered = false;
    Logger.error(TAG, `register knock share failed: ${(err as Error).message}`);
  }
}

/**
 * 注销碰一碰事件监听（离开可分享界面 / 退至后台时调用）
 */
export function unregisterKnockShare(): void {
  if (!knockRegistered) {
    return;
  }
  try {
    harmonyShare.off('knockShare', knockShareCallback);
  } catch (err) {
    Logger.error(TAG, `unregister knock share failed: ${(err as Error).message}`);
  }
  knockRegistered = false;
  knockProvider = (): systemShare.SharedData | null => null;
}

/**
 * 构造 HYPERLINK 类型分享数据（分享面板与碰一碰共用）
 * @param url 链接内容
 * @param title 标题（分享卡片）
 * @param description 描述（分享卡片）
 * @returns systemShare.SharedData
 */
export function buildHyperlinkShareData(url: string, title: string, description: string): systemShare.SharedData {
  return new systemShare.SharedData({
    utd: utd.UniformDataType.HYPERLINK,
    content: url,
    title: title,
    description: description
  });
}
