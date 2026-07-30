## Parent

PRD：帖子详情页回复输入交互重写（沉浸式 Sheet 优化）

## What to build

为 ReplyBox 新增自定义顶栏，并将发送按钮从底部工具栏移到顶栏右侧：

1. 新增 `@Builder TopBar()`：
   - 高度 48vp，背景 `card_background`，底部 0.5vp divider 分隔线
   - 左侧：关闭按钮（`ic_close` 图标 24vp + padding 8vp），点击调 `onClose` 回调关闭 sheet
   - 中间：标题文字（`fontSize 16 / FontWeight.Medium`）
     - 普通回帖（postId <= 0）："回复主题"
     - 楼中楼回复（postId > 0）："回复 @用户名"
   - 右侧：发送按钮（`Text` 显示"发送"/"发送中"/"上传图片中"），点击调 `onSend`
     - 字号 15，字重 600
     - 颜色：默认主题色 `themeState.primary`；上传中/发送中/空内容时置灰 `text_caption`
     - padding：{ left: 12, right: 12, top: 6, bottom: 6 }
     - 禁用条件：`isUploading || isSending || (content.trim().length === 0 && selectedImages.length === 0)`

2. 底部工具栏精简：
   - 移除底部工具栏右侧的"发送按钮"
   - 保留：图片按钮 / 表情按钮 / 字数提示 / (楼中楼提示标签) / (原图开关)
   - 高度保持 48vp
   - 字数提示位置调整：因发送按钮移走，字数提示可右对齐或居中

3. 顶部布局顺序变为：
   ```
   TopBar (48vp)
   SelectedImagesPanel (有图时显示)
   TextArea (layoutWeight 1)
   BottomToolbar (48vp，无发送按钮)
   EmojiPanel (showEmojiPanel=true 时显示)
   ```

4. 资源引用：标题文案复用现有 `app.string.reply_thread_title` / `app.string.reply_subpost_title`（与原 bindSheet title 一致）。状态文案复用 `app.string.reply_send` / `app.string.reply_sending` / `app.string.reply_uploading_image`

## Acceptance criteria

- [ ] ReplyBox 新增 `@Builder TopBar()`，包含关闭按钮 + 标题 + 发送按钮
- [ ] 关闭按钮点击触发 `onClose` 回调
- [ ] 标题文案：普通回帖显示"回复主题"，楼中楼显示"回复 @用户名"
- [ ] 发送按钮显示状态：默认"发送"、发送中"发送中"、上传图片中"上传图片中"
- [ ] 发送按钮禁用条件：空内容（无文字且无图）/ 发送中 / 上传中
- [ ] 底部工具栏移除发送按钮，保留图片/表情/字数/原图开关
- [ ] 顶部布局顺序：TopBar → SelectedImagesPanel → TextArea → BottomToolbar → EmojiPanel
- [ ] 编译通过：`hvigorw assembleHap` BUILD SUCCESSFUL
- [ ] 真机/模拟器验证：
  - 点击"写评论" → 顶栏显示"回复主题" + 发送按钮置灰（无内容）
  - 输入内容 → 发送按钮变主题色
  - 点击发送 → 显示"发送中" → 完成后 sheet 关闭 + 列表刷新
  - 楼中楼回复 → 顶栏显示"回复 @用户名"
  - 点击关闭 X → sheet 关闭

## Blocked by

- #240（bindSheet 配置精简 + SheetSize 升级，需先移除系统三件套腾出顶栏空间）
