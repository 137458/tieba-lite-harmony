# HarmonyOS 新项目开发基线

复制本文件到新项目的 `docs/HarmonyOS_开发基线.md`，将方括号占位符替换为项目实际信息。本文不包含业务账号、接口、仓库或页面专有信息，可作为 HarmonyOS NEXT 原生项目的开发约定、HDS 使用规范和交付检查表。

## 1. 项目元信息

| 项目项 | 值 |
|---|---|
| 项目名称 | [项目名称] |
| Bundle Name | [bundleName] |
| 最低支持 API | [最低 API Level] |
| 目标 API | [目标 API Level] |
| 目标设备 | [手机/平板/折叠屏/2in1] |
| SDK 与 DevEco 版本 | [由 DevEco 新建工程生成的组合] |
| HDS 使用范围 | [导航/标题栏/底部导航/不使用] |

## 2. 不可违反的原则

1. 先确认产品行为、原应用实现或协议证据，再开始编码；不根据其他平台习惯猜测接口、字段或交互。
2. 使用 HarmonyOS API 前先查询官方文档、目标 SDK 类型定义与官方样例，确认导入、参数、返回值、权限、API Level 和设备支持范围。
3. 视觉和交互优先采用 ArkUI、UIDesignKit/HDS 的原生组件；不通过自绘控件绕开系统菜单、材质、导航和输入法行为。
4. 涉及方案选择、业务语义不清、API 支持不确定或视觉标准有歧义时，先查本文、项目 ADR、官方样例；仍不能确定时必须向需求方提问，不臆测实现。
5. 每项功能必须具备编译、真机或模拟器验证路径；协议类能力还要保留可复现的请求/响应证据。
6. 不提交或记录真实 Token、Cookie、密码、私钥、测试账号、内部地址、个人数据和敏感日志。

## 3. 工程与 ArkTS 基线

### 3.1 工程结构

```text
entry/src/main/
  ets/
    entryability/     应用和窗口生命周期
    pages/            页面及页面级编排
    components/       可复用 ArkUI 组件
    model/            领域模型与可观察状态
    viewmodel/        加载、分页、错误和业务状态
    api/              网络与协议适配
    utils/            无 UI 依赖的工具
  resources/
    base/             默认字符串、颜色、媒体、profile
    dark/             深色模式同名资源覆盖
    zh_CN/ en_US/     已支持语言的资源覆盖
docs/
  adr/                已确认的架构决策
  prd/                功能需求与验收记录
  HarmonyOS_开发基线.md
references/
  harmonyos/          仅供查证的官方样例
```

### 3.2 ArkTS 约束

- 使用 Stage 模型与 ArkTS；新项目不采用 FA 模型。
- 不使用 `any`、`unknown`、动态字段访问、对象解构、`for...in`、`Function.bind/call/apply`。
- 为参数、响应、状态和回调声明明确的 class 或 interface；类字段在类体内声明并初始化。
- 所有 import 位于文件开头；回调使用箭头函数；不要在 `build()` 中请求网络、修改状态或创建重资源。
- 页面展示文本、颜色、尺寸和图标使用 `$r()`；新增字符串同步所有已支持语言，格式化字符串使用 `%s`。
- 新功能先沿用项目现有状态管理范式。新建 V2 页面优先使用 `@ComponentV2 + @Local`、`@Param + @Event`、`@ObservedV2 + @Trace`、`AppStorageV2` 与 `PersistenceV2`。

### 3.3 构建与权限

- SDK、DevEco Studio、Hvigor、Node.js 和 OHPM 版本以 DevEco 生成的工程为基准，不手工混搭。
- `compileSdkVersion`、`compatibleSdkVersion`、`targetSdkVersion` 只在构建配置的一处声明。
- 每个 user_grant 权限均需在 `module.json5` 声明 `reason`、`usedScene`，并在实际功能入口进行运行时检查与授权。
- 新增依赖前确认项目已有依赖、版本兼容性与许可证；没有必要不新增依赖。

## 4. HDS 与沉浸光感

### 4.1 采用 HDS 前的确认步骤

