// 资源工具函数（issue #10）
// ArkTS 中 $r('app.string.xxx') 返回 Resource 对象，
// .toString() 继承自 Object.prototype.toString() 返回 "[object Object]"
// 需通过 resourceManager.getStringSync 获取实际字符串

/**
 * 获取 Resource 资源对应的字符串
 * 必须在组件方法或生命周期内调用（依赖 getContext()）
 *
 * @param res $r('app.string.xxx') 返回的 Resource 对象
 * @returns 资源字符串值
 */
export function getResourceString(res: Resource): string {
  return getContext().resourceManager.getStringSync(res.id);
}
