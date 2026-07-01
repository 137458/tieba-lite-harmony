# TiebaLite HarmonyOS 版

> 第三方百度贴吧客户端 · HarmonyOS NEXT 移植版

## 项目简介

- **bundleName**: `com.isczjk.tieba`
- **目标平台**: HarmonyOS NEXT (compatibleSdkVersion 6.1.0(23) / targetSdkVersion 6.1.1(24))
- **源项目**: TiebaLite-4.0-dev (Android) + aiotieba-master (Python API 库)
- **迁移策略**: 渐进式重写

通过 BDUSS/STOKEN 凭证调用百度贴吧客户端 HTTP API，实现帖子浏览、搜索、详情查看、用户主页、点赞、图片查看等核心功能。本项目为非官方第三方客户端。

## 当前进度

```
Phase 1: 基础设施      ████████████████ 100% (已完成)
Phase 2: 核心浏览      ████████████████ 100% (已完成)
Phase 3: 交互功能      █████████░░░░░░░  60% (用户资料/TabBar/沉浸式/图片查看器/赞踩已完成，关注/粉丝列表/评论 API 待开发)
Phase 4: 内容生产      ░░░░░░░░░░░░░░░░   0%
Phase 5: 系统功能      ░░░░░░░░░░░░░░░░   0%
Phase 6: 高级功能      ░░░░░░░░░░░░░░░░   0%
```

**总体完成度**: 约 60% (Phase 3 进行中，10/16 周)

## 技术栈

| 能力 | 技术选型 |
|---|---|
| UI 框架 | ArkUI 声明式 (@Entry/@Component/@State/@Prop/@Builder/@Observed) + HdsTabs (UIDesignKit) |
| 语言 | ArkTS (TypeScript 严格子集，禁用 any/unknown/解构/对象字面量类型) |
| 网络 | @kit.NetworkKit · http.createHttp |
| 持久化 | @kit.ArkData · preferences |
| 加密 | @kit.CryptoArchitectureKit · MD5/SHA1 + 手写 helios (CRC32/XXHash32/Base32) |
| 路由 | @kit.ArkUI · router.pushUrl/replaceUrl/back |
| 异步 | async/await + Promise |
| Protobuf | 手写极简编解码器 (ProtoWire/FrsPageProto/PbPageProto)，无第三方依赖 |
| gzip 解压 | pako_arkts ^1.0.4 (init_z_id 流程使用) |
| 图片查看 | Image 组件 + 手写 PinchGesture 双指缩放 + SaveButton 安全控件免权限保存 |

## 目录结构

```
tieba-harmony/
├── AppScope/app.json5                       # 应用级配置
├── entry/src/main/
│   ├── ets/
│   │   ├── api/
│   │   │   ├── TiebaAPI.ets                  # 贴吧 API 静态门面
│   │   │   └── InitZid.ets                   # sofire 设备指纹 17 步注册
│   │   ├── components/
│   │   │   ├── ThreadCard.ets                # 帖子卡片
│   │   │   ├── LoadingView.ets               # 加载占位
│   │   │   ├── ErrorView.ets                 # 错误占位
│   │   │   └── PagePlaceholder.ets           # TabBar 占位页通用组件
│   │   ├── data/AppStorage.ets               # 偏好存储单例
│   │   ├── entryability/EntryAbility.ets     # 应用入口 UIAbility（沉浸式 setWindowLayoutFullScreen）
│   │   ├── model/
│   │   │   ├── ForumModels.ets               # 帖子/回复/用户模型
│   │   │   └── UserProfileModels.ets          # 用户主页模型（@Observed UserProfileInfo）
│   │   ├── net/
│   │   │   ├── HttpClient.ets                 # 通用 HTTP
│   │   │   └── TiebaHttpClient.ets           # 贴吧 HTTP（Cookie/Protobuf/双版本号）
│   │   ├── pages/
│   │   │   ├── Index.ets                      # 启动路由分发
│   │   │   ├── main/
│   │   │   │   ├── MainPage.ets              # TabBar 容器（HdsTabs 沉浸光感）
│   │   │   │   ├── HomePage.ets              # 首页 tab
│   │   │   │   ├── FavoritePage.ets          # 收藏 tab（占位）
│   │   │   │   ├── MessagePage.ets           # 消息 tab（占位）
│   │   │   │   ├── ProfilePage.ets           # 我的 tab（占位）
│   │   │   │   ├── LoginPage.ets             # 手动 BDUSS 登录
│   │   │   │   └── WebLoginPage.ets          # WebView 登录
│   │   │   ├── forum/ForumPage.ets            # 贴吧帖子列表
│   │   │   ├── thread/ThreadPage.ets         # 帖子详情（顶部显示总回复数）
│   │   │   ├── search/SearchPage.ets          # 搜索页（search_exact）
│   │   │   ├── user/UserProfilePage.ets       # 用户主页（关注按钮）
│   │   │   ├── viewer/ImageViewerPage.ets     # 图片查看器（缩放/滑动/保存到相册）
│   │   │   └── settings/SettingsPage.ets      # 设置页
│   │   ├── proto/
│   │   │   ├── ProtoWire.ets                 # 共享 wire format 编解码器
│   │   │   ├── FrsPageProto.ets               # getThreads 编解码（cmd=301001）
│   │   │   ├── PbPageProto.ets                # getPosts 编解码（cmd=302001，含 thread.reply_num）
│   │   │   └── frsPage.proto                  # 字段编号参考
│   │   ├── utils/
│   │   │   ├── CryptoUtil.ets                 # MD5/SHA1/Base64/签名/CUID
│   │   │   ├── ResourceUtil.ets               # $r 字符串安全获取
│   │   │   └── helios/                        # helios hash 算法（CRC32/XXHash32/HashResult/Base32/Hasher）
│   │   └── viewmodel/BaseViewModel.ets       # 分页+加载状态基类
│   ├── module.json5                          # 模块清单（权限/能力）
│   └── resources/                            # 资源（亮色/深色主题对齐）
├── build-profile.json5                       # 工程构建配置
├── oh-package.json5                          # 工程依赖（pako_arkts + hypium + hamock）
└── code-linter.json5                         # 代码检查配置
```

