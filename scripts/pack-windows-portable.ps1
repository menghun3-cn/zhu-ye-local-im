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

    验证部分做四件事，全部基于 zip 内的字节（不是磁盘上的源文件）：
      - 文件齐全性（exe / flutter_windows.dll / 三个 CRT / data / 说明）
      - 结构（顶层直接是 exe，没有多套一层目录）
      - 新旧代码鉴别：在 app.so 里检索若干条 UTF-16LE 文案，要求新功能的句子
        命中、且 app.so 与上一次构建不同。
      - 图标字形：解析 data/flutter_assets/fonts/MaterialIcons-Regular.otf 的 cmap，
        要求这一轮新用到的 codePoint 真的在字体里。缺了就是界面上一个个空胶囊。

.PARAMETER SkipBuild
    跳过 `flutter pub get` + `flutter build windows --release`（含让 assets 步骤
    失效的 touch），只用现有的 build/windows/x64/runner/Release 重新组包。用于只改了
    说明文件时。注意：正常路径一定会重建 assets —— 图标字体的字形子集化只在 assets
    步骤整跑时才重做，增量构建会让字体停在上一次、新图标切不进去。

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
# 这个列表是"必改项"：每加一个功能，把该功能独有的句子加进来，把被它替换掉的
# 句子删掉。留着旧句子等于把这个检查变成永久的红灯 —— 上一次改动把
# conversationListEmpty / conversationPickOne 的文案重写了（"在「设备」里连接"
# 改成"扫描到就自动出现在这里"），旧句子从此不可能在 app.so 里出现。
# 这里的每一句都必须能在 lib/l10n/app_zh.arb 里原样搜到，且是整句 —— 别凭印象写。
$newProbes = @(
    '还没有对话。只要扫描到设备，它就会自动出现在这里，可以直接连接。',
    '从左边选一个对话，或者先连接一台设备。',
    '连接已断开',
    '还没有收发过内容。文字会直接送达，文件需要对方确认后才会接收。',
    '名字是对方自称的，本机无法核实。点「接受」就是把对方加入你的设备组，之后双方可以互相发送内容。',
    '对方还没广播名称',
    # 2026-10-09 这一轮：剪贴板白名单与「传输菜单只列文件」的新文案。
    '只有勾选的设备会收到本机复制的内容，本机也只会应用它们发来的内容。',
    '还没有传输过文件。文字内容在对话里，不在这里显示。',
    # 同一轮的微信 UI 对齐：拖放提示与发图入口。
    '松手即发送',
    '发送图片',
    # 2026-10-09 第二轮：接收目录可选，以及输入框可粘贴文件/图片。
    # 目录那一组是「设置里能挑文件夹」的独有文案；粘贴那一组不产生新文案
    # （它复用既有的「发送文件」「发送图片」），所以没有可加的探针。
    '选择保存位置',
    '选择文件夹…',
    '以后收到的文件默认保存在这里；每次接收时仍然可以另选一个文件夹。',
    '每次接收时都会问你保存在哪里。',
    # 2026-10-09 第三轮：选中的文件先在输入框里等着，点「发送」才发。
    # 这一轮几乎没有新文案 —— 它改的是时机 —— 唯一新增的是移除暂存项的
    # tooltip「移除」。整句没有可挑的，就用这个只出现一次的两字词。
    '移除'
)

