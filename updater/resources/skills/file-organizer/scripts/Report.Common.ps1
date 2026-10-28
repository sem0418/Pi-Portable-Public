#requires -Version 5.1
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Initialize-SkillReport([string]$Name, [string]$OutputDirectory) {
    [Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
    $global:OutputEncoding = New-Object Text.UTF8Encoding($false)
    if (-not $OutputDirectory) {
        $base = $env:PI_PORTABLE_ROOT
        if (-not $base) { $base = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../../..')) }
        $OutputDirectory = Join-Path $base 'data/reports'
    }
    [void][IO.Directory]::CreateDirectory($OutputDirectory)
    $identity = 'unavailable'
    $admin = $false
    try {
        $wi = [Security.Principal.WindowsIdentity]::GetCurrent()
        $identity = $wi.Name
        $admin = (New-Object Security.Principal.WindowsPrincipal($wi)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { }
    $script:SkillOutputDirectory = $OutputDirectory
    $script:SkillReport = [ordered]@{
        schemaVersion = 1; skill = $Name; collectedAt = (Get-Date -Format o)
        computer = $env:COMPUTERNAME; identity = $identity; administrator = $admin
        powerShellVersion = $PSVersionTable.PSVersion.ToString()
        mode = 'read-only'; sections = New-Object Collections.ArrayList
        interpretation = 'Unavailable or empty data is not evidence of health. Review section status and limitations.'
    }
}
function Add-ReportSection([string]$Name, [scriptblock]$Query, [switch]$Required) {
        $status = 'ok'; $errorText = $null; $data = @()
    try {
        $data = @(& $Query)
        if ($data.Count -eq 0) { $status = 'no-data' }
    } catch {
        $status = 'unavailable'
        if ($_.FullyQualifiedErrorId -match 'NoMatchingEventsFound') { $status = 'no-data' }
        if ($_.Exception -is [UnauthorizedAccessException] -or $_.FullyQualifiedErrorId -match 'AccessDenied|Unauthorized') { $status = 'access-denied' }
        $errorText = $_.Exception.Message
    }
    [void]$script:SkillReport.sections.Add([pscustomobject]@{
        name = $Name; status = $status; required = [bool]$Required; data = $data; error = $errorText
    })
}
function Save-SkillReport([switch]$PassThru) {
    $path = Join-Path $script:SkillOutputDirectory ("{0}-{1}-{2}.json" -f $script:SkillReport.skill, (Get-Date -Format 'yyyyMMdd-HHmmss'), [guid]::NewGuid().ToString('N').Substring(0,8))
    [IO.File]::WriteAllText($path, (ConvertTo-Json -InputObject $script:SkillReport -Depth 16), (New-Object Text.UTF8Encoding($false)))
    $requiredFailures = @($script:SkillReport.sections | Where-Object { $_.required -and $_.status -ne 'ok' })
    $unavailable = @($script:SkillReport.sections | Where-Object { $_.status -in @('unavailable','access-denied') })
    Write-Host "Report: $path"
    foreach ($s in $script:SkillReport.sections) { Write-Host ("  {0}: {1}" -f $s.name, $s.status) }
    if ($PassThru) { [pscustomobject]@{ Path = $path; RequiredSucceeded = ($requiredFailures.Count -eq 0); Partial = ($unavailable.Count -gt 0); Report = $script:SkillReport } }
}
function Assert-SkillAdministrator {
    if (-not $script:SkillReport.administrator) { throw 'This action requires an elevated Windows PowerShell. No elevation was requested automatically.' }
}
function Get-StartupEntries {
    $keys = @('HKLM:\Software\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run')
    foreach ($key in $keys) {
        if (Test-Path -LiteralPath $key) {
            $values = Get-ItemProperty -LiteralPath $key
            foreach ($p in $values.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' }) {
                [pscustomobject]@{ Source = $key; Name = $p.Name; Command = [string]$p.Value }
            }
        }
    }
    $folders = @([Environment]::GetFolderPath('Startup'),[Environment]::GetFolderPath('CommonStartup'))
    foreach ($folder in $folders) {
        if ($folder -and (Test-Path -LiteralPath $folder)) {
            Get-ChildItem -LiteralPath $folder -File | Select-Object @{n='Source';e={$folder}},Name,@{n='Command';e={$_.FullName}}
        }
    }
}
function Invoke-SystemCommand([string]$File, [string[]]$Arguments, [int]$TimeoutSeconds = 120) {
    # The launcher/initializer selects console UTF-8; SFC is a known UTF-16 writer.
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $File
    $psi.Arguments = ($Arguments -join ' ')
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $encoding = New-Object Text.UTF8Encoding($false)
    if ([IO.Path]::GetFileName($File) -ieq 'sfc.exe') { $encoding = [Text.Encoding]::Unicode }
    $psi.StandardOutputEncoding = $encoding
    $psi.StandardErrorEncoding = $encoding
    $p = New-Object Diagnostics.Process
    $p.StartInfo = $psi
    try {
        [void]$p.Start(); $outTask = $p.StandardOutput.ReadToEndAsync(); $errTask = $p.StandardError.ReadToEndAsync()
        if (-not $p.WaitForExit($TimeoutSeconds * 1000)) {
            # Do not kill system repair operations midway. Report and let Windows finish.
            return [pscustomobject]@{ ExitCode = $null; ProcessId = $p.Id; TimedOut = $true; Output = 'Still running after the observation timeout. Do not run a duplicate repair.'; Error = '' }
        }
        $p.WaitForExit()
        return [pscustomobject]@{ ExitCode = $p.ExitCode; ProcessId = $p.Id; TimedOut = $false; Output = $outTask.Result; Error = $errTask.Result }
    } finally { $p.Dispose() }
}
