# Agent Note: 功能开发在独立 worktree 里进行

Status: implemented

[English](2026-10-19-feature-work-happens-in-worktrees.md) | 中文

## Problem

主检出区被太多事情共用。功能分支、发布流程和另一个进行中的功能都落在同一个工作树里，
`git status` 一次列出五六个互不相干的改动，让人分不清某个文件属于哪个 PR。一个被打断或
丢弃的任务会把半成品漏进下一个功能的提交里，而门禁（`dart test`、`flutter analyze`）
跑的根本不是将要发布的那棵树。

## Decision

**每个功能或修复都开一个独立 git worktree。** 流程现在是：

```powershell
git worktree add -b <type>/<描述> F:\asc_workspace\code\aicode\zhu-ye-local-im-<名字> origin/develop
```

主检出（`zhu-ye-local-im`）只留给仓库操作与发布流程；某个分支的代码在自己 worktree
里开发、在那里过门禁、从那里提 PR。`AGENTS.md` §2.1 写下了这条规则，今后的 agent 和
贡献者从同一个起点出发。并行任务不再互相弄脏对方的 `git status`，半成品的功能也可以
留在自己的检出区，而不是逼下一个功能替它背着。

## Alternatives considered

**继续用同一个检出区，靠 `git stash`。** 否决：stash 容易忘、容易弹错分支，而且帮不了
两个同时要跑 `test_flutter` 的任务。

**每个功能单独 clone 一份。** 否决：clone 会把整个仓库历史复制一遍，还要各自配 remote；
worktree 复用同一个 `.git` 和同一组 remote。

## Consequences

- `AGENTS.md` §2.1 记录了 worktree 规则。
- 主检出里的发布流程与无关实验不再漏进某个功能的 diff。
- 代价是每个活跃功能一个目录、隔一阵子跑一次 `git worktree prune`，比解开一团混着的
  `git status` 便宜得多。
