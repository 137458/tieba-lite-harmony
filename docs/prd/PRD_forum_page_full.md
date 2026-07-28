# PRD：添加完整版吧内页面（对齐安卓版，开关切换）

## Problem Statement

当前鸿蒙版 `ForumPage` 是简化版（HdsNavDestination + 单 List + titleBar 三菜单），缺少安卓版 TiebaLite-4.0-dev 吧内页面的关键体验：

1. **无可折叠 Header**：吧头像、吧名、等级、关注/签到按钮固定在 titleBar，没有大尺寸 Header 可折叠展开的沉浸感
2. **无 Tab 切换**：只有单个列表，没有"首页/精品/动态通用 Tab"切换
3. **无 FAB**：缺少右下角浮动按钮（发帖/刷新/回顶）
4. **无吧详情页**：点击吧名无法跳转到独立的吧详情页查看吧简介
5. **无吧内搜索入口**：缺少 AppBar 搜索图标跳转到吧内搜索
6. **无签到入口**：Header 上没有签到按钮，签到需进入设置页
7. **无吧务/公告等动态 Tab**：FrsPage 响应的 `nav_tab_info` 字段未被解码，无法显示吧主自定义 Tab

用户希望有一个全面对齐安卓版的完整版吧内页面，通过开关在简化版与完整版之间切换。

## Solution

新建独立文件 `ForumPageFull.ets` 实现完整版吧内页面，与现有简化版 `ForumPage.ets` 共存。在设置页"显示设置"分组新增"使用完整版吧内页面"开关，默认关闭（新用户首次进入看到简化版）。打开开关后，从首页/搜索/关注列表点击吧名跳转时路由到 `ForumPageFull`。

完整版一次性实现安卓版 9 大功能块：

1. 顶部 AppBar（搜索 + 三点菜单：分享/发送到桌面/取消关注）
2. 可折叠 Header（吧头像 + 吧名 + 等级进度条 + 关注/签到按钮）
3. Tab 切换条（首页/精品 + 动态通用 Tab）
4. 帖子列表（首页/精品，复用 `ThreadCard`）
5. 通用 Tab 列表（吧务/公告等动态 Tab）
6. FAB 浮动按钮（4 模式：发帖/刷新/回顶/隐藏，通过偏好切换）
7. 吧内搜索入口（跳转现有 `SearchPage`，传入 fname 参数）
8. 签到入口（复用现有 `TiebaAPI.signForum`）
9. 吧详情页（新建 `ForumDetailPage.ets`，严格对齐安卓版 4 元素：头像 + 吧名 + 统计 + 简介）

## User Stories

### 顶部 AppBar 与导航

1. 作为吧内页面访客，当我进入吧内页面时，希望看到顶部 AppBar 显示吧名（Header 折叠时才显示标题文字），以便我知道当前所在吧
2. 作为吧内页面访客，当我点击 AppBar 左侧返回按钮时，希望能返回上一页
3. 作为吧内页面访客，当我点击 AppBar 搜索图标时，希望能跳转到吧内搜索页（传入当前吧名作为 fname 参数）
4. 作为吧内页面访客，当我点击 AppBar 三点菜单的"分享"时，希望能分享当前吧名到系统分享面板
5. 作为吧内页面访客，当我点击 AppBar 三点菜单的"发送到桌面"时，希望能创建桌面快捷方式直接进入该吧
6. 作为已关注用户，当我点击 AppBar 三点菜单的"取消关注"时，希望能弹出确认对话框，确认后取消关注该吧并返回上一页

### 可折叠 Header

7. 作为吧内页面访客，当我首次进入吧内页面时，希望看到展开的大尺寸 Header（吧头像 + 吧名 + 等级 + 操作按钮），以便直观获取吧信息
8. 作为吧内页面访客，当我向上滚动帖子列表时，希望 Header 平滑折叠到 AppBar 高度，以便给列表更多空间
9. 作为吧内页面访客，当我向下滚动到顶部时，希望 Header 平滑展开恢复完整显示
10. 作为已关注用户，当我已关注该吧时，希望 Header 显示我的等级进度条（Lv + 等级名 + cur_score/levelup_score 进度条）
11. 作为未关注用户，当我未关注该吧时，希望 Header 不显示等级进度条（仅显示吧头像 + 吧名 + 关注按钮）
12. 作为吧内页面访客，当我点击 Header 吧头像/吧名区域时，希望能跳转到吧详情页查看吧简介
13. 作为吧内页面访客，当 Header 中显示的吧头像 URL 来自 FrsPage 响应时，希望鸿蒙版解码 FrsPage 的 ForumInfo.avatar 字段（field 24）自动填充，不再依赖路由参数传入

