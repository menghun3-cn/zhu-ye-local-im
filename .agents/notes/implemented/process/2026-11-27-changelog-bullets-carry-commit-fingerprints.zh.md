# Agent Note: 变更日志条目自带提交指纹

Status: implemented

[English](2026-11-27-changelog-bullets-carry-commit-fingerprints.md) | 中文

## Problem

emoji 功能随版本发布却未被公布之后新增的变更日志完整性门禁
（见[那篇笔记](../../implemented/bug-fix/2026-10-20-the-changelog-that-did-not-mention-emoji.zh.md)）
当时是靠猜来验证覆盖的：它从英文 commit subject 提取特征片段，再到中文
bullet 里找。这个猜测双向都不可靠。`remark`、`dialog`、`wrap` 这类常用英文
词缺少 `translated` 映射时会误报——`v0.1.63`/`v0.1.64` 已发布的条目明明写
了对应变更却被判缺失，`dart test` 一度红在这两个版本上；反过来，bullet 里
只要碰巧含某个已映射的常见词（比如「设备」），所有 fragment 含
`device → 设备` 的 commit 都会被算作「已提及」——真正漏写的 commit 也能蒙混
过关。映射表是一个只能逐词手工补丁的机制（见
[回填记录](../../implemented/process/2026-11-06-changelog-gate-backfill.zh.md)
和[匹配器笔记](../../implemented/testing/2026-10-27-changelog-matcher-knows-gesture-and-address.zh.md)），
永远补不全。

时机也不对。条目在发版时才撰写，遗漏只能等 `dart test` 在版本已经存在之后
才被发现——门禁是在审计历史，而不是在守护发版。而匹配器需要散文启发式，唯
一原因是 commit 与 bullet 的关联从来没有被记录成数据。

## Decision

关联是数据。在每个指纹化版本的条目里（`exactFrom` = `0.1.63`），每条
bullet 的指纹是一个 HTML 注释，**独立成行、且是该 bullet 块的最后一行**
——位于 `- ` 行和所有折行续行之后、下一条 bullet/标题/空行之前：

```markdown
- 可以给已发现的设备设置本地备注名，方便区分多台设备
  <!-- @c2bb4be -->
```

指纹行与 bullet 的续行使用相同缩进，使注释在条目按 markdown 渲染时仍留在
列表项内部。一条 bullet 覆盖多个 commit 时在同一注释里以空格分隔列出：
`<!-- @c2bb4be @39bd4f1 -->`。每个 `@` 记号是 commit 的缩写 hash，按全量
hash 的唯一前缀匹配。

**独立成行是承重设计。** App 内更新面板用 `readUpdateNotes`
（`lib/ui/update_notes.dart`）解析发布说明：它跳过整行 `<!--` 注释，但不剥
行内注释，而且已发布的旧客户端跑的是同一份解析器——跟在 bullet 文字后面的
指纹会被原样画在旧客户端上。注释独立成最后一行会被该解析器原样跳过，所以
这套语法不需要改 App，也不存在客户端版本差。出于同样的原因，指纹必须是块
的**最后**一行：解析器只在缩进续行之间恢复折行 bullet，若注释行插在续行之
前，后面的句子会变成孤儿文本。

**指纹由生成器负责，人只负责散文。** `git-publish` 的 changelog 步骤产出
的是结构化条目：它消费
`dart run test/process/changelog_fingerprint_check.dart --commits` 打印的
commit 集合，把每个 commit 分配到某条 bullet（默认一一对应；合并 bullet 时
把多个 `@token` 写进同一行注释），并自行写入注释行。集合里每个 commit 恰好
出现在一条 bullet 的指纹集合中——覆盖是生成的属性，而不是靠谁记得。

**commit 集合只有一份实现，用 Dart。**「该区间的用户可见 commit」是三段过
滤，不是一句话谓词：生产拓扑上的 `prevTag..tag` log 区间、`isUserVisible`
前缀过滤（`feat`、`fix`、`refactor`、`perf`、`docs`，含 `!`），以及
`changedSomethingNew`——与上一个 tag 做树 diff、剔除早先版本已在不同
commit id 下发布过的提交（排除 `CHANGELOG.md`）。全部实现在
`test/process/changelog_commits.dart`，发布后测试与打 tag 前检查共用——
PowerShell 或 Python 里没有第二份会漂移的移植。git 失败是响亮的：旧匹配器
在 git 出错时 `return true`，共享谓词改为抛错——答不出来的问题就是门禁失败。
没有重试，没有「假定已覆盖」的兜底。

