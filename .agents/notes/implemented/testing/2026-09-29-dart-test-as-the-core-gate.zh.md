# Agent Note: Verify the core with `dart test` where `flutter test` cannot run

Status: implemented

[English](2026-09-29-dart-test-as-the-core-gate.md) | 中文

## Problem

[AGENTS.md](../../../../AGENTS.md) §5 把 `flutter test` 定为验收门禁。但在这台开发机上 `flutter test` 根本跑不起来：每个测试文件都在加载阶段以 `Invalid WebSocket upgrade request` 失败。成因是环境而非本仓库 —— 深信服 aTrust 零信任客户端装了一个 Winsock LSP，它转发回环 HTTP 时会剥掉逐跳的 `Connection` 与 `Upgrade` 头，于是 Flutter 测试框架对自己 `flutter_tester` 进程发起的 WebSocket 永远完成不了握手。同一 socket 上的普通 HTTP 不受影响，而且随着客户端自我更新，这个状态会在几分钟内从可用翻转为不可用。

跑不起来的门禁不算门禁。把它留在原地，要么堵死所有工作，要么把所有人训练成无视红色结果。

## Decision

核心层用 `dart test` 验证，这就是 `lib/core/` 的门禁。`lib/core/` 不引入任何 Flutter 依赖 —— 只有 `dart:*`、`package:crypto` 与 `package:cryptography` —— 因此纯 Dart VM 能跑完它的每一个测试，包括那些绑定真实回环 TCP socket 的用例。`flutter analyze` 与 `dart format --set-exit-if-changed .` 保持不变，仍然覆盖整个仓库。

`test/widget_test.dart` 是 `flutter create` 留下的计数器测试，已删除而非留其失败：它断言的是一个本次增量并未触及的应用外壳，而且在这里根本无法执行。

于是门禁为：

```powershell
.\scripts\verify-agent-notes.ps1
.\scripts\verify-translation-pairs.ps1
flutter analyze
dart format --set-exit-if-changed .
dart test
```

在不被该 LSP 干扰的机器上，`flutter test` 仍是 widget 测试的既定门禁，本决定不妨碍在那里使用它。

## Alternatives considered

**照样跑 `flutter test` 并接受失败。** 否决理由：一个永远为红的门禁，恰恰会掩盖它所报告的那些测试里的真实回归；而且这里的失败是每个文件的加载期错误，而不是某条具体的断言失败。

**把「卸载 aTrust 客户端」或「给 Flutter 二进制加白」当作前置条件。** 否决理由：把它作为阻塞依赖不可行 —— 那是托管机器上的企业安全客户端，本仓库无权移除；而一个需要开工单才能跑的门禁，不是贡献者能依赖的门禁。此处把它记录为「若管理员想要回 `flutter test`，真正的解法是什么」。

**把核心层拆成独立的、无 Flutter 依赖的包，在那里测试。** 否决理由：相比现状并无收益。`lib/core/` 本来就没有 Flutter 依赖，而多拆一个包会为一条导入图已经强制成立的边界，额外引入一个 pubspec、一个版本号与一条依赖边。

**让核心层也通过 `flutter test` 测，用一个 runner 覆盖全部。** 否决理由：这会把一个刻意不依赖 Flutter 的层，耦合到那唯一跑不起来的工具链上。

## Consequences

- `dart test` 完整覆盖核心层，包括真实 socket 行为。它在单一进程内运行、无需构建步骤，整套用例几秒钟跑完。
- 核心层的「无 Flutter 依赖」从顺带性质变成了承重性质：`lib/core/` 下任何一处 `package:flutter` 的导入都会打断门禁。这是刻意约束，不是疏漏。
- 在这台机器上，widget 测试是一处被明确点名的覆盖缺口。应用外壳目前没有任何 widget 测试，在 UI 外壳成型、且有机器能跑它们之前也不会写。
- 该门禁偏离了 AGENTS.md §5 —— 那份文件仍然写着 `flutter test`。本笔记记录了为什么这里的核心门禁是 `dart test`，使这次偏离是一个决定，而不是漂移。
