## Parent

#233

## What to build

HomePage 列表展示从 boolean（homeDualColumnState）升级为 3 档枚举（homeListModeState），新增"双列精简"模式：只显示吧等级和吧名称的圆角小卡片，适合关注吧很多时快速浏览。

具体行为：
- HomePage 的 `homeDualColumnState` 替换为 `homeListModeState`（来自切片 A #234）。
- Grid 渲染逻辑：
  - `mode === 0`（SINGLE）：用现有 List + 完整 FeedCard 单列布局。
  - `mode === 1`（DOUBLE_FULL）：用现有 Grid + 完整 FeedCard 双列布局。
  - `mode === 2`（DOUBLE_COMPACT）：用 Grid + 新增 ForumCardCompact 组件（仅显示吧等级 + 吧名称的精简卡片）。
- 新增 `@Builder ForumCardCompact(forum: SelfFollowForum)` 或独立 @ComponentV2 组件：
  - 卡片尺寸：Grid 2 列等分，aspectRatio 约 1.5（接近正方形偏宽）
  - 内容：吧名 Text（maxLines 1, ellipsis, fontSize 14, fontWeight Medium）+ 吧等级 Text（"Lv." + level, fontSize 12, color themeState.primary）
  - 圆角 10vp，背景 card_background，padding 12vp
  - hitTestBehavior Transparent + onClick 跳转 ForumPage
  - 不显示头像 / 不显示最新帖标题 / 不显示签到按钮
- 设置页 bindMenu 切换 `homeListModeState.value`，HomePage `@Monitor('homeListModeState.value')` 自动响应刷新布局。
- 持久化由切片 A #234 处理（写入时同步 AppStorageManager.setNumber）。

## Acceptance criteria

- [ ] HomePage.ets 的 homeDualColumnState 替换为 homeListModeState
- [ ] build() 根据 homeListModeState.value 分 3 档渲染：SINGLE(0) / DOUBLE_FULL(1) / DOUBLE_COMPACT(2)
- [ ] 新增 ForumCardCompact 组件（@Builder 或独立 @ComponentV2）
- [ ] ForumCardCompact 显示：吧名（maxLines 1, ellipsis）+ 吧等级（"Lv." + level）
- [ ] ForumCardCompact 不显示头像 / 最新帖标题 / 签到按钮
- [ ] ForumCardCompact 卡片：圆角 10vp，背景 card_background，padding 12vp，aspectRatio 约 1.5
- [ ] ForumCardCompact 点击跳转 ForumPage
- [ ] @Monitor('homeListModeState.value') 自动响应设置页切换，立即刷新布局
- [ ] 编译通过：`hvigorw assembleHap -p product=default -p buildMode=debug` BUILD SUCCESSFUL
- [ ] 真机验证：3 档切换正确响应（单列/双列完整/双列精简）
- [ ] 真机验证：精简模式只显示吧等级和吧名称，卡片整齐排列
- [ ] 真机验证：切换模式后退出应用再重开，模式保持

## Blocked by

- #234（持久化机制切片，新增 HomeListModeState）
- #238（设置页分类重组切片，新增 homeListModeMenuItemBuilder）
