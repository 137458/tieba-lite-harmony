# PRD：冷启动与包体积优化 + 评论预览滑动冲突修复 + 广告误渲染过滤

## Problem Statement

用户反馈当前鸿蒙版存在四类体验问题：

1. **冷启动慢**：`Index.aboutToAppear` 在主线程串行 `await` 十多个 `AppStorageManager.getXxx`（每个都是一次磁盘 preferences I/O），且必须等 `ensureReady()` + 网络登录 `TiebaAPI.login()` 全部完成后才路由到 MainPage/LoginPage，导致冷启动白屏 + 转圈时间偏长。
2. **包体积偏大**：release 构建未开启 ArkTS 混淆（`build-profile.json5` 中 `obfuscation.enable=false`），且打包了未必要塞进 Entry 的第三方依赖资源（protobufjs/long/pako/lv-markdown/image-preview 等）与可能冗余的资源文件，HAP 体积有压缩空间。
3. **评论预览区域滑动冲突**：开启评论预览后，在帖子列表（FrsPage/吧内列表）中以预览区域为起点上下滑动时，列表**划不动**。预览区域的每条子回复 `Text` 设置了 `hitTestBehavior(HitTestMode.Block)` + `onClick`，把触摸事件据为己有，未传给外层 List 的滚动手势。
4. **广告被当作正常帖子渲染**：`decodeThread()` 解码 frs / 吧内 / 推荐 thread_list 时完全未读取广告标识字段，广告帖混入正常帖子流，以普通主题帖样式渲染。

## Solution

- **冷启动**：把首帧渲染从主线程串行偏好读取 + 网络登录中解耦出来——将偏好读取批量化/异步化、先绘制轻量欢迎占位页，后台完成偏好装载与自动登录后再切入主界面，缩短首帧可见耗时。
- **包体积**：双管齐下——①清理冗余资源与可裁剪的第三方依赖；②release 构建开启 ArkTS 混淆（`obfuscation.enable=true`）压缩代码体积，并做回归验证。
- **评论预览滑动**：调整预览子回复 Text 的 `hitTestBehavior`，让纵向拖动手势能透传给外层 List 正常滚动，同时保留点击子回复跳转的行为。
- **广告过滤**：在 `decodeThread()` 中读取广告标识字段（ThreadInfo.proto `is_ad=59`、`thread_type=26`），`is_ad != 0` 的广告帖在解码层直接剔除，不进入帖子流；对无法靠字段识别的残留情况做防御性过滤。

## User Stories

**冷启动**
1. 作为用户，我希望 App 启动后尽快看到界面（欢迎占位页），这样冷启动体感更短，不再是长时间白屏/转圈
2. 作为用户，我希望主题、Tab 显隐、列表模式等偏好仍能正确生效，这样启动优化不破坏既有设置
3. 作为用户，我希望偏好读取失败时仍能进入界面而非卡住，这样即使磁盘异常也不白屏
4. 作为开发者，我希望启动路径上的多次 preferences I/O 尽量批量化/并行化，降低主线程阻塞
5. 作为开发者，我希望登录/凭证校验不阻塞首帧渲染，在网络慢时也能先显示界面

**包体积**
6. 作为用户，我希望 HAP 体积更小，这样下载/安装更快、占空间更少
7. 作为开发者，我希望释放未使用的第三方依赖与冗余资源，减小打包体积
8. 作为开发者，我希望 release 开启 ArkTS 混淆压缩代码，且修复后核心功能回归通过（不因混淆产生崩溃）
9. 作为开发者，我希望混淆不破坏资源引用（`$r` / 路由 / 字符串占位符 `%s`），保持功能稳定

**评论预览滑动**
10. 作为用户，我希望在帖子列表上以评论预览区域为起点上下滑动时，列表能正常滚动，不被预览区域吞掉手势
11. 作为用户，我希望点击预览区域中某条子回复仍能正常跳转楼中楼，不因修复滚动而丢失该交互
12. 作为开发者，我希望标记"查看全部回复"的交互保持可用

**广告过滤**
13. 作为用户，我希望帖子列表不再把推广广告当正常帖子渲染，列表更干净
14. 作为开发者，我希望解码层能识别并剔除广告帖（靠 `is_ad`/`thread_type` 等字段），不依赖 UI 层补救
15. 作为开发者，我希望对无法识别为广告的合法帖子不误杀，过滤规则尽量精确

## Implementation Decisions

- **冷启动（修改模块）**
  - `pages/Index.ets`：拆分 `aboutToAppear` 中的串行偏好读取。将可并行的 `getBoolean/getNumber/getString` 批量读取（读取偏好映射表后一次性/并行装载），缩短主线程阻塞。
  - 引入轻量欢迎/占位页作为首帧：先渲染无依赖的欢迎态，后台 `initApp()`（ensureReady → 读凭证 → 自动登录）完成后 `RouterUtil.replace` 到 MainPage/LoginPage。
  - 保持既有的异常回退（storageError → ErrorView 重试、主题初始化失败回退默认主题、`#172/#96` 的 try-catch 语义不变）。
  - 不改变既有持久化 key 与迁移逻辑（`#234` 偏好读回、`homeListMode`/`forum_page_version`/`default_home_page` 迁移）。
