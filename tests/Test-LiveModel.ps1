#requires -Version 5.1
# Optional: this test uses the configured model and can incur API charges.
[CmdletBinding()]
param([switch]$Run)
if (-not $Run) { Write-Host 'Not executed. After model setup, pass -Run to test real model selection (may incur API charges).'; exit 0 }
if ($env:OS -ne 'Windows_NT') { Write-Error 'Native Windows is required.'; exit 2 }
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'updater/scripts/Portable.Common.ps1')
Set-PortableEnvironment $root
$lock = Enter-PortableLock $root
try {
    Update-PortableSettings $root
    $outDir = Join-Path $root ('data/reports/live-model-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    [void][IO.Directory]::CreateDirectory($outDir)
    $cases = [ordered]@{
        'windows-diagnostics'='请诊断这台 Windows 的基本系统、CPU、内存情况。先读取适合的 Skill，再仅运行它的默认只读采集脚本。不要修复或修改系统。'
        'malware-triage'='请检查这台 Windows 的安全软件状态、可疑进程和启动项。先读取适合的 Skill，仅运行默认只读采集，不扫描、不隔离、不删除。'
        'file-organizer'='请分析当前 workspace 文件夹的文件和空间情况。先读取适合的 Skill，仅运行 Scan，不移动、复制、重命名或删除。'
        'network-troubleshooting'='请检查这台 Windows 的适配器、DNS 和 example.com 的 443 端口。先读取适合的 Skill，仅运行默认诊断，不重置或修改网络。'
        'disk-health'='请查看这台 Windows 的磁盘、容量、可取得的可靠性信息。先读取适合的 Skill，仅运行默认只读采集，不进行修复、格式化或全盘压力测试。'
        'windows-repair'='请检查这台 Windows 的更新和组件维护状态。先读取适合的 Skill，仅运行 Inspect，不调用 SFC/DISM 修复，不改变服务或删除任何内容。'
    }
    $results = @()
    foreach ($skill in $cases.Keys) {
        try {
            $r = Invoke-PortableNative (Join-Path $root 'runtime/pi/pi.exe') @('--tools','+bash,+powershell','--mode','json','--no-session',$cases[$skill]) 300 (Join-Path $root 'workspace')
            $events = @($r.Stdout -split "`n" | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json })
            $read = @($events | Where-Object { $_.type -eq 'tool_execution_start' -and $_.toolName -eq 'read' -and (ConvertTo-Json -InputObject $_ -Depth 10) -match [regex]::Escape($skill) })
            $ps = @($events | Where-Object { $_.type -eq 'tool_execution_end' -and $_.toolName -eq 'powershell' -and -not $_.isError })
            $status = 'passed'
            if ($read.Count -eq 0 -or $ps.Count -eq 0) { $status='needs-review' }
            # Store only checks, not model output or tool payloads that may contain local data.
            $results += [pscustomobject]@{skill=$skill;status=$status;skillRead=($read.Count -gt 0);powerShellSucceeded=($ps.Count -gt 0)}
        } catch { $results += [pscustomobject]@{skill=$skill;status='failed';error='Model invocation failed; inspect Pi interactively without printing credentials.'} }
    }
    Write-AtomicJson (Join-Path $outDir 'live-model-summary.json') $results
    $results | Format-Table -AutoSize
} finally { $lock.Dispose() }
