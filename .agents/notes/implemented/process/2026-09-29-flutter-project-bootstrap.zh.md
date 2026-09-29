# Agent Note: Bootstrap the Flutter application shell

Status: implemented

[English](2026-09-29-flutter-project-bootstrap.md) | 中文

## Problem

仓库的文档已经齐备，代码却为零。[AGENTS.md](../../../../AGENTS.md) 第 5 节要求每个改动都通过 Agent Note 校验器、双语配对校验器、`flutter analyze` 与 `dart format --set-exit-if-changed .`，以及 `flutter test`；第 8 节把工具链钉在当前 Flutter 稳定版。但仓库里没有 `pubspec.yaml`、没有 `lib/`、没有 `test/`，也没有平台工程目录 —— 于是其中多数门禁无对象可跑，任何功能都无法落地。

两个 v1 平台在本仓库同样未被验证。Windows 桌面与 Android 的构建链路只在一次性的探测工程上跑过，从未跑在本仓库上。

## Decision

用当前稳定工具链把应用生成到仓库根：
`flutter create --org cn.hnasct --project-name local_transfer --platforms=windows,android .`，
随后对生成结果做六处调整。

**标识。** Dart 包名 `local_transfer`；Android 的 `namespace` 与 `applicationId` 为
`cn.hnasct.local_transfer`；Windows runner 为 `local_transfer`。

**平台范围。** 只存在 `windows/` 与 `android/`，与[ v1 范围笔记](2026-09-29-v1-scope-windows-and-android.md)
一致。不生成其他平台目录，因此不存在无人构建的构建链路。

**工具链钉版。** `pubspec.yaml` 声明 `environment.sdk: ^3.13.4`。`pubspec.lock` 纳入提交：
这是应用而非发布的库，解析出的依赖版本属于交付物的一部分。

**依赖。** 除 SDK 外零第三方包 —— 只有 `flutter`、`cupertino_icons`，以及
`analysis_options.yaml` 激活的 `flutter_lints` 开发依赖。Discovery、Transfer 与剪贴板行为均尚未实现。

**外壳而非演示。** 模板的计数器演示被移除。`lib/main.dart` 只含 `LocalTransferApp` 与
`HomePage`，渲染产品标题与空状态，别无其他；`test/widget_test.dart` 断言的正是这个外壳。
门禁通过的是真正交付的外壳，而不是一个永远不会交付的计数器。

**工作区卫生。** `.gitignore` 忽略 `.workbuddy/` —— 本地代理工作区，不得进入仓库。

## Alternatives considered

**把工程初始化塞进第一个功能改动里。** 否决：这会在同一次评审里混淆两类互不相关的失败 ——
工具链到底能不能构建，以及功能是否正确 —— 并且在那个功能写出来之前门禁一直不可用。

**保留模板计数器演示，直到第一个真实功能。** 否决：演示会成为 `flutter test` 的基线，
于是门禁变绿只意味着一个计数器能用，而不是产品能用。

**手写 `pubspec.yaml` 与平台工程，不用 `flutter create`。** 否决：`windows/runner` 与
`android/app` 是随工具链演进的版本化脚手架，手写副本会偏离已安装 Flutter 的预期，
且破损往往远晚于错误本身才暴露。

**Dart 包名沿用仓库名 `ai_local_im`。** 否决：[CONTEXT.md](../../../../CONTEXT.md)
把产品定名为 **Local Transfer**。包名会出现在每一处 import 与构建产物标识中，
因此它跟随产品，而不是仓库。

**现在生成全部平台，之后再删掉用不上的。** 否决：这会造出四条构建链路 —— iOS、macOS、
Linux、Web —— 没有门禁构建它们，也没有人维护它们，而"之后"没有归属者。

## Consequences

门禁套件变得可执行，这正是目的：`flutter analyze`、`dart format --set-exit-if-changed .`
与 `flutter test` 现在有了对象，Windows 与 Android 构建也可以跑在本仓库上而非探测工程上。

代价是大量工具生成的表面积 —— 49 个文件，其中多数是平台脚手架。一次 Flutter 升级会重写其中许多，
这些 diff 是机械噪声，但仍须评审。

`applicationId` 现为 `cn.hnasct.local_transfer`，且事实上永久：Android 应用 ID 在应用发布后不可更改。

`.metadata` 记录了生成该工程的 Flutter channel 与 revision，因此工具可以判断何时欠下一次迁移。

仓库中没有任何平台插件，因此 Windows 的 `.plugin_symlinks` 约束 —— 在开发机上创建符号链接需要开启
开发者模式，而它并未开启 —— 尚未被触发。第一个带 Windows 实现的插件才会撞上它。

项目在能力上仍是冷的：Discovery、Transfer 与 Clipboard Mirroring 都不存在，
每一个都还要在 `dart:io` 与平台插件之间做选择。

## Testing

`flutter test` 执行 `test/widget_test.dart`，断言外壳渲染出标题与空状态。平台链路通过在本仓库
（而非探测工程）上运行 `flutter build windows --debug` 与 `flutter build apk --debug` 验证。
