# Agent Note: Verify the core with `dart test` where `flutter test` cannot run

Status: implemented

[English](2026-09-29-dart-test-as-the-core-gate.md) | 中文

## Problem

[AGENTS.md](../../../../AGENTS.md) §5 把 `flutter test` 定为验收门禁。但在本项目开发的一段时间里，这台机器上 `flutter test` 根本跑不起来：每个测试文件都在加载阶段以 `Invalid WebSocket upgrade request` 失败。成因是环境而非本仓库 —— 深信服 aTrust 零信任客户端装了一个 Winsock LSP，它转发回环 HTTP 时会剥掉逐跳的 `Connection` 与 `Upgrade` 头，于是 Flutter 测试框架对自己 `flutter_tester` 进程发起的 WebSocket 永远完成不了握手。同一 socket 上的普通 HTTP 不受影响，而且随着客户端自我更新，这个状态会在几分钟内从可用翻转为不可用。

该客户端此后已被卸载，`flutter test` 在这里又跑得起来了 —— 截至 2026-09-30，`flutter test test_flutter` 全部 widget 用例通过。下面的决定是在它跑不起来的时候做的，而它被保留下来，是因为当初的理由比那次故障活得更久：这次拆分让「永远跑得起来的套件」保持永远跑得起来，而在两套件都能跑的今天，它不产生任何代价。

跑不起来的门禁不算门禁。把它留在原地，要么堵死所有工作，要么把所有人训练成无视红色结果。

随后出现的两个问题，让最初的答案不再够用：

- `lib/ui/` 长出了真正的 widget。widget 测试要导入 `package:flutter_test`，而纯 Dart VM 根本跑不了它，所以它们无法待在「能跑的那个门禁」所看的地方。
- `dart test` 只发现 `test/`，别的都不看。因此一个被放进 `test/` 的 widget 测试，会打断这台机器上唯一保证能跑的套件 —— 而这正是最初那个决定要防的事故 —— 并且是在一台根本没法修好它的机器上打断。

## Decision

套件按「谁能跑它」拆分，拆分的界线是目录：

| 目录 | 放什么 | 谁来跑 |
| --- | --- | --- |
| `test/` | 不需要 widget 树的测试 | `dart test` |
| `test_flutter/` | 导入 `package:flutter_test` 的测试 | `flutter test test_flutter` |

`lib/core/` 与 `lib/app/` 不引入任何 Flutter 依赖 —— 只有 `dart:*`、`package:crypto`、`package:cryptography` 以及彼此 —— 所以 `dart test` 能跑完 `test/` 里的每一个测试，包括那些绑定真实回环 TCP socket 的用例。`test/app/plain_dart_test.dart` 是在**强制**这条主张而不是假设它：它扫描这两层，一旦出现 `package:flutter` 导入就失败。

`test_flutter/` 是第二道门禁，也是在那个干扰性客户端还装着时、这台机器跑不了的那一道。`flutter analyze` 则**始终**能在这里跑 —— 它经 stdio 而不是回环 WebSocket 连接分析服务器 —— 并且它覆盖 `test_flutter/`，所以即便在那时，每次改动它也仍会被类型检查。这是一个真实但局部的保证，从未被当作替代品。

`test/widget_test.dart` 是 `flutter create` 留下的计数器测试，已删除而非留其失败：它断言的是一个本次增量并未触及的应用外壳，而且在这里根本无法执行。

于是门禁为：

```powershell
.\scripts\verify-agent-notes.ps1
.\scripts\verify-translation-pairs.ps1
flutter analyze
dart format --set-exit-if-changed .
dart test
flutter test test_flutter
```

不带路径的 `flutter test` 也会把 `test/` 一并收走；widget 门禁写成显式路径，是因为用第二个 runner 再跑一遍纯 Dart 套件只增加开销、不增加覆盖 —— 也因为在这台 widget runner 已坏掉的机器上，更窄的那条命令，其结果才有意义。

