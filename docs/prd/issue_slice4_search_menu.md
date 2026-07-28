## Parent

- #245 (PRD：添加完整版吧内页面)

## What to build

为完整版吧内页面 `ForumPageFull.ets` 添加吧内搜索入口 + AppBar 三点菜单：

1. **AppBar 搜索图标**：在 `HdsNavDestination` 的 `titleBar.menu` 中新增搜索图标（第一个位置），点击跳转现有 `SearchPage`，传入 `SearchNavParams(fname=forumName, keyword='')`：
   - 复用现有 `ROUTE_SEARCH_PAGE` 路由
   - 复用现有 `SearchNavParams` 参数类（已有 fname 字段）
   - 跳转后 SearchPage 自动进入吧内搜索模式（fname 已传入）

2. **AppBar 三点菜单**：在 `titleBar.menu` 的搜索图标后新增"更多"菜单（自动收起到三点图标），包含 3 项：
   - **分享**：调用系统分享面板分享当前吧名（`TiebaUtil.shareText` 类似实现，鸿蒙版用 `@ohos.app.ability.common` 的 `UIContext.showShareAction` 或类似 API）
   - **发送到桌面**（占位）：本次仅实现菜单项，实际桌面快捷方式创建作为后续 issue（参考 PRD #245 Out of Scope 第 8 项）。点击时 Toast 提示"功能开发中"。
   - **取消关注**（已关注时显示）：弹出确认对话框，确认后调用 `TiebaAPI.unfollowForum(forumId, forumName)`，成功后 Toast 提示 + 返回上一页。未关注时不显示此项。

3. **菜单项显隐逻辑**：
   - 搜索图标：始终显示
   - 分享：始终显示
   - 发送到桌面：始终显示（占位）
   - 取消关注：仅 `isFollowing=true` 时显示

4. **菜单视觉规范**：
   - 图标色 `primary`（与简化版 `originalStyle.menuStyle.iconColor` 一致）
   - 沉浸光感模式下图标色自动适配（参考简化版 `scrollEffectStyle.menuStyle.iconColor`）
   - 左右 16vp 安全边距（项目铁律）

5. **分享功能实现**：参考鸿蒙官方 `@ohos.app.ability.common` 的 `UIContext.showShareAction` 或类似 API（需运行时确认 API 23 支持）。如不支持，降级为复制吧名到剪贴板 + Toast 提示。

## Acceptance criteria

- [ ] `ForumPageFull.ets` AppBar 显示搜索图标（`titleBar.menu` 第一个位置）
- [ ] 点击搜索图标跳转 `ROUTE_SEARCH_PAGE`，传入 `SearchNavParams(fname=forumName, keyword='')`
- [ ] SearchPage 自动进入吧内搜索模式（fname 已传入）
- [ ] AppBar 三点菜单包含 3 项：分享 / 发送到桌面 / 取消关注
- [ ] 分享菜单点击调用系统分享面板（或降级为复制到剪贴板 + Toast）
- [ ] 发送到桌面菜单点击 Toast 提示"功能开发中"（占位）
- [ ] 取消关注菜单仅在 `isFollowing=true` 时显示
- [ ] 取消关注点击弹出确认对话框
- [ ] 确认对话框确认后调用 `TiebaAPI.unfollowForum`，成功后 Toast + 返回上一页
- [ ] 菜单图标色为 `primary`
- [ ] 沉浸光感模式下图标色自动适配
- [ ] 编译通过（`hvigorw assembleHap` BUILD SUCCESSFUL）

## Blocked by

- #246（切片 0：基础设施 + 骨架 + Header，需 `ForumPageFull.ets` 骨架 + `isFollowing` 状态）
