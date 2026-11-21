# Agent Note: 一个 Pascal 保留字弄坏了安装包脚本

Status: implemented

[English](2026-11-21-a-pascal-keyword-broke-the-installer-script.md) | 中文

## Problem

v0.1.58 的发布流水线在 Inno Setup 编译步骤失败：
`local_transfer.iss:159: Identifier expected`。Android APK 任务成功，只有
Windows 打包任务挂了，「建 Release」被它挡在后面。

第 159 行是 `CurStepChanged` 的 `var` 块，里面声明了一个名为 `Program` 的
变量。`program` 是 Inno Setup Pascal 脚本语言的保留字——与 Object Pascal
同族，`program` 用来开启程序块——所以编译器在看到变量用途之前就拒绝了这
个标识符。这个 bug 是随防火墙例外功能一起进来的：那份安装包脚本在合入前从
没在任何机器上编译过，因为该功能的门禁只跑 `flutter analyze` 和 Dart 测
试，两者都不解析 `.iss` 文件。

## Decision

把变量改名为 `AppExe`。其余不动：netsh 命令行、UAC 提权、防火墙规则逐字
节不变。netsh 参数里的字符串字面量 `program="..."` 是给 `netsh.exe` 的数
据，不是 Pascal，从来就不是问题。

## Alternatives considered

**本机装 Inno Setup 把脚本编译当一道门禁。** 否决：仓库的打包门禁是
`pack-windows-installer.ps1`，在任何装了它的机器上本来就会端到端跑一遍
ISCC——这次失败恰恰是因为 CI 是第一台真正编译这个文件的机器。「脚本改动
没有门禁」的长期答案记在下面那条笔记里，不是在这里再加一条编译路径。

**改成别的标识符（`Exe`、`Target`、`Path`）。** 等价；选 `AppExe` 是因为
它说的是这个字符串是什么——安装后的可执行文件——而不是它被用来做什么。

## Consequences

- 发布流水线重新能编译安装包；v0.1.59 带上这个修复，因为 tag `v0.1.58`
  已经指向了坏提交，而 tag 永不移动。
- `.iss` 的改动在本地依然没有门禁：`flutter analyze`、`dart test`、
  `flutter test` 都看不见它，笔记格式门禁也看不见。唯一的编译发生在
  `pack-windows-installer.ps1` / CI 里。所以这个文件的语法错误只会在打包
  时才被发现——而它确实就是在那里被发现的，只是晚了一个版本。
