# Agent Note: Backfilling the 0.1.38–0.1.39 changelog entries

Status: implemented

English | [中文](2026-11-06-backfill-changelog-0.1.38-0.1.39.zh.md)

## Problem

`dart test` failed on develop in `changelog_entries_test.dart`: the
`0.1.38` and `0.1.39` entries did not account for every user-visible
commit in their ranges. Two different gaps hid behind the same red:

* `0.1.38`'s screenshot commits *were* described by Chinese bullets, but
  the test's English→Chinese word list lacked `screenshot`, `overlay`
  and friends, so the matcher could not see the mention.
* `0.1.39` genuinely omitted two commits — the docs-alignment commit and
  the Settings-card incoming-folder fix — that no bullet covered.

## Decision

**Backfill the missing bullets, extend the word list.** The `0.1.39`
entry gained a 修复 bullet for the incoming-folder count and a 变更
bullet for the README/site/packaging documentation alignment, worded
from the commits themselves. The test's `translated` map gained the
recurring feature words the shipped entries actually use —
`screenshot`/`screenshots`→截图, `overlay`→遮罩, `hotkey`→快捷键,
`navigation`→导航, `card`→卡片, `folder`→文件夹, `incoming`→接收,
`settings`→设置 — the same mechanism the `0.1.36` entry already used
when it last expanded the list.

## Consequences

* `dart test` is green on develop again; the gate keeps its teeth —
  the word list only got *more* precise about words the changelog
  already uses, it did not get looser about what counts as a mention.
* The `0.1.38`/`0.1.39` release notes on GitHub and in the in-app
  updater now tell the whole story of those versions, which is what
  the entries were always supposed to do.
* Released entries stay editable for exactly this kind of omission —
  the same precedent `0.1.36` set when it backfilled `0.1.30`–`0.1.32`.
  Rewriting an entry's *meaning* would still be off-limits; completing
  it is not.

## Alternatives considered

**Loosen the matcher instead.** Rejected: the failure was not the
matcher's strictness — two commits truly had no bullet, and a matcher
that cannot tell "described in Chinese" from "absent" is the gap the
test exists to close, not widen.

**Leave the entries as released.** Rejected: the entries are what the
GitHub Release body and the in-app update panel show; an omission there
is a change users were never told about, which is the exact defect the
test was written to catch.
