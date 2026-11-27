# Agent Note: 变更日志条目自带提交指纹

Status: proposed

[English](2026-11-27-changelog-bullets-carry-commit-fingerprints.md) | 中文

## Problem

emoji 功能随版本发布却未被公布之后新增的变更日志完整性门禁
（见[那篇笔记](../implemented/bug-fix/2026-10-20-the-changelog-that-did-not-mention-emoji.zh.md)）
是靠猜来验证覆盖的：它从英文 commit subject 提取特征片段，再到中文 bullet 里
找。这个猜测双向都不可靠。`remark`、`dialog`、`wrap` 这类常用英文词缺少
`translated` 映射时会误报——`v0.1.63`/`v0.1.64` 已发布的条目明明写了对应变
更却被判缺失；反过来，bullet 里只要碰巧含某个已映射的常见词（比如「设备」），
所有 fragment 含 `device → 设备` 的 commit 都会被算作「已提及」——真正漏写的
commit 也能蒙混过关。映射表是一个只能逐词手工补丁的机制（见
[回填记录](../implemented/process/2026-11-06-changelog-gate-backfill.zh.md)
和[匹配器笔记](../implemented/testing/2026-10-27-changelog-matcher-knows-gesture-and-address.zh.md)），
永远补不全。

时机也不对。条目在发版时才撰写，遗漏只能等 `dart test` 在版本已经存在之后才
被发现——门禁是在审计历史，而不是在守护发版。而匹配器需要散文启发式，唯一原
因是 commit 与 bullet 的关联从来没有被记录成数据。

## Proposal

把关联变成数据。指纹化版本的每条 bullet 末尾带一个 HTML 注释，列出它覆盖的
commit：

```markdown
- 可以给已发现的设备设置本地备注名 <!-- @c2bb4be -->
- 修复「修改备注」弹窗的说明文字被截断 <!-- @db2ed9b -->
```

一条 bullet 覆盖多个 commit 时在同一注释里列出：
`<!-- @c2bb4be @db2ed9b -->`。注释在条目被渲染的任何地方——GitHub Release
正文、App 内更新面板——都不可见，但门禁可以精确解析。

**指纹由生成器负责，人只负责散文。** `git-publish` 的 changelog 步骤产出的是
结构化条目：它消费该区间全部用户可见 commit，把每个 commit 分配到某条
bullet（默认一一对应；合并 bullet 时拼接指纹集合），并自行写入注释。每个用
户可见 commit 恰好出现在一条 bullet 的指纹集合里——覆盖是生成的属性，而不是
靠谁记得。

**验证变精确，分两处：**

- *打 tag 之前：* 发版流程在推送 tag 前检查待发布条目的指纹集合与上一个 tag
  以来的用户可见 commit 集合相等——用的就是测试里同一套 commit 集合计算。
  漏了会点名具体 hash，且此时修正还免费。
- *发布之后：* `changelog_entries_test.dart` 对 `exactFrom`（本方案下切出的
  第一个版本，预计 `0.1.65`）起的每个版本做集合相等校验。`exactFrom` 之前的
  版本继续用现有片段匹配器，不动——已发布历史冻结，正如 `guardedFrom` 冻结
  `0.1.8` 之前的条目。

`translated` 映射表、`distinguishingFragments`、`commonChinesePairs` 从此只
服务冻结的历史，不再为新词扩充。

`git-publish` 里的人审步骤性质不变：审的是散文。指纹归工具所有——编辑弄丢
或改动指纹会被格式门禁和测试拦下。

## Alternatives considered

**给每个 commit 加 `Changelog:` trailer。** 否：会让每条 commit 正文都携带发
版说明散文——面向用户的 changelog 句子永远留在 `git log` 里、用第二语言写一
份只在发版时需要一次的文档。commit message 是放它的错误位置。

**towncrier 式 `changelog.d/` 碎片文件。** 否：commit 干净、链接精确，但每个
用户可见 PR 都要多一个只装一句话的文件，且覆盖检查被移到 PR 层，本地
`dart test` 门禁看不到。

**在 `[Unreleased]` 下持续累积 bullet。** 否：每个 PR 都改 `CHANGELOG.md`
同一区域；并行 worktree 开发让冲突成为常态，文件沦为合并热点。

**magpie 的做法：不落盘 changelog，发版时 LLM 现写。** 对本仓库否决：条目
必须留在 `CHANGELOG.md`，因为它要喂 GitHub Release 正文、App 内更新面板和
版本历史——不能是 commit subject 之上的临时视图。（但它的方法论被借用了：生
成失败时可以降级为朴素的 commit 列表，而不是卡住发版。）

**保留片段匹配、继续扩充 `translated` 表。** 否：这正是今天产生误报的现状，
而且映射表永远不可能补全——每个新的英文功能词都是一次让正确条目失败、或让
不完整条目蒙混的机会。

**发版时全交给 LLM 写 bullet。** 暂缓而非否决：有了指纹之后，散文将来也可以
交给 LLM、人审退化为可选——与 magpie 同构——但那是「谁来写句子」的独立决
定，不是「覆盖如何验证」的问题。

## Acceptance criteria

- 本方案生成的版本条目把其范围内每个用户可见 commit 恰好指纹化一次；打 tag
  前的检查在 tag 存在之前通过。
- `dart test` 对指纹化版本做精确集合相等校验，`exactFrom` 之前的版本留在现
  有匹配器上。
- 格式门禁拒绝指纹化版本里没有指纹、指纹格式错误或 hash 重复的 bullet。
- 渲染检查确认注释在 GitHub Release 正文和 App 内更新面板中保持不可见。

## Risks

- **人工编辑弄丢或改动指纹。** 被格式门禁和测试拦下；补救是恢复工具写的注
  释，而不是重新推导。
- **多 commit bullet 让 hash 记账变成手工活。** 合并 bullet 时拼接指纹集
  合；拆分一条需要同步拆分指纹。生成器默认的一一对应让这种情况保持罕见。
- **某个消费者渲染 `CHANGELOG.md` 时不剥离 HTML 注释。** 实施时验证；若
  About 面板显示原始文本，指纹语法换成该渲染器同样隐藏的形式。
- **打 tag 前的检查需要能识别待发布条目。** 它读取发版步骤刚写下的条目；绕
  过 `git-publish` 的发版拿不到检查——与所有发版时门禁现有的豁免相同。
