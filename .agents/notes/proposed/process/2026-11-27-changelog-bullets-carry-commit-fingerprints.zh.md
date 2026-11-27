# Agent Note: 变更日志条目自带提交指纹

Status: proposed

[English](2026-11-27-changelog-bullets-carry-commit-fingerprints.md) | 中文

## Problem

emoji 功能随版本发布却未被公布之后新增的变更日志完整性门禁
（见[那篇笔记](../../implemented/bug-fix/2026-10-20-the-changelog-that-did-not-mention-emoji.zh.md)）
是靠猜来验证覆盖的：它从英文 commit subject 提取特征片段，再到中文 bullet 里
找。这个猜测双向都不可靠。`remark`、`dialog`、`wrap` 这类常用英文词缺少
`translated` 映射时会误报——`v0.1.63`/`v0.1.64` 已发布的条目明明写了对应变
更却被判缺失，`dart test` 今天就红在这两个版本上；反过来，bullet 里只要碰
巧含某个已映射的常见词（比如「设备」），所有 fragment 含 `device → 设备` 的
commit 都会被算作「已提及」——真正漏写的 commit 也能蒙混过关。映射表是一个
只能逐词手工补丁的机制（见
[回填记录](../../implemented/process/2026-11-06-changelog-gate-backfill.zh.md)
和[匹配器笔记](../../implemented/testing/2026-10-27-changelog-matcher-knows-gesture-and-address.zh.md)），
永远补不全。

时机也不对。条目在发版时才撰写，遗漏只能等 `dart test` 在版本已经存在之后才
被发现——门禁是在审计历史，而不是在守护发版。而匹配器需要散文启发式，唯一原
因是 commit 与 bullet 的关联从来没有被记录成数据。

## Proposal

把关联变成数据。在每个指纹化版本的条目里，每条 bullet 的指纹是一个 HTML 注
释，**独立成行、且是该 bullet 块的最后一行**——位于 `- ` 行和所有折行续行之
后、下一条 bullet/标题/空行之前：

```markdown
- 可以给已发现的设备设置本地备注名，方便区分多台设备
  <!-- @c2bb4be -->
- 修复「修改备注」弹窗的说明文字被截断
  <!-- @db2ed9b -->
```

指纹行与 bullet 的续行使用相同缩进，使注释在条目按 markdown 渲染时仍留在列
表项内部。一条 bullet 覆盖多个 commit 时在同一注释里以空格分隔列出：
`<!-- @c2bb4be @39bd4f1 -->`。每个 `@` 记号是 commit 的缩写 hash（
`git rev-parse --short` 形式，在仓库内唯一的前缀）。

**独立成行不是美化，是承重设计。** App 内更新面板用 `readUpdateNotes`
（`lib/ui/update_notes.dart`）解析发布说明：它只丢弃**整行** `<!--` 注释，
不剥行内注释，而且已发布的旧客户端跑的是同一份解析器——跟在 bullet 文字
后面的指纹会被原样画在旧客户端上，而新客户端又把它藏起来。注释独立成最后
一行会被该解析器原样跳过，所以这套语法不需要改 App，也不存在客户端版本
差。出于同样的原因，指纹必须是块的**最后**一行：解析器只在缩进续行之间恢
复折行 bullet，若注释行插在续行之前，后面的句子会变成孤儿文本。

**指纹由生成器负责，人只负责散文。** `git-publish` 的 changelog 步骤产出
的是结构化条目：它消费该区间的完整 commit 集合，把每个 commit 分配到某条
bullet（默认一一对应；合并 bullet 时拼接指纹集合），并自行写入注释行。集合
里每个 commit 恰好出现在一条 bullet 的指纹集合中——覆盖是生成的属性，而不
是靠谁记得。

**commit 集合只定义一次，用 Dart。**「该区间的用户可见 commit」不是一句话
谓词：它是 `releaseCommits` 已经应用的三段过滤——生产拓扑上的
`prevTag..tag` log 区间、`isUserVisible` 前缀过滤（`feat`、`fix`、
`refactor`、`perf`、`docs`，含 `!`），以及 `changedSomethingNew`——与上一
个 tag 做树 diff、剔除早先版本已在不同 commit id 下发布过的提交（排除
`CHANGELOG.md`）。打 tag 前的检查与发布后的测试必须共用这一份实现——检查是
一个由 `dart test` 覆盖的 Dart 入口，而不是在 PowerShell 或 Python 里另写一
份会漂移的移植。

**失败必须响亮，绝不静默。** 旧匹配器在 git 出错时 `return true`
（`changedSomethingNew` 的 `exitCode != 0` 兜底）；精确路径把「答不出来」
当作失败：算不出区间、diff 不出某个 commit 的文件、指纹解析不到区间内的
commit，门禁一律失败。不重试，不「假定已覆盖」。

**验证变精确，分两处：**

- *打 tag 之前：* `pre-publish-check.ps1` 新增一步，在推送 tag 前对待发布
  条目运行共享的 Dart 检查：待发布条目的指纹集合必须等于 release 分支上
  `prevTag..HEAD` 算出的 commit 集合。漏了会点名具体 hash，且此时修正还免
  费。这是现有脚本里新增的一次调用——`dart test` 本身并不加入其中。
- *发布之后：* `changelog_entries_test.dart` 对 `exactFrom` 起的每个版本
  做集合相等校验。