### 关注与签到按钮

14. 作为未关注用户，当我在 Header 看到关注按钮时，希望点击后调用 `followForum` API 关注该吧，成功后按钮变为签到按钮并 Toast 提示
15. 作为已关注未签到用户，当我在 Header 看到签到按钮时，希望点击后调用 `signForum` API 签到，成功后显示"已签 N 天"
16. 作为已关注已签到用户，当我在 Header 看到签到按钮时，希望按钮显示"已签 N 天"且不可点击
17. 作为关注/签到操作用户，当我点击关注或签到按钮时，希望能感受到重震动触感反馈确认操作
18. 作为关注操作用户，当关注成功后希望能自动刷新 Header 显示等级进度条

### Tab 切换

19. 作为吧内页面访客，当我看到 Tab 切换条时，希望默认有"首页"和"精品"两个固定 Tab
20. 作为吧内页面访客，当 FrsPage 响应包含 `nav_tab_info` 字段时，希望 Tab 列表追加动态通用 Tab（吧务/公告等）
21. 作为吧内页面访客，当我点击某个 Tab 时，希望内容区切换到该 Tab 的帖子列表，切换有平滑过渡动画
22. 作为首页 Tab 用户，当我长按"首页"Tab 时，希望能弹出排序选择菜单（按回复数/按发表时间）
23. 作为用户，当我切换排序方式时，希望当前 Tab 列表按新排序刷新，且排序偏好持久化（按吧名维度）
24. 作为吧内页面访客，当 FrsPage 响应不包含 `nav_tab_info` 字段时，希望只显示固定 2 个 Tab 不报错

### 帖子列表

25. 作为吧内页面访客，当我在"首页"Tab 时，希望看到按当前排序的帖子列表，每张卡片用 `ThreadCard` 组件展示
26. 作为吧内页面访客，当我在"精品"Tab 时，希望看到精品分类的帖子列表
27. 作为吧内页面访客，当我点击帖子卡片时，希望能跳转到帖子详情页
28. 作为吧内页面访客，当我点击帖子卡片的回复按钮时，希望能跳转到帖子详情页并滚动到回复区
29. 作为吧内页面访客，当我点击帖子卡片的作者头像时，希望能跳转到用户主页
30. 作为吧内页面访客，当我点击帖子卡片的点赞/点踩按钮时，希望能即时更新状态并同步服务端
31. 作为吧内页面访客，当我向下滚动到列表底部时，希望能自动加载下一页
32. 作为吧内页面访客，当我下拉刷新时，希望能重新加载第一页并同步吧信息

### 通用 Tab 列表

33. 作为吧内页面访客，当我切换到动态通用 Tab（如吧务/公告）时，希望看到该 Tab 的子内容（可能含子 Tab Chip 切换）
34. 作为吧内页面访客，当通用 Tab 的 `sort_menu` 非空时，希望长按 Tab 能弹出排序菜单
35. 作为吧内页面访客，当通用 Tab 的 `sub_tab_list` 非空时，希望顶部显示 Chip 切换不同子分类

### FAB 浮动按钮

36. 作为吧内页面访客，当我看到右下角 FAB 时，希望根据设置项 `forumFabFunction` 显示对应图标（发帖/刷新/回顶/隐藏）
37. 作为吧内页面访客，当我点击 FAB（发帖模式）时，希望能跳转到发帖页面（传入 fid + forumName + tid=0）
38. 作为吧内页面访客，当我点击 FAB（刷新模式）时，希望能刷新当前 Tab 列表并回到顶部
39. 作为吧内页面访客，当我点击 FAB（回顶模式）时，希望当前 Tab 列表平滑滚动到顶部
40. 作为吧内页面访客，当 `forumFabFunction=hide` 时，希望 FAB 不显示
41. 作为发帖用户，当发帖成功后，希望当前 Tab 列表自动刷新并回到顶部显示新帖

