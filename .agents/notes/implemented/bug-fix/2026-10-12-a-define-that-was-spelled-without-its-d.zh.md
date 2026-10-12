# Agent Note: A define that was spelled without its `/D`

Status: implemented

[English](2026-10-12-a-define-that-was-spelled-without-its-d.md) | 中文

## Problem

`v0.1.0` 的第三次流水线执行比前两次走得远 —— 校验版本号通过、Android APK 构建成功、绿色包组装压缩冒烟校验全过 —— 然后停在 `打安装包`：把那份已验证的目录变成 Inno Setup 安装包的那一步。ISCC 只打印了一行：

```
Unknown option: /LTDocs=D:\a\zhu-ye-local-im\zhu-ye-local-im\packaging
```

接着 [`scripts/pack-windows-installer.ps1`](../../../../scripts/pack-windows-installer.ps1) 抛出 `ISCC 失败 (exit 1)`。什么都没发出去。

ISCC 收预处理定义的形式是 `/D名字=值`：`/D` 才是「定义一个变量」那个开关，名字叫 `LTDocs`。这次传了六个定义，**其中五个写成 `/DLT…`**，第六个丢了自己的 `D` —— 一个字符，在一行从没被任何东西执行过的代码里。

**那一次 `.iss` 根本没被解析过，时间戳能作证。** 整场 ISCC（从 banner 到退出）只用了 0.34 秒（`==> ISCC` 在 `07:30:32.0258790`，抛错在 `07:30:32.3662966`），而 CI 的日志里**一行** `Preprocessing`、`Reading file:`、`Parsing`、`Compressing` 都没有。一次真读到脚本的编译在本机要 8.6 秒、打印几十行。也就是说这个作业压根没走到那个文件，而文件里的一切，就这样连续第三次没被行使。

**ISCC 不容忍这个错拼，只是报得不好。** 本机拿同一份参数列表配 ISCC 6.7.3 复现，结果与那次执行一模一样：0.021 秒后以 1 退出，一共 7 行输出，一行 `Parsing` 都没有，上一轮那个 setup.exe 在磁盘上原封不动。抱怨是往 **stderr** 写的 —— 所以 PowerShell 把它报成 `NativeCommandError`，也所以 CI 抓下来的日志把它排在 ISCC 最先打印的 banner **之上**：一个红掉的作业，读起来却像编译器已经开工了。这次失败够响，`$LASTEXITCODE` 也接得住，所以什么都没被静默掉。那条消息做不到的是说出**少的是哪个定义**：它报的是一个调用方不认为自己传过的选项。

有两件事让它成为可能，两件都关乎「错误本来可以在哪里被看见」：

- **本仓库里没有任何东西会跑这个安装包脚本。** `AGENTS.md` §5 的六道门禁一步也不进 `packaging/`，脚本没有本地调用方，发布作业是它唯一的入口。它的首次执行就是一次发布。
- **参数列表是照着那个文件抄的，而那个文件教的正是同一个错拼法。** `packaging/local_transfer.iss` 的头注释把六个定义全列成 `/LTStage`、`/LTName`……`/LTDocs` —— 一个都没带 `/D`。**一份描述接口的注释，就是会被当成接口来读。** 它从写下那天起就是错的，而且永远不会被察觉，因为没有东西消费它。

