# Agent Note: Flutter is confined to `lib/ui`

Status: implemented

[English](2026-09-30-flutter-confined-to-lib-ui.md) | 中文

## Problem

[应用层](2026-09-30-app-layer-plain-dart-orchestration.md) 是纯 Dart，
`test/app/plain_dart_test.dart` 会遍历 `lib/core` 与 `lib/app`，任何
`package:flutter` 导入都会让它失败。这条规则只覆盖了两层，而接下来要写的
widget 需要第三层。它们最顺手的落点是所调用的 controller 旁边：一个页面和它
驱动的对象放在同一个目录里，既不用写 import，也不用解释。

代价是整套验收策略所依赖的那个性质。在这台开发机上 `flutter test` 根本起不
来 —— 零信任客户端会剥掉 loopback WebSocket 升级所需的 hop-by-hop 头，
runner 永远到不了 `flutter_tester`（记录在
[dart test 门禁笔记](../testing/2026-09-29-dart-test-as-the-core-gate.md)）。
这里能跑的只有 `dart test`，而它只能跑在不含 Flutter 的代码上。如果 widget
可以放在任何地方，那么“这个文件能不能在这台机器上被测”就只能靠逐个读文件来
回答。

## Decision

**`lib/ui` 是 `lib` 下唯一可以导入 `package:flutter` 的地方。**
`lib/main.dart` 是唯一的例外：入口必须导入 `runApp` 与 Material，而一条带有
一处具名豁免的规则，比一条硬把入口塞进以框架命名的目录的规则更诚实。

这条规则是被执行的，而不是被声明的。`test/app/plain_dart_test.dart` 遍历
`lib` 下每一个 `.dart` 文件，跳过 `lib/ui/` 与 `lib/main.dart`，其余任何文件
导入 `package:flutter` 即失败；它还会在遍历到的文件少于二十个时失败，这样一
个被移动或写错根目录的遍历无法因为错误的理由通过。同一组里还有一个用例断言
`lib/ui` 存在且包含多于四个文件，这样跳过名单就不能通过删文件变成一条捷径。

**下层的方向是单向的。** widget 可以导入 `lib/app` 与 `lib/core`；
`lib/app` 与 `lib/core` 下没有任何文件导入 `lib/ui`。`lib/main.dart` 只做最少
的事：打开平台接缝、启动应用、任一环节抛错时显示失败页面。

## Alternatives considered

**把 widget 放进 `lib/app`，紧挨 controller。** 否决：这会让已有的“纯 Dart”
主张对半个目录失效，于是执行用的测试只能退化成逐文件白名单 —— 同一条规则，
却多了出错的地方，而且新文件会悄悄落到错误的一侧。

**为界面单独开一个 package**（`packages/ui`，或用工作区工具把它们连起来）。
否决：一个应用、两个平台、没有任何东西要发布。package 边界换来的是编译器强
制的规则，代价是第二个 `pubspec.yaml`、一个路径依赖，以及与之相伴的每一处编
辑器与 CI 配置；而一个遍历目录树的测试用二十行就能换来同一条规则。

**只作为 `AGENTS.md` 里的约定。** 否决：这个仓库自己的历史就是“没被检查的声明
会腐烂”。一个帧的 payload 之所以长期被别名覆盖，就是因为没有断言去检查字节；
一个签名错误的 `onError` 回调，只有在错误真的到来时才失败。所以约定既要写下
来，也要被检查，而检查就放在这个改动必须通过的同一套测试里。

**禁止 `lib/flutter/` 目录之外出现 Flutter，`main.dart` 也不例外。** 否决：一
条豁免对象是每个 Flutter 开发者都认得的入口文件的规则，比一条假装入口是普通
widget 目录的规则更容易记住。

## Consequences

- “这个文件需不需要 widget 树才能测”由其路径回答 —— 在一台跑不了 widget 测试
  的机器上，这是唯一可得的回答。`lib/core` 与 `lib/app` 仍完全由 `dart test`
  覆盖；`lib/ui` 由 `flutter analyze` 与一次真实构建覆盖。
- 这条规则对后续工作的约束和对本次改动一样多。一个想承载真实逻辑的 widget
  —— 剪贴板监听、路径解析 —— 必须写进可被测的层。本次需要的两个部件正是因此
  下沉到了 `lib/core`，并带回了属于它们自己的 13 个用例。
- 带 Flutter 类型的辅助函数（`IconData`、`Color`、`TextStyle`）永远不可能位于
  `lib/ui` 之下，因此 `labels.dart` 与 `widgets.dart` 天生就是表现层。没有任
  何东西阻止它们变得臃肿，也不应该：这条规则管的是这类类型可以出现在哪里，不
  是它们能有多少。
- `lib/ui` 对纯 Dart 测试不可见，因此它不该有的导入 —— `lib/ui` 伸手去摸
  `lib/core` 的内部、或一个页面导入另一个页面 —— 不会被它抓到。抓**坏**导入
  的是 `flutter analyze`，抓**错**导入的是评审：这条边界只在一个方向上被强制，
  而这正是便于检查的那个方向。
