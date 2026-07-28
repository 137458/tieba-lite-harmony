## Parent

- #245 (PRD：添加完整版吧内页面)

## What to build

构建完整版吧内页面的基础设施 + 端到端骨架 + 可折叠 Header + 开关切换：

1. **协议层扩展**：扩展 `FrsPageProto.ets` 解码 `nav_tab_info` (field 37) + `NavTabInfo` / `FrsTabInfo` / `SortButton` / `TabMenu` message；扩展 ForumInfo 解码（field 6 is_like / field 7 user_level / field 8 level_name / field 9 member_num / field 10 thread_num / field 13 cur_score / field 14 levelup_score / field 24 avatar / field 25 slogan）。新增 `GetForumDetailProto.ets` 解码 `GetForumDetailResIdl` 响应（仅 forum_info 字段）。

2. **模型层扩展**：`ForumModels.ets` 新增 `NavTabInfo` / `FrsTabInfo` / `SortButton` / `TabMenu` 类；`ForumInfo` 新增 `userLevel` / `levelName` / `curScore` / `levelupScore` 字段。新增 `ForumDetailInfo` 类（avatar/forumName/memberCount/threadCount/slogan）。

3. **API 层扩展**：`TiebaAPI.ets` 新增 `getForumDetail(forumId: number): Promise<ForumDetailInfo>` 方法，调用 `/c/f/forum/getforumdetail?cmd=303021` 端点（protobuf，CommonReq field 10 注入 BDUSS）。

4. **路由层扩展**：`RouterUtil.ets` 新增 `ROUTE_FORUM_PAGE_FULL = 'ForumPageFull'` 和 `ROUTE_FORUM_DETAIL_PAGE = 'ForumDetailPage'` 常量；新增 `ForumDetailNavParams(forumId, forumName)` 参数类。`router_map.json` 注册两个新路由项。

5. **持久化层扩展**：`AppStorageV2Models.ets` 新增 `ForumPageVersionState`（持久化键 `forum_page_version`，0=简化版/1=完整版）和 `ForumFabFunctionState`（持久化键 `forum_fab_function`，0=post/1=refresh/2=back_to_top/3=hide）。`Index.ets` 启动任务读取 preferences 写入 AppStorageV2。

6. **开关切换**：修改 `HomePage` / `SearchPage` / `FollowForumsPage` 等调用 `RouterUtil.push(ROUTE_FORUM_PAGE, ...)` 的位置，根据 `ForumPageVersionState.value` 决定 push `ROUTE_FORUM_PAGE` 还是 `ROUTE_FORUM_PAGE_FULL`。

7. **设置页扩展**：`SettingsPage.ets` 在"显示设置"分组新增"使用完整版吧内页面"Toggle，默认关闭。切换时同步写入 AppStorageV2 + preferences。

8. **完整版骨架 `ForumPageFull.ets`**：创建新页面（`pages/forum/ForumPageFull.ets`），实现：
   - `HdsNavDestination` 容器 + `titleBar`（AppBar 标题 + 搜索图标占位 + 三点菜单占位）
   - 可折叠 Header：吧头像（80vp）+ 吧名 + 等级进度条（已关注时显示）+ 关注/签到按钮
   - Header 折叠动画：`animateTo` 包裹状态变化（duration 200ms，curve EaseInOut），通过 `bindToScrollable` 监听列表滚动
   - 复用 `ForumViewModel` + `checkFollowingStatus` + `handleFollowForum`
   - 新增签到逻辑：调用 `TiebaAPI.signForum(forumName, forumId)`，成功后显示"已签 N 天"
   - 沉浸光感材质：`systemMaterialEffect: { materialType: IMMERSIVE, materialLevel: ADAPTIVE }`（与简化版一致）
   - 左右 16vp 安全边距（项目铁律）
   - 深色模式：背景用 `input_background` 而非纯黑
   - 内部禁止加 `backgroundBlurStyle/backgroundColor/borderRadius`（避免与外层 HDS 材质叠加）

## Acceptance criteria

- [ ] `FrsPageProto.ets` 解码 `nav_tab_info` 字段，返回 `NavTabInfo` 对象（含 tabs/menus/heads 三个 FrsTabInfo[]）
- [ ] `FrsPageProto.ets` 解码 ForumInfo 的 avatar/slogan/is_like/member_num/thread_num/user_level/level_name/cur_score/levelup_score 字段
- [ ] `GetForumDetailProto.ets` 正确解码 `GetForumDetailResIdl` 响应的 forum_info 字段
- [ ] `TiebaAPI.getForumDetail(forumId)` 返回 `ForumDetailInfo`（含 avatar/forumName/memberCount/threadCount/slogan）
- [ ] `RouterUtil.ets` 新增 `ROUTE_FORUM_PAGE_FULL` 和 `ROUTE_FORUM_DETAIL_PAGE` 路由常量
- [ ] `router_map.json` 注册 `ForumPageFull` 和 `ForumDetailPage` 两个新路由项
- [ ] `ForumPageVersionState` 和 `ForumFabFunctionState` 通过 AppStorageV2 共享，启动时从 preferences 读取
- [ ] `SettingsPage` "显示设置"分组新增"使用完整版吧内页面"Toggle，默认关闭
- [ ] Toggle 切换时同步写入 AppStorageV2 + preferences，立即生效不需重启
- [ ] 开关关闭时从首页点击吧名跳转到 `ForumPage`（简化版）
- [ ] 开关打开时从首页点击吧名跳转到 `ForumPageFull`（完整版）
- [ ] `ForumPageFull.ets` 显示可折叠 Header（吧头像 + 吧名 + 等级进度条 + 关注/签到按钮）
- [ ] Header 折叠/展开动画流畅（200ms EaseInOut）
- [ ] 关注按钮：未关注→点击→调用 followForum→成功后变为签到按钮
- [ ] 签到按钮：未签到→点击→调用 signForum→成功后显示"已签 N 天"
- [ ] 已签到按钮不可点击
- [ ] 关注/签到操作触发重震动触感反馈
- [ ] 编译通过（`hvigorw assembleHap` BUILD SUCCESSFUL）
- [ ] 单元测试：协议层解码测试通过（手动触发 FrsPage 请求验证 nav_tab_info 解码）

## Blocked by

- None - can start immediately（基础设施切片无前置依赖）
