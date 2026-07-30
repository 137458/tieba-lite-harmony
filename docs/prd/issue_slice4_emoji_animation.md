## Parent

PRD：帖子详情页回复输入交互重写（沉浸式 Sheet 优化）

## What to build

为 ReplyBox 组件的表情面板切换添加平滑过渡动画，消除当前的硬切换跳动：

1. 当前实现（ReplyBox.ets）：`if (this.showEmojiPanel) { this.EmojiPanel() }` 直接条件渲染，无动画
2. 改造：`animateTo({ duration: 200, curve: Curve.EaseInOut })` 包裹 `showEmojiPanel = !showEmojiPanel` 状态变化
3. 表情面板外层加 `Clip(true)` 避免动画过程中子元素溢出
4. 保留现有 `toggleEmojiPanel` 的键盘/表情互斥逻辑（打开表情前 clearFocus 收键盘，关闭表情后 requestFocus 弹键盘）
5. 互斥逻辑的 clearFocus/requestFocus 调用应放在 animateTo 外部或 .onFinish 回调中，避免动画期间焦点切换造成布局抖动

**关键约束**：
- ArkTS 的 `animateTo` 是 ArkUI 标准 API，全版本支持
- 动画 duration 不超过 300ms（避免拖沓感）
- 动画 curve 用 `Curve.EaseInOut`（进出都缓动）

## Acceptance criteria

- [ ] `toggleEmojiPanel` 方法中 `showEmojiPanel = !showEmojiPanel` 被 `animateTo({ duration: 200, curve: Curve.EaseInOut })` 包裹
- [ ] 表情面板外层加 `Clip(true)` 避免溢出
- [ ] `clearFocus` / `requestFocus` 调用放在 animateTo 外部，避免动画期间焦点切换
- [ ] 保留互斥逻辑：打开表情前 clearFocus 收键盘，关闭表情后 requestFocus 弹键盘
- [ ] 编译通过：`hvigorw assembleHap` BUILD SUCCESSFUL
- [ ] 真机/模拟器验证：点击表情按钮 → 表情面板平滑滑出（200ms） → TextArea 失焦 → 再次点击 → 表情面板平滑收起 → TextArea 获焦弹键盘

## Blocked by

None - can start immediately