**迁移：`exactFrom` 是 `0.1.63`，不是下一个版本。** 两个条目可证已正确提及
其 commit 的版本——`v0.1.63`（`c2bb4be` 备注名、`39bd4f1` 官网描述）与
`v0.1.64`（`db2ed9b` 备注弹窗）——已验证为一一对应，回填指纹作为工具写入
的不可见元数据。已发布散文不动；注释行不是对「当时公布了什么」的改写。有
了这两条回填，方案落地当天 `dart test` 就转绿，而不是背着一个永远红的门
禁；`0.1.63` 起的每个版本都被精确集合相等约束。`0.1.63` 之前的版本继续
用现有片段匹配器，不动——与 `guardedFrom` 冻结 `0.1.8` 之前条目同理。

`translated` 映射表、`distinguishingFragments`、`commonChinesePairs` 从此
只服务冻结的历史，不再为新词扩充。

`git-publish` 里的人审步骤性质不变：审的是散文。指纹归工具所有——编辑弄丢
或改动指纹会被格式门禁和测试拦下。

## Alternatives considered

**给每个 commit 加 `Changelog:` trailer。** 否：会让每条 commit 正文都携带
发版说明散文——面向用户的 changelog 句子永远留在 `git log` 里、用第二语言
写一份只在发版时需要一次的文档。commit message 是放它的错误位置。

**towncrier 式 `changelog.d/` 碎片文件。** 否：commit 干净、链接精确，但每
个用户可见 PR 都要多一个只装一句话的文件，且覆盖检查被移到 PR 层，本地
`dart test` 门禁看不到。

**指纹侧车清单**（例如 `CHANGELOG.fingerprints` 记录 版本 → hash 列表）。
否：关联落在第二个必须与条目保持同步的文件里，单独消费条目的任何读者都丢
失这层关联；清单的合并冲突和条目本身一样容易发生，却没有条目自带证据那样
的自证性。

**只从下个版本起指纹化（`exactFrom = 0.1.65`），`0.1.63`/`0.1.64` 留在旧
匹配器上。** 否：今天挂掉的正是旧匹配器，而测试读全部历史——这两个版本永
远不会滑出检查范围，门禁会永远红。回填的成本只是给三条 bullet 加不可见注
释行，而它们的 commit↔bullet 映射已验证一一对应。

**在 `[Unreleased]` 下持续累积 bullet。** 否：每个 PR 都改 `CHANGELOG.md`
同一区域；并行 worktree 开发让冲突成为常态，文件沦为合并热点。

**magpie 的做法：不落盘 changelog，发版时 LLM 现写。** 对本仓库否决：条目
必须留在 `CHANGELOG.md`，因为它要喂 GitHub Release 正文、App 内更新面板和
版本历史——不能是 commit subject 之上的临时视图。（但它的方法论被借用了：
生成失败时可以降级为朴素的 commit 列表，而不是卡住发版。）

**保留片段匹配、继续扩充 `translated` 表。** 否：这正是今天产生误报的现状，
而且映射表永远不可能补全——每个新的英文功能词都是一次让正确条目失败、或
让不完整条目蒙混的机会。

**发版时全交给 LLM 写 bullet。** 暂缓而非否决：有了指纹之后，散文将来也可
以交给 LLM、人审退化为可选——与 magpie 同构——但那是「谁来写句子」的独立
决策，不是「覆盖如何验证」的问题。

## Acceptance criteria

- 本方案生成的版本条目把其范围内每个 commit 恰好指纹化一次；每个指纹是
  独立成行、位于块末尾的 HTML 注释，匹配
  `^\s*<!--\s*@[0-9a-f]+(\s+@[0-9a-f]+)*\s*-->\s*$`。
- commit 集合谓词只有一份实现，打 tag 前检查与 `dart test` 共用；两者计算
  结果一致。
- `pre-publish-check.ps1` 调用打 tag 前的指纹检查；该检查对「git 查询无
  法回答」同样失败，而不仅是集合不匹配。
- `dart test` 对 `>= 0.1.63` 的版本做精确集合相等校验——`0.1.63`/
  `0.1.64` 经回填指纹纳入——更早的版本留在现有匹配器上；套件全绿。
- 格式门禁对指纹化版本拒绝：bullet 无指纹、指纹行不在块末尾、指纹格式错
  误、hash 重复、hash 不是该版本范围内的 commit。
- 渲染经 `readUpdateNotes` 验证：独立成行的注释被按现有解析器跳过，无需
  客户端改动；该检查在实施时重跑确认，而不是想当然。

## Risks

- **人工编辑弄丢或改动指纹，或把指纹插到块中间。** 被格式门禁和测试拦下；
  补救是恢复工具写的注释，而不是重新推导。
- **多 commit bullet 让 hash 记账变成手工活。** 合并 bullet 时拼接指纹集
  合；拆分一条需要同步拆分指纹。生成器默认的一一对应让这种情况保持罕见。
- **独立成行规则与手工折行相互作用。** 续行带缩进；指纹行用相同缩进且必
  须位于所有续行之后。格式门禁强制块末尾位置，块中间的注释无法让
  `readUpdateNotes` 弄丢折行散文。
- **回填指纹改动了已发布条目。** 它们是不可见元数据而非散文；将来若有消
  费者渲染原始 `CHANGELOG.md` 而不剥离 HTML 注释，需要学会跳过的正是这
  套独立成行语法——格式已是 `readUpdateNotes` 所丢弃的那一种。
- **打 tag 前的检查需要能识别待发布条目。** 它读取发版步骤刚写下的条目；
  绕过 `git-publish` 的发版拿不到检查——与所有发版时门禁现有的豁免相同。
