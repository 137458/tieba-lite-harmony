## Parent

- #245 (PRD：添加完整版吧内页面)

## What to build

为完整版吧内页面 `ForumPageFull.ets` 添加 FAB（浮动按钮）4 模式切换：

1. **FAB 4 模式**：根据 `ForumFabFunctionState.value` 显示对应图标和行为：
   - `0=post`（默认）：图标 `Icons.Rounded.Add`，点击跳转发帖页（传入 fid + forumName + tid=0）
   - `1=refresh`：图标 `Icons.Rounded.Refresh`，点击刷新当前 Tab 列表 + 回到顶部
   - `2=back_to_top`：图标 `Icons.Rounded.VerticalAlignTop`，点击当前 Tab 列表平滑滚动到顶部
   - `3=hide`：FAB 不显示

2. **FAB 视觉规范**：
   - 尺寸 56x56
   - 右下角 margin 16vp（避免与悬浮 TabBar 重叠）
   - 背景 `window_background`
   - 图标色 `primary`
   - 阴影效果（参考项目其他 FAB 实现）

3. **发帖模式跳转**：调用现有 `RouterUtil.push(ROUTE_THREAD_PAGE, new ThreadNavParams(0))` 或类似方式跳转发帖页（与现有发帖流程一致，不新建 ReplyPage）。需要确认现有发帖入口的实现方式（可能是 ThreadPage 的 tid=0 触发新建帖子模式）。

4. **发帖成功后自动刷新**：监听全局事件（如 AppStorageV2 中某个状态变化或 `forumsNeedRefresh` 类似机制），发帖成功后自动刷新当前 Tab 列表 + 回到顶部显示新帖。

5. **设置页 FAB 功能菜单**：`SettingsPage.ets` 在"显示设置"分组新增"FAB 功能"选择菜单（4 选项：发帖/刷新/回顶/隐藏），切换时同步写入 `ForumFabFunctionState` + preferences。参考项目记忆中"持久化模式"实现（SettingsPage 写入 + Index.ets 启动时读回）。

6. **FAB 模式持久化**：`ForumFabFunctionState` 通过 AppStorageV2 共享，启动时从 preferences 读取。SettingsPage 修改后立即生效，下次进入吧内页面 FAB 显示对应模式。

## Acceptance criteria

- [ ] `ForumPageFull.ets` 显示右下角 FAB（默认发帖模式）
- [ ] FAB 尺寸 56x56，右下角 margin 16vp
- [ ] FAB 背景为 `window_background`，图标色为 `primary`
- [ ] `ForumFabFunctionState=0`（发帖）时显示 Add 图标，点击跳转发帖页
- [ ] `ForumFabFunctionState=1`（刷新）时显示 Refresh 图标，点击刷新当前 Tab 列表 + 回顶
- [ ] `ForumFabFunctionState=2`（回顶）时显示 VerticalAlignTop 图标，点击列表平滑滚动到顶部
- [ ] `ForumFabFunctionState=3`（隐藏）时 FAB 不显示
- [ ] 发帖成功后当前 Tab 列表自动刷新并回到顶部显示新帖
- [ ] `SettingsPage` "显示设置"分组新增"FAB 功能"选择菜单（4 选项）
- [ ] FAB 模式切换后立即生效，下次进入吧内页面看到对应模式
- [ ] FAB 模式持久化到 preferences，重启应用后保持
- [ ] 编译通过（`hvigorw assembleHap` BUILD SUCCESSFUL）

## Blocked by

- #246（切片 0：基础设施 + 骨架 + Header）
