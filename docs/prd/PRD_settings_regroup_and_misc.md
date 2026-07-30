# PRD：设置页分类重组与多组件体验优化

## Problem Statement

承接 #201 完成后的多维度用户反馈，目前 HarmonyOS 端 Tieba 应用存在 9 个独立体验问题，分布在详情页菜单交互、设置页信息架构、列表展示模式、热榜视觉、置顶帖渲染 5 个功能域。用户期望一次性收口这些遗留体验问题，使整体观感与安卓原版对齐。

## Solution

按功能域分批修复，所有改动均复用现有 HDS 组件与 AppStorageV2/AppStorageManager 持久化机制，不引入新依赖。具体方案：

1. 详情页"更多"按钮的菜单从底部 ActionSheet 改为锚点 bindMenu（从按钮下方右对齐展开），保留沉浸光感材质（继承 titleBar systemMaterialEffect）。
2. SettingsPage 的 Scroll 容器关闭滚动条（`.scrollBar(BarState.Off)`）。
3. TabVisibilityState/MaterialLevelState 双向持久化：写入时同步到 AppStorageManager（preferences 文件），启动时由 EntryAbility 从 preferences 读回 AppStorageV2，解决重启丢失问题。
4. SettingsPage 中 Tab 开关文字与底栏 Tab 实际显示一致：底栏 Tab 显示"动态"，设置页开关也写"动态"。
5. SettingsPage 重新分类为 4 组：个性化 / 内容 / 账号 / 其他。
6. HomePage 列表模式从 boolean 升级为 3 档枚举（SINGLE 单列 / DOUBLE_FULL 双列完整 / DOUBLE_COMPACT 双列精简——只显示吧等级 + 吧名称），设置页用 bindMenu 3 选 1。
7. FavoritePage 热榜 HotTopicItem 在深色模式下的黑色遮罩修复（根因排查并修正背景色/边框叠加）。
8. "话题榜"标题位置调整（margin left 增大，从贴边右移）。
9. ThreadCard 根据 `thread.isTop` 字段分支渲染：置顶帖用简洁样式（"置顶" Chip + 单行标题，无作者/无媒体/无操作按钮），普通帖保持现有 FeedCard 样式。对齐 Android 原版 `TopThreadItem` + `FeedCard` 分支渲染逻辑。

## User Stories

1. 作为帖子详情页用户，我希望点击 titleBar 右侧"更多"按钮后菜单从按钮下方右对齐展开，而不是从底部弹出 ActionSheet，这样菜单位置与触发按钮有视觉关联，交互更直觉。
2. 作为帖子详情页用户，我希望"更多"菜单中的选项与之前一致（收藏 / 分享 / 只看楼主 / 排序 / 跳页 / 沉浸模式），这样功能不丢失。
3. 作为帖子详情页用户，我希望"更多"菜单中的"排序"二级菜单依然可用（正序 / 倒序 / 热门），这样排序切换不受影响。
4. 作为设置页用户，我希望滚动设置页时不出现滚动条，这样视觉更干净。
5. 作为设置页用户，我希望关闭"底栏 Tab 显示 - 收藏"开关后退出应用再进入，开关状态保持关闭，这样我的偏好被持久记住。
6. 作为设置页用户，我希望切换"沉浸光感强度"档位后退出应用再进入，档位保持我选的值，这样不用每次重新设置。
7. 作为设置页用户，我希望底栏 Tab 显示开关的文字与底栏实际显示一致——底栏 Tab 显示"动态"时，设置页开关也写"动态"，这样不会产生认知歧义。
8. 作为设置页用户，我希望设置项按功能域分组（个性化 / 内容 / 账号 / 其他），每组用标题分隔，这样我能在长列表中快速定位。
9. 作为设置页用户，我希望"个性化"组包含：主题、颜色模式、字体大小、沉浸光感强度、列表展示模式。
10. 作为设置页用户，我希望"内容"组包含：图片加载设置、底栏 Tab 显示、帖子详情悬浮底栏、小尾巴。
11. 作为设置页用户，我希望"账号"组包含：BDUSS、退出登录。
12. 作为设置页用户，我希望"其他"组包含：清除缓存、通知设置、关于。
13. 作为首页用户，我希望列表展示模式有 3 档可选（单列 / 双列完整 / 双列精简），这样我能根据偏好选择信息密度。
14. 作为首页用户，我希望"双列精简"模式只显示吧等级和吧名称（无头像/无最新帖标题/无签到按钮），这样在关注吧很多时能快速浏览。
15. 作为首页用户，我希望切换列表模式后状态被持久化，重启应用后保持我的选择。
16. 作为热榜 Tab 用户，我希望深色模式下话题榜条目没有黑色遮罩，与其他卡片背景色一致，这样视觉不割裂。
17. 作为热榜 Tab 用户，我希望"话题榜"三个字的位置往右移一点，不再贴边显示，这样与其他内容对齐。
18. 作为帖子列表用户，我希望置顶帖子用简洁样式显示（左侧"置顶"Chip + 右侧单行标题，无作者信息/无媒体/无操作按钮），这样能视觉上区分置顶帖与普通帖。
19. 作为帖子列表用户，我希望从置顶帖切换到第一个普通帖时有一个 8vp 的视觉分隔间距，这样置顶区与普通列表有明确分界。
20. 作为帖子列表用户，我希望置顶帖点击后依然跳转到帖子详情页，行为与普通帖一致。
21. 作为深色模式用户，我希望置顶 Chip 在深色模式下颜色协调，使用主题色作为背景，这样不出现颜色失配。
22. 作为开发者，我希望 TabVisibilityState/MaterialLevelState/HomeListModeState 的持久化机制与项目其他设置项（深色模式/字体大小/图片加载策略）一致，使用 AppStorageManager + preferences 文件，不引入 PersistenceV2 等新机制。
23. 作为开发者，我希望 ThreadCard 的置顶帖分支通过 `@Param thread.isTop` 驱动渲染，不修改 ThreadInfo 数据结构。
24. 作为开发者，我希望所有新增字符串资源同步添加到 base/zh_CN/en_US 三套 element/string.json，避免国际化遗漏。

