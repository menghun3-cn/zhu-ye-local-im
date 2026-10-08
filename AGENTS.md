# AGENTS.md

本文件是本仓库的权威约定：分支模型、提交规范、文档门禁与质量门禁。`git-publish` 等技能与 `.agents/notes/` 规范都以本文件为准。

## 1. 项目

`ai-local-im` 是一款 Flutter 桌面/移动应用：在局域网内发现设备、传输文本与文件，并在同一 Owner 的设备组内同步剪贴板。无服务端、无账号、无云端。

- 语言与框架：Dart / Flutter
- v1 平台范围：Windows、Android
- 产品术语表：[CONTEXT.md](CONTEXT.md)
- 架构与平台决策：[.agents/notes/](.agents/notes/)

## 2. 分支模型

长期存在三个分支：

| 分支 | 角色 |
| --- | --- |
| `master` | 生产分支。只接受来自 `release/*` 的 PR，永远保持可发布。 |
| `develop` | 集成分支。所有工作分支的合并目标。 |
| `release/*` | 临时发布分支，生命周期止于本次发布结束。 |

### 2.1 工作分支

所有 `feat` / `fix` / `chore` 分支**必须从 `develop` 切出**，并且**只能通过 PR 合回 `develop`**。

命名：`<type>/<简短描述>`，描述用小写连字符。

```
feat/lan-discovery
fix/clipboard-echo-loop
chore/upgrade-flutter
docs/adr-owner-identity
refactor/transfer-session
```

允许的 `type`：`feat`、`fix`、`chore`、`docs`、`refactor`、`test`、`perf`。

**禁止**：从 `master` 或 `release/*` 切工作分支；直接推送 `master`、`develop`、`release/*`。

### 2.2 完整流转

```
develop
  └─ feat/xxx ──PR──▶ develop
                        │
                        └─ release/v1.2.3 ──PR──▶ master ──▶ tag v1.2.3
                                                              │
                                         删除 release/v1.2.3 ◀─┘
                                                              │
                                       master（含 tag）同步回 develop
```

步骤：

1. 从 `develop` 切工作分支，完成后提 PR 合入 `develop`。
2. 发布时从 `develop` 最新 tip 切 `release/vX.Y.Z`。
3. 在 release 分支上升版本号、更新 CHANGELOG。
4. 提 PR：`release/vX.Y.Z` → `master`。
5. **PR 合入 `master` 之后**，在 `master` tip 打 tag `vX.Y.Z` 并推送。
6. 删除 `release/vX.Y.Z`。
7. 把 `master`（含 tag）同步回 `develop`。

### 2.3 顺序硬约束（红线）

> **先 PR 合入 `master`，再在 `master` tip 打并推送 `v*` tag。**
> **禁止**在 release 分支未合入前推送生产 tag。

tag 永远指向 `master` 上合并后的提交，**不指向 release 分支**。release 分支只是待发布的代码与版本号，不是发布产物。

其余红线：

- 禁止覆盖或删除已有生产 tag。
- 禁止把 `develop` 直接 push 或 merge 进 `master`（必须走 `release/*` + PR）。
- 禁止在流程中途失败后继续执行。
- 禁止保留已发完的 `release/*` 作为长期分支。

发布动作由 [.agents/skills/git-publish/SKILL.md](.agents/skills/git-publish/SKILL.md) 执行；其配置（`VERSION_FILE`、`VERSION_PATTERN`、`TARGET_BRANCH` 等）见该技能配置表与 [docs/templates.md](.agents/skills/git-publish/docs/templates.md)。

## 3. 提交信息

采用 Conventional Commits，`git-publish` 依赖前缀生成 CHANGELOG 分类：

| 前缀 | CHANGELOG 归类 |
| --- | --- |
| `feat:` / `feat(...)` | 新增 |
| `fix:` / `fix(...)` | 修复 |
| `refactor:` / `perf:` | 变更 |
| `docs:` | 变更 |
| `chore:` / `test:` / `ci:` | 忽略 |
| 含 `!:` 或正文含 `BREAKING CHANGE:` | 变更（加 `**Breaking:**`） |

