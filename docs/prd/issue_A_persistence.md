## Parent

#233

## What to build

为 TabVisibilityState / MaterialLevelState / 新增的 HomeListModeState 建立持久化机制，让用户的 Tab 显隐、沉浸光感强度、列表模式偏好在应用重启后保持。沿用项目现有 AppStorageManager（preferences 文件）机制，不引入 PersistenceV2。

具体行为：
- 在 `AppStorageV2Models.ets` 新增 `HomeListModeState`（@ObservedV2 + @Trace value: number，0=SINGLE / 1=DOUBLE_FULL / 2=DOUBLE_COMPACT）+ `connectHomeListMode()` + `resolveHomeListMode()` helper。
- EntryAbility.onCreate 中 AppStorageInit 启动任务完成后，从 AppStorageManager 读取 `tabVisibility` / `materialLevel` / `homeListMode` 三个 number 值，写入对应 AppStorageV2 connect 出来的 state.value。
- SettingsPage 写入 `connectXxx().value = newValue` 后立即 `await AppStorageManager.setNumber('xxx', newValue)`，失败时 toast 提示并回滚 state.value。
- 移除或注释旧 `HomeDualColumnState`（被 HomeListModeState 替换，避免双状态混淆）。同步更新所有引用方（HomePage、SettingsPage）。

## Acceptance criteria

- [ ] AppStorageV2Models.ets 新增 HomeListModeState 类、connectHomeListMode() 和 resolveHomeListMode() 导出
- [ ] HomeDualColumnState 被移除或替换，所有引用方改用 HomeListModeState
- [ ] EntryAbility.onCreate 在 AppStorageInit 完成后从 preferences 读取 tabVisibility / materialLevel / homeListMode 三个字段并写入 AppStorageV2 state
- [ ] SettingsPage 的 onTabFavoriteToggle / onTabMessageToggle / onTabProfileToggle / setMaterialLevel / setHomeListMode 在写入 state.value 后同步调用 AppStorageManager.setNumber 持久化
- [ ] 持久化失败时（如 preferences 写入异常）toast 提示用户并回滚 state.value 到原值
- [ ] 编译通过：`hvigorw assembleHap -p product=default -p buildMode=debug` BUILD SUCCESSFUL
- [ ] 真机验证：关闭"动态"Tab → 退出应用 → 重新打开 → 底栏 Tab 仍不显示动态，开关状态保持关闭
- [ ] 真机验证：切换"沉浸光感强度"为"精致" → 退出 → 重开 → 强度保持"精致"
- [ ] 真机验证：切换"列表展示模式"3 档 → 退出 → 重开 → 模式保持

## Blocked by

None - can start immediately
