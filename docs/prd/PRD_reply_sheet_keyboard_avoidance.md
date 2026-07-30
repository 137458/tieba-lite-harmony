# PRD：回复 Sheet 键盘避让与关闭按钮修复

## Problem Statement

帖子详情页和楼中楼页面的回复 Sheet 出现两个影响输入体验的问题：系统默认关闭 X 与自定义顶栏的返回按钮、发送按钮同时存在并发生视觉重叠；软键盘弹出后，底部图片、表情和字数工具栏没有稳定地保持在键盘上方。

## Solution

两个回复入口统一采用 HarmonyOS 官方 BindSheet 键盘避让样例的配置：显式隐藏系统关闭按钮，保留 ReplyBox 自定义顶栏；将 Sheet 键盘避让模式调整为 `RESIZE_ONLY`。ReplyBox 中间输入区域已经使用 `layoutWeight(1)`，在 Sheet 内容区压缩后会自动缩短，使固定高度底部工具栏保持在键盘上方。

## User Stories

1. 作为回帖用户，我希望回复 Sheet 只显示一个明确的关闭入口，以免关闭、返回和发送操作重叠。
2. 作为回帖用户，我希望软键盘打开时，图片、表情和字数工具栏紧贴键盘上沿，以便继续编辑和发送。
3. 作为回帖用户，我希望软键盘收起后，回复 Sheet 自动恢复原始高度和工具栏位置。
4. 作为楼中楼回复用户，我希望原帖预览、图片预览和表情面板存在时，键盘避让行为仍然一致。
5. 作为开发者，我希望帖子详情页和楼中楼页面的回复 Sheet 使用完全一致的官方键盘避让配置。

## Implementation Decisions

- 两个回复 Sheet 均显式设置 `showClose: false`，系统关闭 X 不再渲染；关闭由 ReplyBox 自定义顶栏的返回箭头处理。
- 两个回复 Sheet 均使用 `SheetKeyboardAvoidMode.RESIZE_ONLY`，不使用 `TRANSLATE_AND_RESIZE`，不监听键盘高度进行手动位移。
- 保留 ReplyBox 根 Column 的全高布局、TextArea 的 `layoutWeight(1)` 和底部工具栏固定 48vp 高度，使系统压缩 Sheet 内容区域时自然重新布局。
- 同步更正此前关于 `TRANSLATE_AND_RESIZE` 的代码注释，引用官方 BindSheet 键盘避让样例作为后续维护依据。

## Testing Decisions

- 编译验证确保 ArkTS 和 API 枚举使用正确。
- 真机或模拟器手动验证：普通回帖、楼中楼回复、原帖预览展开、已选图片和表情面板四种状态下，键盘弹出后底部工具栏都位于键盘上方。
- 验证系统 X 不显示，自定义返回箭头和发送按钮无重叠。

## Out of Scope

- 不修改回复发送、图片上传、原帖预览和表情内容业务逻辑。
- 不改为全屏编辑页或手动监听键盘高度位移。

## Further Notes

- 官方参考：`guide-snippets-master/ArkUISample/BindSheet/.../template6/ListenKeyboardHeightChange.ets`，其含输入组件的 Sheet 使用 `SheetKeyboardAvoidMode.RESIZE_ONLY`。