### 吧详情页

42. 作为吧内页面访客，当我点击 Header 吧名区域时，希望能跳转到吧详情页
43. 作为吧详情页访客，当我在吧详情页时，希望看到顶部居中标题栏（"吧资料" + 返回按钮）
44. 作为吧详情页访客，当我在吧详情页时，希望看到吧头像 + 吧名横向 Row 展示
45. 作为吧详情页访客，当我在吧详情页时，希望看到 2 列统计卡片（关注数 + 帖子数）
46. 作为吧详情页访客，当我在吧详情页时，希望看到吧简介区块（标题 Chip + slogan + 正文）
47. 作为吧详情页访客，当吧详情数据来自 `GetForumDetail` 接口时，希望严格对齐安卓版 4 元素实现，不臆想补全吧主/吧务/吧规列表

### 开关切换

48. 作为用户，当我在设置页"显示设置"分组看到"使用完整版吧内页面"开关时，希望能切换简化版/完整版
49. 作为用户，当开关关闭（默认）时，从首页/搜索/关注列表点击吧名跳转到简化版 `ForumPage`
50. 作为用户，当开关打开时，从首页/搜索/关注列表点击吧名跳转到完整版 `ForumPageFull`
51. 作为新用户，首次安装应用后开关默认关闭，看到简化版（避免新功能认知负担）
52. 作为用户，当切换开关后立即生效，下次进入吧内页面看到对应版本

### 沉浸光感与视觉规范

53. 作为吧内页面访客，当完整版 Header 折叠时，希望 AppBar 应用沉浸光感材质（与简化版 `systemMaterialEffect` 一致）
54. 作为吧内页面访客，当完整版使用 HdsTabs 时，希望 Tab 切换条遵循项目"悬浮 TabBar 下方禁止加 padding/遮罩"铁律
55. 作为吧内页面访客，当完整版所有控件有左右 16vp 安全边距时，希望视觉与项目其他页面统一
56. 作为深色模式用户，当完整版所有新增 UI 元素在深色模式下正常显示时，希望背景用 `input_background` 而非纯黑

## Implementation Decisions

### 模块改动

1. **新增 `ForumPageFull.ets`**（`pages/forum/ForumPageFull.ets`）：完整版吧内页面，复用 `ForumViewModel` 但扩展状态字段（Header 折叠、Tab 索引、FAB 模式）
2. **新增 `ForumDetailPage.ets`**（`pages/forum/ForumDetailPage.ets`）：吧详情页，严格对齐安卓版 4 元素（头像 + 吧名 + 统计 + 简介）
3. **扩展 `FrsPageProto.ets`**：解码 `nav_tab_info` (field 37) + 新增 `NavTabInfo` / `FrsTabInfo` / `SortButton` / `TabMenu` message 解码
4. **扩展 `FrsPageProto.ets` 中 ForumInfo 解码**：新增 field 6 (is_like)、field 7 (user_level)、field 8 (level_name)、field 9 (member_num)、field 10 (thread_num)、field 13 (cur_score)、field 14 (levelup_score)、field 24 (avatar)、field 25 (slogan)
5. **扩展 `ForumModels.ets`**：新增 `NavTabInfo` / `FrsTabInfo` / `SortButton` / `TabMenu` 类；`ForumInfo` 新增 `userLevel` / `levelName` / `curScore` / `levelupScore` 字段
6. **新增 `TiebaAPI.getForumDetail(forumId)`**：调用 `/c/f/forum/getforumdetail?cmd=303021` 端点，对齐安卓版 `ForumDetailViewModel.Load`
7. **新增 `GetForumDetailProto.ets`**：解码 `GetForumDetailResIdl` 响应（仅 forum_info 字段，对齐安卓版 4 元素所需字段）
8. **扩展 `RouterUtil.ets`**：新增 `ROUTE_FORUM_PAGE_FULL` 和 `ROUTE_FORUM_DETAIL_PAGE` 路由常量；新增 `ForumDetailNavParams(forumId, forumName)` 参数类
9. **扩展 `router_map.json`**：注册 `ForumPageFull` 和 `ForumDetailPage` 两个新路由项
10. **扩展 `AppStorageV2Models.ets`**：新增 `ForumPageVersionState`（持久化键 `forum_page_version`，0=简化版/1=完整版）；新增 `ForumFabFunctionState`（持久化键 `forum_fab_function`，枚举 0=post/1=refresh/2=back_to_top/3=hide）
11. **扩展 `SettingsPage.ets`**：在"显示设置"分组新增"使用完整版吧内页面"Toggle；新增"FAB 功能"选择菜单（4 选项）
12. **扩展 `Index.ets` 启动任务**：启动时从 preferences 读取 `forum_page_version` 和 `forum_fab_function` 写入 AppStorageV2
13. **修改 `ForumPage.ets` 调用方**：在 `HomePage` / `SearchPage` / `FollowForumsPage` 等调用 `RouterUtil.push(ROUTE_FORUM_PAGE, ...)` 的位置，根据 `ForumPageVersionState` 决定 push `ROUTE_FORUM_PAGE` 还是 `ROUTE_FORUM_PAGE_FULL`
14. **复用 `ThreadCard`**：完整版帖子列表直接复用现有 `ThreadCard` 组件，不新建 `FeedCard`

