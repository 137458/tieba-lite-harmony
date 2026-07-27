# 更新日志编写规则

本文件规定 `CHANGELOG.md` 和 GitHub Release 更新日志的写法。

## 两类更新日志

- `CHANGELOG.md`：保存每个正式版的完整变化，面向项目维护和查阅历史。
- GitHub Release 更新日志：面向普通用户，使用简单中文说明这次添加了什么、修复了什么，并附上安装方法、致谢和许可。

GitHub Release 更新日志应基于 `CHANGELOG.md` 摘要编写，不应只复制提交标题。

## GitHub Release 固定结构

每个正式版 Release 按以下顺序编写：

```md
## 新增

- 添加了……

## 修复

- 修复了……

## 安装方法

1. 下载本页的 `.hap` 安装包。
2. 在 HarmonyOS NEXT 设备上使用 hokit 安装。详细步骤请参考[鸿蒙应用安装教程](https://www.coolapk.com/feed/71672895?s=NDVhZjRjMzMxOTc0MTMxZzZhNjcwM2Uwega1651b3)。
3. 安装后打开“贴吧 Lite”即可使用。

## 系统要求

- HarmonyOS NEXT 6.1.0(23) 及以上。
- 建议使用 HarmonyOS 6.1.1(24) 或更高版本。

## 致谢

- [TiebaLite-4.0-dev](https://github.com/huanchengfly/TiebaLite) — Android 原版参考。
- [aiotieba](https://github.com/lwt12345/aiotieba) — 百度贴吧 API 实现参考。

## 许可

本项目仅供学习交流使用，不得用于商业目的。
```

没有新增内容时保留“修复”章节即可；不要为了凑章节把普通修复写成新增功能。

## 用语要求

- 使用“添加了”“支持了”“修复了”“优化了”这类用户能看懂的表达。
- 只写用户能感知的结果，不写实现细节、类名、Issue 编号、提交哈希或内部 API 名称。
- 不使用表情符号。
- 不把试错过程、回滚过程和中间实现写入更新日志。
- 不承诺未经真机验证的效果。
- 同一问题的多次提交合并为一条最终结果，避免重复。

推荐：

```md
- 修复帖子详情页底栏偶尔显示成小圆球的问题。
- 修复网页登录成功后无法自动回到应用的问题。
```

不推荐：

```md
- 修复 HdsTabs 的 miniBar COLLAPSE 和 barWidth 断点问题。
- 将 ThreadPage 的 FloatingTabBar 改为 layoutWeight 2:3。
```

## CHANGELOG.md 写法

`CHANGELOG.md` 在文件顶部添加新版本，格式如下：

```md
## [v1.2.1] - 2026-07-27

### 新增

- 关于页新增 QQ 群入口。

### 修复

- 修复帖子详情页悬浮底栏布局异常的问题。
```

- 版本日期使用正式发布日期，未发布版本不要写入正式版本区块。
- 按“新增”“修复”“优化”“其他”分类；没有内容的分类不创建。
- 每条记录描述最终结果，必要时可补充涉及的页面或功能。
- 详细记录可以比 GitHub Release 多，但仍应避免只对开发者有意义的实现细节。

## 发布前核对

- 更新范围从上一个正式版标签开始，不遗漏测试版期间已合入的变化。
- `CHANGELOG.md`、GitHub Release 标题、Git 标签和应用内版本号一致。
- Release 包含 `.hap` 安装包。
- 安装方法、系统要求、致谢和许可四个章节完整保留。
- 文本不含表情符号、内部术语和未经验证的描述。
