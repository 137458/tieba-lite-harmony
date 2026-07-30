## Parent

#233

## What to build

ThreadCard 顶层 build() 根据 `thread.isTop` 字段分支渲染：置顶帖用简洁样式（左侧"置顶"Chip + 右侧单行标题），普通帖保持现有 FeedCard 样式。对齐 Android 原版 TopThreadItem + FeedCard 分支渲染逻辑。

具体行为：
- ThreadCard.build() 顶层加 `if (this.thread.isTop) { this.TopThreadItem() } else { /* 现有 FeedCard 主体 */ }`。
- 新增 `@Builder TopThreadItem()`：Row 布局
  - 左侧"置顶"Chip：圆角 3vp（非默认胶囊形），背景色 themeState.primary，文字白色加粗 12sp，padding horizontal 16vp vertical 4vp
  - 右侧标题 Text：layoutWeight(1)，maxLines(1)，textOverflow Ellipsis，fontSize 15，fontWeight Medium，fontColor text_primary
  - 卡片整体 padding 16vp，hitTestBehavior Transparent 让 onClick 跳转详情
  - 无作者信息 / 无媒体 / 无操作按钮
- 调用方（HomePage/FavoritePage 各 Tab 的 LazyForEach）的后续项前判断：若上一项是 isTop、当前项不是 isTop，插入 8vp Blank 作为视觉分隔。
- 置顶 Chip 颜色在深色模式下协调（用 themeState.primary 自动跟随主题）。

参考实现（来自 Android 原版 ForumThreadListPage.kt L136-163）：
```
TopThreadItem(title, onClick, type = "置顶") {
  Row(padding 16dp) {
    Chip(text = "置顶", shape = RoundedCornerShape(3.dp))  // 3dp 圆角矩形
    Text(title, maxLines=1, ellipsis, fontSize=15.sp, fontWeight=Medium, weight=1f)
  }
}
```

## Acceptance criteria

- [ ] ThreadCard.ets build() 顶层根据 this.thread.isTop 分支渲染
- [ ] 新增 @Builder TopThreadItem()：Row 布局，左侧"置顶"Chip + 右侧单行标题
- [ ] 置顶 Chip：圆角 3vp，背景 themeState.primary，文字白色加粗 12sp
- [ ] 置顶帖标题：maxLines(1)，ellipsis，fontSize 15，fontWeight Medium
- [ ] 置顶帖不显示作者信息、媒体、操作按钮
- [ ] 置顶帖点击仍跳转帖子详情页（hitTestBehavior Transparent + onClick）
- [ ] LazyForEach 渲染时，从置顶帖切到第一个普通帖插入 8vp Blank 分隔
- [ ] 深色模式下置顶 Chip 颜色协调（用 themeState.primary 跟随主题）
- [ ] 新增字符串资源 content_top="置顶" 同步添加到 base/zh_CN/en_US 三套 string.json
- [ ] 编译通过：`hvigorw assembleHap -p product=default -p buildMode=debug` BUILD SUCCESSFUL
- [ ] 真机验证：论坛页帖子列表置顶帖显示为"Chip + 单行标题"简洁样式，普通帖保持原样
- [ ] 真机验证：从置顶帖到第一个普通帖之间有 8vp 间距

## Blocked by

None - can start immediately
