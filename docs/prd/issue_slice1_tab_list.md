## Parent

- #245 (PRD：添加完整版吧内页面)

## What to build

为完整版吧内页面 `ForumPageFull.ets` 添加 Tab 切换条 + 帖子列表 + 排序持久化：

1. **Tab 切换条**：使用 `HdsTabs` 单胶囊方案（参考项目记忆铁律），配置：
   - `barHeight=48, barSideMargin=32, barBottomMargin=0, barOverlap=true, barMode=Fixed, scrollable=false`
   - 显式配置 `barWidth`（避免单 Tab 渲染成圆球）
   - 固定 2 个 Tab：首页（`tab_forum_latest`）+ 精品（`tab_forum_good`）
   - 动态追加通用 Tab：从 `navTabInfo.tabs` 过滤 `isGeneralTab == 1 && tabType == 15`（对齐 TiebaLite-4.0-dev）
   - 当 `navTabInfo` 为 null 或 tabs 为空时，只显示固定 2 个 Tab（降级处理）

2. **帖子列表**：每个 Tab 内使用 `List` + `LazyForEach` + 复用现有 `ThreadCard` 组件：
   - 首页 Tab：调用 `TiebaAPI.getThreads(forumName, page, sortType, isGood=false)`
   - 精品 Tab：调用 `TiebaAPI.getThreads(forumName, page, sortType, isGood=true)`
   - 通用 Tab：调用 `TiebaAPI.getThreads` 传入 `tabId` 参数（如 FrsPage 响应支持，否则降级到首页列表）
   - 复用 `ThreadCard` 的 6 个事件回调（onCardClick/onAuthorClick/onAgreeClick/onDisagreeClick/onCommentClick/onForumClick）
   - 点击帖子卡片跳转 `ROUTE_THREAD_PAGE`（复用现有 `navigateToThread` 逻辑）
   - 点击作者头像跳转 `ROUTE_USER_PROFILE_PAGE`（复用现有 `navigateToUserProfile` 逻辑）
   - 点赞/点踩复用 `handleThreadAgree` / `handleThreadDisagree` helper
   - 列表底部加载更多 + 顶部下拉刷新

3. **Tab 长按排序菜单**：
   - 首页 Tab 长按弹出排序菜单（按回复数/按发表时间）
   - 排序选项来自 `FrsTabInfo.sortMenu`（如非空），否则使用默认 2 选项
   - 切换排序后当前 Tab 列表按新排序刷新
   - 排序偏好持久化：按吧名维度存储到 preferences（key: `{forumName}_sort_type`），参考 TiebaLite-4.0-dev 实现

4. **Tab 切换动画**：使用 `animateTo` 包裹 `currentTabIndex` 状态变化（duration 200ms，curve EaseInOut），实现平滑过渡。

5. **悬浮 TabBar 铁律**：遵循项目记忆铁律"悬浮 TabBar 下方禁止加 padding/遮罩"，`HdsTabs` 配置 `barOverlap(true) + barFloatingStyle`，子页面 List **不要加 bottom padding 避让 TabBar**。

6. **Header 折叠联动**：Tab 切换条与 Header 折叠状态联动，Header 折叠时 Tab 切换条保持在 AppBar 下方固定不动。

## Acceptance criteria

- [ ] `ForumPageFull.ets` 显示 `HdsTabs` 单胶囊 Tab 切换条（首页/精品 2 个固定 Tab）
- [ ] FrsPage 响应包含 `nav_tab_info` 时，Tab 列表追加动态通用 Tab（吧务/公告等）
- [ ] FrsPage 响应不包含 `nav_tab_info` 时，只显示固定 2 个 Tab 不报错
- [ ] Tab 切换平滑过渡动画（200ms EaseInOut）
- [ ] 首页 Tab 显示按当前排序的帖子列表，每张卡片用 `ThreadCard` 展示
- [ ] 精品 Tab 显示精品分类的帖子列表
- [ ] 点击帖子卡片跳转 `ROUTE_THREAD_PAGE`
- [ ] 点击帖子卡片作者头像跳转 `ROUTE_USER_PROFILE_PAGE`
- [ ] 点赞/点踩按钮即时更新状态并同步服务端
- [ ] 列表底部自动加载下一页
- [ ] 下拉刷新重新加载第一页并同步吧信息
- [ ] 首页 Tab 长按弹出排序选择菜单（按回复数/按发表时间）
- [ ] 切换排序方式后当前 Tab 列表按新排序刷新
- [ ] 排序偏好按吧名维度持久化到 preferences
- [ ] `HdsTabs` 单 TabContent 显式配置 `barWidth`（避免渲染成圆球）
- [ ] 悬浮 TabBar 下方无 padding/遮罩（遵循项目铁律）
- [ ] Tab 切换条与 Header 折叠状态联动正常
- [ ] 编译通过（`hvigorw assembleHap` BUILD SUCCESSFUL）

## Blocked by

- #246（切片 0：基础设施 + 骨架 + Header）