1. 在当前 DevEco SDK 中查看 HDS 类型定义，确认组件、字段和枚举真实存在。
2. 查找对应官方样例，确认推荐的声明结构和目标 API Level。
3. 在目标设备验证亮色、深色、滚动、字体缩放和横竖屏效果。
4. 若 HDS 当前 SDK 不支持需求，先寻找官方等价 ArkUI 方案，再决定是否自定义实现。

不要把其他项目或其他 API Level 的 HDS 结论直接复制过来。例如 `miniBar`、横向双胶囊布局和菜单能力都必须按当前 SDK 复核。

### 4.2 HdsNavigation 与 HdsNavDestination

- 新项目优先使用 `NavPathStack` 管理导航栈；若项目启用 HDS 导航，统一通过 `HdsNavigation` 与 `HdsNavDestination` 承载页面。
- 页面跳转收敛到一个路由工具或导航状态层，禁止页面间混用多套路由机制。
- HDS 标题栏使用滚动效果或材质前，必须绑定实际滚动容器并在真机验证。
- `avoidLayoutSafeArea: true` 只让标题栏自身内容避让状态栏，不会自动为页面内容让出标题栏高度。页面内容必须根据布局模式显式处理顶部空间。

**非穿透内容布局**：页面内容不需要绘制到标题栏下方时，在外层内容容器预留“状态栏高度 + HDS titleBar 高度”。

**穿透内容布局**：页面内容需要从标题栏下方滚过以获得模糊效果时，在实际 `List` 或 `Grid` 预留顶部空间；是否使用 `clip(false)`、列表预加载等属性必须按目标 SDK 和真实滚动表现验证。

### 4.3 HdsTabs 与悬浮胶囊

- 悬浮底栏可使用 `barOverlap(true)`、`barFloatingStyle` 与外层 `systemMaterialEffect`。
- 沉浸材质只放在 HDS 外层。Builder 根节点禁止重复叠加 `backgroundBlurStyle`、不透明背景、圆角和阴影，避免白色内层、材质断层或层级发灰。
- 单个 `TabContent` 的 HdsTabs 需要显式配置适合各设备尺寸的 `barWidth`，否则可能按 Tab 数量压缩为圆球。
- 需要双胶囊时，先验证 `miniBar` 初始状态、布局模式和目标 SDK 能力；未验证前不要把 miniBar 当作可横向并排的通用方案。
- 悬浮底栏与系统手势区下方不额外添加遮罩。是否为最后一个列表项预留操作空间，应根据产品需求和实际视觉验证决定，不能机械叠加安全区 padding 造成纯色断层。

### 4.4 材质与模糊选型

| 场景 | 优先方案 | 禁止或注意 |
|---|---|---|
| HDS 标题栏/底栏沉浸材质 | HDS `systemMaterialEffect` | 内层不要重复模糊或纯色背景 |
| 普通 ArkUI 浮层 | `backgroundBlurStyle` 或 `linearGradientBlur` | 先确认属性 API Level |
| 滚动标题栏 | HDS `scrollEffectOpts` + 滚动容器绑定 | 先做真机滚动验证 |
| 动画 | `UIContext.animateTo`、`TransitionEffect` | 动画中避免频繁改 width/height/padding/margin |
| CSS/iOS 风格 API | 无 | 不使用 `backdropFilter` 等非 ArkUI API |

### 4.5 HDS 菜单

- 菜单项必须提供可见文本标签或无障碍可理解的描述。
- `maxCount` 的计数规则、更多按钮和直显项目数必须根据当前 HDS 类型定义和真机表现确认。
- 若标题栏菜单不具备需要的锚定位置或材质字段，优先使用原生 `bindMenu` 等等价组件，不虚构 HDS 配置字段。

## 5. 输入、Sheet 与安全区

### 5.1 输入型 Sheet

自定义编辑器顶栏时，先关闭系统默认关闭入口，避免系统 X 与返回/发送操作重叠。

```ts
.bindSheet($$this.isEditorVisible, this.editorBuilder(), {
  height: SheetSize.LARGE,
  showClose: false,
  keyboardAvoidMode: SheetKeyboardAvoidMode.RESIZE_ONLY,
})
```

- 输入区使用 `layoutWeight(1)`；底部图片、表情、计数或发送工具栏使用稳定高度。
- 优先采用 `SheetKeyboardAvoidMode.RESIZE_ONLY` 让系统压缩输入区并使工具栏自然位于键盘上方。
- 不先通过监听键盘高度手动平移；仅当官方 Sheet 行为无法满足明确需求时，再基于官方样例设计最小补充方案。
- 验证自定义关闭、系统返回、展开面板、已选附件、键盘弹出与收起等完整状态组合。

