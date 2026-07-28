## Parent

- #252 (PRD：楼中楼预览)

## What to build

切片A：协议解码层填补 sub_post_list 字段解码。

在 `PbPageProto.ets` 的 `decodePost()` 函数中新增 `case 15` 分支，递归解码 SubPost message（SubPostList field 2 = repeated SubPostList），将解码结果填充到 `PostInfo.subPostList: SubPostInfo[]` 数组。

每条 SubPostList 解码字段（对齐 SubPostList.proto）：
- field 1: id → spid
- field 2: content → 复用 decodePostContent 解码 PbContent 数组
- field 3: time → createTime
- field 4: author_id → author.id
- field 5: title → title
- field 6: floor → floor
- field 7: author → 复用 decodeUser 解码 User message
- field 9: agree → agreeNum（如有 Agree 解码辅助函数）
- field 11: is_fake_top → 标记位
- field 12: is_author_view → 标记位

切片完成后，进入有楼中楼的帖子详情页，`PostInfo.subPostList` 数组应非空（通过临时 console.info 日志验证长度+首条 spid/author.name/content）。

## Acceptance criteria

- [ ] PbPageProto.ets 的 decodePost() 新增 case 15 分支解码 sub_post_list
- [ ] 复用 decodeUser / decodePostContent 函数，不重复造轮子
- [ ] 解码结果填充 PostInfo.subPostList 数组（SubPostInfo[] 模型已存在）
- [ ] 不破坏现有 Post 其他字段解码（pid/floor/content/agree 等保持正确）
- [ ] 编译通过（hvigorw assembleHap BUILD SUCCESSFUL）
- [ ] 运行时验证：进入有楼中楼的帖子详情页，日志确认 subPostList 数组非空且字段填充正确

## Blocked by

None - can start immediately
