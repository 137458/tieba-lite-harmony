# TiebaLite HarmonyOS 版

> 第三方百度贴吧客户端 · HarmonyOS NEXT 移植版

## 项目简介

- **bundleName**: `com.isczjk.tieba`
- **目标平台**: HarmonyOS NEXT (compatibleSdkVersion 6.1.0(23) / targetSdkVersion 6.1.1(24))
- **源项目**: TiebaLite-4.0-dev (Android) + aiotieba-master (Python API 库)
- **迁移策略**: 渐进式重写

通过 BDUSS/STOKEN 凭证调用百度贴吧客户端 HTTP API，实现帖子浏览、搜索、详情查看、用户主页、点赞、图片查看、楼中楼、回帖等核心功能。本项目为非官方第三方客户端。

## 当前进度

```
Phase 1: 基础设施      ████████████████ 100%
Phase 2: 核心浏览      ████████████████ 100%
Phase 3: 交互功能      ████████████████ 100%
Phase 4: 内容生产      ██████████░░░░░░  50% (回帖+图片上传已完成，发主题帖/草稿箱待开发)
Phase 5: 系统功能      ██████████████░░  85% (设置/消息/Push/防窥/应用锁/触感/主题/视频已完成)
Phase 6: 高级功能      ████████████░░░░  75% (V2迁移/AppLinking/AppStartup/崩溃恢复已完成，桌面卡片/悬浮窗/路由迁移待开发)
```

**总体完成度**: 约 92%

## 技术栈

| 能力 | 技术选型 |
|---|---|
| UI 框架 | ArkUI 声明式 V2 (@ComponentV2/@Local/@Param/@Event/@ObservedV2/@Trace/@ReusableV2/@Provider/@Consumer/@Monitor) + HdsTabs/HdsNavigation/HdsNavDestination (UIDesignKit) |
| 语言 | ArkTS (TypeScript 严格子集，禁用 any/unknown/解构/对象字面量类型) |
| 网络 | @kit.NetworkKit · http.createHttp |
| 持久化 | @kit.ArkData · preferences |
| 加密 | @kit.CryptoArchitectureKit · MD5/SHA1 + 手写 helios (CRC32/XXHash32/Base32) |
| 路由 | HdsNavigation + NavPathStack (RouterUtil 封装) |
| Protobuf | 手写极简编解码器 (ProtoWire/FrsPageProto/PbPageProto)，无第三方依赖 |
| gzip 解压 | pako_arkts ^1.0.4 |
| 图片查看 | Image 组件 + 手写 PinchGesture 双指缩放 + SaveButton 安全控件免权限保存 |

## 运行方式

### 环境要求

- DevEco Studio 6.1.1 Release (6.1.1.280)+
- HarmonyOS SDK (compatibleSdkVersion 6.1.0(23), targetSdkVersion 6.1.1(24))
- hvigor 6.24.2+ / ohpm 6.1.2.268+

### 步骤

1. 用 DevEco Studio 打开 `tieba-harmony` 目录
2. 等待 hvigor 同步依赖（首次自动安装 `pako_arkts` 等依赖）
3. 连接 HarmonyOS 设备或启动模拟器
4. 点击运行按钮

### 登录方式

启动后默认进入 LoginPage，两种登录方式：
- **BDUSS 手动登录**（LoginPage 主入口）：输入 BDUSS（必填，Password 类型）
- **百度账号网页登录**（WebLoginPage）：点击"使用百度账号登录"按钮，自动从 Cookie 提取 BDUSS + STOKEN

> API 层保留 stoken 支持，网页登录自动获取 stoken 用于需要 stoken 的接口（如取消点赞）。

## 核心功能

- **浏览**：首页帖子列表 / 贴吧详情（排序+精品筛选+下拉刷新+上拉加载）/ 帖子详情（protobuf+只看楼主+排序+加载上一页+跳页+富文本）/ 搜索（吧内+全吧）
- **交互**：TabBar 容器（HdsTabs 沉浸光感，4 tab）/ 用户主页（关注/粉丝/发帖）/ 关注粉丝列表 / 图片查看器（双指缩放+免权限保存）/ 赞踩（失败自动回滚）/ 动态页 3-Tab（关注/推荐/热榜）
- **内容生产**：楼中楼回复（分页+点赞+回复入口）/ 回帖（TextArea+表情面板）/ 图片上传回帖（分块上传+多图）
- **视频播放**：帖子详情视频贴端到端播放 + 全屏横屏 + 自定义控制层
- **主题换肤**：6 种预设主题色 + 深色变体 + 动态取色（从头像提取主色）
- **系统功能**：设置中心（深色模式/字体大小/图片加载/小尾巴/清除缓存/复制BDUSS/退出登录）/ 消息通知（Push Kit 轮询+本地通知）/ 防窥保护 / 应用锁（生物识别）/ 触感反馈 / 崩溃恢复
- **架构**：V2 状态管理全量迁移 / AppLinking 深链接 / AppStartup 自动模式 / HdsNavigation 路由迁移（进行中）

## 开发规范要点

### ArkTS 严格模式禁忌

- 禁用 `any` / `unknown` / `Object` 类型，改用显式类型或 `Record<K, V>`
- 禁用解构赋值、对象字面量直接做类型
- 禁用 `var` / `for..in` / `Function.apply` / `Function.call` / `Function.bind`
- 禁用 `as const`、映射类型、交叉类型、条件类型别名
- 不支持 `obj["field"]` 索引访问，需用 `obj.field`

### HarmonyOS API 使用规范

- 优先使用官方 API/UI 组件/动画模板，不自行构造 API
- API 调用前确认入参、返回值、API Level 和设备支持情况
- 使用 API 前确认 `module.json5` 权限配置
- UI 常量必须用 `$r` 引用资源，不直接使用字面值
- 新增颜色资源需同时配置亮色和深色主题

### ArkUI 动画规范

- 优先用 `@State` 驱动动画，通过状态变量触发
- 复杂子组件动画设置 `renderGroup(true)` 减少渲染批次
- 动画过程中不可频繁改变 `width`/`height`/`padding`/`margin`

### 项目特定约定

- 数据模型统一用 `class + constructor(init?: Partial<T>) + copyFrom` 模式
- JSON.parse 结果显式 `as` 转换，并提供 `safeGetNumber`/`safeGetString` 防 null
- API 端点选择以 aiotieba-master Python 实现为权威参考，不臆造接口
- 字符串资源用 `utils/ResourceUtil.ets` 的 `getResourceString` 封装

## API 实现参考来源

| 模块 | 参考来源 |
|---|---|
| 网络协议/签名 | TiebaLite-4.0-dev/utils/OKSigner.kt |
| API 端点/参数 | aiotieba-master/src/aiotieba/api/*/\_api.py |
| 数据模型字段 | aiotieba-master/src/aiotieba/api/*/\_classdef.py |
| Protobuf 字段名 | tbclient.protobuf-main/proto/*.proto + TiebaLite-4.0-dev protos |

## 已知限制

- 发主题帖功能未实现（Phase 4 待开发）
- 草稿箱功能未实现（Phase 4 待开发）
- BDUSS 手动登录不传 stoken，部分需要 stoken 的接口需先通过网页登录获取
- 防窥保护功能需要 AGC 申请 DLP 权限，当前未申请，功能暂不可用
- V2 状态管理全量迁移已完成，真机行为验证待推进

## 许可

本项目仅供学习交流使用，不得用于商业目的。
