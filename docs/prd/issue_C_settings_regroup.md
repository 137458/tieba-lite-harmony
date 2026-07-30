## Parent

#233

## What to build

SettingsPage 重新分类为 4 组（个性化 / 内容 / 账号 / 其他），并修复多个体验问题：滚动条隐藏、"收藏"→"动态"文字对齐、新增 3 档列表模式菜单项。

具体行为：
- Scroll 容器加 `.scrollBar(BarState.Off)`，滚动时不显示滚动条。
- 4 组分类容器：每组用 Column 包裹，组间 12vp 间距，组内菜单项之间保留现有 divider。
- 组标题 Text（fontSize 13, fontWeight Medium, color text_secondary, margin top 12 bottom 4 left 4）：
  - **个性化**：主题、颜色模式、字体大小、沉浸光感强度、列表展示模式
  - **内容**：图片加载设置、底栏 Tab 显示（含 3 个 Toggle）、帖子详情悬浮底栏
  - **账号**：BDUSS、退出登录
  - **其他**：清除缓存、通知设置、关于
- "收藏"文字改"动态"：`settings_tab_favorite` 值从"收藏"改为"动态"（与底栏 Tab 实际显示"动态"对齐，避免认知歧义）。
- 新增 `homeListModeMenuItemBuilder()`：右侧显示当前档位文字 + bindMenu 3 档选择（单列 / 双列完整 / 双列精简——只显示吧等级和吧名称），选中档位带 ✓ 标记。
- 新增字符串资源：`settings_list_mode` / `settings_list_mode_single` / `settings_list_mode_double_full` / `settings_list_mode_double_compact` 同步添加到 base/zh_CN/en_US 三套 string.json。

## Acceptance criteria

- [ ] SettingsPage.ets 的 Scroll 加 `.scrollBar(BarState.Off)`，滚动时无滚动条
- [ ] build() 重组为 4 组分类容器，每组用 Column 包裹，组间 12vp 间距
- [ ] 4 个组标题正确显示：个性化 / 内容 / 账号 / 其他
- [ ] "个性化"组包含：主题、颜色模式、字体大小、沉浸光感强度、列表展示模式
- [ ] "内容"组包含：图片加载设置、底栏 Tab 显示（3 个 Toggle）、帖子详情悬浮底栏
- [ ] "账号"组包含：BDUSS、退出登录
- [ ] "其他"组包含：清除缓存、通知设置、关于
- [ ] `settings_tab_favorite` 字符串值从"收藏"改为"动态"
- [ ] 新增 homeListModeMenuItemBuilder() builder，3 档 bindMenu（单列/双列完整/双列精简）
- [ ] 选中档位显示 ✓ 标记
- [ ] 新增字符串资源（settings_list_mode 系列）添加到 base/zh_CN/en_US 三套 string.json
- [ ] 编译通过：`hvigorw assembleHap -p product=default -p buildMode=debug` BUILD SUCCESSFUL
- [ ] 真机验证：设置页 4 组分类正确显示，组内菜单项与设计一致
- [ ] 真机验证：滚动设置页无滚动条显示
- [ ] 真机验证：底栏 Tab 显示开关文字为"动态"（非"收藏"）
- [ ] 真机验证：列表展示模式 3 档可切换，选中档位有 ✓ 标记

## Blocked by

- #234（持久化机制切片，新增 HomeListModeState 后本切片才能引用）
