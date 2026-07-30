## Parent

#233

## What to build

修复 FavoritePage 热榜 Tab 的两个视觉问题：1) "话题榜"标题文字太靠边需要往右移；2) 深色模式下话题榜条目有一圈黑色遮罩。

具体行为：
- "话题榜"标题位置调整：HotTopicSection 的 Text 加 margin left 让标题往右移（与下方条目内容对齐，不再贴左边）。
- 深色模式黑色遮罩修复：排查 HotTopicItem 在深色模式下的实际背景色。当前 HotTopicItem 用 `backgroundColor($r('app.color.background'))`，父容器用 `backgroundColor($r('app.color.card_background'))`。在深色模式下，若 `background` 与 `card_background` 色值差异过大，或某层有未关闭的 border/shadow，会产生视觉上的"黑色遮罩"。
  - 修复方案：让 HotTopicItem 的背景色与父容器一致或协调，移除多余的 border/shadow 叠加。
  - 若根因是 Grid 父容器在深色模式下背景色显示异常，调整 Grid 或 ListItem 的背景色透明度。
- 验证修复在浅色模式和深色模式下都视觉协调。

## Acceptance criteria

- [ ] FavoritePage.ets 的 HotTopicSection "话题榜"标题往右移（margin left 增大，与下方条目对齐）
- [ ] 深色模式下 HotTopicItem 不再有黑色遮罩，背景色与父容器（card_background）协调
- [ ] 浅色模式下视觉保持不变或更协调
- [ ] 编译通过：`hvigorw assembleHap -p product=default -p buildMode=debug` BUILD SUCCESSFUL
- [ ] 真机验证（深色模式）：进入热榜 Tab → 话题榜条目无黑色遮罩
- [ ] 真机验证：标题位置往右移，不再贴左边

## Blocked by

None - can start immediately