## Implementation Decisions

### 模块改动清单

**AppStorageV2Models.ets**
- 新增 `HomeListModeState`（@ObservedV2 + @Trace value: number，0=SINGLE / 1=DOUBLE_FULL / 2=DOUBLE_COMPACT），导出 `connectHomeListMode()` 安全连接 helper 和 `resolveHomeListMode()` 枚举映射函数。
- 移除旧 `HomeDualColumnState`（被 HomeListModeState 替换），或在 HomeDualColumnState 上加 deprecation 注释保留兼容（推荐直接删除避免双状态混淆）。
- TabVisibilityState/MaterialLevelState 保持现有结构，**不在 AppStorageV2 层做持久化**（AppStorageV2 默认内存态，PersistenceV2 API 不稳定且项目未使用），持久化由 EntryAbility 启动时从 AppStorageManager 读回 + 写入方同步 setNumber 完成。

**EntryAbility.ets**
- `onCreate` 中 AppStorageInit 启动任务完成后，从 AppStorageManager 读取 `tabVisibility` / `materialLevel` / `homeListMode` 三个 number 值，写入对应的 AppStorageV2 connect 出来的 state.value。
- 已有的 bduss / theme / imageLoadType 等读取逻辑保持不变，新增 3 个数字字段的读取。

**SettingsPage.ets**
- `Scroll` 加 `.scrollBar(BarState.Off)`。
- 4 组分类容器：每组用 Column 包裹，组间 12vp 间距，组内菜单项之间保留现有 divider。
- 组标题用 Text（fontSize 13, fontWeight Medium, color text_secondary, margin top 12 bottom 4 left 4）。
- 新增 `homeListModeMenuItemBuilder()`：3 档 bindMenu（单列 / 双列完整 / 双列精简）。
- Tab 开关组：文字"收藏"→"动态"（`settings_tab_favorite` 字符串值改为"动态"，或新增 `settings_tab_dynamic` 替换引用，保留 key 兼容）。
- 写入 TabVisibilityState/MaterialLevelState/HomeListModeState 时同步调用 `AppStorageManager.setNumber(key, value)` 持久化。

