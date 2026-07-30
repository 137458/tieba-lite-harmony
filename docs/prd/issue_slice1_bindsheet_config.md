## Parent

PRD：帖子详情页回复输入交互重写（沉浸式 Sheet 优化）

## What to build

重写帖子详情页 ThreadPage 的回复框 bindSheet 配置：

1. 移除系统三件套 `title` / `dragBar` / `showClose`（这些占用了顶部约 56vp，视觉感强且与应用风格不统一）
2. `height` 从 `SheetSize.MEDIUM` 改为 `SheetSize.LARGE`（接近全屏，保留顶部约 80vp 空隙隐约可见原帖上下文）
3. 显式设置 `backgroundColor: $r('app.color.card_background')` 避免不同设备默认值差异
4. 保留 `keyboardAvoidMode: SheetKeyboardAvoidMode.TRANSLATE_AND_RESIZE`（键盘弹起时 sheet 上移+resize）
5. 保留 `onAppear` 中的 `requestFocus('replyTextArea')` 主动获焦逻辑

**注意**：此切片仅改 bindSheet 配置，不动 ReplyBox 内部布局。Slice 2 才会新增自定义顶栏替代系统三件套。本切片完成后视觉上 sheet 顶部会"无标题栏"（系统三件套移除，自定义顶栏还未加入），这是预期的过渡状态。

## Acceptance criteria

- [ ] ThreadPage 中 ReplyBox 的 bindSheet 配置移除 `title` / `dragBar: true` / `showClose: true`
- [ ] `height` 改为 `SheetSize.LARGE`
- [ ] 显式设置 `backgroundColor: $r('app.color.card_background')`
- [ ] 保留 `keyboardAvoidMode: SheetKeyboardAvoidMode.TRANSLATE_AND_RESIZE`
- [ ] 保留 `onAppear` 中的 `requestFocus('replyTextArea')` 主动获焦逻辑
- [ ] 编译通过：`hvigorw assembleHap` BUILD SUCCESSFUL
- [ ] 真机/模拟器验证：点击"写评论" → sheet 弹出接近全屏，顶部无系统标题栏/拖拽条/关闭按钮（顶部空白是过渡状态，Slice 2 补顶栏）

## Blocked by

None - can start immediately