除这两套件之外，本决定还覆盖「依赖平台的分支要怎么被真正触达」。`openPlatformSeams` 接受四个可选参数 —— `platform`、`environment`、`pathsChannel` 与 `beacon` —— 它们的存在，是为了让测试能在不身处 Android、不读真实 `%APPDATA%`、也不绑定那个「一台主机只允许一个进程持有」的知名 discovery 端口的前提下，问出 Android 与 Windows 的规则各自解析成什么，以及应用拿到答案后会怎么做。生产环境这四个都不传。

## Alternatives considered

**照样跑 `flutter test` 并接受失败。** 否决理由：一个永远为红的门禁，恰恰会掩盖它所报告的那些测试里的真实回归；而且这里的失败是每个文件的加载期错误，而不是某条具体的断言失败。

**把「卸载 aTrust 客户端」或「给 Flutter 二进制加白」当作前置条件。** 否决理由：把它作为阻塞依赖不可行 —— 那是托管机器上的企业安全客户端，本仓库无权移除；而一个需要开工单才能跑的门禁，不是贡献者能依赖的门禁。它最终确实被卸载了，`flutter test` 现在也能跑 —— 但本仓库无法假定下一台机器也如此，而这正是这次拆分要继续保留的全部原因。

**把所有测试都留在 `test/` 里。** 否决理由：第一个 widget 测试被加入的那一刻，它就会打断 `dart test` —— 也就是这里唯一总能跑的 runner —— 这恰好把最初那个决定的意义颠倒了过来。

**把 widget 测试放进 `test/`，并接受 `dart test` 在它们上面失败。** 否决理由：它与上一条是同一个错误，只是换了个标签。

**把核心层拆成独立的、无 Flutter 依赖的包，在那里测试。** 否决理由：相比现状并无收益。`lib/core/` 本来就没有 Flutter 依赖，而多拆一个包会为一条导入图已经强制成立的边界，额外引入一个 pubspec、一个版本号与一条依赖边。

**让核心层也通过 `flutter test` 测，用一个 runner 覆盖全部。** 否决理由：这会把一个刻意不依赖 Flutter 的层，耦合到那唯一跑不起来的工具链上。

**改为在 `ProfileStore` 与 `BeaconTransport` 这一层做替身，去触达 Android 与 Windows 分支，而不是在通道与端口这一层。** 否决理由（针对这两处）：那样测的是「给定一个已解析的路径，应用会怎么做」，而把解析本身 —— 恰恰是两个平台不同的那一部分 —— 留在未被覆盖的状态，而那才是最容易出错的部分。

## Consequences

- `dart test` 完整覆盖 `lib/core/` 与 `lib/app/`，包括真实 socket 行为。它在单一进程内运行、无需构建步骤，整套用例几秒钟跑完。它是永远跑得起来的那道门禁。
- widget 测试存在，并且可以被纳入门禁：`test_flutter/` 里有一个 UI 脚手架、各页面的测试，以及一个端到端测试 —— 它在同一进程内配对两台 Device，并在两棵 widget 树之间搬一个文件。
- **widget 套件在这台机器上又能执行了**，因为那个干扰性客户端已经不在了：`flutter test test_flutter` 25 条用例全过。而在它跑不了的那段时间里，`flutter analyze` 是 `test_flutter/` 唯一能得到的覆盖；对一次绿色 `analyze` 的诚实解读是「它能编译」，绝不是「它能工作」—— 这个区别后来被证明是有意义的：套件第一次真正跑起来，就抓到一个 `analyze` 不可能看见的 widget 树缺陷（`ControllerScope` 从未通知过它的依赖者）。
- 核心层与应用层的「无 Flutter 依赖」从顺带性质变成了承重性质：`lib/core/` 或 `lib/app/` 下任何一处 `package:flutter` 的导入都会打断门禁。这是刻意约束，不是疏漏。
- `lib/ui/` 现在带着四个仅为测试而存在的可选参数。它们在定义处被注明为测试接缝，而代价是真实的：这组接缝加宽了每个调用者都要读的签名。接受它，是因为 `openPlatformSeams` 的 Android 与 Windows 分支否则在一台机器上根本触达不了 —— 而触达不了的代码，正是这个文件里的 bug 曾经无人察觉的地方。
- 该门禁在形态上偏离了 AGENTS.md §5 —— 那份文件仍然写着裸的 `flutter test`。§5 是贡献者会读的约定；本笔记记录了这次拆分为何存在。
