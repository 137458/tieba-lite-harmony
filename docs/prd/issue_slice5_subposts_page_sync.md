## Parent

PRD：帖子详情页回复输入交互重写（沉浸式 Sheet 优化）

## What to build

SubPostsPage（楼中楼页面）同步使用新的 ReplyBox 组件，保持楼中楼回复体验一致：

1. **检查 SubPostsPage.ets 当前是否使用 ReplyBox**：
   - 如果已使用：仅需调整 bindSheet 配置与 ThreadPage 一致（移除系统三件套、SheetSize.LARGE、显式 backgroundColor）
   - 如果未使用：需引入 ReplyBox 组件并替换原有的回复交互（参考 ThreadPage 实现）

2. **bindSheet 配置同步**：
   - 移除 `title` / `dragBar: true` / `showClose: true`
   - `height` 改为 `SheetSize.LARGE`
   - 显式设置 `backgroundColor: $r('app.color.card_background')`
   - 保留 `keyboardAvoidMode: SheetKeyboardAvoidMode.TRANSLATE_AND_RESIZE`
   - 保留 `onAppear` 的 `requestFocus('replyTextArea')` 主动获焦逻辑

3. **openReplyBox 调用同步**：
   - 楼中楼回复时传入完整 `originalPost` 参数
   - SubPostsPage 的楼中楼回复场景下，`originalPost` 应为被回复的楼中楼帖子

4. **体验一致性验证**：
   - 从 ThreadPage 进入楼中楼回复 → 体验与 ThreadPage 一致
   - 顶栏 / 原帖预览卡片 / 表情动画 / 发送按钮位置等全部一致

## Acceptance criteria

- [ ] SubPostsPage 的 bindSheet 配置与 ThreadPage 一致（无系统三件套、SheetSize.LARGE、显式 backgroundColor）
- [ ] SubPostsPage.openReplyBox 楼中楼场景传入 originalPost
- [ ] 编译通过：`hvigorw assembleHap` BUILD SUCCESSFUL
- [ ] 真机/模拟器验证：
  - 在 SubPostsPage 点击某楼中楼的"回复" → sheet 弹出，体验与 ThreadPage 一致
  - 顶栏显示"回复 @用户名"
  - 原帖预览卡片显示被回复的楼中楼内容
  - 表情面板切换有动画
  - 发送按钮位置在顶栏右侧

## Blocked by

- #240（bindSheet 配置精简）
- #241（表情面板切换动画）
- #242（自定义顶栏 + 发送按钮移位）
- #243（原帖预览卡片）
