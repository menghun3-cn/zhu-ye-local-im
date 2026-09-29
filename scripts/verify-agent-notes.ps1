#requires -Version 5.1
<#
.SYNOPSIS
验证 Agent Notes 树、文件格式、双语三件套与归档封存。

.DESCRIPTION
替代原 TypeScript/pnpm 门禁：
- 检查生命周期/分类目录与文件名规则
- 检查标题块、生命周期章节、Alternatives considered 与废弃标记
- 校验 archived/ 下的冻结三件套、manifest.json 与 Git blob 哈希
- 传 -ArchiveWrite 时按追加模式封存新归档笔记，禁止覆盖已封存哈希

.EXAMPLE
.\scripts\verify-agent-notes.ps1

.EXAMPLE
.\scripts\verify-agent-notes.ps1 -ArchiveWrite
#>
[CmdletBinding()]
param(
    [switch]$ArchiveWrite
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$notesRoot = Join-Path $repoRoot '.agents\notes'
$errors = [System.Collections.Generic.List[string]]::new()
$allNotes = [System.Collections.Generic.List[object]]::new()

$lifecycles = @('proposed', 'implemented', 'rejected')
$classes = @('feature', 'bug-fix', 'simplification', 'architecture', 'process', 'testing')
$formatAdopted = '2026-07-05'
$grandfather = '<!-- agent-note-format: alternatives-not-recorded (pre-format Agent Note) -->'
$legacyMarkers = @(
    'XXX: legacy ADR/RFC body format',
    'XXX: legacy ADR/Agent Note body format'
)

function Add-Problem([string]$Message) {
    $script:errors.Add($Message)
}

function Read-Utf8Lines([string]$Path) {
    return [System.IO.File]::ReadAllLines($Path, [System.Text.UTF8Encoding]::new($false))
}

function Test-IsoDate([string]$Value) {
    if ($Value -notmatch '^\d{4}-\d{2}-\d{2}$') { return $false }
    $parsed = [datetime]::MinValue
    return [datetime]::TryParseExact(
        $Value,
        'yyyy-MM-dd',
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::None,
        [ref]$parsed
    )
}

function Get-GitBlobHash([string]$Path) {
    $out = & git hash-object -- $Path 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $out) {
        throw "git hash-object 执行失败: $Path"
    }
    return ([string]($out | Select-Object -First 1)).Trim()
}

function Assert-NoLegacyRoots {
    foreach ($legacy in @('docs/rfc', 'docs/rfcs')) {
        if (Test-Path -LiteralPath (Join-Path $repoRoot $legacy)) {
            Add-Problem "legacy-path: $legacy/ 禁止存在，Agent Notes 必须位于 .agents/notes/ 下"
        }
    }
}

function Test-ArchivedHeader([string]$Rel, [string]$Path, [string]$SourceBase, [bool]$Chinese) {
    $lines = Read-Utf8Lines $Path
    if (($lines.Count -lt 6) -or ($lines[0] -notmatch '^# Agent Note: \S')) {
        Add-Problem "${Rel}: 第 1 行必须为 '# Agent Note: <标题>'"
        return
    }
    if ($lines[1] -ne '') { Add-Problem "${Rel}: 第 2 行必须为空" }
    if ($lines[2] -ne 'Status: implemented') { Add-Problem "${Rel}: 第 3 行必须为 'Status: implemented'" }
    if ($lines[3] -notmatch '^Archived: (\d{4}-\d{2}-\d{2})$') {
        Add-Problem "${Rel}: 第 4 行必须为 'Archived: YYYY-MM-DD'"
    } elseif (-not (Test-IsoDate $Matches[1])) {
        Add-Problem "${Rel}: 归档日期必须是有效日期"
    }
    if ($lines[4] -ne '') { Add-Problem "${Rel}: 第 5 行必须为空" }
    $expected = if ($Chinese) { '[English](' + $SourceBase + '.md) | 中文' } else { 'English | [中文](' + $SourceBase + '.zh.md)' }
    if (($lines.Count -lt 6) -or ($lines[5] -ne $expected)) {
        Add-Problem "${Rel}: 第 6 行语言切换行必须为 $expected"
    }
}

# ---- 1. 树结构与分类 ----
Assert-NoLegacyRoots

if (Test-Path -LiteralPath (Join-Path $notesRoot 'INDEX.md')) {
    Add-Problem '结构: INDEX.md — 禁止集中式 Agent Note 索引'
}

