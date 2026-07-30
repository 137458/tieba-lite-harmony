## Parent

#233

## What to build

把帖子详情页 titleBar "更多"按钮的菜单从底部 ActionSheet 改为锚点 bindMenu，从按钮下方右对齐展开（Placement.BottomRight），菜单项与之前完全一致。

具体行为：
- ThreadPage 的 `showMoreActionMenu()` 改为：在 titleBar menu 按钮上配置 `.bindMenu([...])`，placement 用 `Placement.BottomRight`（按钮下方右对齐，菜单往左展开，不超出屏幕右边）。
- 菜单项与原 showActionMenu 完全一致：收藏（带 ✓ 前缀标记已收藏）/ 分享 / 只看楼主（带 ✓）/ 排序 / 跳页 / 沉浸模式（带 ✓）。
- "排序"项点击后弹出二级菜单：正序 / 倒序 / 热门（带 ✓ 标记当前排序），可用 showActionMenu 二级弹窗或二级 bindMenu 实现。
- 保留 titleBar menu 按钮的沉浸光感材质（继承 titleBar systemMaterialEffect，materialType=IMMERSIVE）。
- 不为 Menu 弹出本身应用沉浸光感材质（MenuOptions API 无 systemMaterialEffect 字段，接受此限制）。

## Acceptance criteria

- [ ] ThreadPage.ets 的 showMoreActionMenu 改用 bindMenu 锚点弹出，不再用 promptAction.showActionMenu
- [ ] 菜单 placement 为 Placement.BottomRight，从按钮下方右对齐展开
- [ ] 6 项菜单功能完整：收藏 / 分享 / 只看楼主 / 排序 / 跳页 / 沉浸模式
- [ ] 收藏 / 只看楼主 / 沉浸模式 三项在已开启时显示 ✓ 前缀标记
- [ ] "排序"项点击后弹出二级菜单（正序/倒序/热门），当前排序显示 ✓ 标记
- [ ] titleBar menu 按钮保留沉浸光感材质（systemMaterialEffect IMMERSIVE）
- [ ] 编译通过：`hvigorw assembleHap -p product=default -p buildMode=debug` BUILD SUCCESSFUL
- [ ] 真机验证：点击 titleBar "更多"按钮 → 菜单从按钮下方右对齐展开（非底部 ActionSheet）→ 6 项功能可正常点击触发对应逻辑

## Blocked by

None - can start immediately
