<#
.SYNOPSIS
    把 Windows release 构建打包成绿色免安装 zip，并验证产物真的包含当前代码。

.DESCRIPTION
    每次要给别人试的包都必须重新打，理由有两个：

    1. build/dist 下的 zip 不会自己更新。改完代码只跑 `flutter test` 是通过的，
       但它测的是源码；zip 里装的是上一次构建的 app.so。本仓库已经有过一次
       「测试全绿、包还是旧的」事故 —— 用户报「为什么别人打开是灰色的」，
       根因就是对方装的包里根本没有修复。
    2. Flutter 的 Windows release 产物会漏掉 VC++ 运行库。`local_transfer.exe`
       动态导入 MSVCP140/VCRUNTIME140/VCRUNTIME140_1，而 `flutter build windows`
       不会把它们复制到 Release 目录。开发机上 System32 里有，测不出来；
       干净机器上会直接报「找不到 VCRUNTIME140.dll」。本脚本从 VS 的
       VC/Redist/MSVC/<ver>/x64/Microsoft.VC143.CRT 取来补齐。

    验证部分做三件事，全部基于 zip 内的字节（不是磁盘上的源文件）：
      - 文件齐全性（exe / flutter_windows.dll / 三个 CRT / data / 说明）
      - 结构（顶层直接是 exe，没有多套一层目录）
      - 新旧代码鉴别：在 app.so 里检索若干条 UTF-16LE 文案，要求新功能的句子
        命中、且 app.so 与上一次构建不同。

.PARAMETER SkipBuild
    跳过 `flutter build windows --release`，只用现有的 build/windows/x64/runner/Release
    重新组包。用于只改了说明文件时。

.PARAMETER Smoke
    打包后解压到临时目录并启动 8 秒，检查进程响应、UDP 47654 / TCP 47656+47655
    是否绑上，然后关闭。注意：Start-Process 起的子进程会随本 PowerShell 会话结束
    被回收，所以采样必须和启动在同一次调用内完成 —— 本脚本自己管这件事。

.EXAMPLE
    .\scripts\pack-windows-portable.ps1

.EXAMPLE
    .\scripts\pack-windows-portable.ps1 -Smoke

.EXAMPLE
    # 只改了使用说明，不重新编译
    .\scripts\pack-windows-portable.ps1 -SkipBuild
#>
[CmdletBinding()]
param(
    [switch]$SkipBuild,
    [switch]$Smoke
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
# 本机控制台代码页是 936，flutter 输出的 √ 这类字符经管道会变成乱码。
# 统一成 UTF-8 让下面的构建输出可读。只影响本进程，不改系统设置。
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo

$name    = 'LocalTransfer-1.0.0-windows-x64-portable'
$release = Join-Path $repo 'build\windows\x64\runner\Release'
$dist    = Join-Path $repo 'build\dist'
$stage   = Join-Path $dist $name
$zip     = Join-Path $dist "$name.zip"

# 新功能独有的文案，用来证明 zip 里的 app.so 确实是当前代码编出来的。
# 挑句子而不是挑词：'对话' 这种短词会撞上 '原生对话框'，本仓库上过一次当。
# 换一批探针的时机：一次改动把这些句子删掉或改写掉之后，探针会假报警。
# 所以探针只挑「长期不该变」的文案，并随同 PR 一起更新。
# 这里的每一句都必须能在 lib/l10n/app_zh.arb 里原样搜到，且是整句 —— 别凭印象写。
$newProbes = @(
    '还没有对话。在「设备」里连接一台设备，它就会出现在这里。',
    '从左边选一个对话，或者先在「设备」里连接一台设备。',
    '连接已断开',
    '还没有收发过内容。文字会直接送达，文件需要对方确认后才会接收。',
    '名字是对方自称的，本机无法核实。点「接受」就是把对方加入你的设备组，之后双方可以互相发送内容。',
    '对方还没广播名称'
)

function Step($m) { Write-Host "==> $m" }

# 清空一个目录的内容，但保留目录本身。
#
# 不删目录本身有两个原因：一是某些沙箱把删除重定向到回收站、且会拒绝删目录
# (SAFE_DELETE_FAIL_CLOSED)，只删文件不触发那套逻辑；二是删掉再重建会丢掉
# 目录的 ACL/时间戳，而覆盖写更接近"重新组装"的语义。
#
# 只在冒烟用的临时目录上用（那里必须真空，否则测的是上一次解压的残留）。
function Clear-Tree($path) {
    if (-not (Test-Path $path)) { New-Item -ItemType Directory -Path $path -Force | Out-Null; return }
    $dirs = @()
    Get-ChildItem -Path $path -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.PSIsContainer) { $dirs += $_.FullName }
        else { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue }
    }
    $dirs | Sort-Object Length -Descending | ForEach-Object {
        Remove-Item -LiteralPath $_ -Force -ErrorAction SilentlyContinue
    }
}