CHANGELOG 正文用中文书写，按 [Keep a Changelog](https://keepachangelog.com/) 结构，分类仅限 新增/修复/变更/移除/安全。

## 4. Agent Notes（强制）

`.agents/notes/` 存放 RFC 式决策记录，规则见 [.agents/notes/README.md](.agents/notes/README.md)。

- **每个非平凡改动必须在同一个 PR 里新增或更新至少一条 Agent Note。**
- 路径编码生命周期与类目：`{proposed|implemented|rejected}/{feature|bug-fix|simplification|architecture|process|testing}/yyyy-mm-dd-topic.md`。
- 三件套：`<topic>.md`、`<topic>.zh.md`、`<topic>.i18n.yaml`。
- 每份笔记必须含 `## Problem` 开头与 `## Alternatives considered` 章节。
- 非平凡 = 改变行为、架构、跨文件契约、流程工具、测试策略，或任何磁盘/网络/配置格式。

架构级决策（如「不 fork LocalSend」「引入 Owner 身份层」）记在 `implemented/architecture/`；工程流程决策（如「先升级 Flutter 再写代码」「v1 平台范围」）记在 `implemented/process/`。

## 5. 门禁

提交前必须全部通过：

```powershell
# Agent Note 结构与格式
.\scripts\verify-agent-notes.ps1

# 中英双语配对一致性
.\scripts\verify-translation-pairs.ps1

# Dart 静态分析与格式
flutter analyze
dart format --set-exit-if-changed .

# 测试：纯 Dart 套件（test/）
dart test

# 测试：widget 套件（test_flutter/），需要一台能跑 flutter test 的机器
flutter test test_flutter
```

测试按「谁能跑它」分目录：`test/` 只放不需要 widget 树的测试，必须能被 `dart test` 跑起来；`test_flutter/` 放导入 `package:flutter_test` 的测试。把 widget 测试放进 `test/` 会打断 `dart test` —— 那是本机唯一总能跑的门禁。理由见 [.agents/notes/implemented/testing/2026-09-29-dart-test-as-the-core-gate.md](.agents/notes/implemented/testing/2026-09-29-dart-test-as-the-core-gate.md)。

`flutter analyze` 覆盖整个仓库，包括 `test_flutter/`：它在 widget 套件跑不起来时仍能保证它「能编译」，但这不等于「能工作」。

发布前额外执行：

```powershell
.\agents\skills\git-publish\scripts\pre-publish-check.ps1 `
  -VersionFile pubspec.yaml `
  -VersionPattern '^\s*version:\s*' `
  -ExpectedVersion <目标版本>
```

## 6. 目录约定

```
.agents/
  notes/          Agent Notes（决策记录）
  skills/         项目内技能（git-publish、文档规范等）
docs/             架构与平台事实文档
packaging/        随包发布的文件（使用说明模板），由 scripts/pack-windows-portable.ps1 消费
scripts/          门禁与工具脚本（PowerShell）
lib/              Flutter 源码
test/             纯 Dart 测试（由 dart test 跑）
test_flutter/     widget 测试（由 flutter test test_flutter 跑）
```

### 6.1 Windows 绿色包

`build/dist/` 下的 zip 是仓库之外的人真正运行的东西，**它不随源码自动更新**：
`flutter test` 量的是源码树，压缩包量的是上一次构建。改动 Dart 代码后要出包，
必须重新跑打包脚本——不要手工组装：

```powershell
.\scripts\pack-windows-portable.ps1 -Smoke
```

脚本会在写完之后**验证压缩包本身**（文件齐全、目录布局、包内 `app.so` 含本次新增
文案、解压后可启动并绑上端口）。见
[.agents/notes/implemented/process/2026-10-08-packaging-is-a-script-not-a-ritual.md](.agents/notes/implemented/process/2026-10-08-packaging-is-a-script-not-a-ritual.md)。

## 7. 平台事实约束

以下事实已核实并记录，改动相关代码前先读：

- [docs/platform-clipboard-constraints.md](docs/platform-clipboard-constraints.md) — 六平台剪贴板读写能力差异（读比写严格得多）
- [docs/android-background-constraints.md](docs/android-background-constraints.md) — `dataSync` 前台服务 6 小时预算、Android 17 本地网络权限
- [docs/dart-networking-capabilities.md](docs/dart-networking-capabilities.md) — Dart 双向 TLS、接口与子网枚举能力
- [docs/dart-dependency-baseline.md](docs/dart-dependency-baseline.md) — 依赖版本与维护状态
- [docs/network-baseline.md](docs/network-baseline.md) — 开发机网络实测（仅环境事实，不是需求来源）

## 8. 环境

- Flutter 需为当前稳定版（本项目起始于 3.47.x / Dart 3.13.x）；开发机原有 3.29.2 必须先升级，原因见 [.agents/notes/](.agents/notes/) 中的升级决策笔记。
- 目标平台：Windows、Android。
