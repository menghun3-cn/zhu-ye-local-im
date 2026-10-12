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
packaging/        随包发布的文件（两种装法各自的使用说明、Inno Setup 安装包定义）
site/             官网（纯静态 HTML/CSS/JS，由 .github/workflows/pages.yml 部署到 Pages）
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

### 6.2 Windows 安装包

同一份 `build/windows/x64/runner/Release` 有两种分发方式，两种都要重新构建后才算数：

| 分发方式 | 命令 | 产物 |
| --- | --- | --- |
| 绿色免安装 | `.\scripts\pack-windows-portable.ps1 -Smoke` | `LocalTransfer-<版本>-windows-x64-portable.zip` |
| 安装包 | 先跑上面那条，再 `.\scripts\pack-windows-installer.ps1` | `LocalTransfer-<版本>-windows-x64-setup.exe` |

安装包脚本**不重新构建**，它复用绿色包脚本组装并验证过的那份目录（含 VC++ 运行库
与使用说明）；目录不存在或不完整时它直接报错，不会去猜、也不会在背后替你构建。
它是每用户安装（`%LOCALAPPDATA%\Programs\LocalTransfer`，不需要管理员权限）。
本机没装 Inno Setup 时它会告诉你装法（`choco install innosetup`，需要 6.3 或更高）。

两个脚本的版本号都从 `pubspec.yaml` 读，不写死 —— 写死等于每次发版要记得改多处，
而改漏了不报错，只会产出一个文件名骗人的包。

另外每次打包都会在同一目录里留一份**固定名**的别名 ——
`LocalTransfer-latest-windows-x64-portable.zip` /
`LocalTransfer-latest-windows-x64-setup.exe`，旁边各带一个 `.sha256` 侧车（按
`sha256sum` 的格式写，拉取方一句 `sha256sum -c` 就能验）：局域网里的脚本要按固定名字
拉包，而带版本号的名字没法写死。别名**只在全部检查通过之后**才更新，所以它一出现就
意味着「有一个通过了全部检查的包」；中途任何一步失败时，它保持上一版的完好内容。
两份别名由同一个 `scripts/publish-latest.ps1` 发布（先写 `.new` 再原子改名，写完复算
一次哈希），两个打包脚本都不各写一份。

别名也**跟着 Release 一起发**（`release.yml` 里逐条列出，连 `.sha256` 侧车）：局域网
之外没有别的通道 —— 外网的机器只能按固定地址拉包，即
`releases/latest/download/LocalTransfer-latest-windows-x64-setup.exe`（绿色包同理）。
`releases/latest/download/<名字>` 要求附件名里不带版本号，而「最新」那个 Release 由 tag
决定。发出去之前那一步会再核一遍：`sha256sum -c` 验侧车、`cmp` 确认别名与本次的版本化
产物逐字节相同 —— 外网拿到的东西必须就是刚验完的那个包，不是上一版的遗留。

### 6.3 官网

`site/` 是官网，**纯静态**：一个 `index.html`、一份 `styles.css`、一份 `app.js`，
没有构建步骤、没有依赖、不加载任何第三方脚本或字体 —— 所以
`upload-pages-artifact` 原样上传该目录即可，工作流里没有任何编译动作。
设计语言与 `design-preview/styles.css` 同源（同一套令牌），改配色时两边要一起改。

`.github/workflows/pages.yml` 在 `site/**` 随 PR 合入 `master` 时部署；`develop` 上的
改动不会上线，要立刻看一眼就用 `workflow_dispatch` 手动跑。仓库的
Settings → Pages → Source 必须是 **GitHub Actions**（不是「从分支部署」），
否则这个工作流跑完也没人接管产物。

页面上的下载按钮默认指向 `releases/latest`，能读到 GitHub API 时替换成具体产物、
读不到就退回那个链接 —— 官网不会因为一次限流或离线而给出死链。附件里同时存在别名
（§6.2），后缀匹配会把它一并命中，所以 `app.js` 显式跳过 `-latest-` 的名字：按钮旁边
写着版本号，选到别名就成了「标签是 v0.1.1、文件名里却没有版本」。下载区还列出了那两个
固定地址（不依赖 API，永远指向最新一版），给要写脚本的人直接抄。

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

## 9. 版本号与发版节奏

版本号只有两个来源，必须一致：`pubspec.yaml` 的 `version:` 与
`lib/app/app_version.dart` 的 `appVersion`（`test/app/app_version_test.dart` 读 pubspec
来守着）。`version:` 里 `+` 之后的构建号不进 `appVersion` —— 同一份源码构建两次，
对使用者而言是同一个版本。

AI 辅助开发下迭代很快，发版节奏按「小步快跑」定：

- **第三位（补丁）**：日常的功能与 bug 修复**都只加这一位** —— `0.1.0` → `0.1.1` →
  `0.1.2`。绝大多数发布走这里。
- **第二位（次版本）**：只有**明确**决定「这是一次成规模的里程碑」时才动，
  不因为「这轮加的功能比较多」就动。
- **第一位**：`1.0.0` 之前不动。

发布按 §2.2 的流转执行（`release/vX.Y.Z` → PR 合入 `master` → 在 `master` tip 打 tag）。
tag 推上去之后 `.github/workflows/release.yml` 负责剩下的事：

1. **校验** tag `vX.Y.Z`、`pubspec.yaml`、`appVersion` 三者一致，任何一处对不上一律失败；
2. 产出三个产物：Windows 安装包（`*-setup.exe`）、Windows 绿色包（`*-portable.zip`）、
   Android APK（`*-android.apk`），**外加** Windows 那两个固定名别名与它们的 `.sha256`
   侧车（见 §6.2 —— 外网的机器只能按固定地址拉包，所以别名要跟着上 Release）。产物在
   `release.yml` 里逐条按名字列出，不写 `build/dist/*-portable.zip` 这类通配：同一个
   目录里还有 `使用说明.txt` 之类的东西，通配会把它们一起当成产物；
3. 用 `CHANGELOG.md` 里该版本的条目作为 Release 说明（没有条目时退回自动生成的说明），
   把上述产物附上去。建 Release 之前先核一遍：`sha256sum -c` 验侧车、`cmp` 确认别名与
   本版产物逐字节相同 —— 缺别名或对不上就**不发**（固定地址 404 比不发版更难查）。

因此**发版前必须先写好 CHANGELOG 条目**，且版本号三处（pubspec / appVersion / tag）
要在 release 分支上一次性对齐再合入 `master`。产物由 tag 决定，不由谁的本地机器决定 ——
本地打包脚本仍然是「自己先看一眼」的手段，不是发布通道。
