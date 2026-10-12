#requires -Version 5.1
<#
.SYNOPSIS
校验仓库内 .md / .zh.md 双语配对与 .i18n.yaml 一致性记录。

.DESCRIPTION
替代原 TypeScript/pnpm 配对门禁：
- 扫描 .agents/notes 下所有 .i18n.yaml（archived 由 verify-agent-notes.ps1 负责）
- 对比每侧 Git blob 哈希与 .i18n.yaml 中的记录
- 传 -Write 时仅在两侧确认一致后重写记录

.EXAMPLE
.\scripts\verify-translation-pairs.ps1

.EXAMPLE
.\scripts\verify-translation-pairs.ps1 -Write
#>
[CmdletBinding()]
param(
    [switch]$Write
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$notesRoot = Join-Path $repoRoot '.agents\notes'
$errors = [System.Collections.Generic.List[string]]::new()

function Add-Problem([string]$Message) {
    $script:errors.Add($Message)
}

function Get-GitBlobHash([string]$Path) {
    $out = & git hash-object -- $Path 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $out) {
        throw "git hash-object 执行失败: $Path"
    }
    return ([string]($out | Select-Object -First 1)).Trim()
}

function Parse-PairRecord([string]$Path) {
    $map = @{}
    $lines = [System.IO.File]::ReadAllLines($Path, [System.Text.UTF8Encoding]::new($false))
    foreach ($line in $lines) {
        if ($line -eq '' -or $line.StartsWith('#')) { continue }
        if ($line -notmatch '^([^:#]+\.md): ([0-9a-f]{40})$') { return $null }
        $map[$Matches[1]] = $Matches[2]
    }
    return $map
}

$metaFiles = Get-ChildItem -LiteralPath $notesRoot -Recurse -Filter '*.i18n.yaml' -File |
    Where-Object { $_.FullName -notmatch '\\archived\\' }

foreach ($metaFile in $metaFiles) {
    $rel = $metaFile.FullName.Substring($notesRoot.Length).TrimStart('\', '/').Replace('\', '/')
    $dir = Split-Path -Parent $metaFile.FullName
    $base = $metaFile.Name -replace '\.i18n\.yaml$', ''
    $sourcePath = Join-Path $dir "${base}.md"
    $zhPath = Join-Path $dir "${base}.zh.md"

    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        Add-Problem "${rel}: 缺少 ${base}.md"
        continue
    }
    if (-not (Test-Path -LiteralPath $zhPath -PathType Leaf)) {
        Add-Problem "${rel}: 缺少 ${base}.zh.md"
        continue
    }

    $record = Parse-PairRecord $metaFile.FullName
    if ($null -eq $record) {
        Add-Problem "${rel}: 一致性记录格式非法，每行必须为 '<file>.md: <40位sha1>'"
        continue
    }
    $sourceHash = Get-GitBlobHash $sourcePath
    $zhHash = Get-GitBlobHash $zhPath
    $valid = $record.Count -eq 2 `
        -and $record["${base}.md"] -eq $sourceHash `
        -and $record["${base}.zh.md"] -eq $zhHash
    if (-not $valid) {
        if ($Write) {
            $lines = [System.IO.File]::ReadAllLines($metaFile.FullName, [System.Text.UTF8Encoding]::new($false))
            $rendered = [System.Collections.Generic.List[string]]::new()
            foreach ($line in $lines) {
                if ($line -match '^([^:#]+\.md): ') {
                    $key = $Matches[1]
                    $target = if ($key -eq "${base}.md") { $sourceHash } else { $zhHash }
                    $rendered.Add("${key}: $target")
                } else {
                    $rendered.Add($line)
                }
            }
            [System.IO.File]::WriteAllText(
                $metaFile.FullName,
                ($rendered -join "`n") + "`n",
                [System.Text.UTF8Encoding]::new($false)
            )
            Write-Host "verify-translation-pairs: 已重写 $rel"
        } else {
            Add-Problem "${rel}: 配对不一至，需按项目规则确认后重写记录"
        }
    }
}

if ($errors.Count -gt 0) {
    Write-Host 'verify-translation-pairs: 检查发现违规：' -ForegroundColor Red
    foreach ($problem in $errors) { Write-Host "  $problem" -ForegroundColor Red }
    exit 1
}

Write-Host "verify-translation-pairs: $($metaFiles.Count) 个配对记录一致。"
exit 0
