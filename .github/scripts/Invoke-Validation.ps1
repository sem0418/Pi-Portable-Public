#requires -Version 5.1
[CmdletBinding()]
param([switch]$RunUpdater)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $root 'updater/scripts/Portable.Release.ps1')
$git = (Get-Command git.exe -CommandType Application | Select-Object -First 1).Source
$ps = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
if ($PSVersionTable.PSVersion.Major -ne 5 -or $PSVersionTable.PSVersion.Minor -ne 1) { throw 'Run validation under Windows PowerShell 5.1.' }
if (-not $env:RUNNER_TEMP) { throw 'Use a GitHub-hosted Windows runner for this orchestration.' }
$out = Join-Path $env:RUNNER_TEMP 'PiPortable-results'
[void][IO.Directory]::CreateDirectory($out)
Start-Transcript -Path (Join-Path $out 'execution.log') -Force | Out-Null
function Child([string]$File,[string[]]$Arguments = @(),[int]$Timeout = 900) {
    Write-Host "Running $File (limit: $Timeout seconds)"
    $r = Invoke-PortableNative $ps (@('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',(Join-Path $root $File)) + $Arguments) $Timeout $root
    Write-Host $r.Stdout
}
try {
    Assert-ReleaseLfs $root $git
    $lfsProbe = Invoke-PortableNative (Join-Path $root 'tools/git/ucrt64/bin/git-lfs.exe') @('version') 60 $root
    Write-Host ("Bundled Git LFS native probe: " + $lfsProbe.Stdout.Trim())
    Initialize-PortableDefaults $root
    # Entry's official Git initialization updates its own manifest when required.
    Child 'updater/scripts/Entry.ps1' @('-Action','Check') 300
    Assert-PortableDistribution $root -Native
    $startingVersionHash = (Get-FileHash -LiteralPath (Join-Path $root 'updater/versions.json') -Algorithm SHA256).Hash
    if ($RunUpdater) {
        # The ONLY upstream updater call. Any non-zero exit aborts the publish job.
        Child 'updater/scripts/Entry.ps1' @('-Action','Update') 1800
        Assert-PortableDistribution $root -Native
    }
    # Fetch only the installed release's license; this does not select/check newer versions.
    & (Join-Path $PSScriptRoot 'Update-Licenses.ps1') -Root $root
    # Healthy repair takes its existing offline/no-download path.
    Child 'updater/scripts/Entry.ps1' @('-Action','Repair') 300
    Child 'updater/scripts/Entry.ps1' @('-Action','Launch','--version') 120
    Child 'tests/Test-Windows.ps1' @('-Relocation','-QuickCI','-OutputDirectory',$out) 900
    Child 'tests/Test-Package.ps1' @('-OutputDirectory',$out) 300
    $python = (Get-Command python.exe -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
    $distributionTests = Invoke-PortableNative $python @((Join-Path $root 'tests/Test-Distribution.py')) 300 $root
    Write-Host $distributionTests.Stdout
    # Private component updates remain usable when public source preparation is stale.
    # Only the separate public-distribution workflow downloads and checks source bytes.
    $publicSourceStatus = 'metadata-only; source bytes not verified'
    try { Child '.github/scripts/Test-PublicRelease.ps1' @('-Root',$root,'-MetadataOnly') 300 }
    catch {
        if ($_.Exception.Message -match 'PUBLIC REDISTRIBUTION BLOCKED') {
            $publicSourceStatus = 'blocked; matching corresponding source inventory required before public distribution'
            Write-Host $publicSourceStatus
        } else { throw }
    }
    Child 'tests/Test-ReleasePipeline.ps1' @('-OutputDirectory',$out,'-GitPath',$git) 600
    Assert-PortableDistribution $root -Native
    if (-not $RunUpdater) { Assert-ReleaseLfs $root $git }
    if ($RunUpdater -and (Get-FileHash -LiteralPath (Join-Path $root 'updater/versions.json') -Algorithm SHA256).Hash -ne $startingVersionHash) {
        $installed = Read-PortableJson (Join-Path $root 'updater/versions.json')
        Set-ObjectProperty $installed 'windowsAcceptance' 'passed-native-GitHub-Actions-with-documented-skips'
        Set-ObjectProperty $installed 'windowsAcceptanceRun' "$($env:GITHUB_SERVER_URL)/$($env:GITHUB_REPOSITORY)/actions/runs/$($env:GITHUB_RUN_ID)"
        Write-AtomicJson (Join-Path $root 'updater/versions.json') $installed
    }
    Write-AtomicJson (Join-Path $out 'validation-summary.json') ([pscustomobject]@{status='passed';platform='native Windows runner';powershell=$PSVersionTable.PSVersion.ToString();upstreamUpdateExecuted=[bool]$RunUpdater;credentialedModelTest='not-executed';extendedSystemDiagnostics='skipped-QuickCI';physicalUsbAndDriveChange='not-executed';rollback='real filesystem transaction with mocked network/extraction/executable probes (Test-Core)';componentExecution='native';publicSourceCheck=$publicSourceStatus;runId=$env:GITHUB_RUN_ID})
} catch {
    Write-AtomicJson (Join-Path $out 'validation-summary.json') ([pscustomobject]@{status='failed';error=$_.Exception.Message;upstreamUpdateRequested=[bool]$RunUpdater;runId=$env:GITHUB_RUN_ID})
    throw
} finally { Stop-Transcript | Out-Null }
