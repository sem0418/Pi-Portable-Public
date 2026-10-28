#requires -Version 5.1
# Release/sync validation only. Upstream selection stays in Portable.Update.ps1.
. (Join-Path $PSScriptRoot 'Portable.Common.ps1')
function Invoke-ReleaseGit([string]$Root, [string[]]$GitArguments, [string]$Git = '') {
    if (-not $Git) { $Git = (Get-Command git.exe -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source }
    (Invoke-PortableNative $Git (@('-c','core.quotepath=false','-C',$Root) + $GitArguments) 600).Stdout.TrimEnd("`r","`n")
}
function Get-ReleasePayloadPaths {
    @('.gitattributes','runtime/pi','tools/node','tools/git','updater/manifests/pi.json','updater/manifests/node.json','updater/manifests/git.json','updater/versions.json',
      'licenses')
}
function Assert-PortableDistribution([string]$Root, [switch]$Native) {
    if (Test-Path -LiteralPath (Join-Path $Root 'updater/transaction.json')) { throw 'Incomplete update transaction; refusing distribution.' }
    $versions = Read-PortableJson (Join-Path $Root 'updater/versions.json')
    foreach ($name in @('pi','node','git')) {
        $base = Get-ComponentPath $Root $name
        $manifest = Read-PortableJson (Join-Path $Root "updater/manifests/$name.json")
        if (-not $manifest -or @($manifest.files).Count -eq 0) { throw "Missing/empty $name manifest" }
        if ($manifest.version -ne $versions.components.$name.version) { throw "$name manifest/version mismatch" }
        $known = @{}
        foreach ($f in @($manifest.files)) {
            if ($f.path -match '(^/|^[A-Za-z]:|\\|(^|/)\.\.(/|$))' -or $known.ContainsKey($f.path)) { throw "Unsafe/duplicate $name manifest path" }
            $known[$f.path] = $true
            $p = Join-Path $base $f.path
            if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { throw "$name file missing: $($f.path)" }
            $item = Get-Item -LiteralPath $p -Force
            if ($item.Length -ne $f.size -or (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant() -ne $f.sha256) { throw "$name SHA-256/size mismatch: $($f.path)" }
        }
        foreach ($item in @(Get-ChildItem -LiteralPath $base -Recurse -Force)) {
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Reparse point in release payload: $name" }
            if ($item.PSIsContainer) { continue }
            $relative = $item.FullName.Substring($base.TrimEnd('\','/').Length + 1).Replace('\','/')
            if (-not $known.ContainsKey($relative)) { throw "$name unrecorded file: $relative" }
        }
        if ($Native) {
            $reported = Test-ComponentRuntime $name $base
            if ([version](ConvertTo-ComponentVersion $name $reported) -ne [version]$versions.components.$name.version) { throw "$name executable/version mismatch" }
            Write-Host "Native $name verified: $reported"
        }
        Write-Host "Complete $name manifest verified ($($known.Count) files)."
    }
}
function Assert-ReleaseLfs([string]$Root, [string]$Git, [string]$Ref = 'HEAD') {
    [void](Invoke-ReleaseGit $Root @('lfs','fsck','--objects',$Ref) $Git)
    $lines = (Invoke-ReleaseGit $Root @('lfs','ls-files','--long',$Ref) $Git) -split "`n"
    foreach ($line in $lines) {
        if (-not $line.Trim()) { continue }
        if ($line.TrimEnd("`r") -notmatch '^([a-f0-9]{64}) [*\-] (.+)$') { throw 'Unrecognized git lfs ls-files output' }
        $expected = $Matches[1]; $path = $Matches[2]
        if ((Get-FileHash -LiteralPath (Join-Path $Root $path) -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected) { throw "LFS pointer was not restored or hash differs: $path" }
    }
}
function Stage-PortableDistribution([string]$Root, [string]$Git, [int]$MaxNewLfsMiB = 512) {
    # Force-add ONLY these managed roots, including nested upstream .gitignore files.
    $paths = @(Get-ReleasePayloadPaths)
    foreach ($relativeBase in @('runtime/pi','tools/node','tools/git')) {
        foreach ($f in @(Get-ChildItem -LiteralPath (Join-Path $Root $relativeBase) -File -Recurse -Force | Where-Object Length -ge 10MB)) {
            $relative = $f.FullName.Substring($Root.TrimEnd('\','/').Length + 1).Replace('\','/')
            $attr = Invoke-ReleaseGit $Root @('check-attr','filter','--',$relative) $Git
            if ($attr -notmatch ': filter: lfs$') { [void](Invoke-ReleaseGit $Root @('lfs','track','--filename',$relative) $Git) }
        }
    }
    [void](Invoke-ReleaseGit $Root (@('add','--force','--all','--') + $paths + @(':(exclude,glob)licenses/*.previous',':(exclude,glob)licenses/*.tmp-*')) $Git)
    # Re-apply LFS attributes to any newly classified large files, without migration/history rewrite.
    [void](Invoke-ReleaseGit $Root (@('add','--renormalize','--') + @('runtime/pi','tools/node','tools/git')) $Git)
    $changed = @((Invoke-ReleaseGit $Root @('diff','--cached','--name-only','--diff-filter=ACM') $Git) -split "`n" | Where-Object { $_ })
    $objects = @{}
    foreach ($path in $changed) {
        if ($path -match '^(data/|workspace/|updater/(downloads|backups|staging|logs)/)') { throw 'Protected/runtime data entered the index' }
        $size = [long](Invoke-ReleaseGit $Root @('cat-file','-s',":$path") $Git)
        if ($size -gt 1024) {
            if ($size -ge 100MB) { throw "Oversized non-LFS Git blob: $path" }
            continue
        }
        $blob = Invoke-ReleaseGit $Root @('show',":$path") $Git
        if ($blob -match '(?s)^version https://git-lfs.github.com/spec/v1\r?\noid sha256:([a-f0-9]{64})\r?\nsize (\d+)') {
            $oid = $Matches[1]; $bytes = [long]$Matches[2]
            $objects[$oid] = $bytes
            if ((Get-FileHash -LiteralPath (Join-Path $Root $path) -Algorithm SHA256).Hash.ToLowerInvariant() -ne $oid) { throw "Staged LFS/worktree mismatch: $path" }
        }
    }
    $total = [long]0; foreach ($size in $objects.Values) { $total += $size }
    Write-Host "Conservative changed-LFS budget: $([math]::Ceiling($total / 1MB)) MiB / $MaxNewLfsMiB MiB."
    if ($total -gt ([long]$MaxNewLfsMiB * 1MB)) { throw 'Changed LFS objects exceed the selected budget; nothing committed/uploaded.' }
    $all = @((Invoke-ReleaseGit $Root @('diff','--cached','--name-only') $Git) -split "`n" | Where-Object { $_ })
    foreach ($path in $all) {
        if (-not @($paths | Where-Object { $path -eq $_ -or $path.StartsWith($_ + '/') }).Count) { throw "Staged path outside release allowlist: $path" }
    }
    return [pscustomobject]@{ ChangedFiles = $all.Count; ChangedLfsBytes = $total; ChangedLfsObjects = $objects.Count }
}
