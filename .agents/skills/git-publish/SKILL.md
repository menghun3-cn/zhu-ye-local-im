---
name: git-publish
description: >-
  执行通用的 Git 发布流程：从集成分支切 release 分支，升版本号，更新
  CHANGELOG，推送 release 分支并创建合入生产分支的 PR；合并后在生产分支
  打 tag，并把生产分支同步回集成分支。当用户要求发布、发版、升版本、
  切发布分支、执行 /publish 或 /git-publish 时使用。
metadata:
  trigger: 发布版本, 发版, 升版本, 切发布分支, release, /publish, /git-publish
disable-model-invocation: true
---

# Git Publish

自动化通用 Git 版本发布的完整流程。

**开始时宣告：** "正在使用 git-publish 技能发布版本 {VERSION}。"

## 适用范围

本技能适用于采用完整发布模式的项目：

```
{INTEGRATION_BRANCH} → release/{version} → {TARGET_BRANCH} → tag v{version}
```

只处理 Git 层面的发布动作，不包含制品上传、容器镜像发布等具体发布动作；
具体制品发布由目标项目的 CI/CD 或平台自行完成。

## 配置项

以下配置有默认值，可在项目内复制本技能后修改 `SKILL.md` 中的配置表，或通过环境变量 `GIT_PUBLISH_*` 覆盖。

| 配置项 | 默认值 | 说明 |
|--------|--------|------|
| `CHANGELOG_FILE` | `CHANGELOG.md` | 相对于仓库根目录的路径，文件不存在则跳过 |
| `VERSION_FILE` | `pubspec.yaml` | 主版本来源；Flutter 项目为 `pubspec.yaml` 的 `version:` 行 |
| `VERSION_PATTERN` | `^\s*version:\s*` | 匹配 pubspec 版本行 `version: x.y.z+build` 的正则 |
| `EXTRA_VERSION_FILES` | （空） | 需要同步版本号的额外文件。Flutter 构建从 `pubspec.yaml` 取版本，Android `versionName`/`versionCode` 由 Flutter 注入，因此本仓库留空 |
| `TAG_PREFIX` | `v` | 生产 tag 前缀 |
| `REMOTE` | `origin` | Git 远程仓库名 |
| `INTEGRATION_BRANCH` | `develop` | 本仓库已确定的集成分支；发布必须从最新 tip 切出 |
| `TARGET_BRANCH` | `master` | 本仓库已确定的生产分支；合并请求的目标分支 |
| `RELEASE_BRANCH_PREFIX` | `release/` | 本仓库已确定的 release 分支名前缀，分支为 `release/vX.Y.Z` |
| `TAG_MODE` | `local` | `local`：合并后由技能本地打 tag；`ci`：合并后由 CI 打 tag |
| `DRY_RUN` | `false` | 传 `--dry-run` 时置为 true，只读执行 |

> 本仓库约定：工作分支 `<type>/<描述>` → PR 合入 `develop`（集成）→ `release/vX.Y.Z` → PR 合入 `master`（生产）→ tag `vX.Y.Z`；发布后删除 `release/*` 并把 `master`（含 tag）同步回 `develop`。完整分支模型见根 `AGENTS.md`「分支模型」与「发布流程」。本技能只负责 `develop` 之后的发布段；发布前确认待发布改动均已经工作分支 PR 合入 `develop`。

## 调用方式

```
/git-publish 1.2.3
/git-publish 1.2.3 --dry-run
/publish 1.2.3          # 向后兼容别名
```

目标版本号是唯一必填参数，其余均从配置或自动检测获取。

## 发布流程

> **顺序硬约束：** 先 PR 合入 `{TARGET_BRANCH}`，再在 `{TARGET_BRANCH}` tip 打并推送 `v*` tag。
> **禁止**在 release 分支未合入前推送生产 tag。

### 步骤 0 — Dry-run（可选）

如果用户传入 `--dry-run`，或明确要求“预演 / 不要真的发布”：

1. 执行只读命令：`git rev-parse --show-toplevel`、`git status --short`、`git fetch`（fetch 可视为只读远程状态同步，如需严格离线，改为跳过 fetch 并提示）。
2. 展示完整计划：当前分支、集成分支 tip、目标版本、release 分支名、PR 目标、tag 模式、预计修改的文件。
3. 展示将执行的命令清单与预期副作用。
4. **结束后立即中止**：不修改文件、不创建分支、不提交、不推送、不打 tag、不创建 PR。

