# Agent Note: v1 ships on Windows and Android only

Status: implemented

[English](2026-09-29-v1-scope-windows-and-android.md) | 中文

## Problem

本项目是跨平台 Flutter 应用，而本领域的参照工具覆盖六大平台，因此把 v1 限定为两个平台看起来像是遗漏。平台范围决定了剪贴板功能可达到的保证、权限与打包的工作量，以及测试矩阵的规模，因此不能含糊。

## Decision

v1 目标平台为 **Windows 与 Android**。macOS 与 Linux 是尽力而为的次要目标——它们与 Windows 共享几乎全部代码路径，因而构建成本低，但两者都不做保证。**iOS 不在范围内。**

- **Windows** 是唯一拥有干净、无提示、可完全后台运行的剪贴板路径的平台（`AddClipboardFormatListener` 加 message-only window）。它是剪贴板功能的参照平台，因而也是首要目标。
- **Android** 是用户真正遇到问题时所持的设备，也是文件传输的主要消费方。它虽无法发起剪贴板 Mirror，却能在后台应用收到的 Mirror。
- **macOS 与 Linux** 不可依赖：Wayland 只把剪贴板暴露给焦点客户端；macOS 的 release 构建除非在 `Runner-Release.entitlements` 中补上 `com.apple.security.network.server`，否则会静默无法接受入站连接，因为该权限默认只存在于 debug 与 profile 构建中。
- **iOS** 被排除，原因是自动剪贴板同步用公开 API 无法实现，且接收组播需要 `com.apple.developer.networking.multicast` 权限，而该权限必须向 Apple 申请并获批准。这两项代价对 v1 都换不来任何东西。

## Alternatives considered

**覆盖六大平台，与 LocalSend 一致。** 否决理由：六者之中有三个的剪贴板行为无法兑现产品承诺；iOS 还要为「招牌功能根本不可能实现」的平台额外承担 Apple 审批流程与签名分发负担。

**仅 Windows。** 能给出最强的单平台剪贴板叙事与最小的测试矩阵。否决理由：本产品的动机场景是在电脑与手机之间搬运内容，只有桌面端解决不了它。

**Windows、Android 与 iOS。** 否决理由：Apple 权限与审批成本，叠加 iOS 在自动剪贴板同步上的不可能性。

## Consequences

- 需要测试的平台是两个而非六个，使验证负担真实存在而非名义存在。
- 剪贴板保证按平台天然不同。UI 必须按 Device 声明能力，而不能暗示各端一致——这正是 `Clipboard Capability` 作为领域概念存在的原因。
- 日后增加 iOS 是增量工作，但其剪贴板行为永远不会与 Windows 一致。这种不对称是永久的，应当体现在产品语言中，而不是被隐藏。
