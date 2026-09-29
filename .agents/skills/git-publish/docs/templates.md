# git-publish 模板变量文档

本文档说明 git-publish 技能中各配置项的使用方式与可复制示例。项目接入时，把需要覆盖的配置写入项目内已复制的 `SKILL.md` 配置表，或通过 `GIT_PUBLISH_*` 环境变量注入。

本仓库（Flutter/Dart 项目）的实际取值见下表；下文示例保留其他技术栈的写法，便于复用本技能到别的项目。

## 变量速查

| 变量 | 默认值 | 用途 |
| --- | --- | --- |
| `CHANGELOG_FILE` | `CHANGELOG.md` | CHANGELOG 路径 |
| `VERSION_FILE` | `pubspec.yaml` | 主版本来源 |
| `VERSION_PATTERN` | `^\s*version:\s*` | 版本行匹配正则 |
| `EXTRA_VERSION_FILES` | 空 | 需要同步版本号的额外文件 |
| `TAG_PREFIX` | `v` | 生产 tag 前缀 |
| `REMOTE` | `origin` | Git 远程名 |
| `INTEGRATION_BRANCH` | `develop` | 集成分支 |
| `TARGET_BRANCH` | `master` | 生产分支 |
| `RELEASE_BRANCH_PREFIX` | `release/` | release 分支前缀 |
| `TAG_MODE` | `local` | `local` 或 `ci` |
| `DRY_RUN` | `false` | 是否只读预演 |

## 本仓库：Flutter / Dart

`pubspec.yaml` 是唯一主版本源。版本行形如 `version: 1.2.3+45`，其中 `+45` 是 Android `versionCode` / iOS `CFBundleVersion` 的构建号，由 Flutter 在构建时注入，**不需要**单独同步到 `android/app/build.gradle`。

```yaml
VERSION_FILE: pubspec.yaml
VERSION_PATTERN: '^\s*version:\s*'
EXTRA_VERSION_FILES: （空）
```

发布前一致性校验（要求 `[Unreleased]` 为空且目标版本一致）由 `.agents/skills/git-publish/scripts/pre-publish-check.ps1` 在 Windows 上执行，它内置 CHANGELOG 格式校验：

```powershell
.\agents\skills\git-publish\scripts\pre-publish-check.ps1 `
  -VersionFile pubspec.yaml `
  -VersionPattern '^\s*version:\s*' `
  -ExpectedVersion 1.2.3
```

## 其他技术栈的 VERSION_FILE 示例

### TOML（`Cargo.toml` / `pyproject.toml`）

```yaml
VERSION_FILE: Cargo.toml
VERSION_PATTERN: 'version\s*=\s*"[^"]+"'
```

### JSON（`package.json`）

```yaml
VERSION_FILE: package.json
VERSION_PATTERN: '^\s*"version"\s*:\s*"[^"]+"'
```

### 纯文本（`VERSION`）

纯文本版本文件只需一行版本号：

```text
1.2.3
```

```yaml
VERSION_FILE: VERSION
VERSION_PATTERN: '^[0-9]+\.[0-9]+\.[0-9]+'
```

## 多文件版本同步示例

当主版本源之外还有文件显式声明版本时，把它们列为额外版本文件。以 Cargo workspace 为例，若某个 crate 显式声明了 `version`：

```yaml
VERSION_FILE: Cargo.toml
VERSION_PATTERN: 'version\s*=\s*"[^"]+"'
EXTRA_VERSION_FILES:
  - crates/your_crate/Cargo.toml
```

如果 crate 使用 `version.workspace = true`，则不要把它列为额外版本文件：workspace 根已经唯一。

```powershell
.\agents\skills\git-publish\scripts\pre-publish-check.ps1 `
  -VersionFile Cargo.toml `
  -VersionPattern 'version\s*=\s*"[^"]+"' `
  -ExtraVersionFiles 'crates/your_crate/Cargo.toml' `
  -ExpectedVersion 1.2.3
```

## TAG_MODE 配置示例

### local（本地打 tag）

```yaml
TAG_MODE: local
```

作用：PR 合入生产分支后，技能在本地执行 `git tag v1.2.3` 并推送。

### ci（CI 打 tag）

```yaml
TAG_MODE: ci
```

作用：PR 合入后由 CI 监听 `v*` tag 并自动打 tag；技能侧不打 tag。

> 两种模式都遵守同一条顺序硬约束：**先合入生产分支，再打生产 tag**。tag 永远指向生产分支合并后的提交，不指向 release 分支。

## Hook 模板使用示例

安装 pre-push hook：

```bash
cp .agents/skills/git-publish/scripts/pre-push.example.sh .git/hooks/pre-push
chmod +x .git/hooks/pre-push
```

bash 版发布前检查（含 CHANGELOG 格式校验）：

```bash
VERSION_FILE=pubspec.yaml \
VERSION_PATTERN='^\s*version:\s*' \
EXPECTED_VERSION=1.2.3 \
bash .agents/skills/git-publish/scripts/pre-publish-check.example.sh
```

PowerShell 版（Windows 原生，无需 bash）：

```powershell
.\agents\skills\git-publish\scripts\pre-publish-check.ps1 `
  -VersionFile pubspec.yaml `
  -VersionPattern '^\s*version:\s*' `
  -ExpectedVersion 1.2.3
```

> 跨平台约定：`pre-publish-check.example.sh` 用于 git-bash/Linux/CI，`pre-publish-check.ps1` 用于 Windows PowerShell；两者规则一致。

## 完整发布调用示例

```bash
/git-publish 1.2.3 --dry-run
# 确认计划后再执行
/git-publish 1.2.3
```
