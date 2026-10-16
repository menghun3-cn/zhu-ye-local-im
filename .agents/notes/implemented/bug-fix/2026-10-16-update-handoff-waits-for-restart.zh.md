# Agent Note: 绿色包更新交接等待新进程真正启动

Status: implemented

[English](2026-10-16-update-handoff-waits-for-restart.md) | 中文

## Problem

绿色包自己替换自己的最后一步存在竞争条件：`lib/ui/update_handoff.dart` 的
`_finish()` 在隔离区里把新文件落位之后，调用 `startDetached(executable)`，然后
立即 `exit(0)`。原来的 `startDetached` 是 `Process.start(...)` 的 fire-and-forget
调用，从未被 await。

`Process.start` 返回 `Future`，子进程真正被创建发生在之后的 event loop 轮次；
`exit(0)` 会终止 isolate，也带走尚未完成的 future。于是存在一个窗口：更新文件
已经换好，但新窗口没有起来——「关闭并更新」关掉了程序，却没有把它带回来。

安装包路径不受影响：Inno 的 `[Run]` 条目在静默 `/update` 安装后启动可执行程序。
这个 bug 只属于绿色包自替换的交接流程。

## Decision

把 `startDetached` 改为返回 `Future<void>`，并在内部 `await Process.start(...)`；
`_finish()` 在 `exit(0)` 之前先 `await startDetached(executable)`。

await 的意义不是风格而是顺序：旧进程只有在操作系统已经接受新进程之后才可以
消失。detached 模式下子进程能独立于父进程存活，因此 future 完成就意味着重启
真的已开始。如果启动失败，异常会进入 `_finish()` 的失败分支，交接窗口会报告
原因，而不是默默消失。

## Consequences

- 绿色包更新后的重启不再是「尽量」，而是旧进程确认新进程已创建后才退出。
- 启动新进程失败时，交接窗口会显示失败信息，而不是让用户面对空文件夹。
- 加了一条测试守住契约：给 `startDetached` 传一个不存在的可执行文件会向调用方
  抛出 `ProcessException`，fire-and-forget 实现会把它吞掉。

## Alternatives considered

**保留 fire-and-forget** —— 这正是「更新完但没有重新打开」的来源，不能保留。

**改用 `Process.run`** —— 那不是分离启动，而且等待输出不是交接需要的；子进程
必须比父进程活得久。

**退出前固定延时** —— 延时不是「进程已启动」的证据，而且会让每台正常机器白等；
await 启动结果才是真正有意义的检查。