- **包体积（修改配置/资源）**
  - `entry/build-profile.json5`：release 构建开启 ArkTS 混淆（`obfuscation.enable=true`），复用已有 `obfuscation-rules.txt`；需回归验证核心功能 + `$r` 资源引用 + 路由。
  - 审计 `entry/oh-package.json5` 中 `@ohos/protobufjs`/`long`/`pako_arkts`/`@luvi/lv-markdown-in`/`@rv/image-preview` 的实际使用情况，移除/替换未用或可通过原生能力替代的依赖。
  - 审计 `entry/src/main/resources`（media/rawfile）与 AppScope 资源，裁剪大体积/未用资源。
  - 不拆分动态特性模块（改动过大，本期不做）。
- **评论预览滑动（修改模块）**
  - `components/ThreadCard.ets` `HotPostPreview()`：将每条预览子回复 `Text` 与"查看全部回复"`Text` 的 `hitTestBehavior` 由 `Block` 调整为允许外层 List 接收纵向拖动手势的配置（保留子回复 `onClick` 跳转）。须实测确认"手指落在预览区域上下滑动"能驱动外层 List 滚动。
  - 若仍存在与卡片 `onClick` 的手势竞争，评估统一命中测试策略，确保"点击进详情" vs "纵向滑动滚列表"不冲突。
- **广告过滤（修改模块）**
  - `proto/FrsPageProto.ets` `decodeThread()`：新增读取字段——`is_ad`（ThreadInfo.proto field 59）、`thread_type`（field 26）。当 `is_ad != 0` 时报当前 thread 为广告并标记，解码完成后由调用方（FrsPage/吧内/推荐流解析入口）剔除。
  - `ThreadInfo` 模型（`model/ForumModels.ets`）：新增 `isAd: boolean` 字段（含 `init` 兼容），供过滤与后续样式使用。
  - 过滤位置统一放在解码层拿到 `thread_list` 之后、进入 ViewModel/UI 列表之前；对 `is_ad` 判空/兼容字符串与数字类型（遵循项目错误码类型兼容铁律）。
  - 防御性：若 `thread_type` 的值域无法可靠判定广告，以 `is_ad` 为主信号，避免误杀正常帖子。
- **不修改模块**
  - 本地/远程接口协议（URL、字段编号）不变；`TiebaAPI.ets` 请求构造不变。
  - `ThreadCommentCache` 缓存机制不变；`ForumPage/HomePage` 列表结构不变（仅过滤广告 + 预览命中策略微调）。
  - 不新增多语言资源；（若需新提示文案）按现有 en_US 部分覆盖约定补充。
- **架构决策**
  - 广告过滤属解码层数据清洗，不引入 UI 广告卡片组件（本期用户选择"直接过滤掉"）。
  - 冷启动欢迎页为轻量占位，不承载业务逻辑，登录/跳转仍复用 `initApp`。
  - 混淆开启是发布行为变更，需新增一条回归验收路径。

## Testing Decisions

- **测试接缝**
  1. **评论预览手势接缝（最高）**：在真机/模拟器上以预览区域为起点上下滑动帖子列表，验证列表能正常滚动，且点击预览子回复仍可跳转。
  2. **广告过滤接缝（高）**：构造含 `is_ad` 字段的 protobuf 响应，验证解码后该 thread 被剔除、正常 thread 不受影响。
  3. **冷启动可见性接缝**：冷启动时首帧尽快出现欢迎占位，且偏好/登录完成后能切入主界面；异常时回退 ErrorView。
  4. **回归接缝**：release（开启混淆）构建后核心页面（首页/吧内/帖子详情/设置/主题切换）功能正常、资源引用正常。
- **测试方式**
  - 项目无 arkxest 基础设施（参照 issue #251 决策），采用 **编译验证 + 手动验收**：
  - 编译验证：`hvigorw assembleHap` BUILD SUCCESSFUL（debug 与 release 各一次，release 用于验证混淆）。
  - 手动验收清单：
    - [ ] 开启评论预览后，帖子列表在预览区域上下滑动可正常滚动；点击预览子回复跳楼中楼
    - [ ] 广告不再以普通帖子出现；正常帖子未被误杀
    - [ ] 冷启动首帧尽快出界面，主题/Tab/列表模式偏好仍生效
    - [ ] release（混淆开启）构建后核心页面正常、无资源引用断裂
    - [ ] HAP 体积较优化前明显减小（记录前后大小）
- **Prior art**：参考 issue #251"仅编译验证 + 验收清单"模式；协议/资源参考 `references/protobuf/tbclient.protobuf-main/...` 与上手项目 guide-snippets 中的媒体/启动示例。

## Out of Scope

- 动态特性（Dynamic Feature/Module）拆分（改动过大，仅保留资源与依赖级优化）
- 首页双列精简显示不全（另一独立 issue #287，不在本期 PRD 内）
- 广告卡片样式渲染/广告替换逻辑（本期仅过滤）
- 首次安装的完整初始化体验重构（仅优化冷启动主线程路径）
- 崩溃恢复、AppLinking 等外围启动逻辑的行为改动

## Further Notes

- ThreadInfo.proto 广告关键字段：`is_ad=59`（uint32）、`thread_type=26`（int32）；详见 `references/protobuf/tbclient.protobuf-main/proto/ThreadInfo.proto:128`。
- 评论预览命中测试问题定位：`components/ThreadCard.ets` `HotPostPreview()` L378/L392 的子回复与"查看全部"`Text` 均使用 `HitTestMode.Block`。
- 冷启动主线程串行偏好读取：`pages/Index.ets` aboutToAppear L59-L148。
- release 混淆未开启：`entry/build-profile.json5`。
- 本次四个方向均为用户反馈汇总，来源为用户，非研发臆测。