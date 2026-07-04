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

/**
 * #81 注册网络变化监听，网络切换时回调最新 isWifi 状态
 *
 * 实现：connection.createNetConnection() 创建监听器，
 *   - on('netAvailable') 网络可用：重新查询 isWifi 并回调
 *   - on('netLost') 网络丢失：回调 false（无网络，按非 WiFi 处理）
 *   - on('netUnavailable') 网络不可用：回调 false
 *
 * 调用方：EntryAbility.onCreate 注册，onDestroy 注销
 *
 * @param onNetworkChange 网络变化回调，参数为最新 isWifi 状态
 * @returns NetConnection 对象（用于 unregister），失败返回 null
 */
export function registerNetworkChangeListener(
  onNetworkChange: (isWifi: boolean) => void
): connection.NetConnection | null {
  try {
    const conn: connection.NetConnection = connection.createNetConnection();
    // 网络可用：重新查询 isWifi（新网络可能是 WiFi 也可能是蜂窝）
    conn.on('netAvailable', () => {
      isWifi().then((wifi: boolean) => {
        onNetworkChange(wifi);
      }).catch((err: Error) => {
        console.warn(`[NetworkUtil] netAvailable isWifi check failed: ${err.message}`);
      });
    });
    // 网络丢失：回调 false
    conn.on('netLost', () => {
      onNetworkChange(false);
    });
    // 网络不可用：回调 false
    conn.on('netUnavailable', () => {
      onNetworkChange(false);
    });
    conn.register();
    return conn;
  } catch (err) {
    console.warn(`[NetworkUtil] registerNetworkChangeListener failed: ${(err as Error).message || err}`);
    return null;
  }
}

/**
 * #81 注销网络变化监听
 *
 * @param conn registerNetworkChangeListener 返回的 NetConnection 对象
 */
export function unregisterNetworkChangeListener(conn: connection.NetConnection | null): void {
  if (conn === null) {
    return;
  }
  try {
    conn.unregister();
  } catch (err) {
    console.warn(`[NetworkUtil] unregisterNetworkChangeListener failed: ${(err as Error).message || err}`);
  }
}
