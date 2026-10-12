<#
.SYNOPSIS
    把已经组装好的 Windows 绿色目录打成一个安装包（Inno Setup）。

.DESCRIPTION
    这一步**不重新构建**，也不重新组装目录：它复用
    `scripts/pack-windows-portable.ps1` 产出的那一份
    `build/dist/LocalTransfer-<版本>-windows-x64-portable/`，交给 Inno Setup 压成
    每用户安装的 .exe 安装包。

    这么分工是有意的。绿色包脚本已经负责「包里该有什么、以及它确实是当前代码」
    （文件齐全性、VC++ 运行库、app.so 里的文案、字体字形、解压后能否绑上端口）。
    安装包再走一遍那套验证，就会变成两处各有一份说法，迟早对不上。所以本脚本
    只做三件事：

      1. **验证它要复用的那份目录真的存在且完整**（缺了就报错，绝不自己去猜、也
         不替你去跑构建 —— 打包脚本不该在背后悄悄构建）；
      2. 检查 `packaging\local_transfer.iss` 的**编码**（见下），然后调用 ISCC；
      3. 验证产出的 .exe 确实落在预期路径上，并打印大小与 sha256。

    关于编码：`.iss` 里含中文，Inno Setup 6 要求这类文件是 UTF-8 **带 BOM**。
    没有 BOM 时它会按系统 ANSI 代码页解析，而本机是 936 —— 简体中文有相当一部分
    能被 936 吃下去，于是**不报错**，只是字符串悄悄变成乱码。这是最难查的一类问题，
    所以本脚本宁可拒绝执行，也不愿意产出一个名字是乱码的安装包。

.PARAMETER Stage
    要打包的目录。默认按 pubspec.yaml 的版本号推出来
    （build/dist/LocalTransfer-<版本>-windows-x64-portable）。

.PARAMETER SkipStageCheck
    跳过目录完整性检查。仅用于排查 —— 正常打包永远不要用它。

.EXAMPLE
    .\scripts\pack-windows-portable.ps1 -Smoke
    .\scripts\pack-windows-installer.ps1

.EXAMPLE
    # 只重打安装包（绿色目录已经就绪）
    .\scripts\pack-windows-installer.ps1
