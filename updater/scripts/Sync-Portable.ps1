#requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Root,
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._/-]*$')][string]$Branch = 'main',
    [switch]$MigrateLegacyData,
    [string]$GitPath,
    [switch]$SkipNativeValidation
)
$ErrorActionPreference = 'Stop'
if (-not $Root) { $Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
. (Join-Path $PSScriptRoot 'Portable.Release.ps1')
. (Join-Path $PSScriptRoot 'Portable.Update.ps1')
$Root = [IO.Path]::GetFullPath($Root).TrimEnd('\','/')
$lock = $null; $copiedGit = $null; $dataBackup = $null; $restoreData = $false; $baselineData = @{}
$id = (Get-Date -Format 'yyyyMMddTHHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8)
function Git([string[]]$Words) { Invoke-ReleaseGit $Root $Words $GitPath }
function FileMap([string]$Path) {
    $map = @{}
    if (Test-Path -LiteralPath $Path) {
        foreach ($item in @(Get-ChildItem -LiteralPath $Path -Recurse -Force)) {
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'User-data reparse point found; back up and migrate manually.' }
            if (-not $item.PSIsContainer) { $map[$item.FullName.Substring($Path.Length+1)] = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash }
        }
    }
    return $map
}
try {
    if ($env:OS -ne 'Windows_NT') { throw 'Native Windows is required.' }
    New-PortableDirectories $Root
    $lock = Enter-PortableLock $Root -Exclusive
    Assert-NoPortableProcesses $Root
    if (Test-Path -LiteralPath (Join-Path $Root 'updater/transaction.json')) { throw 'Run Repair to recover the existing transaction before Git sync.' }
    if (-not $GitPath) {
        $outside = @(Get-Command git.exe -All -CommandType Application -ErrorAction SilentlyContinue | Where-Object { -not $_.Source.StartsWith($Root + '\',[StringComparison]::OrdinalIgnoreCase) })
        if ($outside.Count) { $GitPath = $outside[0].Source }
        else {
            # Git cannot replace its own loaded Windows executables. Use a disposable copy.
            $copiedGit = Join-Path $Root "updater/sync-tools/$id"
            [void][IO.Directory]::CreateDirectory((Split-Path -Parent $copiedGit))
            Copy-Item -LiteralPath (Join-Path $Root 'tools/git') -Destination $copiedGit -Recurse
            $GitPath = Join-Path $copiedGit 'cmd/git.exe'
        }
    }
    # An explicitly supplied Git may never execute from the directory being replaced.
    if ($GitPath.StartsWith((Join-Path $Root 'tools') + '\',[StringComparison]::OrdinalIgnoreCase)) { throw 'GitPath must be outside managed tools/. Omit it to use a safe temporary copy.' }
    [void](Git @('check-ref-format','--branch',$Branch))
    [void](Git @('lfs','version'))
    $currentBranch = Git @('symbolic-ref','--short','HEAD')
    if ($currentBranch -ne $Branch) { throw "Switch to local $Branch first. Sync does not switch branches or merge personal commits." }
    $old = Git @('rev-parse','HEAD')
    if (Git @('diff','--cached','--name-only')) { throw 'Staged edits exist; commit or save them explicitly before sync.' }
    $dirty = @((Git @('diff','--name-only')) -split "`n" | Where-Object { $_ })
    $legacy = @((Git @('ls-files','--','data','workspace')) -split "`n" | Where-Object { $_ })
    if (@($legacy | Where-Object { $_ -like 'workspace/*' }).Count) { throw 'Tracked workspace detected. Back up and migrate manually.' }
    $nonDataDirty = @($dirty | Where-Object { $_ -notlike 'data/*' })
    if ($nonDataDirty.Count) { throw 'Local tracked release/source edits exist. No overwrite, stash or reset was performed.' }
    if ($legacy.Count -and -not $MigrateLegacyData) { throw 'Legacy tracked data detected. First back up the whole folder, then rerun with -MigrateLegacyData; see docs/LOCAL-SYNC.md.' }
    # Always fetch objects before changing files. Only the requested branch is fetched.
    [void](Git @('fetch','--no-tags','origin',$Branch))
    $target = Git @('rev-parse','FETCH_HEAD')
    [void](Git @('merge-base','--is-ancestor',$old,$target))
    $targetFiles = @((Git @('ls-tree','-r','--name-only',$target)) -split "`n" | Where-Object { $_ })
    if (@($targetFiles | Where-Object { $_ -match '^(data/|workspace/|updater/(downloads|backups|staging|logs|sync-tools|sync-backups)/)' }).Count) { throw 'Remote tracks user or temporary data; refusing sync.' }
    $tracked = @{}; foreach ($p in @((Git @('ls-files')) -split "`n")) { $tracked[$p] = $true }
    foreach ($p in $targetFiles) {
        if (-not $tracked.ContainsKey($p) -and (Test-Path -LiteralPath (Join-Path $Root $p))) { throw "Incoming path collides with an untracked/ignored local file: $p. Preserve it explicitly before retrying." }
    }
    [void](Git @('lfs','fetch','origin',$target))
    [void](Git @('lfs','fsck','--objects',$target))
    # Preserve current bytes, including ignored credentials, before the legacy deletion commit.
    if ($legacy.Count) {
        $dataBackup = Join-Path $Root "updater/sync-backups/$id/data"
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $dataBackup))
        $sourceData = Join-Path $Root 'data'
        $before = FileMap $sourceData
        Copy-Item -LiteralPath $sourceData -Destination $dataBackup -Recurse
        $saved = FileMap $dataBackup
        if ($before.Count -ne $saved.Count) { throw 'Data backup file count mismatch; sync stopped.' }
        foreach ($p in $before.Keys) { if ($before[$p] -ne $saved[$p]) { throw 'Data backup SHA-256 mismatch; sync stopped.' } }
        Write-Host "Verified user-data backup: $dataBackup"
        $latest = FileMap $sourceData
        foreach ($p in $before.Keys) { if ($latest[$p] -ne $before[$p]) { throw 'User data changed during backup. Close editors/sync tools and retry; no live files were restored.' } }
        if ($latest.Count -ne $before.Count) { throw 'User data changed during backup; sync stopped before changing tracked files.' }
        $restoreData = $true
        # Explicit migration flag authorizes ONLY restoring the already-backed-up legacy data paths.
        [void](Git @('restore','--source=HEAD','--worktree','--','data'))
        $baselineData = FileMap $sourceData
    }
    [void](Git @('branch',"sync-backup/$id",$old))
    $oldSmudge = $env:GIT_LFS_SKIP_SMUDGE
    try {
        $env:GIT_LFS_SKIP_SMUDGE = '0'
        [void](Git @('merge','--ff-only',$target))
        [void](Git @('lfs','checkout'))
    } finally { $env:GIT_LFS_SKIP_SMUDGE = $oldSmudge }
    Assert-ReleaseLfs $Root $GitPath
    Assert-PortableDistribution $Root -Native:(-not $SkipNativeValidation)
    Write-Host "Synchronized to $target. Local recovery ref: sync-backup/$id."
} catch {
    Write-Host "Sync stopped: $($_.Exception.Message)" -ForegroundColor Red
    if ($dataBackup) { Write-Host "Preserved data backup: $dataBackup" }
    throw
} finally {
    try {
        if ($restoreData) {
            $dest = Join-Path $Root 'data'
            [void][IO.Directory]::CreateDirectory($dest)
            $saved = FileMap $dataBackup
            $live = FileMap $dest
            $conflicts = @()
            foreach ($p in $saved.Keys) {
                $path = Join-Path $dest $p
                if ($live.ContainsKey($p) -and $live[$p] -eq $saved[$p]) { continue }
                if ((Test-Path -LiteralPath $path) -and
                    (-not $baselineData.ContainsKey($p) -or $live[$p] -ne $baselineData[$p])) {
                    # An editor/hook may have saved new bytes during merge. Keep both.
                    $conflicts += $p
                    continue
                }
                [void][IO.Directory]::CreateDirectory((Split-Path -Parent $path))
                Copy-Item -LiteralPath (Join-Path $dataBackup $p) -Destination $path -Force
            }
            $after = FileMap $dest
            foreach ($p in $saved.Keys) {
                if ($conflicts -notcontains $p -and $saved[$p] -ne $after[$p]) { throw "Data restoration mismatch. Keep backup: $dataBackup" }
            }
            if ($conflicts.Count) { throw "Concurrent user-data edits preserved in place ($($conflicts.Count) files); original bytes remain in $dataBackup. Reconcile manually; nothing was silently overwritten." }
            Write-Host 'Original user-data bytes restored and verified; backup retained.'
        }
    } finally {
        if ($lock) { $lock.Dispose() }
        if ($copiedGit -and (Test-Path -LiteralPath $copiedGit)) { Remove-Item -LiteralPath $copiedGit -Recurse -Force }
    }
}