### 接口契约

- `ForumPageFull` 组件无对外接口（作为路由目标），通过 `NavPathStack.getParamByName` 读取 `ForumNavParams`（与 `ForumPage` 一致）
- `ForumDetailPage` 组件无对外接口，通过 `NavPathStack.getParamByName` 读取 `ForumDetailNavParams(forumId, forumName)`
- `TiebaAPI.getForumDetail(forumId: number): Promise<ForumDetailInfo>` 返回 `ForumDetailInfo`（含 avatar/forumName/memberCount/threadCount/slogan）
- `NavTabInfo` 类结构：`tabs: FrsTabInfo[]` + `menus: FrsTabInfo[]` + `heads: FrsTabInfo[]`（对齐 proto field 1/2/3）
- `FrsTabInfo` 类结构：`tabId` / `tabType` / `tabName` / `tabUrl` / `tabGid` / `tabTitle` / `isGeneralTab` / `tabCode` / `tabVersion` / `isDefault` / `sortMenu: SortButton[]` / `subTabList: TabMenu[]`（对齐 proto 定义）
- `ForumPageVersionState.value`：0=简化版 / 1=完整版
- `ForumFabFunctionState.value`：0=post / 1=refresh / 2=back_to_top / 3=hide

### 状态机

- `ForumPageFull` 内部状态：`isHeaderExpanded: boolean = true`（Header 展开/折叠）、`currentTabIndex: number = 0`（当前 Tab 索引）、`sortType: number = SORT_REPLY`（首页 Tab 排序）、`isGoodClassify: number = 0`（精品 Tab 分类 ID）
- Header 折叠状态机：列表上滑（`onDidScroll` 检测 `yOffset` 增量 < 0）时折叠，下滑到顶（`yOffset` 增量 > 0 且 `yOffset <= 0`）时展开
- FAB 模式状态：从 `ForumFabFunctionState.value` 读取，运行时不可切换（需进设置页修改）

### 视觉规范

- 完整版 Header 高度：展开时 200vp（含吧头像 80 + 等级进度条 32 + 按钮区 48 + padding），折叠时 0（完全隐藏，AppBar 显式吧名）
- Tab 切换条高度：48vp，使用 `HdsTabs` 单胶囊配置（`barHeight=48, barSideMargin=32, barBottomMargin=0, barOverlap=true`）
- FAB 尺寸：56x56，右下角 margin 16vp，背景 `window_background`，图标色 `primary`
- 左右安全边距：所有控件 16vp（遵循项目铁律）
- 深色模式：新增 UI 元素背景用 `input_background` 而非纯黑

### API 兼容性