$topLevels = Get-ChildItem -LiteralPath $notesRoot -Directory -Force
foreach ($dir in $topLevels) {
    if ($dir.Name -eq 'archived') { continue }
    if ($dir.Name -notin $lifecycles) {
        Add-Problem "结构: $($dir.Name)/ — 未知生命周期目录（允许: $($lifecycles -join ', ') 与 archived/）"
    }
}

foreach ($lifecycle in $lifecycles) {
    $lifeDir = Join-Path $notesRoot $lifecycle
    if (-not (Test-Path -LiteralPath $lifeDir -PathType Container)) { continue }
    $mdFiles = Get-ChildItem -LiteralPath $lifeDir -Recurse -Filter '*.md' -File
    foreach ($file in $mdFiles) {
        $rel = $file.FullName.Substring($notesRoot.Length).TrimStart('\', '/').Replace('\', '/')
        if ($rel.EndsWith('.zh.md')) { continue }
        $segs = $rel.Split('/')
        if ($segs.Count -eq 2 -and $segs[1] -in @('AGENTS.md', 'CLAUDE.md')) { continue }
        if ($segs.Count -ne 3) {
            Add-Problem "结构: $rel — 期望 {lifecycle}/{class}/file.md（实际深度 $($segs.Count)）"
            continue
        }
        $class = $segs[1]
        $base = $segs[2]
        if ($class -notin $classes) {
            Add-Problem "结构: $rel — 未知类目 `"$class`"（允许: $($classes -join ', ')）"
            continue
        }
        if ($base -notmatch '^\d{4}-\d{2}-\d{2}-.+\.md$') {
            Add-Problem "结构: $rel — 文件名必须为 yyyy-mm-dd-topic.md"
            continue
        }
        $allNotes.Add([pscustomobject]@{
            Rel       = $rel
            Lifecycle = $segs[0]
            Date      = $base.Substring(0, 10)
        })
    }
}

# ---- 2. 活跃笔记格式 ----
$statusRegex = @{
    proposed    = '^Status: proposed$'
    implemented = '^Status: implemented$'
    rejected    = '^Status: rejected — .+$'
}
$requiredSections = @{
    proposed    = @('## Proposal', '## Acceptance criteria', '## Risks')
    implemented = @('## Decision', '## Consequences')
    rejected    = @('## Proposal')
}

foreach ($note in $allNotes) {
    $path = Join-Path $notesRoot ($note.Rel.Replace('/', '\'))
    $lines = Read-Utf8Lines $path
    $fail = { param([string]$Message) Add-Problem "格式: $($note.Rel) — $Message" }

    if (($lines.Count -lt 4) -or ($lines[0] -notmatch '^# Agent Note: \S')) {
        & $fail '第 1 行必须为 `# Agent Note: <标题>`'
    }
    if (($lines.Count -lt 2) -or ($lines[1] -ne '')) { & $fail '第 2 行必须为空' }
    $pattern = $statusRegex[$note.Lifecycle]
    if ($pattern -and (($lines.Count -lt 3) -or ($lines[2] -notmatch $pattern))) {
        & $fail "第 3 行必须匹配 $($note.Lifecycle) 生命周期状态语法"
    }
    if (($lines.Count -lt 4) -or ($lines[3] -ne '')) { & $fail '第 4 行必须为空' }

    $inFence = $false
    $prose = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $lines) {
        if ($line.StartsWith('```')) {
            $inFence = -not $inFence
            continue
        }
        if (-not $inFence) { $prose.Add($line) }
    }

    $statusLines = @($prose | Where-Object { $_ -and $_.StartsWith('Status:') })
    if ($statusLines.Count -ne 1) {
        & $fail '第 3 行的 `Status:` 必须是文件中唯一的状态行'
    }

    $h2s = @($prose | Where-Object { $_ -and $_.StartsWith('## ') } | ForEach-Object { $_.TrimEnd() })
    if ($h2s.Count -gt 0) {
        if ($h2s[0] -ne '## Problem') { & $fail '第一个章节必须是 `## Problem`' }
        foreach ($required in $requiredSections[$note.Lifecycle]) {
            if ($required -notin $h2s) { & $fail "缺少必需章节 $required" }
        }
    } else {
        & $fail '缺少 `## Problem` 章节'
    }
    if ($note.Lifecycle -eq 'implemented') {
        foreach ($h2 in $h2s) {
            if ($h2 -match '^## (?:Proposal\b|Plan\b|Migration plan\b|Acceptance criteria\b)') {
                & $fail "${h2} 是提案期标题，implemented 笔记只能陈述现状"
            }
        }
    }

    $hasSection = $h2s -contains '## Alternatives considered'
    $hasGrandfather = $prose -contains $grandfather
    if ($hasSection -and $hasGrandfather) {
        & $fail '同时存在 `## Alternatives considered` 与免责注释，应删除免责注释'
    }
    if (-not $hasSection -and -not $hasGrandfather) {
        & $fail '缺少 `## Alternatives considered`'
    }
    if ($hasGrandfather -and $note.Date -ge $formatAdopted) {
        & $fail "免责注释仅对 $formatAdopted 之前的笔记有效"
    }

    foreach ($line in $prose) {
        if ($legacyMarkers | Where-Object { $line -and $line.Contains($_) }) {
            & $fail '包含废弃的 legacy 格式标记'
        }
    }
}

# ---- 3. 归档封存校验 ----
$archiveRoot = Join-Path $notesRoot 'archived'
$archiveExists = Test-Path -LiteralPath $archiveRoot -PathType Container
if (-not $archiveExists) {
    Add-Problem 'archived/ 目录必须存在'
    $archiveExists = $true
    $null = New-Item -ItemType Directory -Path $archiveRoot -Force
}
if (-not (Test-Path -LiteralPath (Join-Path $archiveRoot 'AGENTS.md'))) {
    Add-Problem 'archived/AGENTS.md 必须存在'
}

$artifacts = @{}
$kinds = @()
$allowedRootFiles = @('AGENTS.md', 'manifest.json')
foreach ($entry in (Get-ChildItem -LiteralPath $archiveRoot -Force)) {
    if ($entry.PSIsContainer) {
        if ($entry.Name -notin $classes) {
            Add-Problem "archived/$($entry.Name)/: 未知 Agent Note 类目"
            continue
        }
        $kinds += $entry.Name
        foreach ($child in (Get-ChildItem -LiteralPath $entry.FullName -File -Force)) {
            if ($child.Name -eq '.gitkeep') { continue }
            $rel = "$($entry.Name)/$($child.Name)"
            $hash = (Get-FileHash -LiteralPath $child.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            $artifacts[$rel] = "sha256:$hash"
        }
        continue
    }
    if ($entry.Name -notin $allowedRootFiles) {
        Add-Problem "archived/$($entry.Name): 不允许的根文件"
    }
}
foreach ($kind in $classes) {
    if ($kind -notin $kinds) {
        Add-Problem "archived/$kind/: 缺少必需类目目录"
    }
}

$triplets = @{}
foreach ($path in $artifacts.Keys) {
    if ($path -notmatch '^([^/]+)/(\d{4}-\d{2}-\d{2}-.+?)(\.zh\.md|\.i18n\.yaml|\.md)$') {
        Add-Problem "${path}: 期望 {kind}/yyyy-mm-dd-topic.{md,zh.md,i18n.yaml}"
        continue
    }
    $kind = $Matches[1]
    $base = $Matches[2]
    $ext = $Matches[3]
    if ($kind -notin $classes) {
        Add-Problem "${path}: 未知 Agent Note 类目"
        continue
    }
    $key = "$kind/$base"
    if (-not $triplets.ContainsKey($key)) { $triplets[$key] = @{ md = $null; zh = $null; meta = $null } }
    if ($ext -eq '.md') { $triplets[$key].md = $path }
    elseif ($ext -eq '.zh.md') { $triplets[$key].zh = $path }
    else { $triplets[$key].meta = $path }
}

foreach ($key in ($triplets.Keys | Sort-Object)) {
    $t = $triplets[$key]
    $missing = @()
    if ($null -eq $t.md) { $missing += "${key}.md" }
    if ($null -eq $t.zh) { $missing += "${key}.zh.md" }
    if ($null -eq $t.meta) { $missing += "${key}.i18n.yaml" }
    if ($missing.Count -gt 0) {
        Add-Problem "${key}: 归档三件套不完整，缺少 $($missing -join ', ')"
        continue
    }
    $sourceBase = Split-Path $key -Leaf
    Test-ArchivedHeader "${key}.md" (Join-Path $archiveRoot ($t.md.Replace('/', '\'))) $sourceBase $false
    Test-ArchivedHeader "${key}.zh.md" (Join-Path $archiveRoot ($t.zh.Replace('/', '\'))) $sourceBase $true

    $metaLines = Read-Utf8Lines (Join-Path $archiveRoot ($t.meta.Replace('/', '\')))
    $pair = @{}
    foreach ($line in $metaLines) {
        if ($line -eq '' -or $line.StartsWith('#')) { continue }
        if ($line -notmatch '^([^:#]+\.md): ([0-9a-f]{40})$') {
            $pair = $null
            break
        }
        $pair[$Matches[1]] = $Matches[2]
    }
    $expectedDate = $key.Substring($key.Length - 10, 10)
    $sourceHash = Get-GitBlobHash (Join-Path $archiveRoot ($t.md.Replace('/', '\')))
    $zhHash = Get-GitBlobHash (Join-Path $archiveRoot ($t.zh.Replace('/', '\')))
    if ($null -eq $pair -or $pair.Count -ne 2 `
            -or ($pair.GetEnumerator() | Where-Object { $_.Key -notin @("${sourceBase}.md", "${sourceBase}.zh.md") }) `
            -or $pair["${sourceBase}.md"] -ne $sourceHash `
            -or $pair["${sourceBase}.zh.md"] -ne $zhHash) {
        Add-Problem "$($t.meta): 一致性记录必须包含两侧当前的 Git blob 哈希"
    }
}

$manifestPath = Join-Path $archiveRoot 'manifest.json'
$manifestFileExists = Test-Path -LiteralPath $manifestPath -PathType Leaf
$manifest = @{ version = 1; files = @{} }
if ($manifestFileExists) {
    try {
        $parsed = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
        $parsedProps = @($parsed.PSObject.Properties | ForEach-Object { $_.Name } | Sort-Object)
        if (($parsedProps -join ',') -ne 'files,version' -or $parsed.version -ne 1) {
            Add-Problem 'archived/manifest.json: 必须只有 version=1 与 files 字段'
        } else {
            $manifestFiles = @{}
            foreach ($prop in $parsed.files.PSObject.Properties) {
                if ($prop.Value -notmatch '^sha256:[0-9a-f]{64}$') {
                    Add-Problem "archived/manifest.json: $($prop.Name) 哈希格式非法"
                }
                $manifestFiles[$prop.Name] = [string]$prop.Value
            }
            $manifest = @{ version = 1; files = $manifestFiles }
        }
    } catch {
        Add-Problem "archived/manifest.json: 无法解析: $($_.Exception.Message)"
    }
} elseif (-not $ArchiveWrite) {
    Add-Problem 'archived/manifest.json 必须存在；新归档请使用 -ArchiveWrite 封存'
}

foreach ($sealed in $manifest.files.GetEnumerator()) {
    if (-not $artifacts.ContainsKey($sealed.Key)) {
        Add-Problem "$($sealed.Key): 已封存清单条目对应的归档文件缺失"
    } elseif ($artifacts[$sealed.Key] -ne $sealed.Value) {
        Add-Problem "$($sealed.Key): 已封存内容哈希被修改"
    }
}
$newArtifacts = @()
foreach ($path in ($artifacts.Keys | Sort-Object)) {
    if (-not $manifest.files.ContainsKey($path)) { $newArtifacts += $path }
}
if ($ArchiveWrite) {
    foreach ($path in $newArtifacts) { $manifest.files[$path] = $artifacts[$path] }
} else {
    foreach ($path in $newArtifacts) {
        Add-Problem "${path}: 归档产物尚未封存进 manifest.json"
    }
}

if ($errors.Count -gt 0) {
    Write-Host 'verify-agent-notes: 检查发现违规：' -ForegroundColor Red
    foreach ($problem in $errors) { Write-Host "  $problem" -ForegroundColor Red }
    exit 1
}

if ($ArchiveWrite -and $newArtifacts.Count -gt 0) {
    $files = [ordered]@{}
    foreach ($path in ($manifest.files.Keys | Sort-Object)) { $files[$path] = $manifest.files[$path] }
    $rendered = [ordered]@{ version = 1; files = $files } | ConvertTo-Json -Depth 3
    [System.IO.File]::WriteAllText($manifestPath, $rendered + "`n", [System.Text.UTF8Encoding]::new($false))
    Write-Host "verify-agent-notes: 已封存 $($newArtifacts.Count) 个新归档产物，现有封存保持不变。"
} else {
    Write-Host "verify-agent-notes: Agent Note 结构与格式检查通过（$($allNotes.Count) 份活跃笔记）。"
}
exit 0
