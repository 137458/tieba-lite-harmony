## Parent

- #245 (PRD：添加完整版吧内页面)

## What to build

为完整版吧内页面编写路由级集成测试，验证开关切换、路由目标正确性、关键功能可点：

1. **测试接缝**（按优先级）：
   - **最高接缝（路由级）**：通过 `RouterUtil.push` 验证路由目标正确性
   - **次高接缝（开关响应）**：通过 `AppStorageV2` 监听 `ForumPageVersionState.value` 变化
   - **协议层接缝**：通过实际请求 FrsPage 验证 `nav_tab_info` 字段解码正确性

2. **路由级集成测试**：使用 `arkxtest` 框架（项目记忆提到已用于测试），编写以下测试用例：
   - **开关切换路由测试**：
     - 开关关闭时从 HomePage 点击吧名跳转，验证路由栈顶为 `ForumPage`
     - 开关打开时从 HomePage 点击吧名跳转，验证路由栈顶为 `ForumPageFull`
     - 开关切换后立即生效（不需重启应用）
   - **完整版关键功能可点测试**：
     - 完整版 Header 关注按钮可点
     - 完整版 Header 签到按钮可点
     - 完整版 Header 吧名区域可点（跳转吧详情页）
     - 完整版 Tab 切换条可切换（首页/精品）
     - 完整版 FAB 可点（默认发帖模式）
     - 完整版 AppBar 搜索图标可点
     - 完整版 AppBar 三点菜单可展开
   - **吧详情页路由测试**：
     - 从完整版 Header 跳转吧详情页，验证路由栈顶为 `ForumDetailPage`
     - 吧详情页返回按钮可点
   - **协议层解码测试**：
     - FrsPage 响应包含 `nav_tab_info` 字段时正确解码为 `NavTabInfo` 对象
     - FrsPage 响应不包含 `nav_tab_info` 字段时不报错（返回 null）
     - `GetForumDetail` 响应正确解码为 `ForumDetailInfo` 对象

3. **测试文件组织**：参考项目现有测试目录结构（如 `entry/src/ohosTest/` 或类似位置），新增测试文件：
   - `ForumPageFullRouteTest.ets`：路由级集成测试
   - `ForumDetailPageRouteTest.ets`：吧详情页路由测试
   - `FrsPageProtoDecodeTest.ets`：协议层解码测试（如已有则扩展）

4. **测试运行**：通过 `hvigorw test` 或 DevEco Studio 运行测试，确保所有测试用例通过。

5. **完整验证场景清单**（参考 PRD #245）：
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

## Acceptance criteria

- [ ] 路由级集成测试文件 `ForumPageFullRouteTest.ets` 创建成功
- [ ] 开关关闭时路由测试通过（跳转 `ForumPage`）
- [ ] 开关打开时路由测试通过（跳转 `ForumPageFull`）
- [ ] 开关切换立即生效测试通过
- [ ] 完整版 Header 关注/签到按钮可点测试通过
- [ ] 完整版 Header 吧名区域可点测试通过（跳转吧详情页）
- [ ] 完整版 Tab 切换测试通过
- [ ] 完整版 FAB 可点测试通过
- [ ] 完整版 AppBar 搜索图标可点测试通过
- [ ] 完整版 AppBar 三点菜单可展开测试通过
- [ ] 吧详情页路由测试通过
- [ ] 协议层解码测试通过（`nav_tab_info` 字段解码 + `GetForumDetail` 解码）
- [ ] 所有测试用例通过（`hvigorw test` 或 DevEco Studio 测试运行）
- [ ] 完整验证场景清单全部勾选完成
- [ ] 编译通过（`hvigorw assembleHap` BUILD SUCCESSFUL）

## Blocked by

- #246（切片 0：基础设施 + 骨架 + Header）
- #247（切片 1：Tab 切换 + 帖子列表 + 排序持久化）
- #248（切片 2：FAB 4 模式）
- #249（切片 3：吧详情页 ForumDetailPage）
- #250（切片 4：吧内搜索 + AppBar 三点菜单）
