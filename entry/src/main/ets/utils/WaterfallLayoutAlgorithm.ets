/**
 * 瀑布流布局算法（#117 首页瀑布流模式）
 * 基于 HarmonyOS DynamicLayout + CustomLayoutAlgorithm 实现
 * 参考：references/harmonyos/guide-snippets-master/ArkUISample/DynamicLayout/.../WaterFlowLayout.ets
 *
 * 算法：将子组件按序分配到当前高度最小的列，实现瀑布流效果
 * 用于首页关注吧列表的瀑布流展示模式
 */

import { CustomLayoutAlgorithm, FrameNode, LayoutConstraint, Position } from '@kit.ArkUI';

/**
 * 瀑布流布局算法
 * 将子组件分配到 N 列中，每次选择当前累计高度最小的列放置
 */
export class WaterfallLayoutAlgorithm extends CustomLayoutAlgorithm {
  /** 列数 */
  private columnCount: number = 2;
  /** 列间距 */
  private columnGap: number = 12;
  /** 行间距 */
  private rowGap: number = 12;

  constructor(columnCount: number = 2, columnGap: number = 12, rowGap: number = 12) {
    super();
    this.columnCount = columnCount;
    this.columnGap = columnGap;
    this.rowGap = rowGap;
  }

  onMeasure(self: FrameNode, constraint: LayoutConstraint): void {
    const childCount: number = self.getChildrenCount();
    if (childCount === 0) {
      self.setMeasuredSize({ width: constraint.maxSize.width, height: 0 });
      return;
    }

    const columnWidth: number = (constraint.maxSize.width - (this.columnCount - 1) * this.columnGap) / this.columnCount;
    // 记录每列当前累计高度
    const columnHeights: number[] = new Array<number>(this.columnCount).fill(0);

    for (let i = 0; i < childCount; i++) {
      const child: FrameNode | null = self.getChild(i);
      if (child !== null) {
        // 固定子组件宽度为列宽，高度无上限（让子组件自行测量）
        const childConstraint: LayoutConstraint = {
          maxSize: {
            width: columnWidth,
            height: constraint.maxSize.height
          },
          minSize: {
            width: columnWidth,
            height: 0
          },
          percentReference: constraint.percentReference
        };
        child.measure(childConstraint);
        // 找到当前高度最小的列
        const minColumn: number = this.findMinIndex(columnHeights);
        columnHeights[minColumn] += child.getMeasuredSize().height + this.rowGap;
      }
    }

    // 总高度 = 最高列的高度
    const maxHeight: number = Math.max(...columnHeights);
    self.setMeasuredSize({
      width: constraint.maxSize.width,
      height: maxHeight > 0 ? maxHeight : 0
    });
  }

  onLayout(self: FrameNode, position: Position): void {
    const childCount: number = self.getChildrenCount();
    if (childCount === 0) {
      self.setLayoutPosition(position);
      return;
    }

    const measuredSize = self.getMeasuredSize();
    const columnWidth: number = (measuredSize.width - (this.columnCount - 1) * this.columnGap) / this.columnCount;
    // 记录每列当前 Y 坐标
    const columnYs: number[] = new Array<number>(this.columnCount).fill(0);

    for (let i = 0; i < childCount; i++) {
      const child: FrameNode | null = self.getChild(i);
      if (child !== null) {
        const childSize = child.getMeasuredSize();
        // 找到当前 Y 坐标最小的列
        const minColumn: number = this.findMinIndex(columnYs);
        const x: number = minColumn * (columnWidth + this.columnGap);
        const y: number = columnYs[minColumn];
        child.layout({ x, y });
        columnYs[minColumn] += childSize.height + this.rowGap;
      }
    }
    self.setLayoutPosition(position);
  }

  /**
   * 查找数组中最小值的索引
   */
  private findMinIndex(arr: number[]): number {
    let minIdx: number = 0;
    let minVal: number = arr[0];
    for (let j = 1; j < arr.length; j++) {
      if (arr[j] < minVal) {
        minVal = arr[j];
        minIdx = j;
      }
    }
    return minIdx;
  }
}