### 步骤 1 — 读取配置并确认版本

1. 获取仓库根目录：`git rev-parse --show-toplevel`
2. 记录当前分支为 `{original_branch}`。
3. `git fetch {REMOTE} {INTEGRATION_BRANCH} {TARGET_BRANCH}`
4. 从 `{TARGET_BRANCH}` 或 `{INTEGRATION_BRANCH}` 的最近一次 tag 读取上次版本；从 `{REMOTE}/{INTEGRATION_BRANCH}` tip 的 `VERSION_FILE` 读取当前版本。
5. 检查未提交的更改：
   ```bash
   git status --short
   ```
   若工作树不干净：**中止**并要求用户先提交或 stash。发布不得夹带无关脏文件。
6. 查找最近的 git tag：
   ```bash
   git tag --sort=-creatordate | head -1
   ```
   如果没有 tag，视为首次发布（步骤 3 使用仓库初始到 HEAD 的全部提交）。
7. 展示确认信息：

```
当前版本 (VERSION_FILE @ {INTEGRATION_BRANCH}): X.Y.Z
目标版本:                                     A.B.C
上次发布 tag:                                 vX.Y.Z (YYYY-MM-DD) 或 “无”
Release 分支:                                 release/A.B.C
集成起点:                                     {INTEGRATION_BRANCH}
合入目标:                                     {TARGET_BRANCH}
Tag 模式:                                     local / ci
Tag 时机:                                     {TARGET_BRANCH} 合并之后

确认发布 X.Y.Z → A.B.C？[y/N]
```

如果用户未输入 `y` 确认，立即中止。

### 步骤 2 — 从集成分支创建 release 分支

```bash
git checkout -B {RELEASE_BRANCH_PREFIX}{version} {REMOTE}/{INTEGRATION_BRANCH}
```

如果本地或远程已存在同名 release 分支，中止：

```
✗ 分支 {RELEASE_BRANCH_PREFIX}{version} 已存在。
请手动删除后再运行 /git-publish。
```

### 步骤 3 — 分析变更并生成 CHANGELOG 草稿

1. 获取上次 tag 以来的提交（相对 release HEAD，即集成分支 tip）：
   ```bash
   git log {last_tag}..HEAD --oneline
   # 首次发布时：
   git log --oneline
   ```

2. 如果没有找到提交：
   ```
   ⚠ 自上次发布 tag ({last_tag}) 以来没有新提交。
   是否继续？[y/N]
   ```
   用户未确认则中止。

3. 按提交前缀分类，生成 Keep a Changelog 格式的条目。

   **CHANGELOG 内容必须用中文书写。** 将每个提交总结为简洁的中文要点，不要逐字翻译提交信息，适当合并相关提交。

   分类规则：
   - 以 `feat:` 或 `feat(` 开头 → **新增**
   - 以 `fix:` 或 `fix(` 开头 → **修复**
   - 以 `refactor:` 或 `perf:` 开头 → **变更**
   - 包含 `!:` 或提交正文含 `BREAKING CHANGE:` → **变更**，加 `**Breaking:**` 前缀
   - 以 `docs:` 开头 → **变更**
   - 以 `chore:`、`test:`、`ci:` 开头 → 忽略（基础设施噪音）
   - 其他所有提交 → **变更**
   - 移除的功能 → **移除**
   - 安全修复 → **安全**

   输出格式：

   ```markdown
   ## [A.B.C] - YYYY-MM-DD

   ### 新增
   - 中文描述新增功能

   ### 修复
   - 中文描述修复内容

   ### 变更
   - 中文描述行为变更

   ### 移除
   - 中文描述移除内容

   ### 安全
   - 中文描述安全修复
   ```

   省略空的分类。日期使用 ISO 8601 格式（当天日期）。日期行与第一个分类之间、各分类之间保留空行。

4. 向用户展示草稿并请求确认：

   ```
   CHANGELOG 草稿：

   {draft}

   添加到 {CHANGELOG_FILE}？[y/N/edit]
   ```
   - `y` → 继续
   - `n` → 中止
   - `edit` 或其他反馈 → 询问用户："需要什么修改？"，等待回复后重新生成，再次展示确认。循环直到 `y` 或 `n`。

