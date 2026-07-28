# PRD：楼中楼预览（直接显示部分子回复）

## Problem Statement

当前鸿蒙版帖子详情页楼层卡片只显示一个孤零零的"查看全部 N 条回复"按钮，用户必须点按钮跳转到 SubPostsPage 才能看到具体子回复内容。这个交互方式让用户每次查看楼中楼都要多一次跳转，体验割裂。用户希望直接在楼层卡片内就能看到前几条子回复的预览内容。

## Solution

在楼层卡片内嵌渲染服务端返回的前 N 条子回复预览（作者名 + 内容），"查看全部 N 条回复"按钮放在预览列表底部。预览数据来自 PbPage 响应 Post.sub_post_list 字段（Post.proto field 15），无需新增 API 请求。

## User Stories

1. 作为帖子详情页访客，我希望在楼层卡片内直接看到前几条楼中楼回复，这样我不必每次都跳转就能快速了解回复概况
2. 作为帖子详情页访客，我希望预览的每条子回复显示作者名（主题色）和内容文本（最多 4 行后省略号），这样我能快速识别谁说了什么
3. 作为帖子详情页访客，我希望点击预览的子回复能跳转到楼中楼指定楼层，这样我能定位查看完整上下文
4. 作为帖子详情页访客，我希望"查看全部 N 条回复"按钮放在预览列表底部，这样当我想看全部时按钮位置符合阅读顺序
5. 作为帖子详情页访客，我希望当楼中楼总数等于预览数（无更多回复）时不显示"查看全部"按钮，避免冗余
6. 作为帖子详情页访客，我希望当楼层无回复时不显示预览区域，避免空白浪费
7. 作为帖子详情页访客，我希望预览区域的视觉风格（背景色、圆角、间距、深色模式适配）与楼层卡片整体协调
8. 作为帖子详情页访客，我希望预览区域不显示图片/表情/视频等富媒体附件（仅显示文本），保证预览轻量
9. 作为帖子详情页访客，我希望深色模式下预览区域文字颜色与楼层卡片其他辅助文字一致
10. 作为开发者，我希望协议解码层正确解码 Post.sub_post_list 字段为 SubPostInfo[]，这样 UI 层可以直接消费
11. 作为开发者，我希望解码复用现有的 decodeUser 和 decodePostContent 函数，避免重复造轮子
12. 作为开发者，我希望预览渲染组件能复用现有的 ContentText 或 SpanText 组件，保持视觉一致
13. 作为开发者，我希望渲染条件清晰可读（replyNum>0 且 subPostList.length>0），便于后续维护
14. 作为开发者，我希望"查看全部"按钮显示条件使用 `replyNum > subPostList.length` 而非魔法数字，语义清晰
15. 作为开发者，我希望资源字符串 `view_all_sub_posts` 继续复用，不新增冗余字符串

## Implementation Decisions

- **修改模块1：协议解码层 PbPageProto.ets**
  - 在 `decodePost()` 函数中新增 `case 15` 分支，递归解码 SubPost message（SubPostList field 2 = repeated SubPostList）
  - 复用现有 `decodeUser`、`decodePostContent`（PbContent）函数
  - 解码结果填入 `PostInfo.subPostList: SubPostInfo[]`（模型层字段已定义就绪）
  - 不修改 `decodeSubPostList` 之外的解码逻辑

- **修改模块2：UI 层 ThreadPage.ets 的 PostItem**
  - 调整渲染条件：原 `if (post.replyNum > 0)` 改为 `if (post.replyNum > 0 && post.subPostList.length > 0)`（预览非空才显示区域）
  - 在预览区域内先渲染 `subPostList` 数组（SubPostItem 等价物），再在底部放"查看全部 N 条回复"按钮
  - 按钮显示条件：`post.replyNum > post.subPostList.length`（还有更多才显示）
  - 每条预览子回复布局：作者名（primary 主题色）+ '：' + 内容文本（最多 4 行，maxLines=4 + ellipsis），点击跳楼中楼
  - 子回复点击跳转：复用 `navigateToSubPosts(post)` 等价路径，可选传入 spid 让 SubPostsPage 滚动到指定子回复（如实现成本高可降级为跳楼中楼不滚动，与原"查看全部"行为一致）
  - 预览区域样式：Column 垂直排列，圆角 6vp，背景 `input_background`，内边距 12vp，子项间距 2vp（对齐安卓版）