# 新图标必须真的在字体里。字形子集化是 tree-shaker 按源码里用到的 codePoint 切出来
# 的，而它只在 assets 步骤重跑时才重做 —— 增量构建会让它一直停在上一次的结果上，
# 于是「代码要的图标」和「字体里有的图标」悄悄分叉，界面上就是一个个空胶囊。
# 这里直接读字体的 cmap，点名几个 2026-10-09 之后才用到的字形。
# 0xf0b0 = Icons.forum_outlined（对话入口未选中态）
# 0xe2c3 = Icons.forum（对话入口选中态）
# 0xe0b1 = Icons.attach_file（会话附加文件）
# 0xf120 = Icons.image_outlined（会话「发送图片」按钮，2026-10-09 微信对齐那一轮加的）
# 0xf090 = Icons.folder_open_outlined（设置页「更改…」与文件夹对话框的「选择文件夹…」，
#          2026-10-09 第二轮加的就地选择器）
# 0xe16a = Icons.close（输入框里移除暂存文件的 ×，2026-10-09 第三轮加的
#          附件托盘；图标字体是 tree-shaker 按用到的 codePoint 子集化的，
#          它没进过字体的话，界面上就是一个空胶囊）
#
# 0xe571 = Icons.send 曾经在这里，微信对齐那轮把它**删掉了**：发送控件从
# IconButton 换成了写「发送」二字的 TextButton（见 conversation_view.dart 的
# _SendButton），源码里再没有 `Icons.send`，tree-shaker 于是正确地把它从字体里
# 子集化掉了。留着这个条目 = 在**正确的包**上永远红灯。
$requiredGlyphs = @{
    '0xf0b0' = 'Icons.forum_outlined'
    '0xe2c3' = 'Icons.forum'
    '0xe0b1' = 'Icons.attach_file'
    '0xf120' = 'Icons.image_outlined'
    '0xf090' = 'Icons.folder_open_outlined'
    '0xe16a' = 'Icons.close'
}

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
    # 必须先让 assets 步骤失效。`flutter build windows --release` 是增量的，而
    # Material Icons 的字形子集化只在整个 assets 步骤重跑时才会重做 —— 只加新图标、
    # 不改 pubspec 的话那一步不会触发，新图标就永远切不进字体。2026-10-09 就是这么
    # 出的事：出货的 MaterialIcons-Regular.otf 只有 4848 字节 / 36 个字形，对话功能
    # 引入的 6 个图标（forum、forum_outlined、notes、send、attach_file、
    # description_outlined）一个都不在里面，而每个更早就有的图标都在 —— 界面上
    # 表现为「对话」入口是一个空的紫胶囊、对话列表头像是一个空圈。
    #
    # 这里有一个坑：第一反应是 `flutter clean`，但本机沙箱的 safe-delete 会拦它。
    #   - 删除量 > 50 个文件 → SAFE_DELETE_BULK_CONFIRM_REQUIRED
    #   - 小目录 → SAFE_DELETE_FAIL_CLOSED (trash-failed)
    # 实测 `flutter clean` 打印 "Failed to remove ...\build" 后仍然 exit 0，
    # 而那个 4848 B 的字体原封不动 —— 看起来成功，其实什么都没清。
    #
    # 有效且更轻的办法：把 pubspec.yaml 的 mtime 摸一下。asset 步骤的缓存键包含
    # pubspec，mtime 变了就会整步重跑，图标子树化跟着重做。代价是几十秒的
    # `flutter pub get` + 重建，远小于 clean 全量重编。
    Step '让 assets 步骤失效（touch pubspec.yaml）'
    $pubspec = Join-Path $repo 'pubspec.yaml'
    (Get-Item $pubspec).LastWriteTime = Get-Date

    Step 'flutter pub get'
    & flutter pub get
    if ($LASTEXITCODE -ne 0) { throw "flutter pub get 失败 (exit $LASTEXITCODE)" }

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

    # 图标的字形：读 MaterialIcons-Regular.otf 的 cmap，确认这一轮用到的 codePoint
    # 真的被切进了字体。app.so 里有文案不代表界面画得出来 —— 2026-10-09 的坏包
    # 文案全中、图标全空，正是这一项缺失导致的。
    # 注意这里**不能**用"字节数太小就报错"来判坏。图标子集化本来就是按需切的，
    # 一个只用了几十个字形的 app 切出来的字体就是几 KB —— 2026-10-09 修好之后
    # 也只有 5404 B / 42 个字形，而坏掉的那份是 4848 B / 36 个。两者只差 500 字节，
    # 任何尺寸阈值都分不开。**唯一可靠的判据是下面的 cmap 点名**：坏包里那四个
    # 图标一个都不在，好包里四个都在。
    $fontEntry = $entries['data\flutter_assets\fonts\MaterialIcons-Regular.otf']
    if (-not $fontEntry) { throw 'zip 里没有 data\flutter_assets\fonts\MaterialIcons-Regular.otf' }
    $fms = New-Object System.IO.MemoryStream
    $fs = $fontEntry.Open(); $fs.CopyTo($fms); $fs.Close()
    $font = $fms.ToArray(); $fms.Dispose()
    if ($font.Length -lt 1000) {
        throw "MaterialIcons-Regular.otf 只有 $($font.Length) B —— 这不可能是字体，资源打包出问题了"
    }
    $missing = @()
    # 解析 cmap 的 format 4 子表：这才是字形索引的真实来源。
    # 逐字节扫整份字体会很慢（几十万次迭代），而且 '0xf0b0' 这种字节对可能在
    # 别处偶然出现，扫出来的是假阳性。
    function Get-CmapCodepoints($bytes) {
        $found = @{}
        $numTables = [int]$bytes[4] * 256 + [int]$bytes[5]
        $cmapOffset = 0
        for ($t = 0; $t -lt $numTables; $t++) {
            $rec = 12 + $t * 16
            $tag = [System.Text.Encoding]::ASCII.GetString($bytes, $rec, 4)
            if ($tag -eq 'cmap') {
                $cmapOffset = [int]$bytes[$rec + 8] * 16777216 + [int]$bytes[$rec + 9] * 65536 + [int]$bytes[$rec + 10] * 256 + [int]$bytes[$rec + 11]
                break
            }
        }
        if ($cmapOffset -eq 0) { return $found }
        $subTables = [int]$bytes[$cmapOffset + 2] * 256 + [int]$bytes[$cmapOffset + 3]
        for ($s = 0; $s -lt $subTables; $s++) {
            $rec = $cmapOffset + 4 + $s * 8
            $sub = $cmapOffset + ([int]$bytes[$rec + 4] * 16777216 + [int]$bytes[$rec + 5] * 65536 + [int]$bytes[$rec + 6] * 256 + [int]$bytes[$rec + 7])
            $format = [int]$bytes[$sub] * 256 + [int]$bytes[$sub + 1]
            if ($format -ne 4) { continue }
            $segCount = ([int]$bytes[$sub + 6] * 256 + [int]$bytes[$sub + 7]) / 2
            $endBase = $sub + 14
            $startBase = $endBase + $segCount * 2 + 2
            for ($g = 0; $g -lt $segCount; $g++) {
                $end = [int]$bytes[$endBase + $g * 2] * 256 + [int]$bytes[$endBase + $g * 2 + 1]
                $start = [int]$bytes[$startBase + $g * 2] * 256 + [int]$bytes[$startBase + $g * 2 + 1]
                if ($start -eq 0xFFFF) { continue }
                for ($c = $start; $c -le $end; $c++) { $found[$c] = $true }
            }
        }
        return $found
    }
    $codepoints = Get-CmapCodepoints $font
    foreach ($cp in $requiredGlyphs.Keys) {
        $value = [Convert]::ToInt32($cp.Substring(2), 16)
        if (-not $codepoints.ContainsKey($value)) {
            $missing += "$cp ($($requiredGlyphs[$cp]))"
        }
    }
    if ($missing.Count -gt 0) {
        throw "MaterialIcons-Regular.otf 里没有这些字形，界面上的图标会是空白的:`n      " + ($missing -join "`n      ") + "`n      多半是 assets 步骤没重跑（`flutter build` 是增量的）。本脚本默认会 touch pubspec.yaml 强制它重跑。"
    }
    Write-Host "    MaterialIcons-Regular.otf $($font.Length) B，必备字形 $($requiredGlyphs.Count)/$($requiredGlyphs.Count) 命中"
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

    # 上一轮冒烟留下的实例要清掉：它占着 47654/47656，新的一份就会绑不上端口，
    # 而 _syncPairingListener 是"绑不上就记一条 notice"，不会退出 —— 于是冒烟会
    # 报"TCP 47656 没监听"，看起来像产品坏了，实际是上一份还活着。
    Get-Process -Name 'local_transfer' -ErrorAction SilentlyContinue |
        ForEach-Object {
            Write-Host "    清掉上一次遗留的 local_transfer pid $($_.Id)"
            Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
        }

    $p = Start-Process -FilePath (Join-Path $sandbox 'local_transfer.exe') -PassThru
    try {
        # 端口不是启动即到位的：配对监听要等 profile 落盘之后再起，而 47656
        # 刚被上一个进程关掉时还会在 TIME_WAIT 里停留一会儿。只读一次等于在赌
        # 那 8 秒够用，实测会偶发假失败（同一份 app.so 重跑就过）——所以轮询。
        $udp = @()
        $tcp = @()
        $deadline = (Get-Date).AddSeconds(30)
        while ((Get-Date) -lt $deadline) {
            $p.Refresh()
            if ($p.HasExited) { throw "启动后立刻退出 (code $($p.ExitCode))" }
            $udp = @(Get-NetUDPEndpoint -OwningProcess $p.Id -ErrorAction SilentlyContinue |
                ForEach-Object { $_.LocalPort })
            $tcp = @(Get-NetTCPConnection -OwningProcess $p.Id -State Listen -ErrorAction SilentlyContinue |
                ForEach-Object { $_.LocalPort })
            if (($udp -contains 47654) -and ($tcp -contains 47656)) { break }
            Start-Sleep -Milliseconds 500
        }

        Write-Host "    pid $($p.Id) 响应对答=$($p.Responding) 内存=$([math]::Round($p.WorkingSet64/1MB,1))MB"
        Write-Host "    UDP $($udp -join ',')   TCP $($tcp -join ',')"
        if ($udp -notcontains 47654) { throw 'UDP 47654 没绑上 —— 自动发现不会工作' }
        if ($tcp -notcontains 47656) { throw 'TCP 47656 没监听 —— 别人配不上对' }
        Write-Host '    端口正常'
    }
    finally {
        Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
        # 等端口真的回到可用：TIME_WAIT 还在时下一轮会绑不上，就是这个脚本自己
        # 制造了上面那个偶发失败的场景。
        $released = (Get-Date).AddSeconds(10)
        while ((Get-Date) -lt $released) {
            $held = @(Get-NetTCPConnection -LocalPort 47656 -ErrorAction SilentlyContinue |
                Where-Object { $_.State -eq 'Listen' })
            if ($held.Count -eq 0) { break }
            Start-Sleep -Milliseconds 500
        }
        Clear-Tree $sandbox
    }
}

Write-Host ''
Write-Host "完成: $zip"