5. 如果 `CHANGELOG_FILE` 不存在，跳过此步骤（无需警告）。

> 结构约定与分类规则见 `docs/templates.md`；提交前必须通过 `.agents/skills/git-publish/scripts/changelog_check.py` 自动校验。

### 步骤 4 — 更新文件、提交并推送 release 分支

按顺序执行：

**4a. 更新 CHANGELOG：**

在 `CHANGELOG_FILE` 中找到 `## [Unreleased]` 标题，在其后插入新版本条目（保持 `[Unreleased]` 为空）：

```markdown
## [Unreleased]

## [A.B.C] - YYYY-MM-DD
### 新增
- ...
```

如果 `## [Unreleased]` 标题不存在：在 `# Changelog` 标题行之后补 `## [Unreleased]` 空段，再插入新版本条目；新建文件时先写 `# Changelog` 标题与 `## [Unreleased]`。

**4b. 升级版本号（同步所有版本来源）：**

发布版本号必须保持多文件一致。依次升级以下位置：

1. `VERSION_FILE` — 主版本源：
   ```bash
   grep -n '{VERSION_PATTERN}' {VERSION_FILE}
   # 用编辑工具将当前版本替换为 A.B.C
   ```
2. `EXTRA_VERSION_FILES`（如配置）：
   ```bash
   grep -n '{VERSION_PATTERN}' {EXTRA_VERSION_FILES}
   # 用编辑工具逐文件替换版本号
   ```

**4c. 多文件版本一致性校验：**

```bash
# 替换完成后，对主版本源与所有额外版本文件执行同一匹配
grep -nE '{VERSION_PATTERN}' {VERSION_FILE}
grep -nE '{VERSION_PATTERN}' {EXTRA_VERSION_FILES...}
```

所有文件都必须匹配同一个 `A.B.C`；任一文件未匹配、缺失或版本不一致：**中止**，补齐后再继续。可用模板 `.agents/skills/git-publish/scripts/pre-publish-check.example.sh`（bash）或 `.agents/skills/git-publish/scripts/pre-publish-check.ps1`（PowerShell）自动完成该校验。

**4d. CHANGELOG 格式校验：**

```bash
python3 .agents/skills/git-publish/scripts/changelog_check.py --file {CHANGELOG_FILE} --require-unreleased-empty --version {version}
```

校验不通过：**中止**，按脚本输出修正后重跑。要求 `[Unreleased]` 为空、首个版本条目标题为 `## [A.B.C] - YYYY-MM-DD`、分类仅限 新增/修复/变更/移除/安全 且每个分类至少一条列表项。

**4e. 提交：**

```bash
git status --short
```

- 如果有更改：暂存并提交：
  ```bash
  git add -A
  git commit -m "chore: release {version}"
  ```
- 如果工作树已干净：无需提交，跳过。

**4f. 推送 release 分支：**

```bash
git push -u {REMOTE} {RELEASE_BRANCH_PREFIX}{version}
```

推送失败则中止，不创建 PR、不打 tag。

### 步骤 5 — 创建合入生产分支的 Pull Request

优先使用 `gh` CLI：

```bash
gh pr create \
  --base {TARGET_BRANCH} \
  --head {RELEASE_BRANCH_PREFIX}{version} \
  --title "chore: release {version}" \
  --body "$(cat <<'EOF'
{步骤 3 生成的 CHANGELOG 条目}

## Release checklist
- [ ] CI green
- [ ] Merge this PR into {TARGET_BRANCH}
- [ ] After merge, tag v{version} on {TARGET_BRANCH} tip
EOF
)"
```

- 成功时展示 PR URL，并明确告知：合并前不要手动打 tag。
- 若 `gh` 失败：中止（此时尚未发版），提示手动创建 PR：
  `{RELEASE_BRANCH_PREFIX}{version}` → `{TARGET_BRANCH}`

如果项目不使用 GitHub CLI，按项目平台创建 PR，但必须在创建前展示目标分支、release 分支与版本号并等待用户确认。

### 步骤 6 — 合入后在生产分支打 tag

1. 询问用户 PR 是否已合并，或轮询：
   ```bash
   gh pr view {pr_url} --json state,mergedAt
   ```
   未合并则等待；不执行本地 tag。