**验证变精确，分两处：**

- *打 tag 之前：* `dart run test/process/changelog_fingerprint_check.dart`
  把待发布条目解析出的指纹集合与 release 分支上 `prevTag..HEAD` 的 commit
  集合比对，并点名缺失与多余的 hash。`pre-publish-check.ps1` 与
  `pre-publish-check.example.sh` 在脚本存在时调用它，检查同时是发布前门禁
  的一部分。
- *发布之后：* `changelog_entries_test.dart` 对 `exactFrom`（`0.1.63`）起
  的每个版本做集合相等校验，并包含集合相等本身看不见的「同一 hash 被两条
  bullet 声明」检测。`exactFrom` 之前的版本继续用旧片段匹配器，不动。

**迁移：`exactFrom` 是 `0.1.63`，`0.1.63`/`0.1.64` 已回填。** 这两个条目
的 commit↔bullet 映射已验证一一对应，指纹作为工具写入的不可见元数据补上
——已发布散文不动，注释行不是对「当时公布了什么」的改写。两条回填让方案落
地当天 `dart test` 就转绿，而不是背着一个永远红的门禁。`translated` 映射
表、`distinguishingFragments`、`commonChinesePairs` 是只服务冻结历史的遗留
机制；不再为新词扩充。

**格式约束按各门禁所能看见的范围分工。** `changelog_check.py` 校验待发布
条目的指纹*语法*——独立成行的块末尾位置、`<!-- @hash… -->` 形状、条目内
不重复——版本不低于 `--fingerprint-from`（`0.1.63`）时生效。集合相等、
hash 到 commit 的解析、跨 bullet 的重复声明属于 Dart 侧——它拥有 commit
谓词。

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
匹配器上。** 否：当时挂掉的正是旧匹配器，而测试读全部历史——那两个版本永
远不会滑出检查范围，门禁会永远红。回填的成本只是给三条 bullet 加不可见注
释行，而它们的 commit↔bullet 映射已验证一一对应。

**在 `[Unreleased]` 下持续累积 bullet。** 否：每个 PR 都改 `CHANGELOG.md`
同一区域；并行 worktree 开发让冲突成为常态，文件沦为合并热点。

**magpie 的做法：不落盘 changelog，发版时 LLM 现写。** 对本仓库否决：条目
必须留在 `CHANGELOG.md`，因为它要喂 GitHub Release 正文、App 内更新面板和
版本历史——不能是 commit subject 之上的临时视图。（但它的方法论被借用了：
生成失败时可以降级为朴素的 commit 列表，而不是卡住发版。）

**保留片段匹配、继续扩充 `translated` 表。** 否：这正是当时产生误报的现
状，而且映射表永远不可能补全——每个新的英文功能词都是一次让正确条目失
败、或让不完整条目蒙混的机会。

**发版时全交给 LLM 写 bullet。** 暂缓而非否决：有了指纹之后，散文将来也可
以交给 LLM、人审退化为可选——与 magpie 同构——但那是「谁来写句子」的独立
决策，不是「覆盖如何验证」的问题。

## Consequences

方案换来的是：覆盖是生成的属性——commit 集合由 `--commits` 枚举，每个
commit 落进且只落进一个指纹集合，两个门禁做的都是集合比对而不是猜散文。
打 tag 前的检查在 release 尚未推送时就点名出错的 hash，`dart test` 精确且
全绿。指纹行在 GitHub Release 正文和 App 内更新面板中不可见：`readUpdateNotes`
按现有解析器跳过整行注释，验证的是解析器本身而不是想当然。

代价是：每个用户可见的发版多了一道机械步骤——草稿必须带正确指纹，否则两
个门禁都失败；`git-publish` 的步骤 3 被改写为「工具写指纹、人写散文」。
commit 集合谓词对每个 commit 要跑三次 git 查询，所以发布后测试的耗时大头
仍是 `changedSomethingNew` 的逐 commit diff——与旧匹配器本来就付的成本相
同。旧匹配器与其 `translated` 表留在树里服务冻结历史，是有意的重复，保留
到 `0.1.63` 之前的条目自身也被视为封存为止。

约束行为的机制：`test/process/changelog_entries_test.dart`（`>= 0.1.63`
的精确集合相等、解析器单元测试、更早版本的旧匹配器）、
`test/process/changelog_fingerprint_check.dart`（`--commits` 清单与打 tag
前比对）、`changelog_check.py` 的 `--fingerprint-from` 语法规则，以及
`pre-publish-check` 脚本对 Dart 检查的调用。
