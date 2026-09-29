# 数据源获取脚本：按 data/pins/*.json 下载并校验数据源缓存
# 用法： .\scripts\fetch-sources.ps1 [-WritePins] [-Force] [-DryRun]
#   -WritePins   首次运行回填 sha256/size/fetched_at 到 pin JSON（随后以哈希锁定版本）
#   -Force       缓存哈希一致也强制重下（用于刷新源内容后重锁）
#   -DryRun      只输出每个源的预期动作，不下载不写文件
# 规则：哈希不一致即失败并保留旧缓存（人工审查 pin），绝不静默降级
# 兼容：Windows PowerShell 5.1+；脚本文件使用 UTF-8 BOM

param(
    [string]$PinsDir = 'data/pins',
    [string]$CacheDir = 'data/cache',
    [switch]$WritePins,
    [switch]$Force,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

# 历史 PowerShell 默认仅 SSL3/TLS1.0，强制启用 TLS1.2（部分源站只支持 TLS1.2）
try { [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12 } catch { }

$root = (Get-Location).Path

function Get-Sha256([string]$Path) {
    (Get-FileHash -Path $Path -Algorithm SHA256).Hash
}

function Write-PinBack($Pin, [string]$PinPath) {
    $Pin.PSObject.Properties.Remove('fetched_at')
    $Pin | Add-Member -NotePropertyName 'fetched_at' -NotePropertyValue (Get-Date -Format 'yyyy-MM-dd') -Force
    $Pin | ConvertTo-Json -Depth 6 | Set-Content -Path $PinPath -Encoding UTF8
}

function Download-Once([string]$Url, [string]$Target, $Pin, [string]$PinPath) {
    $tmp = "$Target.tmp"
    $attempt = 0
    while ($attempt -lt 3) {
        try {
            Write-Host ("     下载 {0} ({1:N0} 字节目标)" -f $Url, $Pin.size)
            Invoke-WebRequest -Uri $Url -OutFile $tmp -UseBasicParsing -TimeoutSec 300
            break
        } catch {
            $attempt++
            if ($attempt -ge 3) { throw "下载失败（第 $attempt 次仍失败）：$Url —— $($_.Exception.Message)" }
            Write-Host ("     第 {0} 次失败，2 秒后重试：{1}" -f $attempt, $_.Exception.Message)
            Start-Sleep -Seconds 2
            Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        }
    }
    $h = Get-Sha256 $tmp
    if ($Pin.sha256 -and ($h -ne $Pin.sha256)) {
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        throw "哈希校验失败：期望 $($Pin.sha256)，实际 $h（源内容已变化，人工审查 pin 后重锁）"
    }
    Move-Item -Path $tmp -Destination $Target -Force
    $Pin.size = (Get-Item $Target).Length
    $Pin.sha256 = $h
    if ($WritePins) { Write-PinBack $Pin $PinPath }
    return $h
}

if (-not $DryRun) {
    New-Item -ItemType Directory -Force -Path (Join-Path $root $CacheDir) | Out-Null
}

$pinFiles = Get-ChildItem -Path (Join-Path $root $PinsDir) -Filter '*.json' | Sort-Object Name
$summary = @()
$failed = $false

foreach ($pinFile in $pinFiles) {
    $pin = Get-Content -Path $pinFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
    $id = $pin.id
    if (-not $id) {
        Write-Host "跳过（非 pin 文件）：$($pinFile.Name)"
        continue
    }
    $status = ''
    $hashNote = ''
    try {
        if ($pin.kind -eq 'snapshot') {
            # 快照类：已提交入库的文件，只核对哈希（刷新快照是人工步骤）
            $snap = Join-Path $root $pin.snapshot_file
            if (-not (Test-Path $snap)) { throw "快照文件缺失：$($pin.snapshot_file)" }
            $h = Get-Sha256 $snap
            if ($pin.sha256 -and ($h -ne $pin.sha256)) { throw "快照哈希不一致：期望 $($pin.sha256)，实际 $h" }
            if ($pin.sha256) { $status = 'ok（快照锁定）' } else { $status = 'ok（未锁定）' }
            $hashNote = $h.Substring(0, 12)
        }
        elseif ($pin.kind -eq 'bundle') {
            # 打包类：由专用抓取脚本按锁定 commit 逐条抓取并拼接为单文件，此处只做哈希锁定
            $target = Join-Path (Join-Path $root $CacheDir) $pin.cache_file
            if ($DryRun) {
                $state = if (Test-Path $target) { '缓存已存在' } else { "需运行 $($pin.fetch_script)" }
                $status = "dry-run（$state）"
            }
            else {
                if ($Force -or -not (Test-Path $target)) {
                    & (Join-Path $root $pin.fetch_script)
                    if (-not (Test-Path $target)) { throw "打包脚本未产出：$target" }
                }
                $h = Get-Sha256 $target
                if ($pin.sha256) {
                    if ($h -ne $pin.sha256) { throw "打包哈希漂移：期望 $($pin.sha256)，实际 $h（锁定 commit 下内容不应变化，人工审查）" }
                    $status = 'ok（打包一致）'
                }
                elseif ($WritePins) {
                    $pin.sha256 = $h
                    $pin.size = (Get-Item $target).Length
                    Write-PinBack $pin $pinFile.FullName
                    $status = 'ok（打包回填锁定）'
                }
                else { $status = '未锁定（加 -WritePins 回填哈希）' }
                $hashNote = $h.Substring(0, 12)
            }
        }
        else {
            if (-not $pin.url) { throw "pin 缺少 url 字段" }
            $target = if ($pin.cache_rel) {
                Join-Path $root $pin.cache_rel.Replace('/', '\')
            } else {
                Join-Path (Join-Path $root $CacheDir) $pin.cache_file
            }
            if ($DryRun) {
                $state = if (Test-Path $target) { '缓存已存在' } else { '需下载' }
                $status = "dry-run（$state）"
            }
            elseif ($Force -or -not (Test-Path $target)) {
                $status = 'ok（新下载）'
                $hashNote = (Download-Once $pin.url $target $pin $pinFile.FullName).Substring(0, 12)
            }
            else {
                $h = Get-Sha256 $target
                if ($pin.sha256) {
                    if ($h -ne $pin.sha256) {
                        throw "缓存哈希漂移：$target 期望 $($pin.sha256)，实际 $h（源内容已变化或缓存被改，人工审查）"
                    }
                    $status = 'ok（缓存一致）'
                    $hashNote = $h.Substring(0, 12)
                }
                else {
                    if ($WritePins) {
                        $pin.sha256 = $h
                        $pin.size = (Get-Item $target).Length
                        Write-PinBack $pin $pinFile.FullName
                        $status = 'ok（缓存回填锁定）'
                        $hashNote = $h.Substring(0, 12)
                    }
                    else {
                        $status = '未锁定（加 -WritePins 回填哈希）'
                        $hashNote = $h.Substring(0, 12)
                    }
                }
            }
        }
    } catch {
        $status = "失败：$($_.Exception.Message)"
        $failed = $true
    }
    $summary += [pscustomobject]@{ id = $id; status = $status; hash = $hashNote }
    Write-Host ("[{0}] {1}" -f $id.PadRight(22), $status)
}

Write-Host ''
$summary | ForEach-Object { Write-Host ("  {0,-27} {1,-24} {2}" -f $_.id, $_.status, $_.hash) }
if ($failed) { Write-Host '结果：存在失败项。' -ForegroundColor Red; exit 1 } else { Write-Host '结果：全部通过。' -ForegroundColor Green; exit 0 }
