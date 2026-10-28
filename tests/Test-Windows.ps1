#requires -Version 5.1
[CmdletBinding()]
param([switch]$Online, [switch]$Relocation, [string]$RelocationDirectory, [string]$OutputDirectory, [switch]$QuickCI)
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { Write-Error 'Windows acceptance tests were not run: native Windows is required.'; exit 2 }
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'updater/scripts/Portable.Common.ps1')
. (Join-Path $root 'updater/scripts/Portable.Check.ps1')
$output = $OutputDirectory
if (-not $output) { $output = Join-Path $root ('data/reports/windows-acceptance-' + (Get-Date -Format 'yyyyMMdd-HHmmss')) }
[void][IO.Directory]::CreateDirectory($output)
$results = New-Object Collections.ArrayList
function Record([string]$Name,[string]$Status,[string]$Detail='') {
    [void]$results.Add([pscustomobject]@{name=$Name;status=$Status;detail=$Detail})
    Write-Host "[$Status] $Name $Detail"
}
function Check([string]$Name,[scriptblock]$Body) {
    try { & $Body; Record $Name 'passed' } catch { Record $Name 'failed' $_.Exception.Message }
}
function Get-SystemPathSnapshot {
    # Compare registry bytes/strings, not REG_EXPAND_SZ values expanded using the
    # process-local USERPROFILE/HOME that this test intentionally relocates.
    $user = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment')
    $machine = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('SYSTEM\CurrentControlSet\Control\Session Manager\Environment')
    try {
        $options = [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames
        return [pscustomobject]@{
            user = $(if ($user) { $user.GetValue('Path','',$options) } else { '' })
            machine = $machine.GetValue('Path','',$options)
        }
    } finally { if ($user) { $user.Dispose() }; if ($machine) { $machine.Dispose() } }
}
$pathBefore = Get-SystemPathSnapshot
$lock = $null
try {
    New-PortableDirectories $root
    $lock = Enter-PortableLock $root -Exclusive
    # Remove host developer-tool directories for this test process.
    $env:PATH = @((Join-Path $env:SystemRoot 'System32'),$env:SystemRoot,(Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0')) -join ';'
    Set-PortableEnvironment $root
    Initialize-PortableGit $root
    Update-PortableSettings $root
    Check 'Bundled executables, PATH, PowerShell and configuration' {
        if (-not (Show-PortableCheck $root)) { throw 'Environment checker failed' }
    }
    Check 'Core logic and transaction fault injection' {
        [void](Invoke-PortableNative (Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe') @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $PSScriptRoot 'Test-Core.ps1'),'-OutputDirectory',$output) 180)
    }
    Check 'File inventory, duplicates, move/copy/rename/undo and conflict tests' {
        [void](Invoke-PortableNative (Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe') @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $PSScriptRoot 'Test-FileOrganizer.ps1'),'-OutputDirectory',$output) 180)
    }
    Check 'Bash resolves bundled Node npm npx Git and native PowerShell' {
        $command = 'node --version && npm --version && npx --version && git --version && powershell.exe -NoProfile -NonInteractive -Command "Write-Output portable-shell-ok"'
        [void](Invoke-PortableNative (Join-Path $root 'tools/git/bin/bash.exe') @('--noprofile','--norc','-c',$command) 60)
    }
    $fixture = Join-Path $output '只读 资料'
    [void][IO.Directory]::CreateDirectory($fixture)
    [IO.File]::WriteAllText((Join-Path $fixture '测试.txt'),'read-only fixture')
    $cases = @(
        @{name='windows-diagnostics';script='Collect-Diagnostics.ps1';args=@{}},
        @{name='malware-triage';script='Collect-MalwareTriage.ps1';args=@{InspectPath=(Join-Path $fixture '测试.txt')}},
        @{name='file-organizer';script='Invoke-FileOrganizer.ps1';args=@{Mode='Scan';Path=$fixture;FindDuplicates=$true}},
        @{name='network-troubleshooting';script='Collect-Network.ps1';args=@{}},
        @{name='disk-health';script='Collect-DiskHealth.ps1';args=@{}},
        @{name='windows-repair';script='Invoke-WindowsRepair.ps1';args=@{Action='Inspect'}}
    )
    if ($QuickCI) { Record 'Extended system diagnostic collection' 'skipped' 'Quick CI validates actual native PowerShell tools without repeating WMI/Defender/SMART/event collection. Run without -QuickCI for the full suite.' }
    else {
    foreach ($case in $cases) {
        try {
            $helper = Join-Path $root "data/agent/skills/$($case.name)/scripts/$($case.script)"
            $parameters = $case.args
            $r = & $helper @parameters -OutputDirectory $output -PassThru
            if (-not $r.RequiredSucceeded) { throw "Required read-only section unavailable; report: $($r.Path)" }
            if ($r.Partial) { Record "$($case.name) actual Windows workflow" 'partial' 'Core evidence obtained; optional sections unsupported or denied. See per-section report.' }
            else { Record "$($case.name) actual Windows workflow" 'passed' }
        } catch { Record "$($case.name) actual Windows workflow" 'failed' $_.Exception.Message }
    }
    }
    $piFixtureArgs = @((Join-Path $PSScriptRoot 'Test-PiIntegration.cjs'),'--output',(Join-Path $output 'test-pi-integration.json'))
    if ($QuickCI) { $piFixtureArgs += '--quick-windows' }
    Check 'Official Pi: six slash commands and actual native tool execution via local fixture' {
        [void](Invoke-PortableNative (Join-Path $root 'tools/node/node.exe') $piFixtureArgs 900)
    }
    if ($Relocation -or $RelocationDirectory) {
        $clone = $RelocationDirectory
        if (-not $clone) { $clone = Join-Path (Split-Path -Parent $root) ('便携 测试-' + [guid]::NewGuid().ToString('N').Substring(0,6)) }
        Check 'Relocated bundle: Chinese/space path, portable resolution and unchanged model sentinel' {
            if (Test-Path -LiteralPath $clone) { throw 'RelocationDirectory must not exist; no existing folder will be overwritten.' }
            [void][IO.Directory]::CreateDirectory($clone)
            try {
                foreach ($d in @('runtime','tools')) { Copy-Item -LiteralPath (Join-Path $root $d) -Destination $clone -Recurse }
                New-PortableDirectories $clone
                Copy-Item -LiteralPath (Join-Path $root 'data/agent/skills') -Destination (Join-Path $clone 'data/agent') -Recurse -Force
                Write-AtomicJson (Join-Path $clone 'data/agent/settings.json') ([pscustomobject]@{ defaultProvider='migration-fixture'; defaultModel='keep-this-model'; shellPath='Q:\old-location\bash.exe' })
                Set-PortableEnvironment $clone; Update-PortableSettings $clone
                foreach ($n in @('pi','node','git')) { [void](Test-ComponentRuntime $n (Get-ComponentPath $clone $n)) }
                if ((Read-PortableJson (Join-Path $clone 'data/agent/settings.json')).defaultModel -ne 'keep-this-model') { throw 'Model sentinel lost' }
                foreach ($cmd in @('node.exe','npm.cmd','npx.cmd','git.exe','bash.exe')) {
                    if (-not (Get-Command $cmd -CommandType Application | Select-Object -First 1).Source.StartsWith($clone, [StringComparison]::OrdinalIgnoreCase)) { throw "Host/old executable selected: $cmd" }
                }
                $relocatedArgs = @((Join-Path $PSScriptRoot 'Test-PiIntegration.cjs'),'--root',$clone,'--output',(Join-Path $output 'test-pi-relocated.json'))
                if ($QuickCI) { $relocatedArgs += '--quick-windows' }
                [void](Invoke-PortableNative (Join-Path $clone 'tools/node/node.exe') $relocatedArgs 900)
                if ([IO.Path]::GetPathRoot($clone) -eq [IO.Path]::GetPathRoot($root)) { Record 'Different drive letter' 'skipped' 'Specify -RelocationDirectory on a different drive to test this.' }
                else { Record 'Different drive letter' 'passed' }
            } finally {
                Set-PortableEnvironment $root
                # clone was required to be absent at entry and belongs only to this test.
                if (Test-Path -LiteralPath $clone) { Remove-Item -LiteralPath $clone -Recurse -Force }
            }
        }
    } else { Record 'Chinese path and drive relocation runtime' 'skipped' 'Run with -Relocation or a new -RelocationDirectory.' }
    Record 'Real model credentials and automatic skill selection' 'skipped' 'Requires your model; see Test-LiveModel.ps1. No external API used by default.'
    if ($Online) {
        . (Join-Path $root 'updater/scripts/Portable.Update.ps1')
        Check 'Live official stable release detection (no archive downloads)' {
            $catalog = Get-ComponentCatalog $root
            if ($catalog.Errors.Count -gt 0 -or $catalog.Components.Count -ne 3) { throw ($catalog.Errors -join '; ') }
            Write-AtomicJson (Join-Path $output 'official-catalog.json') $catalog
        }
    } else { Record 'Live official update detection' 'skipped' 'Use -Online; network not required for other tests.' }
    Check 'No permanent user/machine PATH changes' {
        $after = Get-SystemPathSnapshot
        if ($after.user -ne $pathBefore.user -or $after.machine -ne $pathBefore.machine) { throw 'Registry PATH changed during tests' }
    }
} catch { Record 'Windows acceptance setup' 'failed' $_.Exception.Message }
finally {
    if ($lock) { $lock.Dispose() }
    Write-AtomicJson (Join-Path $output 'windows-summary.json') ([pscustomobject]@{executedAt=(Get-Date -Format o);platform=[Environment]::OSVersion.ToString();results=@($results.ToArray())})
    Write-Host "Acceptance results: $output"
}
if (@($results | Where-Object status -eq 'failed').Count -gt 0) { exit 1 }