- `HdsTabs` 单胶囊方案已验证（项目记忆铁律），单 TabContent 必须显式配置 `barWidth` 避免渲染成圆球
- `HdsNavDestination` 沉浸光感材质（`systemMaterialEffect: { materialType: IMMERSIVE, materialLevel: ADAPTIVE }`）API 23 已验证支持
- `bindToScrollable` 绑定 Scroller 实现 Header 折叠（通过 `onScrollFrame` 监听滚动增量）
- `animateTo` 包裹 Header 折叠状态变化（duration 200ms，curve EaseInOut）
- 所有新增 API 需确认 API 23 支持

### 协议层扩展

- `nav_tab_info` (FrsPage.DataRes field 37)：proto 定义已存在于 `references/protobuf/tbclient.protobuf-main/proto/FrsPage/NavTabInfo.proto`，鸿蒙版只需扩展解码器
- `ForumInfo` 字段扩展：avatar (24) / slogan (25) / is_like (6) / member_num (9) / thread_num (10) / user_level (7) / level_name (8) / cur_score (13) / levelup_score (14) 字段已在 proto 中定义
- `GetForumDetail` 接口端点 `/c/f/forum/getforumdetail?cmd=303021`，响应 proto 定义在 `references/protobuf/tbclient.protobuf-main/proto/GetForumDetail/`
- 通用 Tab 过滤规则：`is_general_tab == 1 && tab_type == 15`（对齐 TiebaLite-4.0-dev）

## Testing Decisions

### 测试策略

采用路由级集成测试 + 手动验证：

1. **路由级集成测试**（最高接缝）：验证开关切换、路由目标正确性、关键功能可点
2. **手动验证**：每个功能块完成后截图对比新旧效果
3. **协议层验证**：扩展的 FrsPageProto 解码器通过实际请求验证 nav_tab_info 字段正确解析
4. **GetForumDetail 接口验证**：在吧详情页手动进入验证接口响应正确解码

### 验证场景清单

- [ ] 开关关闭时从首页点击吧名跳转到 `ForumPage`（简化版）
- [ ] 开关打开时从首页点击吧名跳转到 `ForumPageFull`（完整版）
- [ ] 开关切换后立即生效（不需重启应用）
- [ ] 完整版 Header 展开/折叠动画流畅
- [ ] Tab 切换（首页/精品/动态 Tab）切换正常
- [ ] Tab 长按排序菜单弹出
- [ ] FAB 4 模式切换正常
- [ ] 发帖成功后列表自动刷新
- [ ] 关注/签到按钮状态正确切换
- [ ] 点击 Header 跳转吧详情页
- [ ] 吧详情页 4 元素正确显示
- [ ] 吧内搜索入口跳转 `SearchPage` 传入 fname
- [ ] AppBar 三点菜单（分享/发送到桌面/取消关注）功能正常
- [ ] 深色模式下所有新增 UI 元素显示正常
- [ ] 左右 16vp 安全边距所有控件对齐
- [ ] 沉浸光感材质与简化版视觉一致

### 测试接缝

- **最高接缝（路由级）**：通过 `RouterUtil.push` 验证路由目标正确性
- **次高接缝（开关响应）**：通过 `AppStorageV2` 监听 `ForumPageVersionState.value` 变化
- **协议层接缝**：通过实际请求 FrsPage 验证 `nav_tab_info` 字段解码正确性

## Out of Scope

1. **简化版 `ForumPage` 不修改**：保留现有简化版作为默认体验，仅通过开关切换路由目标
2. **吧主/吧务/吧规列表不实现**：安卓版 `ForumDetailPage` 实际只有 4 元素，不臆想补全这些列表
3. **`GetForumDetail` 接口返回的吧务管理功能不实现**：仅使用 `forum_info` 字段展示吧详情，不实现吧主选举/吧务申请等管理向功能
4. **`FeedCard` 组件不新建**：完整版帖子列表直接复用现有 `ThreadCard`，不新建 `FeedCard`
5. **精品分类 Chip 切换不实现**：精品 Tab 内部的 `GoodClassify` Chip 切换作为后续 issue，本次仅实现精品 Tab 基础列表
6. **`frs_tab_info` (field 22) / `frs_main_tab_list` (field 127) 等其他 Tab 字段不实现**：仅解码 `nav_tab_info` (field 37)
7. **发帖页 `ReplyPage` 不新建**：FAB 发帖跳转到现有帖子详情页的回复框（与现有发帖流程一致）
8. **桌面快捷方式创建逻辑**：本次仅实现菜单项占位，实际桌面快捷方式创建作为后续 issue
9. **路由转场动画**：本次不实现页面切换转场动画（已有 issue #206 跟踪）

