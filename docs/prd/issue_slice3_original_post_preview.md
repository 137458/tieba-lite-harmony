## Parent

PRD：帖子详情页回复输入交互重写（沉浸式 Sheet 优化）

## What to build

为 ReplyBox 新增原帖预览卡片，仅楼中楼回复场景显示，解决"看不到原帖上下文"痛点：

1. **扩展 ReplyTarget 参数类**：新增 `originalPost: PostInfo` 字段
   - ArkTS 不支持 `T | null` 联合类型，使用空对象标记（如 `new PostInfo()` 或 `postId === 0` 判断"无原帖"）
   - 普通回帖时该字段保持默认空对象，ReplyBox 内通过 `originalPost.postId > 0` 判断是否显示预览卡片
   - PostInfo 类型已在 `ForumModels.ets` 中定义，包含 author/floor/fragments/mediaList 等字段

2. **ThreadPage.openReplyBox 改造**：楼中楼场景下传入完整 post：
   ```
   target.originalPost = post;  // 楼中楼场景：传入被回复的帖子
   ```
   普通回帖场景保持空对象，不传原帖

3. **ReplyBox 新增 `@Param originalPost: PostInfo`**：接收父组件传入的原帖

4. **新增 `@Builder OriginalPostPreview()`**：
   - 整体：左右 16vp 边距，圆角 8，背景 `input_background`，padding 12vp，margin top 8vp
   - 头部 Row：
     - 左：头像 28vp（圆角 14），从 `originalPost.author.avatar` 加载
     - 中：用户名（`fontSize 13 / Medium / text_primary`）+ 楼层号 `#xxx`（`fontSize 12 / text_caption`）
     - 右：时间（`formatRelativeTime(originalPost.time)`，`fontSize 11 / text_caption`）
   - 正文预览：
     - 收起态：`maxLines(2)` + `textOverflow(Ellipsis)`，显示正文 fragments 拼接的前 2 行
     - 展开态：完整显示正文 fragments
   - 点击整个卡片切换展开/收起状态
   - **关键约束**：背景用 `input_background` 不用 `background`（深色模式 `#2C2C2E` 避免黑色遮罩，参考项目记忆 #237 修复）

5. **新增内部状态 `@Local isOriginalPostExpanded: boolean = false`**：原帖预览卡片展开/收起状态，默认 false（收起显示 2 行）

6. **展开/收起动画**：`animateTo({ duration: 200, curve: Curve.EaseInOut })` 包裹 `isOriginalPostExpanded = !isOriginalPostExpanded`

7. **正文 fragments 渲染**：复用 PostItem 的 fragments 渲染逻辑（文字 fragment + 表情 fragment + 图片 fragment）。如果 ReplyBox 中无现成的 fragment 渲染 Builder，可以简化为纯文本拼接（仅取 text 类型 fragment 拼接）

8. **顶部布局顺序更新**：
   ```
   TopBar (48vp)
   OriginalPostPreview (楼中楼场景显示，普通回帖不显示)
   SelectedImagesPanel (有图时显示)
   TextArea (layoutWeight 1)
   BottomToolbar (48vp，无发送按钮)
   EmojiPanel (showEmojiPanel=true 时显示)
   ```

## Acceptance criteria

- [ ] ReplyTarget 类新增 `originalPost: PostInfo` 字段
- [ ] ThreadPage.openReplyBox 楼中楼场景传入完整 post
- [ ] ReplyBox 新增 `@Param originalPost: PostInfo` 接收参数
- [ ] 新增 `@Builder OriginalPostPreview()` 渲染头像+楼层+用户名+时间+正文
- [ ] 卡片背景用 `input_background`（避免深色模式黑色遮罩）
- [ ] 卡片点击切换展开/收起，`animateTo` 200ms EaseInOut 过渡
- [ ] 收起态 `maxLines(2)` + Ellipsis，展开态完整显示
- [ ] 普通回帖（postId <= 0）不显示预览卡片
- [ ] 楼中楼回复（postId > 0）显示预览卡片
- [ ] 编译通过：`hvigorw assembleHap` BUILD SUCCESSFUL
- [ ] 真机/模拟器验证：
  - 普通回帖：sheet 弹出，无原帖预览卡片
  - 楼中楼回复：sheet 弹出，顶栏下方显示原帖预览卡片，可见头像+楼层+用户名+正文前 2 行
  - 点击预览卡片 → 卡片展开显示完整正文 → 再次点击 → 收起
  - 深色模式下卡片背景与父容器协调，无黑色遮罩感

## Blocked by

- #242（自定义顶栏 + 发送按钮移位，顶栏就位后才能在下方加预览卡片）
