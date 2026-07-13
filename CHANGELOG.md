# 更新日志

本项目所有版本变更记录。GitHub Release 仅保留简短摘要，详细内容见本文件。

## [v1.2.0] - 2026-07-13

### 路由架构迁移（#162-#170, #194-#196）

- **HdsNavigation 全量迁移**：Index.ets Navigation → HdsNavigation；全部页面 NavDestination → HdsNavDestination + titleBar
- **RouterUtil 封装**：NavPathStack 单例管理，push/replace/back 统一 API，替代 @ohos.router
- **路由表配置**：router_map.json 声明式路由，main_pages.json 精简
- **titleBar 沉浸光感材质**：GRADIENT_BLUR 渐变模糊 + ADAPTIVE 沉浸光感，内容滚动时顶栏动态模糊
- **三种避让模式**：非穿透模式（Column/List padding top）/ Scroll 自动避让 / 穿透模式（clip(false) + cachedCount）
- **HomePage 混合式穿透**：Refresh + List 双 clip(false) 让内容穿透到 titleBar 下方做模糊
- **FavoritePage Tab 栏 bottomBuilder**：Tab 栏作为 titleBar 的 bottomBuilder 与 titleBar 同层，解决穿透模式下 Tab 栏被模糊和灰色遮罩问题

### UI 优化

- **HomePage 双列网格**：首页帖子卡片双列瀑布流布局
- **HomePage 浮动顶栏**：titleBar menu 加排序按钮，图标颜色跟随主题色
- **WebLoginPage 全屏 WebView**（#167）：网页登录页全屏沉浸式体验，登录成功 toast 提示
- **关于页 Telegram**：AboutPage 新增 Telegram 联系方式
- **ForumPage 吧头像**：吧详情页展示吧头像
- **主题动态取色修复**：ThemePage 动态取色卡片移入 Scroll，修复跑到状态栏 + 左右边距丢失

### 性能优化

- **protobuf 解码 TaskPool 化**（#201）：protobuf 解码迁移到 TaskPool 子线程，避免阻塞主线程；enum 跨线程传递 undefined 修复
- **头像异步解码**：PostItem 头像 syncLoad(true) → false，避免批量加载 30 个回复时同步解码阻塞主线程约 1 秒
- **PostItem themeState 改 @Param**：避免每实例 connectTheme，减少 V2 状态连接开销
- **列表视频懒创建**：视频组件懒加载 + cachedCount 提升
- **内存压力响应**（#203）：EntryAbility onMemoryLevel 回调 + BaseViewModel 自动 clearCache，系统 CRITICAL 时释放缓存
- **登录流程并行化**（#202）：Promise 并行化，缩短登录耗时
- **DynamicColorUtil imageSource 释放**（#200）：动态取色图片资源释放修复内存泄漏

### Bug 修复

- **350004 时序竞态修复**：aboutToAppear 参数读取前置，避免 await 期间 tid=0 发送无效请求
- **视频全屏进度恢复**：竖屏视频全屏时不旋转横屏，全屏进度条恢复修复
- **视频宽高解析**：用 field18/19 替代 bsize 解析视频宽高
- **AppStorageV2.connect 非空断言空指针**（#176）：修复 connect 返回 undefined 时的空指针风险
- **消息页首次打开**：不主动拉取消息，避免无谓请求
- **主题冷启动不生效**：修复主题色冷启动未应用的问题

### 其他

- **防窥保护功能移除**：删除防窥保护相关代码、权限配置、字符串
- **debug_acl 测试证书 product**：新增 debug_acl product 用于 ACL 测试
- **README 精简**：从 375 行精简到 137 行，新增项目文档索引章节
- **代码审查修复**：P0 路由迁移问题、P1 路由稳定性/安全/生命周期/调试日志、P2 代码质量全面修复

## [v1.1.0] - 2026-07-11

### 新增功能

- 视频播放（A10）：帖子详情页视频贴端到端播放 + 全屏横屏 + 自定义控制层
- 主题换肤（A9）：6 种亮色预设 + 深色变体 + 动态取色
- V2 状态管理全量迁移（A12）：26 文件 40 个 @Component 全量迁移
- 应用锁（#135）：生物识别/密码锁屏
- Push Kit 消息通知（#127）：workScheduler 轮询 + 本地通知
- 触感反馈（#121）：点赞/切换/长按等场景振动反馈
- 崩溃恢复（#111）：30s 频繁崩溃检测 + 自动重启

## [v1.0.0] - 2026-07-08

### 首个正式版本

- 基础功能：登录、首页、吧详情、帖子详情、楼中楼、用户主页、搜索
- 3-Tab 动态页：关注/推荐/热榜
- 网络层：手写 protobuf 编解码 + 双版本号 + Cookie 策略
- 数据层：AppStorageManager 持久化 + AppStartup 自动模式