**ThreadPage.ets**
- `showMoreActionMenu()` 改为：将按钮自身作为 bindMenu 的锚点（用 ComponentContent 或保留 titleBar menu 配置的 `bindMenu` 内嵌），菜单项 array 与原 showActionMenu 一致。
- 实现：在 titleBar.menu 的 menu.value[0] 上加 `.bindMenu()`，Placement 用 `Placement.BottomRight`（按钮下方右对齐，菜单往左展开），`titleBar menu` 的 `action` 触发弹出（保留按钮沉浸光感材质），Menu 与 showActionMenu 选项完全一致。
- 排序二级菜单：用二级 bindMenu（hover 第一个菜单的"排序"项时展开）或保留 showActionMenu 二级弹窗。

**HomePage.ets**
- `homeDualColumnState` 替换为 `homeListModeState`。
- Grid 的 List 渲染逻辑：`mode === 1` 用现有 FeedCard 完整双列，`mode === 2` 用新增 `ForumCardCompact`（仅显示吧等级 + 吧名称，圆角小卡片，单行布局）。
- 单列模式 `mode === 0` 保持现有 List + FeedCard。
- 设置页 bindMenu 写入 `homeListModeState.value`，HomePage `@Monitor` 自动响应刷新布局。

**FavoritePage.ets**
- `HotTopicSection` 的 "话题榜" Text 加 `.margin({ left: 4 })` 或调整 ListItem 的 left margin。
- `HotTopicItem` 排查深色模式黑色遮罩根因：检查 `backgroundColor($r('app.color.background'))` 与父 `Grid`/`Column` 的 `backgroundColor($r('app.color.card_background'))` 在深色模式下的实际色值，确认是否资源引用错误或叠加 shadow/border 导致遮罩。修复方案待根因排查后确定。

**ThreadCard.ets**
- 顶层 `build()` 加 `if (this.thread.isTop) { this.TopThreadItem() } else { /* 现有 FeedCard 主体 */ }` 分支。
- 新增 `@Builder TopThreadItem()`：Row 布局，左侧"置顶" Chip（圆角 3vp，背景色 theme.primary，文字白色加粗 12sp）+ 右侧标题 Text（layoutWeight 1, maxLines 1, ellipsis, fontSize 15, fontWeight Medium），无作者/无媒体/无操作按钮。
- 卡片整体 padding 16vp，hitTestBehavior Transparent 让 onClick 跳转详情。
- 调用方（HomePage/FavoritePage 各 Tab）的 LazyForEach 后续项前判断：若上一项是置顶、当前项不是置顶，插入 8vp Blank 作为视觉分隔。

### 持久化机制决策

- **不引入 PersistenceV2**：项目其他设置项（深色模式/字体大小/图片加载策略/小尾巴/帖子悬浮底栏开关）均使用 `AppStorageManager`（preferences 文件）持久化，保持一致。
- **AppStorageV2 作为运行时全局共享态**：UI 层 connect 后响应式更新，启动时由 EntryAbility 从 preferences 读回写入。
- **写入路径**：SettingsPage 调用 `connectXxx().value = newValue` 后立即 `await AppStorageManager.setNumber('xxx', newValue)`，失败时 toast 提示并回滚 state.value。
- **读取路径**：EntryAbility.onCreate 中 AppStorageInit 启动任务完成后，调用 `AppStorageManager.getNumber('xxx', defaultValue)` 读回值写入 AppStorageV2。

### MenuOptions 沉浸光感限制

- HDS `MenuOptions` 接口无 `systemMaterialEffect` 字段（API 硬限制），弹出菜单本身无法应用沉浸光感。
- 但 `bindMenu` 锚定在 titleBar menu 按钮上，按钮自身继承 titleBar 的 systemMaterialEffect 沉浸光感，弹出的 Menu 在按钮旁边视觉上仍与沉浸光感区域关联。
- 接受此限制，不再尝试为 Menu 强加 backgroundBlurStyle（之前测试会与系统材质冲突）。

### 列表模式枚举状态机

```
HomeListMode:
  0 = SINGLE         // 单列，现有 List + 完整 FeedCard
  1 = DOUBLE_FULL    // 双列完整，现有 Grid + FeedCard
  2 = DOUBLE_COMPACT // 双列精简，Grid + ForumCardCompact（仅等级+名称）
```

### 置顶帖渲染决策