#>
[CmdletBinding()]
param(
    [string]$Stage,
    [switch]$SkipStageCheck
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
# ⚠️ 这里**不**把 [Console]::OutputEncoding 改成 UTF-8（与打包绿色包那个脚本相反）：
# ISCC 是原生程序，它按本机 ANSI（936）写输出，强行按 UTF-8 解码只会让日志变乱码。
# 绿色包脚本要改是因为 flutter 的输出是 UTF-8。两者需求相反，别互相抄。

$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo

function Step($m) { Write-Host "==> $m" }

# ------------------------------------------------------------------ 1. 版本号
# 版本号只有一个来源：pubspec.yaml。写死在脚本里就等于每次发版要记得改两处，
# 而改漏了不报错，只会产出一个名字骗人的包。
Step '读 pubspec.yaml 的版本号'
$pubspec = Join-Path $repo 'pubspec.yaml'
$match = Select-String -Path $pubspec -Pattern '^\s*version:\s*(\S+)' | Select-Object -First 1
if (-not $match) { throw "$pubspec 里没找到 version: 行" }
$version = $match.Matches[0].Groups[1].Value.Split('+')[0]
Write-Host "    $version"

$dist = Join-Path $repo 'build\dist'
if (-not $Stage) {
    $Stage = Join-Path $dist "LocalTransfer-$version-windows-x64-portable"
}

# ------------------------------------------------------------------ 2. 复用目录
Step "复用绿色目录 $Stage"
if (-not (Test-Path $Stage)) {
    throw @"
找不到 $Stage。

本脚本不重新构建，它打包的是绿色包脚本组装出来的那份目录。先跑：

    .\scripts\pack-windows-portable.ps1 -Smoke

（不想跑构建、只想重打安装包时，也可以确认上一轮的目录还在。）
"@
}

if (-not $SkipStageCheck) {
    # 抽查这几项就够说明「这是绿色包脚本组装过的那份目录」，而不是半成品：
    # 主程序、Flutter 运行时、AOT 产物、三个 VC++ 运行库、使用说明。
    # VC++ 运行库尤其重要 —— 安装包和绿色包共用它，缺了的话装出来的程序
    # 在干净机器上直接起不来，而那正是当初加这一步的原因。
    $must = @(
        'local_transfer.exe',
        'flutter_windows.dll',
        'data\app.so',
        'vcruntime140.dll',
        'vcruntime140_1.dll',
        'msvcp140.dll',
        '使用说明.txt'
    )
    $missing = @($must | Where-Object { -not (Test-Path (Join-Path $Stage $_)) })
    if ($missing.Count -gt 0) {
        throw "绿色目录不完整，缺少: $($missing -join ', ')`n      先跑 .\scripts\pack-windows-portable.ps1 -Smoke 重新组装。"
    }
    Write-Host "    完整性抽查通过（$($must.Count) 项）"
    # 目录名里的版本号必须和 pubspec 一致，否则打出来的安装包版本与内容不符。
    if ((Split-Path $Stage -Leaf) -notlike "*$version*") {
        Write-Warning "目录名与 pubspec 的版本号（$version）看不出关系：$(Split-Path $Stage -Leaf)"
    }
}

# ------------------------------------------------------------------ 3. 找 ISCC
Step '定位 Inno Setup 编译器 (ISCC.exe)'
$candidates = @()
$onPath = Get-Command ISCC.exe -ErrorAction SilentlyContinue
if ($onPath) { $candidates += $onPath.Source }
$candidates += @(
    # 用户级安装（Inno Setup 自身的安装程序支持 /CURRENTUSER）：装到
    # %LOCALAPPDATA%\Programs，**不需要管理员权限**，是免 UAC 的那条路。
    # CI 上是 choco 装的全机器一份（下面的 Program Files），本地则多半是这个，
    # 所以两条都要认 —— 否则本机永远走不到「真的跑一次 ISCC」，而这一步恰恰是
    # 六道门禁都不进、只能靠跑一次才能发现问题的那种。
    # 用字符串插值而不是 Join-Path：32 位系统上 ProgramFiles(x86) 不存在，
    # Join-Path 收到 $null 会直接抛错，而插值只会拼出一个 Test-Path 返回 false 的串。
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
    'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
    'C:\Program Files\Inno Setup 6\ISCC.exe',
    'D:\Program Files (x86)\Inno Setup 6\ISCC.exe',
    'D:\Program Files\Inno Setup 6\ISCC.exe'
)
$iscc = $candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $iscc) {
    throw @"
找不到 ISCC.exe（Inno Setup 的编译器）。

装一个即可 —— 两种都行：

    # 免管理员（装到 %LOCALAPPDATA%\Programs，推荐本地开发机用）
    # 从 https://jrsoftware.org/isdl.php 下载 innosetup-6.x.x.exe 后：
    .\innosetup-6.7.3.exe /VERYSILENT /CURRENTUSER /SUPPRESSMSGBOXES /NORESTART

    # 需要管理员
    choco install innosetup -y

本仓库需要 **Inno Setup 6.3 或更高**：packaging\local_transfer.iss 里用了
6.3 才有的 ArchitecturesAllowed=x64compatible。
"@
}
Write-Host "    $iscc"

# ------------------------------------------------------------------ 4. .iss 编码
Step '检查 .iss 的编码'
$iss = Join-Path $repo 'packaging\local_transfer.iss'
if (-not (Test-Path $iss)) { throw "找不到 $iss" }
$head = [System.IO.File]::ReadAllBytes($iss)[0..2]
if (-not ($head[0] -eq 0xEF -and $head[1] -eq 0xBB -and $head[2] -eq 0xBF)) {
    throw @"
$iss 不是 UTF-8 带 BOM（前三字节是 $($head | ForEach-Object { '{0:X2}' -f $_ } -join ' ')，应为 EF BB BF）。

文件里有中文，Inno Setup 6 在缺 BOM 时会按系统 ANSI（本机 936）解析 ——
它不会报错，只会把界面上的产品名和快捷方式名悄悄变成乱码。
补 BOM（或在编辑器里选「UTF-8 with BOM」另存）之后再跑。
"@
}
Write-Host '    UTF-8 with BOM，正确'

