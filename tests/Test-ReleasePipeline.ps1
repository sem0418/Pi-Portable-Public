#requires -Version 5.1
[CmdletBinding()]
param([string]$OutputDirectory, [string]$GitPath)
$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
. (Join-Path $project 'updater/scripts/Portable.Release.ps1')
if (-not $GitPath) { $GitPath = (Get-Command git.exe -CommandType Application | Select-Object -First 1).Source }
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $project 'data/reports' }
$ps = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
$temp = Join-Path ([IO.Path]::GetTempPath()) ('PiPortable-release-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temp)
$results = New-Object Collections.ArrayList
function Assert($Condition,[string]$Message) { if (-not $Condition) { throw $Message } }
function Case([string]$Name,[scriptblock]$Body) {
    try { & $Body; [void]$results.Add([pscustomobject]@{name=$Name;status='passed'}) }
    catch { [void]$results.Add([pscustomobject]@{name=$Name;status='failed';error=$_.Exception.Message}) }
    Write-Host "[$($results[$results.Count-1].status)] $Name"
}
function G([string]$Root,[string[]]$Words) { Invoke-ReleaseGit $Root $Words $GitPath }
function Init([string]$Root) {
    [void][IO.Directory]::CreateDirectory($Root)
    [void](G $Root @('init','-b','main'))
    [void](G $Root @('config','user.name','Fixture'))
    [void](G $Root @('config','user.email','fixture@example.invalid'))
    [void](G $Root @('config','core.autocrlf','false'))
    [void](G $Root @('lfs','install','--local'))
}
function Payload([string]$Root) {
    New-PortableDirectories $Root
    $v = [pscustomobject]@{schemaVersion=1;components=[pscustomobject]@{}}
    foreach ($n in @('pi','node','git')) {
        $d = Get-ComponentPath $Root $n; [void][IO.Directory]::CreateDirectory($d)
        [IO.File]::WriteAllText((Join-Path $d 'program.bin'), "fixture-$n")
        Write-AtomicJson (Join-Path $Root "updater/manifests/$n.json") (New-ComponentManifest $d '1.0.0')
        Set-ObjectProperty $v.components $n ([pscustomobject]@{version='1.0.0'})
    }
    Write-AtomicJson (Join-Path $Root 'updater/versions.json') $v
    [void][IO.Directory]::CreateDirectory((Join-Path $Root 'licenses'))
    [IO.File]::WriteAllText((Join-Path $Root 'licenses/fixture.txt'),'fixture license')
    [IO.File]::WriteAllText((Join-Path $Root '.gitattributes'),"runtime/** -text`ntools/** -text`n")
    [IO.File]::WriteAllText((Join-Path $Root '.gitignore'),"/data/`n/workspace/`n/updater/operation.lock`n/updater/downloads/`n/updater/staging/`n/updater/backups/`n/updater/logs/`n/updater/sync-tools/`n/updater/sync-backups/`n*.previous`n")
}
function Commit([string]$Root,[string]$Message) { [void](G $Root @('add','--all')); [void](G $Root @('commit','-m',$Message)) }
function Sync([string]$Root,[switch]$Migration) {
    $words = @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',(Join-Path $project 'updater/scripts/Sync-Portable.ps1'),'-Root',$Root,'-GitPath',$GitPath,'-SkipNativeValidation')
    if ($Migration) { $words += '-MigrateLegacyData' }
    Invoke-PortableNative $ps $words 180
}
try {
    Case 'Default resources seed missing files and preserve custom skills and configuration' {
        $r = Join-Path $temp 'defaults'
        [void][IO.Directory]::CreateDirectory((Join-Path $r 'updater'))
        Copy-Item -LiteralPath (Join-Path $project 'updater/resources') -Destination (Join-Path $r 'updater/resources') -Recurse
        Copy-Item -LiteralPath (Join-Path $project 'updater/skills-manifest.json') -Destination (Join-Path $r 'updater/skills-manifest.json')
        Initialize-PortableDefaults $r
        $f = Join-Path $r 'data/agent/skills/windows-diagnostics/SKILL.md'
        [IO.File]::WriteAllText($f,'CUSTOM SKILL')
        [IO.File]::WriteAllText((Join-Path $r 'data/agent/models.json'),'OPAQUE USER CONFIG')
        Initialize-PortableDefaults $r
        Assert ([IO.File]::ReadAllText($f) -eq 'CUSTOM SKILL') 'Custom skill overwritten'
        Assert ([IO.File]::ReadAllText((Join-Path $r 'data/agent/models.json')) -eq 'OPAQUE USER CONFIG') 'Config overwritten'
    }
    Case 'Release staging captures nested ignored additions, changes and deletions; excludes data/temp/logs' {
        $r = Join-Path $temp 'stage'; Init $r; Payload $r; Commit $r 'baseline'
        [IO.File]::WriteAllText((Join-Path $r 'tools/node/.gitignore'),"node_modules/`n")
        [void][IO.Directory]::CreateDirectory((Join-Path $r 'tools/node/node_modules/new-package'))
        [IO.File]::WriteAllText((Join-Path $r 'tools/node/node_modules/new-package/new.js'),'NEW FILE')
        Remove-Item -LiteralPath (Join-Path $r 'runtime/pi/program.bin')
        [IO.File]::WriteAllText((Join-Path $r 'tools/git/program.bin'),'CHANGED')
        [IO.File]::WriteAllText((Join-Path $r 'data/agent/auth.json'),'fixture-secret-never-stage')
        [IO.File]::WriteAllText((Join-Path $r 'updater/downloads/test.partial'),'TEMP')
        [IO.File]::WriteAllText((Join-Path $r 'updater/logs/test.log'),'LOG')
        [IO.File]::WriteAllText((Join-Path $r 'updater/manifests/pi.json.previous'),'OLD MANIFEST')
        [IO.File]::WriteAllText((Join-Path $r 'licenses/component-provenance.json.previous'),'OLD PROVENANCE')
        [void](Stage-PortableDistribution $r $GitPath)
        $diff = G $r @('diff','--cached','--name-status')
        Assert ($diff -match 'A\s+tools/node/node_modules/new-package/new.js') 'Nested ignored addition lost'
        Assert ($diff -match 'D\s+runtime/pi/program.bin') 'Deletion lost'
        Assert ($diff -match 'M\s+tools/git/program.bin') 'Modification lost'
        Assert ($diff -notmatch 'data/|downloads/|logs/|\.previous') 'User or temporary files staged'
    }
    Case 'LFS clean/smudge bytes and missing-object rejection use real Git LFS' {
        $r = Join-Path $temp 'lfs'; Init $r
        [IO.File]::WriteAllText((Join-Path $r '.gitattributes'),"*.bin filter=lfs diff=lfs merge=lfs -text`n")
        [IO.File]::WriteAllText((Join-Path $r 'payload.bin'),'LFS FIXTURE BYTES')
        Commit $r 'lfs fixture'
        $blob = G $r @('show','HEAD:payload.bin')
        Assert ($blob -match 'version https://git-lfs.github.com/spec/v1') 'No LFS pointer committed'
        Assert-ReleaseLfs $r $GitPath
        $object = @(Get-ChildItem -LiteralPath (Join-Path $r '.git/lfs/objects') -Recurse -File)[0]
        Remove-Item -LiteralPath $object.FullName
        $failed=$false; try { Assert-ReleaseLfs $r $GitPath } catch { $failed=$true }
        Assert $failed 'Missing LFS object accepted'
    }
    Case 'LFS budget stops a new large-object commit before upload' {
        $r = Join-Path $temp 'budget'; Init $r; Payload $r; Commit $r 'baseline'
        $head = G $r @('rev-parse','HEAD')
        [IO.File]::WriteAllBytes((Join-Path $r 'runtime/pi/large.bin'), (New-Object byte[] (11MB)))
        $blocked=$false
        try { [void](Stage-PortableDistribution $r $GitPath 0) } catch { $blocked=$_.Exception.Message -match 'exceed the selected budget' }
        Assert $blocked 'Changed LFS size limit did not block'
        Assert ((G $r @('rev-parse','HEAD')) -eq $head) 'Budget failure created a commit'
    }
    Case 'Complete manifest rejects extra files, not just recorded-file corruption' {
        $r = Join-Path $temp 'manifest'; Payload $r
        Assert-PortableDistribution $r
        [IO.File]::WriteAllText((Join-Path $r 'runtime/pi/unrecorded.txt'),'UNRECORDED')
        $failed=$false; try { Assert-PortableDistribution $r } catch { $failed=$true }
        Assert $failed 'Unrecorded payload file accepted'
    }
    # This fixture uses a local bare Git remote. No upstream APIs or real credentials.
    $seed = Join-Path $temp 'seed'; Init $seed; Payload $seed
    [IO.File]::WriteAllText((Join-Path $seed 'data/agent/models.json'),'LEGACY CONFIG')
    [void](G $seed @('add','--force','data/agent/models.json'))
    Commit $seed 'legacy baseline'
    $legacyCommit = G $seed @('rev-parse','HEAD')
    $remote = Join-Path $temp 'remote.git'; [void][IO.Directory]::CreateDirectory($remote)
    [void](G $remote @('init','--bare'))
    [void](G $seed @('remote','add','origin',$remote))
    [void](G $seed @('push','--set-upstream','origin','main'))
    $client = Join-Path $temp '中文 空格 客户端'
    [void](G $temp @('clone','--branch','main',$remote,$client))
    [void](G $client @('config','user.name','Fixture'))
    [void](G $client @('config','user.email','fixture@example.invalid'))
    New-PortableDirectories $client
    [IO.File]::WriteAllText((Join-Path $client 'data/agent/models.json'),'CUSTOM CONFIG SENTINEL')
    [IO.File]::WriteAllText((Join-Path $client 'data/agent/auth.json'),'API/OAUTH SENTINEL')
    [IO.File]::WriteAllText((Join-Path $client 'data/sessions/keep.jsonl'),'SESSION SENTINEL')
    [IO.File]::WriteAllText((Join-Path $client 'workspace/keep.txt'),'WORKSPACE SENTINEL')
    [IO.File]::WriteAllText((Join-Path $client 'data/agent/skills/custom.txt'),'SKILL SENTINEL')
    [void](G $seed @('rm','--cached','--','data/agent/models.json'))
    [IO.File]::WriteAllText((Join-Path $seed 'tools/node/program.bin'),'NEW NODE PAYLOAD')
    Write-AtomicJson (Join-Path $seed 'updater/manifests/node.json') (New-ComponentManifest (Get-ComponentPath $seed 'node') '1.0.0')
    Commit $seed 'release without user data'; [void](G $seed @('push','origin','main'))
    Case 'Legacy tracked-data deletion is blocked without explicit migration' {
        $head = G $client @('rev-parse','HEAD')
        $failed=$false; try { [void](Sync $client) } catch { $failed=$true }
        Assert $failed 'Legacy migration silently ran'
        Assert ((G $client @('rev-parse','HEAD')) -eq $head) 'HEAD changed on refused migration'
    }
    Case 'Real fast-forward sync at Chinese/space path preserves config, OAuth, sessions, skills and workspace' {
        [void](Sync $client -Migration)
        foreach ($pair in @(@('data/agent/models.json','CUSTOM CONFIG SENTINEL'),@('data/agent/auth.json','API/OAUTH SENTINEL'),@('data/sessions/keep.jsonl','SESSION SENTINEL'),@('workspace/keep.txt','WORKSPACE SENTINEL'),@('data/agent/skills/custom.txt','SKILL SENTINEL'))) {
            Assert ([IO.File]::ReadAllText((Join-Path $client $pair[0])) -eq $pair[1]) "User bytes lost: $($pair[0])"
        }
        Assert (-not (G $client @('ls-files','--','data'))) 'User data still tracked'
        Assert ([IO.File]::ReadAllText((Join-Path $client 'tools/node/program.bin')) -eq 'NEW NODE PAYLOAD') 'Payload did not update'
    }
    Case 'A merge hook saving new user data preserves both versions without silent overwrite' {
        $other = Join-Path $temp 'concurrent-client'
        [void](G $temp @('clone','--branch','main',$remote,$other))
        [void](G $other @('checkout','-B','main',$legacyCommit))
        New-PortableDirectories $other
        [IO.File]::WriteAllText((Join-Path $other 'data/agent/auth.json'),'ORIGINAL AUTH')
        $hook = "#!/bin/sh`nmkdir -p data/agent`nprintf '%s' 'CONCURRENT AUTH' > data/agent/auth.json`n"
        [IO.File]::WriteAllText((Join-Path $other '.git/hooks/post-merge'),$hook,(New-Object Text.UTF8Encoding($false)))
        $blocked=$false; try { [void](Sync $other -Migration) } catch { $blocked=$_.Exception.Message -match 'Concurrent user-data edits preserved' }
        Assert $blocked 'Concurrent edit was not reported'
        Assert ([IO.File]::ReadAllText((Join-Path $other 'data/agent/auth.json')) -eq 'CONCURRENT AUTH') 'Concurrent user bytes were overwritten'
        $copies=@(Get-ChildItem -LiteralPath (Join-Path $other 'updater/sync-backups') -Filter auth.json -Recurse -File)
        Assert ($copies.Count -eq 1 -and [IO.File]::ReadAllText($copies[0].FullName) -eq 'ORIGINAL AUTH') 'Original user bytes were not retained'
    }
    Case 'Local tracked modifications block sync without overwrite' {
        $path = Join-Path $client 'tools/node/program.bin'
        [IO.File]::WriteAllText($path,'LOCAL EDIT')
        $failed=$false; try { [void](Sync $client) } catch { $failed=$true }
        Assert $failed 'Local tracked edit accepted'
        Assert ([IO.File]::ReadAllText($path) -eq 'LOCAL EDIT') 'Local edit overwritten'
        [void](G $client @('restore','--','tools/node/program.bin'))
    }
    Case 'Ignored local file collision blocks fast-forward before files change' {
        [IO.File]::WriteAllText((Join-Path $seed 'incoming.txt'),'REMOTE FILE')
        Commit $seed 'new incoming file'; [void](G $seed @('push','origin','main'))
        [IO.File]::AppendAllText((Join-Path $client '.git/info/exclude'),"`nincoming.txt`n")
        [IO.File]::WriteAllText((Join-Path $client 'incoming.txt'),'LOCAL IGNORED FILE')
        $head=G $client @('rev-parse','HEAD')
        $failed=$false; try { [void](Sync $client) } catch { $failed=$true }
        Assert $failed 'Ignored collision accepted'
        Assert ((G $client @('rev-parse','HEAD')) -eq $head) 'HEAD changed despite collision'
        Assert ([IO.File]::ReadAllText((Join-Path $client 'incoming.txt')) -eq 'LOCAL IGNORED FILE') 'Ignored local bytes lost'
    }
} finally {
    Write-AtomicJson (Join-Path $OutputDirectory 'test-release-pipeline.json') ([pscustomobject]@{suite='release-pipeline';powershell=$PSVersionTable.PSVersion.ToString();note='Real local Git/LFS and filesystem operations; synthetic release payloads and local remotes; native binary validation is covered by Test-Windows separately.';results=@($results.ToArray())})
    if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force }
}
if (@($results | Where-Object status -eq 'failed').Count) { exit 1 }