还有第三个原因让本地逃生口也不存在：脚本只在 `PATH` 和 `C:\Program Files*\Inno Setup 6\` 及其 `D:` 对应位置里找 ISCC。本机这几个都没有，也没有 `choco` —— 所以「我在本机跑一次就好了」这条路也走不通。一步构建就是这样一年都没被跑过。

## Decision

**参数改成 `/DLTDocs=`。** 错字修掉，教出这个错字的六行 `.iss` 头注释一起修掉；注释现在还说明了 `/D` 是干什么的，并写明它曾经写错过，免得下一个读者把旧拼法当范本。

**脚本不再相信这两份清单是一致的。** 交给 ISCC 之前，它把 `.iss` 里所有 `{#名字}` 抠出来，逐个要求参数列表里有对应的 `/D名字=`，缺了就报错并同时打印两份清单：

```powershell
$defined = @{}
foreach ($a in $isccArgs) {
    if ($a -match '^/D([A-Za-z_][A-Za-z0-9_]*)=') { $defined[$Matches[1]] = $true }
}
$issText = Get-Content -Path $iss -Raw -Encoding UTF8
$used = @(
    [regex]::Matches($issText, '\{#([A-Za-z_][A-Za-z0-9_]*)\}') |
        ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
)
$undefined = @($used | Where-Object { -not $defined.ContainsKey($_) })
```

**权威在 `.iss` 那边**：它才是「我需要哪些名字」的出处，守卫只负责核对调用方给没给。代价是读一次文件，而且它没法漂移 —— 往脚本里加一个占位符却忘了在命令行定义，会以完全相同的方式失败。就这一个缺陷而言，它**不改变**作业红不红（ISCC 本来就是 1），改变的全是**读的人为什么看得懂**：一条消息说出的是「哪个定义没有参数」，另一条说的是「你传了一个我从没听说过的选项」。

**ISCC 在它真正安装的位置被找到。** 候选列表现在以 `%LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe` 开头 —— 那是 Inno Setup 自己的安装程序走 `/CURRENTUSER` 时装到的地方，**不需要管理员权限** —— 「找不到」的提示也把这条安装命令和原有的 `choco install innosetup -y` 并列教出去。路径用字符串插值拼而不是 `Join-Path`，这样在 32 位宿主上没有 `ProgramFiles(x86)` 时，只是多一个 `Test-Path` 返回 false 的候选，而不是直接抛错。

**这一步现在在本机被跑过了。** 从官方 GitHub 发布按用户级装了 Inno Setup 6.7.3（sha256 与 API 的 asset digest 核对一致），[`scripts/pack-windows-installer.ps1`](../../../../scripts/pack-windows-installer.ps1) 产出了 `build/dist/LocalTransfer-0.1.0-windows-x64-setup.exe`：11,283,994 B、`Successful compile (8.594 sec)`，版本资源读到 `ProductVersion 0.1.0` / `ProductName 竹叶局域网传输` / `FileDescription 竹叶局域网传输 Setup`。最后这项才是重点：退出码只说明 ISCC 收下了这组参数，对「它随后把这些参数替换成了什么」一言不发。替换的结果要看版本资源，要看产物，不是看控制台。

## Alternatives considered

**只修错字，到此为止。** 否决：这个错字只是「一份参数列表和一份脚本必须互相对上，靠手工维护，而且从没被执行过」的一个实例。修掉实例、留下类，而这个类已经产出三次红的发布作业 —— zip 分隔符、Kotlin import、这一个 —— 每一次都发生在只有推 tag 才会跑的步骤里。

**给守卫配一份「期望名字」清单。** 否决：那是同一个事实的第三份副本，而会漂移的永远是没人跑的那一份。`.iss` 已经写明了它需要哪些名字，而且写在唯一一个「要装出安装包就必须写对」的地方。

**把头注释当成权威，从它生成参数列表。** 否决：注释是散文。`{#名字}` 才是预处理器自己解析的机器可读记号，所以守卫读的应该和编译器读的是同一个东西。去解析注释，等于把它要防的那个失效模式又请回来 —— 一份被信仰而不是被查阅的文档。

**不再传定义，把路径写死在 `.iss` 里。** 否决：这恰恰是定义存在的意义。stage 目录在本机是 `F:\asc_workspace\…`、在 runner 上是 `D:\a\zhu-ye-local-im\…`，一份 `.iss` 能同时伺候两边，靠的就是调用方把路径传进来。

**ISCC 的查找逻辑不动，本机改用 `choco` 装。** 否决：本机没有 `choco`，而「要行使一个构建步骤就得有管理员权限」正是这一步长期不被跑的原因。用户级安装就是那条免 UAC 的路，代价只是候选列表里多一行。

**把 ISCC 塞进仓库。** 否决：为了一个偶尔才跑一次的脚本，往 git 里放 10 MB 第三方二进制。版本该由装它的人负责，而 `.iss` 已经声明了它要求的下限。

**加一条在每次 PR 上跑那两个打包脚本的工作流。** 推迟，不是否决 —— 就是[兄弟那篇 note](2026-10-12-two-build-steps-that-had-only-ever-run-on-one-side.md) 记下的同一个待办。它才是真正能关掉这一类的改动，也比一个错字修复大。

## Consequences

- **安装包这条路由一台机器、一个编译器证明。** CI 的 ISCC 是 choco 装的 6.x（`C:\ProgramData\Chocolatey\bin\ISCC.exe`），本机是 `/CURRENTUSER` 装的 6.7.3。两者都是 6.x，而下载页当前的发布版已经是 7.1.0 —— 所以将来某次 `choco install` 可能在没人选择的情况下把编译器的大版本换掉。`.iss` 需要 6.3 或更高（`ArchitecturesAllowed=x64compatible`）。
- **`.iss` 的正文现在被编译过一次，由本机编译。** 它的 `[Files]` 段把每一条 `Source` 都匹配上了：`Compressing:` 行里列出了 stage 目录的内容、来自 `{#LTDocs}` 的 `packaging\安装说明.txt`，以及使用说明。前三次执行从没走到这么远，所以这是新信息，不是重跑。
- **门禁依旧不进 `packaging/`。** 变的是脚本现在不肯把对不上的参数列表交给 ISCC。至于 `.iss` 里写了一个不存在的文件，仍然只有跑一次才能发现 —— 报这件事的是编译，不是守卫。
- 抓取日志里的中文文件名显示为乱码，是因为 ISCC 按本机 ANSI 代码页写、而抓取按 UTF-8 收。这正是本脚本**刻意**不设 `[Console]::OutputEncoding` 的原因，与产出者写 UTF-8 的绿色包脚本相反。两个脚本不是不一致，它们面对的是相反的产出者。
- **`v0.1.0` 会被删掉、重推到新的 `master` tip 上。** tag 会移动，版本号不动。理由与之前相同：流水线是在自己的工具上失败、而不是在产品上，而 `releases` 仍然是空的，没有人用这个 tag 名下载过任何东西。