- **不修改模块**
  - `ForumModels.ets`：`PostInfo.subPostList` 和 `SubPostInfo` 类已存在，无需扩展
  - `TiebaAPI.ets`：不新增 API 请求
  - `string.json`：`view_all_sub_posts` 字符串继续复用，不新增

- **架构决策**
  - 预览渲染不引入新组件，直接在 PostItem 中用 Column + 循环 forEach 渲染（数组长度由服务端控制，通常 2-3 条，性能无忧）
  - 不为预览子回复单独抽组件文件，避免文件爆炸（PostItem 内部 @Builder 方法即可）
  - 不做富媒体渲染（图片/表情包/视频），只渲染纯文本内容（与安卓版 SubPostItem 一致）

- **降级策略**
  - 若服务端某楼层返回 `replyNum > 0` 但 `subPostList` 为空（极端情况），保留原"查看全部 N 条回复"按钮作为兜底
  - 即：渲染条件 `replyNum > 0 && subPostList.length > 0` 不满足但 `replyNum > 0` 时，回退到原按钮样式

## Testing Decisions

- **测试接缝（2 个，按优先级）**
  1. **协议解码接缝（最高）**：验证 `decodePost()` 解码 Post.sub_post_list 字段后，`PostInfo.subPostList` 数组长度和字段（spid/author/content/createTime）正确填充
  2. **UI 渲染接缝**：验证 PostItem 在 `replyNum>0 && subPostList.length>0` 时渲染预览区域，且 `replyNum > subPostList.length` 时显示"查看全部"按钮

- **测试方式**
  - 项目当前无 arkxest 测试基础设施（已在 issue #251 决策不搭建）
  - 采用 **手动验收 + 编译验证** 策略
  - 手动验收场景：
    - [ ] 进入有楼中楼的帖子详情页，验证楼层卡片显示前 N 条子回复预览
    - [ ] 预览底部显示"查看全部 N 条回复"按钮（仅当 replyNum > 预览数时）
    - [ ] 点击预览子回复跳转楼中楼
    - [ ] 点击"查看全部"按钮跳转楼中楼
    - [ ] 无回复的楼层不显示预览区域
    - [ ] 深色模式下预览样式正确
  - 编译验证：`hvigorw assembleHap` BUILD SUCCESSFUL

- **Prior art**：参考 issue #251 的"仅编译验证 + 验收清单"模式

## Out of Scope

- 楼中楼列表页（SubPostsPage）本身的 UI 优化
- 子回复富媒体（图片/表情包/视频）的预览渲染
- 楼中楼点赞/回复操作
- 沉浸模式（immersiveMode）下的预览行为（鸿蒙版无 immersiveMode 概念）
- 帖子卡片黑名单屏蔽逻辑（BlockableContent）
- 服务端预览条数策略调整（由服务端决定返回多少条）

## Further Notes

- 安卓版参考实现：`references/android/TiebaLite-4.0-dev/app/src/main/java/com/huanchengfly/tieba/post/ui/page/thread/ThreadPage.kt:2210-2268`
- 协议定义：`references/android/TiebaLite-4.0-dev/app/src/main/protos/Post.proto:44-46`、`SubPost.proto`、`SubPostList.proto`
- 模型层 `PostInfo.subPostList` 字段已存在（`ForumModels.ets:343`），此 PRD 只需填补解码层和 UI 层
- 与 #245 完整版吧内页面无关，本 PRD 作用于简化版和完整版共用的 ThreadPage
