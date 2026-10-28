#requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet('Launch','Update','Repair','Check')][string]$Action = 'Launch',
    [switch]$CheckOnly,
    [switch]$AllowComponentReplacement,
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$PiArguments
)
$ErrorActionPreference = 'Stop'
$lock = $null
$exitCode = 0
try {
    . (Join-Path $PSScriptRoot 'Portable.Common.ps1')
    $root = Get-PortableRoot
    if ($env:OS -ne 'Windows_NT') { throw 'This distribution requires native Windows 10/11 x64, not WSL or Linux.' }
    if (-not [Environment]::Is64BitOperatingSystem -or -not [Environment]::Is64BitProcess) {
        throw 'Use 64-bit Windows and 64-bit Windows PowerShell for this x64 distribution.'
    }
    New-PortableDirectories $root
    $exclusive = $Action -in @('Update','Repair') -or (Test-Path -LiteralPath (Join-Path $root 'tools/git/post-install.bat'))
    $lock = Enter-PortableLock $root -Exclusive:$exclusive
    Initialize-PortableDefaults $root
    Set-PortableEnvironment $root
    if ($Action -in @('Launch','Check')) {
        Initialize-PortableGit $root
        if ($exclusive) { $lock.Dispose(); $lock = Enter-PortableLock $root }
    }
    if ($Action -eq 'Update' -or $Action -eq 'Repair') {
        . (Join-Path $PSScriptRoot 'Portable.Update.ps1')
        Invoke-PortableUpdate $root -Repair:($Action -eq 'Repair') -CheckOnly:$CheckOnly -AllowComponentReplacement:$AllowComponentReplacement
    } elseif ($Action -eq 'Check') {
        . (Join-Path $PSScriptRoot 'Portable.Check.ps1')
        if (-not (Show-PortableCheck $root)) { $exitCode = 1 }
    } else {
        if (Test-Path -LiteralPath (Join-Path $root 'updater/transaction.json')) {
            throw 'An interrupted update needs recovery. Run the Repair launcher first.'
        }
        foreach ($p in @('runtime/pi/pi.exe','tools/node/node.exe','tools/git/bin/bash.exe','tools/git/cmd/git.exe')) {
            if (-not (Test-Path -LiteralPath (Join-Path $root $p))) { throw "Missing $p. Run the Repair launcher." }
        }
        Update-PortableSettings $root
        Push-Location (Join-Path $root 'workspace')
        try {
            # Add native shells without replacing user tools or future native extensions.
            & (Join-Path $root 'runtime/pi/pi.exe') --tools '+bash,+powershell' @PiArguments
            $exitCode = $LASTEXITCODE
            if ($exitCode -ne 0) { Write-Host "Pi exited with code $exitCode. Run the environment checker for details." -ForegroundColor Yellow }
        } finally { Pop-Location }
    }
} catch {
    Write-Host "`nPi-Portable failed: $($_.Exception.Message)" -ForegroundColor Red
    $exitCode = 1
} finally { if ($lock) { $lock.Dispose() } }
exit $exitCode