# ------------------------------------------------------------------ 5. 编译
Step 'ISCC'
New-Item -ItemType Directory -Path $dist -Force | Out-Null
$icon = Join-Path $repo 'windows\runner\resources\app_icon.ico'
if (-not (Test-Path $icon)) { throw "找不到图标 $icon（安装包与卸载项都用它）" }

$isccArgs = @(
    "/DLTStage=$Stage",
    "/DLTName=LocalTransfer",
    "/DLTVersion=$version",
    "/DLTOut=$dist",
    "/DLTIcon=$icon",
    "/DLTDocs=$(Join-Path $repo 'packaging')",
    $iss
)

# ISCC 的参数是 `/D名字=值`：「/D」才是「定义一个预处理变量」的开关，名字里没有它。
# 少写那个 D（如 `/LTDocs=…`）时 ISCC 把它当成一个不认识的开关：往 **stderr** 写一行
# `Unknown option: /LTDocs=…`，然后**立刻以 1 退出，`.iss` 一个字都不解析**
# （本机实测 0.021 秒、7 行输出、一行 `Parsing` 都没有，上一轮的 setup.exe 原封不动）。
# 崩得够响（下面的 $LASTEXITCODE 接得住），但**报的是「这个选项不认识」，不是
# 「你少定义了一个 LTDocs」**；而 stderr 与 stdout 是无序交织的，CI 抓下来的日志里
# 那行甚至排在同一次输出最前面的 banner 之上 —— 看着像编译器已经开工了。
# 2026-10-12 第一次真正发版就栽在这里，而且六个定义里**只有这一个**少写了 D。
# 根因是这类参数平时谁都不跑：本仓库六道门禁一步也不进 packaging\，本地也跑不起来，
# 所以「记得跑一次」不是能靠自觉保证的事 —— 让脚本自己比对：
# 把 .iss 里所有 `{#名字}` 抠出来，逐个要求 $isccArgs 里有对应的 `/D名字`。
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
if ($undefined.Count -gt 0) {
    throw @"
packaging\local_transfer.iss 用了这些占位符，却没有对应的 /D 定义: $($undefined -join ', ')

传给 ISCC 的是: $($isccArgs -join ' ')
（`/D名字=值` 才定义变量。漏了 D 的话 ISCC 只会往 stderr 写一行 Unknown option
就以 1 退出 —— 它不会告诉你少了哪个定义。）
"@
}
Write-Host "    .iss 的 $($used.Count) 个占位符都有 /D 定义：$($used -join ', ')"

& $iscc @isccArgs
if ($LASTEXITCODE -ne 0) { throw "ISCC 失败 (exit $LASTEXITCODE)" }

# ------------------------------------------------------------------ 6. 验证产物
Step '验证安装包'
$setup = Join-Path $dist "LocalTransfer-$version-windows-x64-setup.exe"
if (-not (Test-Path $setup)) { throw "ISCC 报成功，但 $setup 不存在" }
$info = New-Object System.IO.FileInfo $setup
if ($info.Length -lt 1MB) {
    # 内容是一整套 Flutter 运行时 + app.so，绝不可能只有几百 KB。
    # 这个下限用来抓「Source 没匹配到文件、只打出一个空壳」这类静默错误。
    throw "安装包只有 $($info.Length) B，太小了 —— Source 很可能没匹配到文件"
}
$sha = (Get-FileHash $setup -Algorithm SHA256).Hash
Write-Host ("    {0:N0} B ({1:N2} MB)" -f $info.Length, ($info.Length / 1MB))
Write-Host "    sha256 $sha"

# ------------------------------------------------------------------ 7. latest 别名
# 与绿色包同一个理由（见 pack-windows-portable.ps1 里那段），也放在最后一步：安装包
# 验完了才更新别名。两个产物各由**它自己的**脚本发布别名 —— 让绿色包脚本顺手去发安装
# 包的别名，就得先假设另一个产物在不在，那个假设迟早是错的。
Step '更新 latest 别名（局域网脚本按这个名字拉）'
$latestSetup = Join-Path $dist 'LocalTransfer-latest-windows-x64-setup.exe'
& (Join-Path $PSScriptRoot 'publish-latest.ps1') -Source $setup -Name (Split-Path $latestSetup -Leaf)

Write-Host ''
Write-Host "完成: $setup"
Write-Host "完成: $latestSetup  (固定名，跟这次打包一起更新)"
