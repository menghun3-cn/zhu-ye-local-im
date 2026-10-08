# 项目脚本

本目录存放开发流程与门禁脚本，全部面向 Windows/PowerShell 与 Flutter/Dart/git，不依赖 Node 或 pnpm。

## 校验脚本

| 脚本 | 用途 |
| --- | --- |
| `verify-agent-notes.ps1` | 校验 Agent Notes 目录结构、文件格式、归档三件套与 `manifest.json` 封存；`-ArchiveWrite` 追加封存新归档笔记 |
| `verify-translation-pairs.ps1` | 校验 `.md` / `.zh.md` 双语配对的 `.i18n.yaml` 一致性记录；确认一致后可用 `-Write` 重写记录 |
| `fetch-sources.ps1` | 按 `data/pins/*.json` 下载并校验数据源缓存，哈希不一致即失败 |
| `pack-windows-portable.ps1` | 把 Windows release 构建打成绿色免安装 zip，并验证产物确实含当前代码；`-Smoke` 追加启动冒烟 |

## 打 Windows 绿色包

每一次要给别人试的包都必须重新打：

```powershell
# 完整流程：构建 → 组包 → 压 zip → 验证 → （可选）冒烟
.\scripts\pack-windows-portable.ps1 -Smoke

# 只改了说明文件，不重新编译
.\scripts\pack-windows-portable.ps1 -SkipBuild
```

两个必须知道的事实：

- **`build/dist/*.zip` 不会自己更新。** `flutter test` 通过只说明源码对，zip 里装的是上一次构建的 `app.so`。本项目出过一次「测试全绿、包还是旧的」——用户报「为什么别人打开是灰色的」，根因就是对方装的包里没有那个修复。
- **`flutter build windows` 不会带上 VC++ 运行库。** `local_transfer.exe` 动态导入 `MSVCP140.dll` / `VCRUNTIME140.dll` / `VCRUNTIME140_1.dll`，开发机上 `System32` 里有所以测不出来，干净机器上会直接报「找不到 VCRUNTIME140.dll」。脚本从 VS 的 `VC\Redist\MSVC\<ver>\x64\Microsoft.VC143.CRT` 取来补齐。

说明文件的维护位置：**`build/dist/使用说明.txt`**（在仓库里被 `.gitignore` 忽略，因为它含构建日期与 commit 号）。脚本每次把它复制进包；没有才生成一份最小的兜底。

## 常用命令

```powershell
# 提交前门禁：Agent Notes 结构与格式
.\scripts\verify-agent-notes.ps1

# 提交前门禁：中英双语配对一致性
.\scripts\verify-translation-pairs.ps1

# 提交前门禁：Dart 静态分析与格式
flutter analyze
dart format --set-exit-if-changed .

# 提交前门禁：测试
flutter test

# 发布前检查（版本号一致性与 CHANGELOG 格式）
.\agents\skills\git-publish\scripts\pre-publish-check.ps1 `
  -VersionFile pubspec.yaml `
  -VersionPattern '^\s*version:\s*' `
  -ExpectedVersion <目标版本>
```

## 归档 Agent Note

```powershell
# 先把三件套移到 archived/{class}/ 并补 Archived: 行，再追加封存哈希
.\scripts\verify-agent-notes.ps1 -ArchiveWrite
```

## 数据源缓存

```powershell
# 首次运行回填 sha256/size/fetched_at 到 pin JSON（随后以哈希锁定版本）
.\scripts\fetch-sources.ps1 -WritePins

# 只输出预期动作，不下载不写文件
.\scripts\fetch-sources.ps1 -DryRun
```

完整规范见仓库根 [AGENTS.md](../AGENTS.md) 与 [.agents/notes/README.md](../.agents/notes/README.md)。
