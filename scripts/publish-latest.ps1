<#
.SYNOPSIS
    把一个带版本号的产物发布成固定名（latest）别名，供局域网里的脚本按固定名字拉取。

.DESCRIPTION
    产物名里带着版本号，而版本号每次发版都变（AGENTS.md §9 的节奏是几乎每次只动
    第三位）。局域网里按固定地址拉包的脚本没法把这种名字写死；GitHub 的
    `releases/latest` 也帮不上 —— 它解析到的是「最新的那个 release」，可里面的附件
    文件名照样带着版本号，`releases/latest/download/<名字>` 还是得先知道版本号。

    所以每次打包额外留一份名字里没有版本号的别名，旁边配一个 `.sha256`。

    两个刻意的选择：

    1. **先写 `.new` 再改名，不直接覆盖写别名。** 同一卷内改名是原子的：正在拉的
       脚本读到的要么是上一版、要么是这一版，不会读到拷了一半的 zip。直接覆盖写会
       留下一段「文件已被截断、内容还没写完」的窗口，而它比「文件不存在」难查得多 ——
       拉取方拿到的是一个长度对得上、解压却报错的包。
    2. **写完之后重新算一遍哈希再比。** 别名存在的全部意义是「这就是那个刚验完的包」；
       复制没成功却留在那儿，比没有它更糟。

    调用方（两个打包脚本）都把它放在**最后一步**，所以「latest 存在」的含义是
    「有一个通过了全部检查的包」，而不是「刚打出来一个包」：中途任何一步失败，别名
    都保持上一版的完好内容（旧，但是好的）。

.PARAMETER Source
    刚打出来并验证过的那个带版本号的文件，例如
    build\dist\LocalTransfer-0.1.0-windows-x64-portable.zip。

.PARAMETER Name
    别名的文件名（不含目录），写在 Source 所在的那个目录里，例如
    LocalTransfer-latest-windows-x64-portable.zip。

.EXAMPLE
    .\scripts\publish-latest.ps1 `
      -Source build\dist\LocalTransfer-0.1.0-windows-x64-portable.zip `
      -Name   LocalTransfer-latest-windows-x64-portable.zip
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$Name
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Source)) { throw "找不到源文件 $Source（先把它打出来）" }
# 只接受文件名：带上目录的话别名会落到别处，而调用方以为它就在产物旁边。
if ($Name -ne (Split-Path $Name -Leaf)) { throw "-Name 只接受文件名，不要带目录：$Name" }

$src = (Resolve-Path -LiteralPath $Source).Path
$srcInfo = New-Object System.IO.FileInfo $src
if ($srcInfo.Length -le 0) { throw "源文件 $src 是空的 —— 别把空文件发成别名" }

$alias = Join-Path (Split-Path -Parent $src) $Name
$tmp = "$alias.new"
$sha = (Get-FileHash -LiteralPath $src -Algorithm SHA256).Hash

Copy-Item -LiteralPath $src -Destination $tmp -Force
if (Test-Path -LiteralPath $alias) { [System.IO.File]::Delete($alias) }
[System.IO.File]::Move($tmp, $alias)

$aliasSha = (Get-FileHash -LiteralPath $alias -Algorithm SHA256).Hash
if ($aliasSha -ne $sha) {
    throw "别名 $Name 的哈希与源文件不一致（$aliasSha vs $sha）—— 复制没成功。别让它留在那儿冒充最新包，删掉重来。"
}

# 侧车按 sha256sum 的格式写（`<哈希>  文件名`，两个空格），不自创一种：拉取方那边
# 一句 `sha256sum -c` 就能验，比我们自己发明一个格式有用得多。
# 两个细节都是为了不把拉取方绊倒：**不带 BOM**（BOM 会让第一个字段凭空多三个字节，
# `sha256sum -c` 直接报格式错），**只写 \n 不写 CRLF**（`\r` 会被当成文件名的一部分）。
[System.IO.File]::WriteAllText(
    "$alias.sha256",
    "$($sha.ToLower())  $Name`n",
    (New-Object System.Text.UTF8Encoding($false)))

Write-Host ("    别名 {0}（{1:N0} B）" -f $Name, $srcInfo.Length)
Write-Host "    sha256 $($sha.ToLower())"
