// 资源工具函数（issue #10）
// ArkTS 中 $r('app.string.xxx') 返回 Resource 对象，
// .toString() 继承自 Object.prototype.toString() 返回 "[object Object]"
// 需通过 resourceManager.getStringSync 获取实际字符串

/**
 * 获取 Resource 资源对应的字符串
 * 必须在组件方法或生命周期内调用（依赖 getContext()）
 * 支持 $r('app.string.xxx', arg) 带格式化参数的资源
 *
 * @param res $r('app.string.xxx') 返回的 Resource 对象
 * @returns 资源字符串值
 */
export function getResourceString(res: Resource): string {
  // res.params 非空时为格式化资源（如 $r('app.string.age_years', '3')），需传参给 getStringSync
  if (res.params && res.params.length > 0) {
    // ArkTS 展开运算符仅支持展开数组到 rest 参数
    return getContext().resourceManager.getStringSync(res.id, ...res.params);
  }
  return getContext().resourceManager.getStringSync(res.id);
}