## Further Notes

### 关键约束

1. **沉浸光感一致性**：项目记忆铁律"沉浸光感组件必须检查完整渲染层级"，`ForumPageFull` 内部禁止加 `backgroundBlurStyle/backgroundColor/borderRadius`（避免与外层 HDS 材质叠加形成白色内层）
2. **左右 16vp 安全边距**：所有页面所有控件必须 16vp 左右边距（项目铁律）
3. **悬浮 TabBar 下方禁止加 padding/遮罩**：项目铁律，`HdsTabs` 配置 `barOverlap(true) + barFloatingStyle`
4. **系统底部手势导航条下方禁止加遮罩**：项目铁律，滚动容器禁止加 `padding bottom: safeBottom`
5. **资源字符串**：新增文案通过 `$r` 引用，不直接字面值
6. **API 23 兼容**：项目 `compatibleSdkVersion: 6.1.0(23)`，所有新增 API 需确认 API 23 支持
7. **HdsTabs 单胶囊方案**：项目记忆铁律，单 TabContent 必须显式配置 `barWidth`，双胶囊方案已废弃
8. **状态管理 V2**：使用 `@ComponentV2 + @Local + @Param + @Event + @Monitor + @ObservedV2 + @Trace + AppStorageV2`，不使用 V1

### 待运行时确认项

1. `HdsTabs` 在 `ForumPageFull` 中是否需要 `barFloatingStyle` 配置悬浮效果（参考 `MainPage` 配置）
2. `HdsNavDestination` 的 `bindToScrollable` 是否支持同时绑定 List 和 HdsTabs 的 Scroller（用于 Header 折叠 + Tab 切换条联动）
3. `GetForumDetail` 接口在鸿蒙版 `TiebaAPI` 中的 Cookie 与 BDUSS 鉴权方式（protobuf 端点，需在 CommonReq field 10 注入 BDUSS）
4. `nav_tab_info` 字段在实际 FrsPage 响应中的命中率（部分吧可能不返回该字段，需降级到固定 2 Tab）

### 复用现有资产

- `ThreadCard` 组件：完整版帖子列表直接复用，所有 6 个事件回调可用
- `ForumViewModel` 类：扩展字段后可被完整版复用（新增 `navTabInfo` / `forumDetailInfo` 字段）
- `TiebaAPI.signForum` / `followForum` / `unfollowForum`：签到/关注/取关接口已实现
- `TiebaAPI.searchExact`：吧内搜索接口已实现（参数含 fname/keyword/searchType）
- `handleThreadAgree` / `handleThreadDisagree`：点赞/点踩 helper 已实现
- `VibratorUtil.heavy`：触感反馈已实现
- `LoadingView` / `ErrorView`：加载/错误视图已实现
- `CommonDataSource`：LazyForEach 数据源已实现

### 安卓版对齐参考

- 主页面：`references/android/TiebaLite-4.0-dev/app/src/main/java/com/huanchengfly/tieba/post/ui/page/forum/ForumPage.kt`
- 吧详情页：`references/android/TiebaLite-4.0-dev/app/src/main/java/com/huanchengfly/tieba/post/ui/page/forum/detail/ForumDetailPage.kt`
- 帖子列表：`references/android/TiebaLite-4.0-dev/app/src/main/java/com/huanchengfly/tieba/post/ui/page/forum/threadlist/ForumThreadListPage.kt`
- 通用 Tab 列表：`references/android/TiebaLite-4.0-dev/app/src/main/java/com/huanchengfly/tieba/post/ui/page/forum/generaltablist/GeneralTabListPage.kt`
- 吧内搜索：`references/android/TiebaLite-4.0-dev/app/src/main/java/com/huanchengfly/tieba/post/ui/page/forum/searchpost/ForumSearchPostPage.kt`
- Proto 定义：`references/protobuf/tbclient.protobuf-main/proto/FrsPage/` 和 `references/protobuf/tbclient.protobuf-main/proto/GetForumDetail/`