2. 合并后，**先更新本地 `{TARGET_BRANCH}`**：
   ```bash
   git fetch {REMOTE} {TARGET_BRANCH}
   git checkout {TARGET_BRANCH}
   git pull --ff-only {REMOTE} {TARGET_BRANCH}
   ```

3. 校验生产分支版本与目标版本一致（再次执行 `grep` 版本行），不一致则中止并排查是否合入错误。

4. 根据 `TAG_MODE` 执行：

   - `local`：
     ```bash
     git tag {TAG_PREFIX}{version} {REMOTE}/{TARGET_BRANCH}
     git push {REMOTE} {TAG_PREFIX}{version}
     ```
   - `ci`：
     - **本地不打 tag**，提示用户确认 CI 已监听 `{TAG_PREFIX}*`。
     - CI 已自动打 tag 时跳过；未出现则提示检查 CI 配置，不手动补推。

5. tag 已存在时：停止并确认是否为重复发布，禁止覆盖已有 tag。

### 步骤 7 — 删除 release 分支

```bash
git push {REMOTE} --delete {RELEASE_BRANCH_PREFIX}{version}
git branch -D {RELEASE_BRANCH_PREFIX}{version}
```

删除失败则警告（非致命），提示手动删除。

### 步骤 8 — 同步集成分支

完整模式下，合入并打 tag 后需要把 `{TARGET_BRANCH}` 同步回 `{INTEGRATION_BRANCH}`：

1. 如果项目 CI 已有同步工作流：确认同步 PR / merge 成功，失败时手动处理。
2. 如果没有 CI 同步：
   ```bash
   git checkout {INTEGRATION_BRANCH}
   git pull --ff-only {REMOTE} {INTEGRATION_BRANCH}
   git merge {TARGET_BRANCH}
   ```
   或按项目规范开 `{TARGET_BRANCH} → {INTEGRATION_BRANCH}` PR。
3. 有冲突时不要强推，创建同步 PR 或提示用户人工解决。

### 步骤 9 — 切回原分支

```bash
git checkout {original_branch}
```

确保流程结束后用户不会停留在 release / 临时检出上。

## Githook（模板，不自动安装）

技能自带两个可复制的 bash hook 模板、Windows 原生 PowerShell 检查脚本和配套的 CHANGELOG 校验脚本，防止发布流程被绕过：

1. `scripts/pre-push.example.sh`：禁止直推受保护分支，强制走 release 分支 + PR。
2. `scripts/pre-publish-check.example.sh`：发布前检查工作树、版本一致性与 CHANGELOG 格式。
3. `scripts/pre-publish-check.ps1`：与 bash 模板等效的 PowerShell 版发布前检查。
4. `scripts/changelog_check.py`：CHANGELOG 格式自动校验，供流程与 hook 调用。

### 1. `scripts/pre-push.example.sh`

作用：
- 禁止直接推送 `main`、`master`、`develop` 等受保护分支；
- 强制发布必须走 release 分支 + PR。

安装示例（git-bash / Linux）：

```bash
cp .agents/skills/git-publish/scripts/pre-push.example.sh .git/hooks/pre-push
chmod +x .git/hooks/pre-push
```

### 2. `scripts/pre-publish-check.example.sh`

作用：
- 检查工作树是否干净；
- 检查 `CHANGELOG_FILE` 是否存在并调用 `.agents/skills/git-publish/scripts/changelog_check.py` 校验格式；
- 检查 `VERSION_FILE` 与 `EXTRA_VERSION_FILES` 是否都匹配 `VERSION_PATTERN`；
- 可选检查期望版本号 `EXPECTED_VERSION` 是否存在于所有版本文件中。

使用示例：

```bash
VERSION_FILE=pubspec.yaml \
VERSION_PATTERN='^\s*version:\s*' \
EXPECTED_VERSION=1.2.3 \
bash .agents/skills/git-publish/scripts/pre-publish-check.example.sh
```

### 3. `scripts/pre-publish-check.ps1`

作用：与 bash 模板一致，Windows 原生运行；自动从脚本所在目录定位 `changelog_check.py`，不要求先进入技能目录。

使用示例：

```powershell
.\agents\skills\git-publish\scripts\pre-publish-check.ps1 `
  -VersionFile pubspec.yaml `
  -VersionPattern '^\s*version:\s*' `
  -ExpectedVersion 1.2.3
