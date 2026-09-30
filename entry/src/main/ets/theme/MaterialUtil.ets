import { hdsMaterial } from '@kit.UIDesignKit';

/**
 * 沉浸光感材质常量与解析函数（自 AppStorageV2Models 迁出）
 * 模型层文件不应依赖 UI kit：AppStorageV2Models 位于 BaseViewModel 依赖链上，
 * hdsMaterial(@kit.UIDesignKit) 无法在本地单元测试环境解析，导致整条测试链编译失败
 */

/**
 * #201 沉浸光感材质类型常量（固定 IMMERSIVE，真正沉浸光感材质）
 * 之前用 ADAPTIVE（跟随系统策略）导致部分设备不渲染沉浸光感，用户反馈"很明显不是沉浸光感材质"
 * 全局所有 systemMaterialEffect 配置处统一使用 IMMERSIVE 类型
 */
export const MATERIAL_TYPE_IMMERSIVE: hdsMaterial.MaterialType = hdsMaterial.MaterialType.IMMERSIVE;

/**
 * #201 解析沉浸光感材质强度（从 MaterialLevelState 数字值 → hdsMaterial.MaterialLevel 枚举）
 * 共享函数，避免每个页面重复实现 resolveMaterialLevel 方法
 * @param level MaterialLevelState.value 数字值（0=EXQUISITE / 1=GENTLE / 2=SMOOTH / 10=ADAPTIVE）
 * @returns 对应的 hdsMaterial.MaterialLevel 枚举值
 */
export function resolveMaterialLevel(level: number): hdsMaterial.MaterialLevel {
  if (level === 0) {
    return hdsMaterial.MaterialLevel.EXQUISITE;
  }
  if (level === 1) {
    return hdsMaterial.MaterialLevel.GENTLE;
  }
  if (level === 2) {
    return hdsMaterial.MaterialLevel.SMOOTH;
  }
  return hdsMaterial.MaterialLevel.ADAPTIVE;
}
