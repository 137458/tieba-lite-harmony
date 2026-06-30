# TiebaLite HarmonyOS 版

> 第三方百度贴吧客户端 · HarmonyOS NEXT 移植版

## 项目简介

- **bundleName**: `com.isczjk.tieba`
- **目标平台**: HarmonyOS NEXT (API 12+)
- **源项目**: TiebaLite-4.0-dev (Android) + aiotieba-master (Python API 库)
- **迁移策略**: 渐进式重写

通过 BDUSS/STOKEN 凭证调用百度贴吧客户端 HTTP API，实现帖子浏览、搜索、详情查看、用户主页等核心功能。本项目为非官方第三方客户端。

## 当前进度

```
Phase 1: 基础设施      ████████████████ 100% (已完成)
Phase 2: 核心浏览      ████████████████ 100% (已完成)
Phase 3: 交互功能      ████░░░░░░░░░░░░  25% (用户资料页完成，关注/粉丝/点赞 UI/图片查看器待开发)
Phase 4: 内容生产      ░░░░░░░░░░░░░░░░   0%
Phase 5: 系统功能      ░░░░░░░░░░░░░░░░   0%
Phase 6: 高级功能      ░░░░░░░░░░░░░░░░   0%
```

**总体完成度**: 43.75% (Phase 3 进行中)

## 技术栈

| 能力 | 技术选型 |
|---|---|
| UI 框架 | ArkUI 声明式 (@Entry/@Component/@State/@Prop/@Builder/@Observed) |
| 语言 | ArkTS (TypeScript 严格子集，禁用 any/unknown/解构/对象字面量类型) |
| 网络 | @kit.NetworkKit · http.createHttp |
| 持久化 | @kit.ArkData · preferences |
| 加密 | @kit.CryptoArchitectureKit · MD5/SHA1 |
| 路由 | @kit.ArkUI · router.pushUrl/replaceUrl/back |
| 异步 | async/await + Promise |

## 目录结构

```
tieba-harmony/
├── AppScope/app.json5                       # 应用级配置
├── entry/src/main/
│   ├── ets/
│   │   ├── api/TiebaAPI.ets                  # 贴吧 API 静态门面
│   │   ├── components/                        # 通用 UI 组件
│   │   │   ├── ThreadCard.ets
│   │   │   ├── LoadingView.ets
│   │   │   └── ErrorView.ets
│   │   ├── data/AppStorage.ets               # 偏好存储单例
│   │   ├── entryability/EntryAbility.ets     # 应用入口 UIAbility
│   │   ├── model/                            # 数据模型
│   │   │   ├── ForumModels.ets
│   │   │   └── UserProfileModels.ets
│   │   ├── net/                              # 网络层
│   │   │   ├── HttpClient.ets
│   │   │   └── TiebaHttpClient.ets
│   │   ├── pages/                            # 页面层
│   │   │   ├── Index.ets
│   │   │   ├── main/{Home,Login,WebLogin}Page.ets
│   │   │   ├── forum/ForumPage.ets
│   │   │   ├── thread/ThreadPage.ets
│   │   │   ├── search/SearchPage.ets
│   │   │   ├── user/UserProfilePage.ets
│   │   │   └── settings/SettingsPage.ets
│   │   ├── utils/CryptoUtil.ets              # 加密/签名工具
│   │   └── viewmodel/BaseViewModel.ets       # 分页+加载状态基类
│   ├── module.json5                          # 模块清单（权限/能力）
│   └── resources/                            # 资源（颜色/字符串/媒体）
├── build-profile.json5                       # 工程构建配置
├── oh-package.json5                          # 工程依赖
└── code-linter.json5                         # 代码检查配置
```

## 运行方式

### 环境要求

- DevEco Studio 5.0+
- HarmonyOS SDK (compatibleSdkVersion 6.1.0, targetSdkVersion 6.1.1)
- hvigor 构建工具

### 步骤

1. 用 DevEco Studio 打开 `tieba-harmony` 目录
2. 等待 hvigor 同步依赖
3. 连接 HarmonyOS 设备或启动模拟器
4. 点击运行按钮

### 登录方式

启动后进入登录页，支持两种方式：
- **手动登录**: 输入 BDUSS（必填，192 位）和 STOKEN（可选）
- **WebView 登录**: 加载百度登录页，自动从 Cookie 提取凭证

## 关键文档索引

> 以下文档位于本项目上级目录 `../`，作为开发过程文档维护，与本项目 README 同步更新。

| 文档 | 路径 | 用途 |
|---|---|---|
| Code Wiki | [../Code_Wiki.md](../Code_Wiki.md) | 整体架构、模块职责、关键类与函数说明 |
| 迁移计划 | [../HarmonyOS_Migration_Plan.md](../HarmonyOS_Migration_Plan.md) | 16 周分阶段迁移路线图 |
| 迁移进度 | [../HarmonyOS_Migration_Progress.md](../HarmonyOS_Migration_Progress.md) | 当前完成度、ArkTS 经验积累、已知问题 |
| 技术规范 | [../HarmonyOS_Migration_Technical_Document.md](../HarmonyOS_Migration_Technical_Document.md) | API 接口规范、协议参考 |
| 代码审查 | [../Code_Review_Report.md](../Code_Review_Report.md) | 历次 code-review 结果与修复记录 |

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

- 数据模型统一用 `class + constructor(init?: Partial<T>) + copyFrom` 模式（替代 Object.assign）
- JSON.parse 结果显式 `as` 转换，并提供 `safeGetNumber`/`safeGetString` 防 null
- API 端点选择以 aiotieba-master Python 实现为权威参考，不臆造接口
- 贴吧数字字段含"万"后缀需用 `parseTbNum` 统一转整数

## API 实现参考来源

| 模块 | 参考来源 |
|---|---|
| 网络协议/签名 | TiebaLite-4.0-dev/utils/OKSigner.kt |
| API 端点/参数 | aiotieba-master/src/aiotieba/api/*/\_api.py |
| 数据模型字段 | aiotieba-master/src/aiotieba/api/*/\_classdef.py |
| Protobuf 字段名 | tbclient.protobuf-main/proto/*.proto + TiebaLite-4.0-dev protos |

## 已知限制

- isFollowing 字段无服务端来源，仅本地状态（重启后丢失）
- "TA的发帖"区域为占位，需 get_user_contents API（protobuf，未实现）
- 图片查看器、点赞 UI、关注/粉丝列表页待开发
- protobuf 链路已完成（手写极简编解码器 FrsPageProto.ets，getThreads 已重写为 multipart POST + protobuf）

## 许可

本项目仅供学习交流使用，不得用于商业目的。
