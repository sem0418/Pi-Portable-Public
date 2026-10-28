#requires -Version 5.1
[CmdletBinding()]
param([string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'updater/scripts/Portable.Common.ps1')
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $root 'data/reports' }
$results = New-Object Collections.ArrayList
function Check([string]$Name,[scriptblock]$Body) {
    try { & $Body; [void]$results.Add([pscustomobject]@{name=$Name;status='passed'}); Write-Host "[PASS] $Name" }
    catch { [void]$results.Add([pscustomobject]@{name=$Name;status='failed';error=$_.Exception.Message}); Write-Host "[FAIL] ${Name}: $($_.Exception.Message)" }
}
foreach ($component in @('pi','node','git')) {
    Check "$component full recorded-file SHA-256 integrity" {
        $integrity = Get-ComponentIntegrity $root $component
        if (-not $integrity.Healthy) { throw ($integrity.Issues -join '; ') }
    }
}
foreach ($file in @('runtime/pi/pi.exe','tools/node/node.exe','tools/git/cmd/git.exe','tools/git/bin/bash.exe','tools/git/usr/bin/bash.exe')) {
    Check "$file is an AMD64 Windows PE (not a runtime execution test)" {
        $stream = [IO.File]::OpenRead((Join-Path $root $file))
        $reader = New-Object IO.BinaryReader($stream)
        try {
            if ($reader.ReadUInt16() -ne 0x5A4D) { throw 'MZ header missing' }
            $stream.Position = 0x3C; $offset = $reader.ReadUInt32(); $stream.Position = $offset
            if ($reader.ReadUInt32() -ne 0x4550 -or $reader.ReadUInt16() -ne 0x8664) { throw 'Expected AMD64 PE' }
        } finally { $reader.Dispose(); $stream.Dispose() }
    }
}
Check 'Four launchers and all project PowerShell UTF-8 BOM encodings' {
    foreach ($file in @('启动 Pi.bat','一键更新.bat','一键修复.bat','检查环境.bat')) {
        if (-not (Test-Path -LiteralPath (Join-Path $root $file))) { throw "Missing entry: $file" }
        if (-not ([IO.File]::ReadAllText((Join-Path $root $file)) -match 'setlocal DisableDelayedExpansion')) { throw "Unsafe inherited delayed expansion: $file" }
    }
    $owned = @(Get-ChildItem -LiteralPath (Join-Path $root '.github/scripts') -Filter *.ps1 -Recurse) +
        @(Get-ChildItem -LiteralPath (Join-Path $root 'updater/scripts') -Filter *.ps1 -Recurse) +
        @(Get-ChildItem -LiteralPath (Join-Path $root 'data/agent/skills') -Filter *.ps1 -Recurse) + @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter *.ps1)
    foreach ($file in $owned) {
        $bytes = [IO.File]::ReadAllBytes($file.FullName)
        if ($bytes.Length -lt 3 -or $bytes[0] -ne 239 -or $bytes[1] -ne 187 -or $bytes[2] -ne 191) { throw "PowerShell 5.1 UTF-8 BOM missing: $($file.Name)" }
    }
}
Check 'Skills have valid routing metadata and matching restore resources' {
    $manifest = Read-PortableJson (Join-Path $root 'updater/skills-manifest.json')
    foreach ($status in @(Get-SkillStatus $root)) { if (-not $status.Healthy) { throw "Invalid skill $($status.Name)" } }
    foreach ($file in @($manifest.files)) {
        $original = Join-Path (Join-Path $root 'updater/resources/skills') $file.path
        if ((Get-FileHash -LiteralPath $original).Hash.ToLowerInvariant() -ne $file.sha256) { throw "Restore resource invalid: $($file.path)" }
    }
    foreach ($dir in Get-ChildItem -LiteralPath (Join-Path $root 'data/agent/skills') -Directory) {
        $text = [IO.File]::ReadAllText((Join-Path $dir.FullName 'SKILL.md'))
        if ($text -notmatch '(?m)^name: ([a-z0-9]+(?:-[a-z0-9]+)*)\r?$') { throw 'Invalid skill name' }
        if ($Matches[1].Length -gt 64 -or $Matches[1] -ne $dir.Name) { throw 'Skill name does not match directory' }
        if ($text -notmatch '(?m)^description: (.+)\r?$' -or $Matches[1].Length -gt 1024) { throw 'Invalid skill description' }
    }
}
Check 'Project source inventory matches exact checked-out bytes' {
    $inventory = Read-PortableJson (Join-Path $root 'updater/source-manifest.json')
    foreach ($f in @($inventory.files)) {
        if ((Get-FileHash -LiteralPath (Join-Path $root $f.path) -Algorithm SHA256).Hash.ToLowerInvariant() -ne $f.sha256) { throw "Project source checksum differs: $($f.path)" }
    }
}
Check 'Upstream and project license records present' {
    foreach ($file in @('LICENSE','licenses/Pi-MIT.txt','licenses/Node-LICENSE.txt','licenses/Git-GPLv2.txt','licenses/THIRD-PARTY-NOTICES.md','tools/git/etc/package-versions.txt')) {
        if (-not (Test-Path -LiteralPath (Join-Path $root $file))) { throw "Missing license/source reference: $file" }
    }
}
Write-AtomicJson (Join-Path $OutputDirectory 'test-package.json') ([pscustomobject]@{suite='package';executedAt=(Get-Date -Format o);runtimeExecution=$false;results=@($results.ToArray())})
if (@($results | Where-Object status -eq 'failed').Count -gt 0) { exit 1 }

