#requires -Version 5.1
[CmdletBinding()]
param([string]$Root, [string]$SourcesDirectory, [switch]$MetadataOnly)
$ErrorActionPreference = 'Stop'
if (-not $Root) { $Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
. (Join-Path $Root 'updater/scripts/Portable.Release.ps1')
Assert-PortableDistribution $Root
$sourceManifest = Read-PortableJson (Join-Path $Root 'updater/source-manifest.json')
if (-not $sourceManifest -or @($sourceManifest.files).Count -eq 0) { throw 'PUBLIC REDISTRIBUTION BLOCKED: project source manifest missing.' }
foreach ($file in @($sourceManifest.files)) {
    if ($file.path -match '(^/|^[A-Za-z]:|\\|(^|/)\.\.(/|$))') { throw 'PUBLIC REDISTRIBUTION BLOCKED: unsafe source manifest path.' }
    $path = Join-Path $Root $file.path
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or
        (Get-Item -LiteralPath $path).Length -ne $file.size -or
        (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -ne $file.sha256) {
        throw "PUBLIC REDISTRIBUTION BLOCKED: project source checksum differs: $($file.path)"
    }
}
$bundledLfs = Join-Path $Root 'tools/git/ucrt64/bin/git-lfs.exe'
if (-not (Test-Path -LiteralPath $bundledLfs)) { throw 'PUBLIC REDISTRIBUTION BLOCKED: bundled Git LFS executable missing.' }
$lfsResult = Invoke-PortableNative $bundledLfs @('version') 60 $Root
Write-Host ("Bundled Git LFS native probe: " + $lfsResult.Stdout.Trim())
if ($lfsResult.Stdout -notmatch 'git-lfs/(\d+\.\d+\.\d+)' -or [version]$Matches[1] -lt [version]'3.8.1') {
    throw 'PUBLIC REDISTRIBUTION BLOCKED: bundled Git LFS predates the CVE-2026-105803 fix.'
}
$python = (Get-Command python.exe -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$arguments = @((Join-Path $PSScriptRoot 'Distribution.py'))
if ($MetadataOnly) {
    # This is a cheap PRIVATE CI consistency check, never a public byte-readiness pass.
    $arguments += @('metadata','--root',$Root)
} else {
    if (-not $SourcesDirectory) { $SourcesDirectory = Join-Path (Split-Path -Parent $Root) 'corresponding-source' }
    $arguments += @('verify','--root',$Root,'--sources',$SourcesDirectory)
}
$result = Invoke-PortableNative $python $arguments 1800 $Root
Write-Host $result.Stdout
if ($MetadataOnly) { Write-Host 'Metadata-only result does not authorize publication. Run the full public distribution workflow.' }
else { Write-Host 'Exact corresponding source bytes verified. Explicit owner approval is still required to publish.' }