## 运行方式

### 环境要求

- DevEco Studio 6.1.1 Release (6.1.1.280)+
- HarmonyOS SDK (compatibleSdkVersion 6.1.0(23), targetSdkVersion 6.1.1(24))
- hvigor 6.24.2+ 构建工具
- ohpm 6.1.2.268+

### 步骤

1. 用 DevEco Studio 打开 `tieba-harmony` 目录
2. 等待 hvigor 同步依赖（首次会自动安装 `pako_arkts` 等依赖）
3. 连接 HarmonyOS 设备或启动模拟器
4. 点击运行按钮

### 登录方式

启动后进入登录页，支持两种方式：
- **手动登录**: 输入 BDUSS（必填，192 位）和 STOKEN（可选）
- **WebView 登录**: 加载百度登录页，自动从 Cookie 提取凭证

## 已完成核心功能

### 基础设施（Phase 1）
- 网络层（HttpClient/TiebaHttpClient，支持 Cookie/Protobuf/双版本号）
- 加密工具（CryptoUtil + helios 算法 + 4 步登录 init_z_id 设备指纹）
- 数据模型（ForumModels + UserProfileModels，@Observed 字段级刷新）
- 偏好存储（AppStorageManager 双重保险防 UIAbility 竞态）

### 核心浏览（Phase 2）
- 登录页 + WebView 登录页
- 主页（贴吧 steam 帖子列表 + 搜索框）
- 贴吧浏览页（排序切换 + 精品筛选 + 下拉刷新 + 上拉加载）
- 帖子详情页（protobuf + 楼主标签 + 总回复数显示）
- 搜索页（search_exact，吧内搜索 + ExactSearch 结果）

### 交互功能（Phase 3 进行中）
- TabBar 容器（HdsTabs 沉浸光感材质，4 tab：首页/收藏/消息/我的）
- 用户主页（关注/取消关注按钮 + @Observed 字段级刷新）
- 全局沉浸式状态栏（7 个页面统一模式：HomePage/ForumPage/ThreadPage/UserProfilePage/SearchPage/SettingsPage/WebLoginPage/ImageViewerPage）
- 图片查看器（双指缩放 + 双击缩放 + 左右滑动 + 长按 SaveButton 免权限保存到相册）
- 赞/踩按钮（agree/unagree/disagree/undisagree 4 方法）

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

### 沉浸式状态栏统一模式

新增页面顶部需避让状态栏时，统一采用以下模式：

```typescript
import { router, window } from '@kit.ArkUI';

@State statusBarHeight: number = 36;

async aboutToAppear() {
  try {
    const mainWindow = await window.getLastWindow(getContext(this));
    const avoidArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
    this.statusBarHeight = px2vp(avoidArea.topRect.height);
  } catch (err) {
    // 获取失败保留默认值 36
  }
}

build() {
  Column() {
    Row() { /* 顶部内容 */ }
      .height(56 + this.statusBarHeight)
      .padding({ left: 16, right: 16, top: this.statusBarHeight })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP])
  }
}
```

> **特殊场景**：浮层按钮（如 ImageViewerPage 关闭按钮）只加 `top: this.statusBarHeight` padding 避让，**不加** `expandSafeArea`，避免按钮区域穿透。

### 项目特定约定

- 数据模型统一用 `class + constructor(init?: Partial<T>) + copyFrom` 模式（替代 Object.assign）
- JSON.parse 结果显式 `as` 转换，并提供 `safeGetNumber`/`safeGetString` 防 null
- API 端点选择以 aiotieba-master Python 实现为权威参考，不臆造接口
- 贴吧数字字段含"万"后缀需用 `parseTbNum` 统一转整数
- 字符串资源用 `utils/ResourceUtil.ets` 的 `getResourceString` 封装，避免 `$r(...).toString()` 返回 `[object Object]`

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
- 关注/粉丝列表页 FollowsPage.ets 未创建（API 已封装，待开发）
- 评论 API（POST /c/c/post/add?cmd=309731，60+ 字段）未实现
- 收藏/消息/我的 tab 为占位页，待后续 Phase 接入

## 许可

本项目仅供学习交流使用，不得用于商业目的。
