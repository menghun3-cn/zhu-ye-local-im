# Agent Note: Upgrade to current Flutter stable before writing any code

Status: implemented

[English](2026-09-29-upgrade-flutter-before-coding.md) | 中文

## Problem

开发机安装的是 Flutter 3.29.2 / Dart 3.7.2，而当前稳定版为 3.47.5 / Dart 3.13.4——落后约八个月、六个次版本。本项目最依赖的几个包无法在 Dart 3.7.2 上取到当前版本：

| 包 | 最新版 | 要求 | Dart 3.7.2 上可用的最新版 |
| --- | --- | --- | --- |
| `nsd` | 5.0.1 | Dart `^3.11.0` | 5.0.0 |
| `bonsoir` | 7.1.5 | Dart `>=3.8.0` | 5.1.11（2025-02） |
| `flutter_secure_storage` | 11.2.0 | Dart `>=3.8.0` | 无 |

发现机制与安全密钥存储正是平台差异最密集的两个领域，因而也是依赖过时代价最大的地方。`bonsoir` 5.1.11 将放弃 19 个月的上游修复。

## Decision

在写下第一行产品代码**之前**把工具链升级到当前稳定版，并把升级当作前置步骤而非 v1 功能工作的一部分。在铺开项目骨架之前，先完成并验证它——一个简单应用能在 Windows 与 Android 上构建并运行。

## Alternatives considered

**留在 3.29.2 并锁定旧包。** 今天的迁移成本为零。否决理由：在项目起点就背上永久的依赖债，且恰好落在最可能需要上游修复的两个包上，同时放弃 Dart 3.8+ 的语言特性。

**等产品代码成型后再升级。** 否决理由：同样的迁移到那时会变成「工具链迁移 + 跨成熟代码库的依赖审计」，且有真实代码可能被破坏。

## Consequences

- 由于跨六个次版本，Android SDK、构建工具链与任何 IDE 配置都必须在升级后重新验证。
- 在升级完成前，任何依赖决策都无法最终确定，也不应针对旧 SDK 约束编写产品代码。
- `docs/dart-dependency-baseline.md` 中记录的依赖基线以升级后的工具链为前提；在 3.29.2 上它并不成立。
