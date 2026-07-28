## Parent

- #245 (PRD：添加完整版吧内页面)

## What to build

新建吧详情页 `ForumDetailPage.ets`，严格对齐安卓版 TiebaLite-4.0-dev 的 `ForumDetailPage.kt` 4 元素实现：

1. **页面结构**（严格按安卓版 `ForumDetailPage.kt:60-184`）：
   - 顶部居中标题栏：返回按钮 + 标题"吧资料"（`R.string.title_forum_info`）
   - 吧头像 + 吧名横向 Row 展示
   - 2 列统计卡片：关注数（`member_count`）+ 帖子数（`thread_count`）
   - 吧简介区块：标题 Chip"吧简介"（`R.string.title_forum_intro`）+ slogan + content plainText

2. **数据来源**：调用 `TiebaAPI.getForumDetail(forumId)`（切片 0 已实现），返回 `ForumDetailInfo`（avatar/forumName/memberCount/threadCount/slogan）。

3. **不实现的内容**（严格按安卓版，不臆想补全）：
   - 吧主列表
   - 吧务列表
   - 吧规入口
   - 签到入口
   - 推荐吧
   - 任何安卓版 `ForumDetailPage.kt` 未实现的元素

4. **Header 跳转**：完整版 `ForumPageFull.ets` 的 Header 吧名/吧头像区域点击时，调用 `RouterUtil.push(ROUTE_FORUM_DETAIL_PAGE, new ForumDetailNavParams(forumId, forumName))` 跳转到吧详情页。

5. **视觉规范**：
   - 左右 16vp 安全边距（项目铁律）
   - 深色模式：背景用 `input_background` 而非纯黑
   - 标题栏使用 `HdsNavDestination` + `titleBar`（与项目其他二级页面一致）
   - 沉浸光感材质：`systemMaterialEffect: { materialType: IMMERSIVE, materialLevel: ADAPTIVE }`
   - 内部禁止加 `backgroundBlurStyle/backgroundColor/borderRadius`（避免与外层 HDS 材质叠加）

6. **加载状态**：使用 `LoadingView` 显示加载中，`ErrorView` 显示错误并提供重试按钮（复用现有组件）。

7. **路由注册**：`RouterUtil.ets` 的 `ROUTE_FORUM_DETAIL_PAGE` 常量和 `router_map.json` 的 `ForumDetailPage` 路由项已在切片 0 注册。

## Acceptance criteria

- [ ] `ForumDetailPage.ets` 页面创建成功，路由 `ROUTE_FORUM_DETAIL_PAGE` 可访问
- [ ] 顶部居中标题栏显示"吧资料" + 返回按钮
- [ ] 返回按钮点击返回上一页
- [ ] 吧头像 + 吧名横向 Row 展示
- [ ] 2 列统计卡片显示关注数 + 帖子数
- [ ] 吧简介区块显示标题 Chip"吧简介" + slogan + 正文
- [ ] 严格按安卓版 4 元素实现，**不包含**吧主/吧务/吧规/签到入口/推荐吧
- [ ] 数据来自 `TiebaAPI.getForumDetail(forumId)` 接口
- [ ] 加载中显示 `LoadingView`
- [ ] 加载失败显示 `ErrorView` + 重试按钮
- [ ] 完整版 `ForumPageFull.ets` Header 吧名/吧头像点击跳转到吧详情页
- [ ] 左右 16vp 安全边距（项目铁律）
- [ ] 深色模式背景用 `input_background` 而非纯黑
- [ ] 沉浸光感材质与项目其他二级页面一致
- [ ] 编译通过（`hvigorw assembleHap` BUILD SUCCESSFUL）

## Blocked by

- #246（切片 0：基础设施 + 骨架 + Header，需 `TiebaAPI.getForumDetail` 接口 + 路由注册）
