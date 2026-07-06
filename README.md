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
Phase 1: 基础设施      ████████████████ 100% (已完成 + 全面审查修复)
Phase 2: 核心浏览      ████████████████ 100% (已完成 + 全面审查修复)
Phase 3: 交互功能      ████████████████ 100% (已完成 + 全面审查修复)
  注：原 README 提及"我的"页点赞/评论列表，调研 Android TiebaLite UserPage.kt 后确认该功能在原版不存在；语义实际归属消息中心（Phase 5 范畴）
Phase 4: 内容生产      ██████████░░░░░░  50% (回帖 + 图片上传(#74)已完成 + 全面审查修复，发主题帖/草稿箱待开发)
Phase 5: 系统功能      ██░░░░░░░░░░░░░░  15% (设置页深色模式/清除缓存/退出登录已完成，消息中心 2-Tab 待开发：回复我的/提到我的)
Phase 6: 高级功能      ░░░░░░░░░░░░░░░░   0%
```

**总体完成度**: 约 78%（#70/#71/#72/#73/#74(含图片上传)/FollowsPage/Phase 1-4 全面双 skill 审查修复 + 登录方式重构 + 推荐/关注页加载失败修复均已完成）

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
│   │   │   ├── ForumModels.ets               # 帖子/回复/用户模型 + ContentFragment（富文本）
│   │   │   └── UserProfileModels.ets          # 用户主页模型（@Observed + FollowUserInfo/FollowsPageInfo/FansPageInfo）
│   │   ├── net/
│   │   │   ├── HttpClient.ets                 # 通用 HTTP
│   │   │   └── TiebaHttpClient.ets           # 贴吧 HTTP（Cookie/Protobuf/双版本号）
│   │   ├── pages/
│   │   │   ├── Index.ets                      # 启动路由分发
│   │   │   ├── main/
│   │   │   │   ├── MainPage.ets              # TabBar 容器（HdsTabs 沉浸光感）
│   │   │   │   ├── HomePage.ets              # 首页 tab
│   │   │   │   ├── FavoritePage.ets          # 动态 tab（3-Tab：关注/推荐/热榜）
│   │   │   │   ├── MessagePage.ets           # 消息 tab（占位）
│   │   │   │   ├── ProfilePage.ets           # 我的 tab（账号卡片 + 退出/切换/设置）
│   │   │   │   ├── LoginPage.ets             # 登录主入口（iOS 风格，BDUSS Password 类型 + "使用百度账号登录"按钮跳转 WebLoginPage）
│   │   │   │   └── WebLoginPage.ets          # WebView 登录（自动获取 BDUSS + STOKEN）
│   │   │   ├── forum/ForumPage.ets            # 贴吧帖子列表
│   │   │   ├── thread/
│   │   │   │   ├── ThreadPage.ets             # 帖子详情（顶栏吧名+只看楼主+排序+加载上一页+跳页+沉浸+富文本）
│   │   │   │   ├── SubPostsPage.ets           # 楼中楼列表（#73，分页+点赞+回复入口）
│   │   │   │   └── ReplyPage.ets              # 回帖页（#74，TextArea+表情面板，支持楼中楼回复）
│   │   │   ├── search/SearchPage.ets          # 搜索页（search_exact）
│   │   │   ├── user/
│   │   │   │   ├── UserProfilePage.ets         # 用户主页（关注/粉丝数点击跳转 FollowsPage）
│   │   │   │   └── FollowsPage.ets             # 关注/粉丝列表（Tabs 切换 + LazyForEach）
│   │   │   ├── viewer/ImageViewerPage.ets     # 图片查看器（缩放/滑动/保存到相册）
│   │   │   └── settings/SettingsPage.ets      # 设置页
│   │   ├── proto/
│   │   │   ├── ProtoWire.ets                 # 共享 wire format 编解码器
│   │   │   ├── FrsPageProto.ets               # getThreads 编解码（cmd=301001，含 authorId case 50 + hotNum case 182）
│   │   │   ├── PbPageProto.ets                # getPosts 编解码（cmd=302001，含 thread.reply_num + forumId）
│   │   │   ├── PbFloorProto.ets               # getComments 楼中楼编解码（cmd=309701，#73）
│   │   │   ├── AddPostProto.ets               # addPost 回帖编解码（cmd=309731，#74）
│   │   │   ├── ProfileProto.ets               # 用户主页 Profile 编解码（cmd=303012）
│   │   │   ├── PersonalizedProto.ets           # 个性推荐编解码（cmd=309264）
│   │   │   ├── UserLikeProto.ets              # 关注动态编解码（cmd=309474）
│   │   │   ├── HotThreadListProto.ets          # 热榜编解码（cmd=309661）
│   │   │   └── frsPage.proto                  # 字段编号参考
│   │   ├── utils/
│   │   │   ├── CryptoUtil.ets                 # MD5/SHA1/Base64/签名/CUID（pkcs7Unpad 全字节校验 + Promise 缓存失败可恢复）
│   │   │   ├── ResourceUtil.ets               # $r 字符串安全获取
│   │   │   ├── AvatarUtil.ets                 # 头像 URL 拼接（getAvatarUrl(portrait, size)，https 协议）
│   │   │   ├── EmoticonManager.ets             # 表情映射（56 表情 name↔id，对齐 TiebaLite EmoticonManager.kt，#74，并行数组替代 Record+Object.keys）
│   │   │   ├── CommonDataSource.ets           # LazyForEach 数据源（IDataSource 实现，越界兜底）
│   │   │   ├── StatusBarUtil.ets              # 沉浸式状态栏高度获取（getWindowAvoidArea 提取，10 页面共用）
│   │   │   ├── TimeUtil.ets                    # 时间格式化（formatRelativeTime）
│   │   │   ├── FormatUtil.ets                  # 数字格式化（formatCount + NaN/Infinity/负数防御，2026-07-04 抽取）
│   │   │   ├── ThreadInteractionHelper.ets     # 帖子交互工具（点赞/点踩，接收 UIContext 参数）
│   │   │   └── helios/                        # helios hash 算法（CRC32/XXHash32/HashResult/Base32/Hasher，Base32 改数组 push+join）
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

启动后默认进入 LoginPage（iOS 风格主入口），用户可选择两种方式登录：
- **BDUSS 手动登录**（LoginPage 主入口）：输入 BDUSS（必填，长度 100-256，Password 类型不明文显示），不传 stoken
- **百度账号网页登录**（WebLoginPage）：点击 LoginPage 上"使用百度账号登录"按钮跳转，加载百度登录页，自动从 Cookie 提取 BDUSS + STOKEN 并持久化

> **设计说明**：API 层保留 stoken 支持（`TiebaAPI.login(bduss, stoken='')`），网页登录自动获取 stoken 用于需要 stoken 的接口（如取消点赞）。LoginPage 不再输入 stoken，减少敏感凭证暴露面。

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

### 交互功能（Phase 3 已完成 100%）
- TabBar 容器（HdsTabs 沉浸光感材质，4 tab：首页/动态/消息/我的）
- 用户主页（关注/取消关注按钮 + @Observed 字段级刷新 + 关注/粉丝数点击跳转 FollowsPage）
- 关注/粉丝列表页（Tabs 切换关注/粉丝 + LazyForEach + 自定义 TabBar 带数量和选中下划线）
- 全局沉浸式状态栏（7 个页面统一模式：HomePage/ForumPage/ThreadPage/UserProfilePage/SearchPage/SettingsPage/WebLoginPage/ImageViewerPage）
- 图片查看器（双指缩放 + 双击缩放 + 左右滑动 + 长按 SaveButton 免权限保存到相册）
- 赞/踩按钮（agree/unagree/disagree/undisagree 4 方法，失败自动回滚本地状态）
- 帖子详情楼主标识（ThreadPage post.author.uid === thread.author.uid 推导，对齐原 app，分页后仍正确）
- 帖子详情增强（#70/#71/#72）：只看楼主/排序切换（正序/倒序/热门）/加载上一页（服务端 back=1+pid 锚点）/跳转楼层（实为跳页）/沉浸模式（纯 UI 状态）/富文本渲染（TEXT/LINK/EMOJI/IMAGE/AT 5 类）
- 动态页 3-Tab（关注/推荐/热榜，对齐 Android ExplorePage）
  - 关注 Tab：pageTag 游标分页，未登录显示登录引导
  - 推荐 Tab：pn 数字分页，默认初始页
  - 热榜 Tab：3 段式（话题榜 2x2 Grid + 子 Tab 横向 Scroll + 帖子列表 LazyForEach 带排名/热度）

### 内容生产（Phase 4 进行中 50%）
- 楼中楼回复（#73）：SubPostsPage 列表分页 + 点赞（@ObjectLink 局部刷新）+ 富文本 + 作者跳转 + 回复入口
- 回帖页面（#74）：ReplyPage TextArea + 表情面板（Grid 8 列，56 表情）+ 楼中楼回复前缀构造（`回复 #(reply, portrait, userName) :`）
- 回帖 API（addPost：POST /c/c/post/add?cmd=309731，BDUSS+stoken+tbs 三件套鉴权）
- 图片上传回帖（#74，commit 1ffd26e）：完整两阶段流程
  - 阶段 1 上传图片：ImageUploader 分块上传（512000 字节/块，串行 flatMapConcat）→ POST `/c/s/uploadPicture`（multipart/form-data，固定 boundary `--------7da3d81520810*`）→ 拿 picId + 原图宽高
  - 阶段 2 嵌入回帖：图片以 `#(pic,picId,width,height)` 文本嵌入 content 字段，多图 `\n` 分隔
  - 严格对齐 Android ImageUploader.kt 10 条约束：分块大小 512000、chunkNo 从 1 开始、resourceId=fileMd5+"512000"、width/height 填原始解码宽高、size 填压缩后字节数、字段顺序 alt→chunkNo→forum_name→groupId→height→isFinish→is_bjh→pic_water_type→resourceId→saveOrigin→size→small_flow_fname→width→chunk(file)
  - 压缩策略：JPEG quality=95，普通 5MB 限制，原图 10MB 限制，超限缩放至 1080P 长边
  - UI：PhotoViewPicker 免权限选择（最多 9 张）+ 横向预览 + 删除按钮 + 原图开关（仅有图时显示）
  - 复用：CryptoUtil.md5Bytes + TiebaHttpClient.buildWebCookie + textEncoder
- 表情映射（EmoticonManager：56 表情 name↔id，对齐 TiebaLite EmoticonManager.kt:61-121）

### Phase 1-4 全面双 skill 审查修复（2026-07-04，commit eb960f5 + 2db362f）
> 调用 harmonyos-development + code-review 双 skill，4 个并行 subagent 分别审查 Phase 1-4，共修复 53 个问题（3 P0 + 30 P1 + 20 P2）

- **P0 修复（3 项）**：LoginPage BDUSS 输入框改 Password 类型（敏感凭证不明文显示）；ThreadPage tid 加 NaN + 正数校验（非法时显示 error_invalid_params）；HomePage/ForumPage/ThreadPage/FollowForumsPage/FollowsPage onReachEnd async 调用加 .catch（避免未捕获 Promise rejection）
- **P1 修复（约 30 项，关键项）**：
  - 安全：CryptoUtil pkcs7Unpad 全字节校验（防填充预言攻击）+ rc442 空 key 校验；4 个 Promise 缓存（deviceId/androidId/uuid/aesCbcSecKey）失败可恢复；AppStorage ensureReady 失败可重试
  - 协议：ProtoWriter writeInt32 负值符号扩展到 64 位 10 字节 varint
  - 网络：HttpClient 新增 HttpError 类保留 code；TiebaHttpClient TOKEN_RE 提升为模块级 const
  - 性能：Base32 字符串拼接改数组 push+join；PbFloorProto 解码循环改数组 push+join
  - UI 全局：promptAction.showToast 34 处迁移到 UIContext.getPromptAction()（避免全局 API 警告）；formatCount 提取到 FormatUtil.ets + NaN 防御；LazyForEach 全部加 keyGenerator
  - 数据：ProfilePage 关注数写死 '0' 改 profile.followNum；AvatarUtil 头像 URL http 改 https；TiebaAPI getFollows/getFans 硬编码版本号改复用 STABLE_VERSION 常量
  - 列表：UserProfilePage/SubPostsPage ForEach 改 LazyForEach + CommonDataSource + cachedCount(5)
  - 资源化：SubPostsPage '操作失败' 字面值改资源化
  - 健壮性：3 处页面 aboutToAppear 中 getStatusBarHeight 包裹 try-catch（避免路由参数未读取导致空白）
- **P2 修复（3 项）**：ReplyPage maxLength 2000 提取为 MAX_CONTENT_LENGTH 常量；EmoticonManager Record+Object.keys 改并行数组（NAMES + IDS）
- **ArkTS 严格模式陷阱修复**：6 处 catch 子句中 `throw e` 改为 `throw new Error((e as Error).message)`（arkts-limited-throw 编译错误）

### 登录方式重构（2026-07-04，commit eb960f5 + 2db362f）
- **LoginPage 为主入口**（iOS 风格，保持原风格）：BDUSS 输入框（Password 类型）+ "使用百度账号登录"按钮跳转 WebLoginPage
- **WebLoginPage 网页登录**：内嵌 WebView 加载百度登录页，自动从 Cookie 提取 BDUSS + STOKEN 并持久化
- **STOKEN 处理**：LoginPage 移除 STOKEN 输入框；API 层保留 stoken 支持（`TiebaAPI.login(bduss, stoken='')`），stoken 由网页登录自动获取
- **路由调整**：Index.ets 未登录默认跳 LoginPage（不再跳 WebLoginPage）

### 首页关注的贴吧列表无法加载 修复（2026-07-04，commit cd8cfee）
- **根因**：`TiebaHttpClient.buildCookie()` 为修复 350004 刻意移除 BDUSS（对齐 Android V12 protobuf 端点），但 `/c/f/forum/forumGuide` 是 **web 端 form POST**，按 aiotieba web cookie jar (`http.py:82-89`) 必须在 Cookie 中带 BDUSS + STOKEN 鉴权。postWeb 复用 buildCookie（无 BDUSS）导致服务器无法鉴权返回空列表。
- **修复**：TiebaHttpClient 新增 `buildWebCookie()` 方法（含 BDUSS + STOKEN），postWeb 改用该 cookie 覆盖 headers。postProtobuf/post 仍用原 buildCookie（不含 BDUSS，保住 350004 修复）。
- **关键决策**：web 端点（postWeb）和 protobuf 端点（postProtobuf）使用不同的 Cookie 策略。web 端点鉴权靠 Cookie（BDUSS + STOKEN），protobuf 端点鉴权靠 CommonReq field 10（BDUSS）。对齐 aiotieba 实现：web cookie jar 含 BDUSS + STOKEN，proto 请求体含 BDUSS。

### 推荐/关注页加载失败 + 设置摆设 + 头像空白 修复（2026-07-04，commit 5e8dd93）
- **Bug1 推荐页/关注页无法加载**：PersonalizedProto/UserLikeProto 的 encodeCommonReq 缺 BDUSS/cuid/timestamp/net_type/stoken 字段。补全 5 字段（cuid=7 / _timestamp=8 / BDUSS=10 / net_type=12 / stoken=30），TiebaAPI 注入认证参数。对齐 Android TiebaLite V11/V12 路径 + AddPostProto 已修复模式。热榜正常是因为该端点不严格校验这些字段。
- **Bug2 设置页摆设**：SettingsPage menuItemBuilder 无 onClick 参数，三项菜单点击无响应。完整重写：深色模式 bindMenu 三选项 + setColorMode 调 appContext.setColorMode + AppStorageManager 持久化；清除缓存 fs.listFile(cacheDir) + 循环 fs.unlink；退出登录清理 13 个 storage key + TiebaAPI.setAuth('','') + router.replaceUrl。EntryAbility.onCreate 启动时读 colorMode 并应用。
- **Bug3 头像空白**：ProfilePage avatar 为空时 getAvatarUrl 返回空字符串，Image 显示空白。加 fallback：avatar 有值显示 Image，无值显示昵称首字 + 渐变背景（linearGradient 135deg primary→accent_blue）。
- **fs 导入正确写法**：`import fs from '@ohos.file.fs';`（默认导入），不是 `import { fs } from '@kit.CoreFileKit'`（编译报错）。

### 第 3 轮 code-review 切片修复（2026-07-06，issue #93-#102）🚧 进行中

> 调用 code-review skill 对 49 个 .ets 文件进行 Phase 1/2/3 三阶段审查，输出 46 个 P1+P2 问题。按拆分 Issue 技能分为 10 个垂直切片（GitHub Issue #93-#102）按依赖顺序推进。已完成 slice 1/2/3/4。

- **Slice 1: ThreadPage 状态锁生命周期修复**（issue #93，commit 271b074）：新增 `isDestroyed` 字段 + `aboutToDisappear` 重置状态锁 + 8 个 async 方法 await 后检查销毁状态，防止组件销毁后 @State 被写入触发"state lock on destroyed component"告警；修复 handleThreadShare finally 中 isSharing 重置 bug；MessageProto.ets `throw err` 改为保证 Error 实例
- **Slice 2: TiebaAPI 异常处理一致性**（issue #94，commit 68677a9）：新增 `buildEndpointError(err, operation)` 统一端点异常包装器（3 层策略：网络错误统一文案 / 已含业务前缀透传 / 其他加 operation 前缀），16 个 web/JSON 端点统一加外层 try-catch 调用该包装器，消除 13+ 处重复 catch 块，补全 getUserProfile/getReplys 两个无 try-catch 端点（P1）
- **Slice 3: TiebaAPI options 对象重构**（issue #95）：3 个 ≥6 参方法改为 options 对象传参（`addPost` 8 参 → `IAddPostParams`、`getPosts` 6 参 → `IGetPostsParams`、`getTopicDetail` 6 参 → `IGetTopicDetailParams`）；`getPosts` 的 `back=true` 分支拆为独立方法 `getPrevPosts`（语义更清晰）；6 个调用点同步更新（ReplyBox/ReplyPage/TopicDetailPage/ThreadPage×3）
- **Slice 4: EntryAbility + MainPage + Index 异常兜底**（issue #96）：3 处启动白屏风险修复 - ① EntryAbility `getMainWindow()` 包入 try-catch（避免窗口服务异常时 onWindowStageCreate 失败导致永久白屏）+ 注册 `errorManager.on('error')` 全局未捕获异常监听（hilog 记录 name/message/stack，onDestroy 注销）② MainPage `getSystemMaterialTypes()` 包入 try-catch + `@State loadError` + ErrorView 兜底（HdsTabs API 不可用时显示错误页+重试）③ Index `ensureReady()` 失败时显示 ErrorView 错误页+重试按钮（不再静默跳登录页，因为 preferences 不可用时登录也无法持久化）
- **Slice 5: ImageViewerPage 资源生命周期+动画**（issue #97）：2 P1 + 2 P2 修复 - ① `handleLongPress` / `onSaveButtonClick` async 方法在 await 后加 `isDestroyed` 守卫（防止组件销毁后写入 @State + 防止 getUIContext 销毁后调用异常）② ImageViewerItem Image.scale 后接 `.animation({ duration: 300, curve: curves.springMotion() })` 实现双击/双指回弹的弹簧动画（替代瞬时跳变）③ ImageViewerItem Stack 加 `.renderGroup(true)` 减少复杂子组件动画的渲染批次。同步修复 slice 4 引入的回归 bug：`errorManager.ErrorObserver` 在 ArkTS 中是类不是接口，禁止 `implements`，改为对象字面量写法（对齐华为官方 ErrorManagerDemo 示例）
- **Slice 6: ProfilePage 边距+NaN+资源化**（issue #98）：1 P1 + 4 P2 修复 - ① ProfileCard 边距双倍叠加（父 Column 已有 padding 16 + 自身 margin 16 = 32vp 实际边距，违反 UI 铁律，移除子组件 left/right margin）② `Number(uid)` 加 `Number.isNaN` 校验（uid 非数字字符串时 fallback 到 0）③ `getAgeText(age)` 加 `Number.isNaN(age)` 严格判断（避免显示"NaN年"）④ `getGenderText` 中 gender 1/2 提取为 `GENDER_MALE`/`GENDER_FEMALE` 常量 ⑤ 弹窗 `result.index === 1` 提取为 `DIALOG_CONFIRM_BUTTON_INDEX` 常量（2 处统一）
- **Phase 1/2/3 review 修复**：P1 修复 `getTopicDetail` 中 `resJson.data` 空值访问风险（JSON.parse 返回值不保证含 data 字段，加空值检查防止 TypeError）；P2 修复 `buildEndpointError` 中 `'http'` 匹配过宽（改为精确匹配 `'http request failed'`/`'network error'`/`'网络错误'`，避免误判含 URL 的业务错误）
- **架构模式沉淀**：isDestroyed 模式（@Component 异步任务守护 + getUIContext 守护）+ buildEndpointError 模式（API 层异常统一包装器）+ options 对象模式（≥5 参方法封装接口对象）+ 启动异常兜底模式（errorManager 全局监听 + ErrorView 错误页 + try-catch 包裹关键初始化）+ @State 驱动 + springMotion + renderGroup 动画三件套 + ArkTS errorManager.ErrorObserver implements 陷阱 + UI 边距双倍叠加陷阱，已写入 Code_Wiki.md 附录
- **剩余切片（4 项待开发）**：切片 7 SubPostsPage 语义修正 / 切片 8 SearchPage 图片策略+ForEach key / 切片 9 PbPageProto 空校验+副作用 / 切片 10 杂项 P2 批量修复

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
import { getStatusBarHeight } from '../../utils/StatusBarUtil';

@State statusBarHeight: number = 36;

async aboutToAppear() {
  // 失败不阻塞后续逻辑，保留默认值 36
  try {
    this.statusBarHeight = await getStatusBarHeight(getContext(this));
  } catch (err) {
    console.error(`[PageName] getStatusBarHeight failed: ${(err as Error).message}`);
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
- UI 界面展示常量必须定义 resources 资源值并用 `$r` 引用，禁止硬编码字面量
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
- 发主题帖功能未实现（Phase 4 待开发）
- 草稿箱功能未实现（Phase 4 待开发）
- 消息 tab 为占位页，待 Phase 5 接入（计划实现「回复我的」+「提到我的」2 Tab，对齐 Android NotificationsPage；aiotieba 参考：get_replys /c/u/feed/replyme protobuf cmd=303007、get_ats /c/u/feed/atme JSON）
- 动态页 Tab 切换已用 Stack+Visibility.None 临时解决状态丢失（Issue #68 P0-1 已处理，Phase C 计划重构为 Tabs 组件彻底优化）
- 首次进入贴吧偶现"该吧还未建立"错误（Bug #2，待 hilog 运行时日志确认根因）
- BDUSS 手动登录不传 stoken，部分需要 stoken 的接口（如取消点赞）需先通过网页登录获取 stoken 才能正常工作

> 注：原 README 中"我的"页点赞/评论列表条目已移除——调研 Android TiebaLite UserPage.kt 确认该功能在原版根本不存在，README 描述存在误导。"点赞/评论列表"语义实际归属消息中心范畴。

## 许可

本项目仅供学习交流使用，不得用于商业目的。
