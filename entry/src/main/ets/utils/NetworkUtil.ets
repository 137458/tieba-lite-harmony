// 网络状态工具（图片加载设置 #77 切片1）
// 封装 @ohos.net.connection API，提供网络类型判断
// 用于 ImageLoadUtil.shouldLoad/shouldLoadOrigin 的 isWifi 参数
//
// 失败时返回 false（按移动网络处理，保守省流，避免误判 WiFi 导致超流量）
// 项目已在 module.json5 配置 ohos.permission.GET_NETWORK_INFO 权限

import connection from '@ohos.net.connection';

/**
 * 判断当前默认网络是否为 WiFi
 *
 * 实现：connection.getDefaultNet + getNetCapabilities，检查 bearerTypes 是否包含 BEARER_WIFI
 * - netHandle.netId === 0 表示无网络，按非 WiFi 处理
 * - bearerTypes 包含 BEARER_WIFI 即为 WiFi
 * - 任何异常（权限拒绝/系统服务异常）返回 false
 *
 * @returns true=当前为 WiFi 网络，false=非 WiFi 或获取失败
 */
export async function isWifi(): Promise<boolean> {
  try {
    const netHandle: connection.NetHandle = await connection.getDefaultNet();
    // netId 为 0 表示无网络，按非 WiFi 处理（保守省流）
    if (netHandle.netId === 0) {
      return false;
    }
    const netCapabilities: connection.NetCapabilities = await connection.getNetCapabilities(netHandle);
    const bearerTypes: connection.NetBearType[] = netCapabilities.bearerTypes;
    for (let i = 0; i < bearerTypes.length; i++) {
      if (bearerTypes[i] === connection.NetBearType.BEARER_WIFI) {
        return true;
      }
    }
    return false;
  } catch (err) {
    // 获取失败按非 WiFi 处理（保守省流，避免误判 WiFi 导致超流量）
    console.warn(`[NetworkUtil] isWifi failed: ${(err as Error).message || err}, fallback to false`);
    return false;
  }
}