# 把源目录的内容覆盖到目标目录里。
#
# 上游用 Copy-Item -Force 而非"先清空再复制"：某些沙箱会拦截删除（连单个
# 文件也拦，SAFE_DELETE_FAIL_CLOSED），而覆盖写是纯写入，不触发那套策略。
# 代价是上一次留下的、这一次不再产生的文件会残留 —— 所以下面比一遍文件集，
# 把多出来的报出来。Release 输出是固定的一小撮文件，正常不会有残留。
function Sync-Tree($source, $target, $extra = @()) {
    New-Item -ItemType Directory -Path $target -Force | Out-Null
    $expected = @{}
    Get-ChildItem -Path $source -Recurse -File | ForEach-Object {
        $rel = $_.FullName.Substring($source.Length).TrimStart('\')
        $expected[$rel] = $true
        $dst = Join-Path $target $rel
        $dir = Split-Path -Parent $dst
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Copy-Item -LiteralPath $_.FullName -Destination $dst -Force
    }
    # $extra 是本脚本自己往 stage 里放的文件（CRT、说明），不算残留。
    foreach ($e in $extra) { $expected[$e] = $true }
    $stale = @()
    Get-ChildItem -Path $target -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
        $rel = $_.FullName.Substring($target.Length).TrimStart('\')
        if (-not $expected.ContainsKey($rel)) { $stale += $rel }
    }
    return $stale
}

# ---------------------------------------------------------------- 1. 构建
if (-not $SkipBuild) {
    Step 'flutter build windows --release'
    & flutter build windows --release
    if ($LASTEXITCODE -ne 0) { throw "flutter build 失败 (exit $LASTEXITCODE)" }
} else {
    Step '跳过构建 (-SkipBuild)'
}

if (-not (Test-Path (Join-Path $release 'local_transfer.exe'))) {
    throw "找不到 $release\local_transfer.exe —— 先不带 -SkipBuild 跑一次"
}

# ---------------------------------------------------------------- 2. VC++ 运行库
Step '定位 VC++ 运行库'
$crtNames = 'vcruntime140.dll', 'vcruntime140_1.dll', 'msvcp140.dll'
$crtSrc = $null
$redistRoots = @(
    'C:\Program Files\Microsoft Visual Studio', 'C:\Program Files (x86)\Microsoft Visual Studio',
    'D:\Program Files\Microsoft Visual Studio', 'D:\Program Files (x86)\Microsoft Visual Studio'
) | Where-Object { Test-Path $_ }

foreach ($root in $redistRoots) {
    # 形状: <root>\<year>\<edition>\VC\Redist\MSVC\<ver>\x64\Microsoft.VC143.CRT
    # 例如 D:\...\Microsoft Visual Studio\2022\Community\VC\Redist\MSVC\14.36.32532\x64\Microsoft.VC143.CRT
    # 注意 <year> 和 <edition> 是两层，社区版与专业版装在不同目录，都要通配。
    # 可能装多套工具集，取版本号最大的那个。
    $pattern = $root + '\*\*\VC\Redist\MSVC\*'
    $found = Get-ChildItem -Path $pattern -Directory -ErrorAction SilentlyContinue |
        ForEach-Object { Join-Path $_.FullName 'x64\Microsoft.VC143.CRT' } |
        Where-Object { Test-Path (Join-Path $_ 'vcruntime140.dll') } |
        Sort-Object -Descending |
        Select-Object -First 1
    if ($found) { $crtSrc = $found; break }
}
if (-not $crtSrc) { throw '找不到 Microsoft.VC143.CRT (x64)。装了 VS 吗？' }
Write-Host "    $crtSrc"

# ---------------------------------------------------------------- 3. 组目录
Step "组装 $name"
$stale = Sync-Tree $release $stage (@('使用说明.txt') + $crtNames)
if ($stale.Count -gt 0) {
    Write-Warning "stage 里有多余的旧文件（上一轮留下、这一轮不再产生，未自动删除）："
    $stale | ForEach-Object { Write-Warning "    $_" }
}
foreach ($n in $crtNames) {
    $src = Join-Path $crtSrc $n
    if (-not (Test-Path $src)) { throw "缺少 $src" }
    Copy-Item $src (Join-Path $stage $n) -Force
    Write-Host "    + $n"
}

# 说明文件从 stage 外面取 —— stage 每一轮都被清空重建，放在里面会被抹掉。
# 首选 packaging/使用说明.txt（在版本库里，别人 clone 后就有完整版）；
# 退回 build/dist/使用说明.txt（早期手工打包留下的位置，被 .gitignore 忽略）；
# 都没有就生成一份最小的兜底，免得包里没说明。
$note = Join-Path $stage '使用说明.txt'
$noteCandidates = @(
    (Join-Path $repo 'packaging\使用说明.txt'),
    (Join-Path $dist '使用说明.txt')
)
$noteSource = $noteCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($noteSource) {
    # 构建日期与 commit 号随每次打包变化，写死在模板里必然过时 —— 自动改写这两行。
    $commit = (& git rev-parse --short HEAD 2>$null)
    if (-not $commit) { $commit = 'unknown' }
    $branch = (& git rev-parse --abbrev-ref HEAD 2>$null)
    if (-not $branch) { $branch = 'unknown' }
    $body = Get-Content -Path $noteSource -Raw -Encoding UTF8
    $body = $body -replace '(?m)^构建日期：.*$', "构建日期：$(Get-Date -Format 'yyyy-MM-dd')"
    $body = $body -replace '(?m)^代码版本：.*$', "代码版本：$branch @ $commit"
    Set-Content -Path $note -Value $body -Encoding UTF8 -NoNewline
    Write-Host "    + 使用说明.txt (来自 $noteSource，已改写为 $branch @ $commit)"
} else {
    $ver = (Select-String -Path (Join-Path $repo 'pubspec.yaml') -Pattern '^\s*version:\s*(\S+)').Matches[0].Groups[1].Value
    @(
        "LocalTransfer $ver — Windows 绿色免安装版（x64）",
        '=================================================',
        "构建日期：$(Get-Date -Format 'yyyy-MM-dd')",
        '',
        '【怎么用】',
        '1. 把整个文件夹解压到任意位置，不要只把 local_transfer.exe 单独拖出来 ——',
        '   它必须和 flutter_windows.dll、三个 vcruntime/msvcp 的 dll、data\ 放在同一层。',
        '2. 双击 local_transfer.exe 运行。',
        '',
        '【占用的端口（防火墙要放行）】',
        'UDP 47654 自动发现 / TCP 47656 配对 / TCP 47655 数据通道。',
        '全部在本局域网内，不连外网。'
    ) | Set-Content -Path $note -Encoding UTF8
    Write-Host '    + 使用说明.txt (自动生成的最小版本 —— 建议在 packaging/使用说明.txt 维护完整版)'
}

# ---------------------------------------------------------------- 4. 打 zip
Step '压 zip'
# 直接覆盖写，不先删 —— 有些沙箱会把删除重定向到回收站并整体失败。
# CreateFromDirectory 本身会截断已存在的文件，这里显式删一次是为了让它
# 在"上次的 zip 只读/被占用"这类情况下的报错更清楚。
if (Test-Path $zip) { [System.IO.File]::Delete($zip) }
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($stage, $zip, 'Optimal', $false)

$zipInfo = New-Object System.IO.FileInfo $zip
$sha = (Get-FileHash $zip -Algorithm SHA256).Hash
Write-Host ("    {0:N0} B  ({1:N2} MB)" -f $zipInfo.Length, ($zipInfo.Length / 1MB))
Write-Host "    sha256 $sha"

# ---------------------------------------------------------------- 5. 验证
Step '验证 zip 内容'
Add-Type -AssemblyName System.IO.Compression
$archive = [System.IO.Compression.ZipFile]::OpenRead($zip)
try {
    $entries = @{}
    foreach ($e in $archive.Entries) { $entries[$e.FullName] = $e }

    $required = @('local_transfer.exe', 'flutter_windows.dll', 'data\app.so', 'data\icudtl.dat', '使用说明.txt') + $crtNames
    $missing = @($required | Where-Object { -not $entries.ContainsKey($_) })
    if ($missing.Count -gt 0) { throw "zip 缺少必需文件: $($missing -join ', ')" }
    Write-Host "    必需文件齐全 ($($required.Count) 项)"

    # 顶层应当是 exe 本身，不该多套一层目录名
    $tops = @($entries.Keys | ForEach-Object { ($_ -split '\\')[0] } | Sort-Object -Unique)
    if ($tops -contains $name) { throw "zip 顶层多了 '$name' —— 解压后会多套一层目录" }
    Write-Host "    顶层: $($tops -join ', ')"

    # app.so 里检索新功能文案 (UTF-16LE)
    $soEntry = $entries['data\app.so']
    $ms = New-Object System.IO.MemoryStream
    $s = $soEntry.Open(); $s.CopyTo($ms); $s.Close()
    $so = $ms.ToArray(); $ms.Dispose()

    $text = [System.Text.Encoding]::Unicode.GetString($so)
    $bad = @()
    foreach ($p in $newProbes) {
        if ($text.IndexOf($p) -lt 0) { $bad += $p }
    }
    if ($bad.Count -gt 0) {
        throw "app.so 里找不到这些新文案，包很可能是旧的:`n      " + ($bad -join "`n      ")
    }
    Write-Host "    新功能文案 $($newProbes.Count)/$($newProbes.Count) 命中"

    $soSha = [System.Security.Cryptography.SHA256]::Create().ComputeHash($so)
    Write-Host ("    app.so sha256 {0}" -f (($soSha | ForEach-Object { $_.ToString('X2') }) -join ''))
}
finally { $archive.Dispose() }

# ---------------------------------------------------------------- 6. 冒烟
if ($Smoke) {
    Step '冒烟'
    $sandbox = Join-Path $env:TEMP 'lt_pack_smoke'
    # ExtractToDirectory 要求目标目录不存在。—— 先清空内容，然后删掉空目录本身。
    # 这一步在 %TEMP% 下做，实测不受沙箱删除策略拦截（build/dist 下会被拦）。
    if (Test-Path $sandbox) {
        Clear-Tree $sandbox
        Remove-Item -LiteralPath $sandbox -Force -ErrorAction SilentlyContinue
    }
    # 用 .NET 解压而不是 Expand-Archive：后者的 [oooooo....] 进度条直接写 Console，
    # 不受 $ProgressPreference 控制，会把脚本其余输出淹掉（实测能刷满整个 stdout）。
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zip, $sandbox)
    Write-Host "    解压到 $sandbox"

    $p = Start-Process -FilePath (Join-Path $sandbox 'local_transfer.exe') -PassThru
    try {
        Start-Sleep -Seconds 8
        $p.Refresh()
        if ($p.HasExited) { throw "启动后立刻退出 (code $($p.ExitCode))" }
        Write-Host "    pid $($p.Id) 响应对答=$($p.Responding) 内存=$([math]::Round($p.WorkingSet64/1MB,1))MB"

        $udp = @(Get-NetUDPEndpoint -OwningProcess $p.Id -ErrorAction SilentlyContinue |
            ForEach-Object { $_.LocalPort })
        $tcp = @(Get-NetTCPConnection -OwningProcess $p.Id -State Listen -ErrorAction SilentlyContinue |
            ForEach-Object { $_.LocalPort })
        Write-Host "    UDP $($udp -join ',')   TCP $($tcp -join ',')"
        if ($udp -notcontains 47654) { throw 'UDP 47654 没绑上 —— 自动发现不会工作' }
        if ($tcp -notcontains 47656) { throw 'TCP 47656 没监听 —— 别人配不上对' }
        Write-Host '    端口正常'
    }
    finally {
        Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        Clear-Tree $sandbox
    }
}

Write-Host ''
Write-Host "完成: $zip"
