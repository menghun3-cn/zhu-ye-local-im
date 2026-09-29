#requires -Version 5.1
<#
.SYNOPSIS
git-publish 发布前检查（PowerShell 版，Windows 原生）。

.DESCRIPTION
与 pre-publish-check.example.sh 逻辑等价：
- 检查工作树是否干净；
- 检查 CHANGELOG 是否存在并调用 changelog_check.py 校验格式；
- 检查 VERSION_FILE 与 EXTRA_VERSION_FILES 是否匹配 VERSION_PATTERN；
- 可选检查 EXPECTED_VERSION 是否存在于所有版本文件中。

.EXAMPLE
.\pre-publish-check.ps1 -VersionFile pubspec.yaml -ExpectedVersion 1.2.3

.EXAMPLE
$env:EXTRA_VERSION_FILES = "android/app/build.gradle"
.\pre-publish-check.ps1
#>
[CmdletBinding()]
param(
    [string]$VersionFile = $env:VERSION_FILE,
    [string]$VersionPattern = $env:VERSION_PATTERN,
    [string]$ChangelogFile = $env:CHANGELOG_FILE,
    [string]$ChangelogCheckScript = $env:CHANGELOG_CHECK_SCRIPT,
    [string[]]$ExtraVersionFiles = @($env:EXTRA_VERSION_FILES -split ','),
    [string]$ExpectedVersion = $env:EXPECTED_VERSION
)

$ErrorActionPreference = 'Stop'

function Fail([string]$Message) {
    Write-Host "✗ $Message" -ForegroundColor Red
    exit 1
}

if (-not $VersionFile) { $VersionFile = 'pubspec.yaml' }
if (-not $VersionPattern) { $VersionPattern = '^\s*version:\s*' }
if (-not $ChangelogFile) { $ChangelogFile = 'CHANGELOG.md' }
if (-not $ChangelogCheckScript) { $ChangelogCheckScript = Join-Path $PSScriptRoot 'changelog_check.py' }

$extraFiles = @($ExtraVersionFiles | ForEach-Object { $_.Trim() } | Where-Object { $_ })

# 1. 工作树必须干净
$dirty = git status --porcelain
if ($LASTEXITCODE -ne 0) { Fail 'git status 执行失败，请确认已安装 git 并在仓库根目录运行' }
if ($dirty) { Fail '工作树不干净，请先提交或暂存后再发布' }

# 2. CHANGELOG 必须存在
if (-not (Test-Path -LiteralPath $ChangelogFile -PathType Leaf)) {
    Fail "$ChangelogFile 不存在（如项目不使用 CHANGELOG 请调整配置）"
}

# 3. CHANGELOG 格式必须通过自动校验
$python = $null
foreach ($candidate in @('python', 'py')) {
    if (Get-Command $candidate -ErrorAction SilentlyContinue) {
        $python = $candidate
        break
    }
}
if (-not $python) { Fail '未找到 python/py，无法执行 CHANGELOG 格式校验' }

$checkArgs = @($ChangelogCheckScript, '--file', $ChangelogFile, '--require-unreleased-empty')
if ($ExpectedVersion) { $checkArgs += @('--version', $ExpectedVersion) }

if ($python -eq 'py') {
    & py -3 @checkArgs
} else {
    & $python @checkArgs
}
if ($LASTEXITCODE -ne 0) { Fail 'CHANGELOG 格式校验失败，请按脚本输出修正' }

# 4. 主版本文件必须匹配版本规则
if (-not (Test-Path -LiteralPath $VersionFile -PathType Leaf)) {
    Fail "$VersionFile 不存在"
}
if (-not (Select-String -LiteralPath $VersionFile -Pattern $VersionPattern -Quiet)) {
    Fail "$VersionFile 未匹配版本规则"
}

# 5. 可选：主版本文件必须包含期望版本
if ($ExpectedVersion) {
    $versionText = Get-Content -Raw -LiteralPath $VersionFile
    if ($versionText -notmatch [regex]::Escape($ExpectedVersion)) {
        Fail "$VersionFile 中未找到期望版本 $ExpectedVersion"
    }
}

# 6. 额外版本文件必须全部一致
foreach ($file in $extraFiles) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
        Fail "额外版本文件不存在: $file"
    }
    if (-not (Select-String -LiteralPath $file -Pattern $VersionPattern -Quiet)) {
        Fail "版本未同步: $file"
    }
    if ($ExpectedVersion) {
        $fileText = Get-Content -Raw -LiteralPath $file
        if ($fileText -notmatch [regex]::Escape($ExpectedVersion)) {
            Fail "$file 中未找到期望版本 $ExpectedVersion"
        }
    }
}

Write-Host '✓ 发布前检查通过'
exit 0