- ThreadInfo.isTop 字段已存在（ForumModels.ets L38，@Trace isTop: boolean = false）。
- 安卓原版 `TopThreadItem` 实现：Row { Chip("置顶", 3dp 圆角) + Text(title, maxLines=1, ellipsis) }，无作者/媒体/操作。
- 不显式拆分置顶区与普通区，跟随服务端返回顺序渲染，仅在 isTop 切换到非 isTop 时插入 8vp 分隔。
- 置顶 Chip 颜色：背景 `themeState.primary`，文字白色加粗 12sp，圆角 3vp（对齐安卓 3dp 圆角矩形而非默认胶囊形）。

## Testing Decisions

### 测试 seams

- **AppStorageManager 持久化**：现有 `AppStorageManager` 是单例 preferences 封装，已被深色模式/字体大小等设置使用。新增 3 个 number 字段（tabVisibility/materialLevel/homeListMode）沿用同一持久化路径，**不引入新 seam**。
- **ThreadCard isTop 分支**：现有 `ThreadCard` 是 @ReusableV2 @ComponentV2，通过 `@Require @Param thread: ThreadInfo` 接收数据，`isTop` 字段已是 @Trace。新分支在 build() 顶层判断，**不需要新 seam**。
- **HomeListMode 状态**：与现有 HomeDualColumnState 同位置（AppStorageV2Models），UI 层 connect 后响应，**不需要新 seam**。

### 手工验证项（无自动化测试框架，沿用项目惯例）

1. 设置页关闭"动态"Tab 开关 → 退出应用 → 重新打开 → 底栏 Tab 不显示动态，开关状态保持关闭。
2. 设置页切换"沉浸光感强度"为"精致" → 退出 → 重开 → 强度保持"精致"，TabBar 视觉变化。
3. 设置页切换"列表展示模式"3 档 → 首页立即响应布局变化 → 退出 → 重开 → 模式保持。
4. 帖子详情页点击 titleBar "更多"按钮 → 菜单从按钮下方右对齐展开（非底部 ActionSheet）。
5. 设置页滚动 → 无滚动条显示。
6. 设置页 4 组分类标题正确显示，组内菜单项与设计一致。
7. 深色模式进入热榜 Tab → 话题榜条目无黑色遮罩，背景色与父容器一致。
8. "话题榜"标题与下方条目对齐，不贴左边。
9. 论坛页帖子列表置顶帖显示为"Chip + 单行标题"简洁样式，普通帖保持原样。
10. 从置顶帖到第一个普通帖之间有 8vp 间距。

## Out of Scope

- 不修改 ThreadInfo 数据结构（isTop 字段已存在）。
- 不引入 PersistenceV2 等 V2 持久化新机制（保持与现有设置项一致用 AppStorageManager）。
- 不修改 HDS MenuOptions 接口（API 硬限制无法加 systemMaterialEffect）。
- 不为 Menu 弹出本身应用沉浸光感材质（接受按钮继承沉浸光感、菜单本身普通材质的限制）。
- 不修改关注 Tab / 推荐 Tab / 热榜 Tab 内部的帖子渲染逻辑（仅修改 ThreadCard 顶层分支）。
- 不修改 FavoritePage 内部 3-Tab 的 Tab 名（关注/推荐/热榜保持不变），只改底栏 Tab 文字与设置开关文字的一致性。
- 不调整通知/关于/退出登录等已有功能的实现，仅归到对应分类组下。

## Further Notes

- 用户对"动态"Tab 命名的澄清：底栏 Tab 当前已显示"动态"（资源 `tab_favorite` 值为"动态"？需核实），设置页开关文字写的"收藏"（`settings_tab_favorite` 值为"收藏"），两者不一致。修复方式：把 `settings_tab_favorite` 值改为"动态"，与底栏 Tab 保持一致。**实施时先 grep 确认 `tab_favorite` 的实际资源值，再决定改哪个**。
- 用户偏好"效果最优"铁律：ThreadCard 置顶帖分支要严格对齐安卓原版 TopThreadItem 视觉，不要在普通 FeedCard 上叠加"置顶"标签的妥协方案。
- 实施顺序建议：先持久化机制（解决状态丢失）→ 设置页分类与列表模式（基础设施）→ ThreadCard isTop 分支（独立）→ 详情页菜单锚点 → 热榜视觉修复（最小改动）。