### 5.2 安全区

- 全屏沉浸式由窗口级配置和页面背景延伸共同实现，不能仅依赖某个组件属性。
- 顶部栏、页面内容、滚动容器和浮动操作区的避让职责必须明确，避免同一安全区重复 padding。
- 不在系统手势导航条下方添加遮罩；需要保留底部操作空间时，优先调整内容/操作区结构，并检查不会形成纯色空白带。
- 统一页面左右边距规范，并确保根容器、列表和列表项只由一个层级负责该边距，避免重复叠加。

## 6. 状态、网络与安全

- 页面只负责编排展示和用户操作；协议构造、解析、分页、重试、凭据读取与复杂状态放入 api、model 或 viewmodel。
- 路由参数在异步操作前读取并校验；无效关键参数不得发起请求。
- 长列表使用 `LazyForEach` 与稳定唯一 key；离屏页面解绑监听器、定时器、播放器和 WebView 回调。
- 凭据使用 Asset Store Kit 或项目确定的安全存储。迁移旧明文后立即删除旧 key；登出必须先确认安全存储和 Cookie 清理成功，再清空内存登录态。
- 外部 URL、深链、Web 回调和 Intent 参数均视为不可信输入，校验 host、path、类型与范围；网络默认 HTTPS。

## 7. PRD 与 Issue 模板

每个功能或修复先建立 PRD，再拆为独立、可验收的纵向 Issue。一个切片只解决一项可以独立验证的用户价值，避免把 UI、协议、持久化和重构混在不可回滚的大改动中。

```markdown
# [功能/问题名称]

## 背景与证据
- 用户可见问题：[最短复现路径]
- 预期行为依据：[原应用/产品需求/官方文档/官方样例]
- 影响范围：[页面、设备、登录态、深浅色等]

## 方案
- 责任层：[页面/组件/ViewModel/API/配置]
- 使用的官方 API 与样例：[链接或本地路径]
- 不采用的方案及原因：[API 不支持/体验不一致/安全风险]

## 验收标准
- [ ] [可观察的用户结果]
- [ ] [异常、空态、重复操作结果]
- [ ] [深色、键盘、旋转或多设备结果]
- [ ] 构建通过
- [ ] 真机或模拟器路径通过

## 不在范围内
- [明确不修改的能力]
```

## 8. 每次变更验证清单

- [ ] 检查当前项目 ADR、本文档、官方 API 文档和官方样例。
- [ ] 检查新增 ArkTS 写法符合严格语法约束。
- [ ] 检查新增 API 的导入、API Level、权限和设备支持。
- [ ] 检查字符串、颜色、图标、尺寸使用资源，并补齐深色和多语言。
- [ ] 执行 HAP 构建，并处理新增诊断。
- [ ] 验证成功、空数据、失败、重复点击、弱网/断网。
- [ ] 验证深色模式、字体缩放、键盘、Sheet、返回手势和窗口尺寸变化。
- [ ] 验证新增监听器、任务、WebView、播放器或资源有释放和解绑。
- [ ] 检查文档、ADR、PRD 与实际实现一致；移除任何凭据和敏感日志。

## 9. 必备项目文档

- `docs/CONTEXT.md`：领域术语、模块边界和不使用的同义词。
- `docs/adr/`：导航、状态、存储、网络、安全和线程模型等决策。
- `docs/兼容性矩阵.md`：SDK、设备、权限、系统能力与降级策略。
- `docs/真机验证记录.md`：设备、系统版本、构建号、路径、截图/日志和已知限制。
- `docs/协议证据.md`：端点来源、字段、认证位置、错误码与脱敏样本。

## 10. 官方参考入口

- HarmonyOS 开发者文档：<https://developer.huawei.com/consumer/cn/doc/>
- HarmonyOS 官方样例：<https://developer.huawei.com/consumer/cn/samples/>
- HarmonyOS Samples：<https://gitcode.com/HarmonyOS_Samples>
- HDS/UIDesignKit：以当前安装 SDK 的 `@hms.hds` 类型定义和对应官方文档为准。
