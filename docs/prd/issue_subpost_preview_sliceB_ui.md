## Parent

- #252 (PRD：楼中楼预览)

## What to build

切片B：UI 层渲染楼中楼预览，端到端完成 PRD #252 的用户可见行为。

修改 `ThreadPage.ets` 的 PostItem 组件：

1. **渲染条件调整**：
   - 原条件 `if (post.replyNum > 0)` 显示"查看全部 N 条回复"按钮
   - 新逻辑：
     - 若 `post.replyNum > 0 && post.subPostList.length > 0`：渲染预览区域（Column 容器 + 子回复列表 + 底部按钮）
     - 若 `post.replyNum > 0 && post.subPostList.length === 0`：降级保留原"查看全部 N 条回复"按钮（兜底）

2. **预览区域结构**（对齐安卓版 ThreadPage.kt:2210-2268）：
   - 外层 Column：圆角 6vp，背景 `input_background`，内边距 vertical=12vp，子项间距 2vp
   - 循环渲染 `post.subPostList` 数组，每条子回复：
     - 布局：作者名（primary 主题色）+ '：' + 内容文本
     - 文本最多 4 行后省略号（maxLines(4) + textOverflow(Ellipsis)）
     - 点击跳楼中楼：复用 navigateToSubPosts(post)（与原按钮行为一致，不要求滚动到 spid）
   - 预览列表底部（仅当 `post.replyNum > post.subPostList.length` 时显示）：
     - "查看全部 N 条回复"文本按钮，primary 主题色，复用 $r('app.string.view_all_sub_posts') 资源
     - 点击跳楼中楼：navigateToSubPosts(post)

3. **样式细节**：
   - 预览区域 top margin 10vp（对齐原按钮 margin）
   - 子回复文字字号 13（与原按钮一致）
   - 深色模式下文字颜色与楼层卡片其他辅助文字一致（input_background 背景已适配深色）

4. **不修改**：
   - ForumModels.ets（PostInfo.subPostList 字段已就绪）
   - TiebaAPI.ets（不新增 API 请求）
   - string.json（view_all_sub_posts 字符串继续复用）
   - SubPostsPage.ets（楼中楼列表页本 PRD 不动）

## Acceptance criteria

- [ ] PostItem 在 `replyNum>0 && subPostList.length>0` 时渲染预览区域
- [ ] 预览区域循环渲染 subPostList 数组，每条显示作者名（主题色）+ '：' + 内容（4 行省略号）
- [ ] 预览底部"查看全部 N 条回复"按钮仅当 `replyNum > subPostList.length` 时显示
- [ ] 降级路径：replyNum>0 但 subPostList 为空时保留原按钮样式（兜底）
- [ ] 无回复楼层不显示预览区域
- [ ] 点击预览子回复跳转楼中楼
- [ ] 点击"查看全部"按钮跳转楼中楼
- [ ] 深色模式下预览样式正确（背景、文字颜色、圆角）
- [ ] 编译通过（hvigorw assembleHap BUILD SUCCESSFUL）

## Blocked by

- #253（切片A：协议解码 sub_post_list）