```

> 注意：本模板要求工作树干净，适合发布前手动预检或 CI 阶段运行；不要直接装成 `pre-commit`（提交时工作树必然不干净）。


## 错误处理参考

| 场景 | 行为 |
|------|------|
| 配置缺失或 `VERSION_FILE` 未找到 | 中止，提示补全配置 |
| 文件中未匹配到版本号 | 中止，提示检查 `VERSION_PATTERN` |
| 工作树不干净 | 中止，先清理再发布 |
| 没有 git tag（首次发布） | 使用完整历史，提示“首次发布” |
| 上次 tag 以来无提交 | 警告并询问是否继续 |
| Release 分支已存在 | 中止并给出删除指令 |
| 步骤 4f 推送失败 | 中止：文件已在本地更新但未推送 |
| 多文件版本不一致 | 中止：必须全部同步 |
| CHANGELOG 格式校验失败 | 中止：按脚本输出修正格式后重跑 |
| 步骤 5 PR 创建失败 | 中止（尚未打 tag / 未发版） |
| 未合入时尝试打 tag | **禁止** — 硬红线 |
| tag 已存在 | 中止并给出核对指令 |
| local 模式下 tag 推送成功但制品 CI 失败 | 非致命：提示到 CI 重跑 |
| 步骤 7 删分支失败 | 警告并给出手动命令 |
| 同步集成分支有冲突 | 不合并、不强推，创建同步 PR 或人工解决 |

## 失败恢复指引

1. **dry-run 阶段失败**：没有副作用，修配置后直接重跑。
2. **步骤 4 更新文件后、推送前失败**：保留本地提交检查内容，修复后重新推送；不要重复插入 CHANGELOG 条目。
3. **步骤 4f 推送失败**：确认网络与远程分支是否存在；存在同名远程分支时不要 `force push`，先核对。
4. **PR 创建失败**：release 分支仍在，可手动开 PR 或修正后重试；此时未发版。
5. **local 模式合并后 tag 推送失败**：未发版，检查远程 tag 与网络，重试推送；已存在则核对是否重复。
6. **ci 模式 CI 失败**：release 已合入，tag 可能已打；先看 CI 日志，不要在本地盲目补发。
7. **集成分支同步冲突**：保留冲突现场，创建 `{TARGET_BRANCH} → {INTEGRATION_BRANCH}` 同步 PR，或人工解决后本地合并。
8. **恢复原则**：任何失败恢复前，先 `git status --short` 并记录当前分支；不覆盖远程 tag、不强推 `main`/`develop`。

## 红线规则

**绝不：**

- 在 release / feature 分支上、于合入 `{TARGET_BRANCH}` **之前**推送生产 `v*` tag
- 覆盖或删除已有生产 tag
- 将 `{INTEGRATION_BRANCH}` 直接 push / merge 进 `{TARGET_BRANCH}`（必须走 PR）
- 跳过步骤 1 的用户确认
- 跳过步骤 3 的 CHANGELOG 确认
- 跳过步骤 4d 的 CHANGELOG 格式校验
- 在任何步骤失败后继续执行（清理/同步警告除外）
- 流程结束后让用户留在 release 分支
- 保留已发完的 `release/*` 作为长期分支
- 在 non-protected 分支被强制推送时静默通过

**始终：**

- 从最新 `{REMOTE}/{INTEGRATION_BRANCH}` 切 release
- 先合入 `{TARGET_BRANCH}`，再打 tag
- 发版后删除 `release/*`；`{TARGET_BRANCH} → {INTEGRATION_BRANCH}` 自动或手动同步
- 发出任何命令前先说明动作与副作用
- 中止前展示完整错误输出
- 插入新版本条目后保持 `[Unreleased]` 为空
- 用户要求 dry-run 时，不做任何写操作

## 已实现的能力

- `.agents/skills/git-publish/scripts/changelog_check.py`：自动校验 `[Unreleased]` 结构、版本标题、日期、分类与列表项。
- `.agents/skills/git-publish/scripts/pre-publish-check.ps1`：Windows 原生发布前检查，与 bash 模板保持同一规则。
- `docs/templates.md`：提供配置变量速查、`VERSION_FILE` 常见格式示例、多文件同步与调用示例。
