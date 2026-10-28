#requires -Version 5.1
[CmdletBinding()]
param([string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
. (Join-Path $project 'updater/scripts/Portable.Common.ps1')
. (Join-Path $project 'updater/scripts/Portable.Update.ps1')
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $project 'data/reports' }
[void][IO.Directory]::CreateDirectory($OutputDirectory)
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('PiPortable-Core-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($scratch)
$script:CoreResults = New-Object Collections.ArrayList
function Assert-True($Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Test-Case([string]$Name, [scriptblock]$Body) {
    try { & $Body; [void]$script:CoreResults.Add([pscustomobject]@{name=$Name;status='passed'}); Write-Host "[PASS] $Name" }
    catch { [void]$script:CoreResults.Add([pscustomobject]@{name=$Name;status='failed';error=$_.Exception.Message}); Write-Host "[FAIL] ${Name}: $($_.Exception.Message)" -ForegroundColor Red }
}
try {
    Test-Case 'Project and skill PowerShell syntax' {
        $scripts = @(Get-ChildItem -LiteralPath (Join-Path $project '.github/scripts') -Filter *.ps1 -Recurse) +
            @(Get-ChildItem -LiteralPath (Join-Path $project 'updater/scripts') -Filter *.ps1 -Recurse) +
            @(Get-ChildItem -LiteralPath (Join-Path $project 'data/agent/skills') -Filter *.ps1 -Recurse) +
            @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter *.ps1)
        foreach ($file in $scripts) {
            $tokens = $null; $errors = $null
            [void][Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
            Assert-True ($errors.Count -eq 0) ("$($file.Name): " + (@($errors | ForEach-Object { $_.Message }) -join '; '))
        }
    }
    Test-Case 'Unicode relocation preserves model settings and opaque user fields' {
        $r = Join-Path $scratch '移动目录 空格/便携工具'
        New-PortableDirectories $r
        $p = Join-Path $r 'data/agent/settings.json'
        Write-AtomicJson $p ([pscustomobject]@{ defaultProvider='example-provider'; defaultModel='my-model'; shellPath='Q:\gone\bash.exe'; custom=[pscustomobject]@{nested=@(1,2,3)}; defaultTools=@('read','write','my-user-tool') })
        $auth = Join-Path $r 'data/agent/auth.json'
        [IO.File]::WriteAllText($auth, '{"test-provider":{"type":"api_key","key":"test-only-not-a-real-credential"}}')
        $hash = (Get-FileHash -LiteralPath $auth).Hash
        Update-PortableSettings $r
        $s = Read-PortableJson $p
        Assert-True ($s.defaultModel -eq 'my-model' -and $s.defaultProvider -eq 'example-provider') 'Model settings were changed'
        Assert-True ($s.custom.nested.Count -eq 3 -and $s.defaultTools -contains 'my-user-tool') 'Opaque settings or user tools lost'
        Assert-True ($s.shellPath -eq (Join-Path $r 'tools/git/bin/bash.exe')) 'Bash path was not relocated'
        Assert-True ((Get-FileHash -LiteralPath $auth).Hash -eq $hash) 'Auth bytes changed'
    }
    Test-Case 'Invalid user settings are preserved byte for byte' {
        $r = Join-Path $scratch 'invalid'; New-PortableDirectories $r
        $p = Join-Path $r 'data/agent/settings.json'; [IO.File]::WriteAllText($p, '{broken-json')
        $hash = (Get-FileHash -LiteralPath $p).Hash
        $rejected = $false; try { Update-PortableSettings $r } catch { $rejected = $true }
        Assert-True $rejected 'Invalid JSON was not rejected'
        Assert-True ((Get-FileHash -LiteralPath $p).Hash -eq $hash) 'Invalid user data overwritten'
    }
    Test-Case 'Absolute path diagnostics redact property values and secrets' {
        $r = Join-Path $scratch 'redaction'; New-PortableDirectories $r
        Write-AtomicJson (Join-Path $r 'data/agent/models.json') ([pscustomobject]@{ apiKey='Z:\SECRET_VALUE'; certificatePath='Z:\ABSOLUTE_PATH_VALUE' })
        $text = @(Find-ConfigurationPathIssues $r) | ConvertTo-Json
        Assert-True ($text -match 'certificatePath') 'Stale file reference was not detected'
        Assert-True ($text -notmatch 'SECRET_VALUE|ABSOLUTE_PATH_VALUE') 'Secret or raw configuration value leaked'
    }
    Test-Case 'Shared launch locks exclude maintenance' {
        $r = Join-Path $scratch 'lock'; New-PortableDirectories $r
        $one = Enter-PortableLock $r; $two = Enter-PortableLock $r
        try {
            $blocked = $false; try { $bad = Enter-PortableLock $r -Exclusive; $bad.Dispose() } catch { $blocked = $true }
            Assert-True $blocked 'Exclusive maintenance lock was allowed while launches hold locks'
        } finally { $two.Dispose(); $one.Dispose() }
        $exclusive = Enter-PortableLock $r -Exclusive; $exclusive.Dispose()
    }
    Test-Case 'Node compatibility rejects old versions and unknown ranges' {
        Assert-True (Test-NodeRequirement 'v24.22.0' '>=22.19.0') 'Compatible LTS rejected'
        Assert-True (-not (Test-NodeRequirement 'v22.18.0' '>=22.19.0')) 'Incompatible runtime accepted'
        $blocked = $false; try { [void](Test-NodeRequirement 'v24.22.0' 'experimental-range') } catch { $blocked = $true }
        Assert-True $blocked 'Unrecognized requirement was guessed'
    }
    Test-Case 'Git first-release and maintenance suffixes match official asset versions' {
        Assert-True ((ConvertTo-ComponentVersion 'git' 'git version 2.57.0.windows.1') -eq '2.57.0') 'First Windows release normalized incorrectly'
        Assert-True ((ConvertTo-ComponentVersion 'git' 'git version 2.56.0.windows.2') -eq '2.56.0.2') 'Maintenance release normalized incorrectly'
    }
    Test-Case 'Archive traversal is rejected before escape' {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archive = Join-Path $scratch 'unsafe.zip'
        $z = [IO.Compression.ZipFile]::Open($archive, 'Create')
        try { [void]$z.CreateEntry('../../escape.txt') } finally { $z.Dispose() }
        $blocked = $false; try { Expand-SafeZip $archive (Join-Path $scratch 'zip/dest') } catch { $blocked = $true }
        Assert-True $blocked 'Archive traversal accepted'
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $scratch 'escape.txt'))) 'Archive escaped destination'
    }
    Test-Case 'Six skills: names, descriptions, helpers and user modifications' {
        $statuses = @(Get-SkillStatus $project)
        Assert-True ($statuses.Count -eq 6) 'Expected six built-in skills'
        foreach ($s in $statuses) { Assert-True $s.Healthy ("Invalid skill: " + $s.Name) }
    }
    Test-Case 'Verified cached archives are reused with zero network download' {
        $dir = Join-Path $scratch 'cached'; [void][IO.Directory]::CreateDirectory($dir)
        $p = Join-Path $dir 'pi-1.0.0-test.zip'; [IO.File]::WriteAllText($p, 'verified-cache-fixture')
        $spec = [pscustomobject]@{name='pi';version='1.0.0';filename='test.zip';url='https://github.com/earendil-works/pi/releases/download/test/test.zip';sha256=(Get-FileHash -LiteralPath $p).Hash.ToLowerInvariant()}
        Assert-True ((Save-VerifiedDownload $spec $dir) -eq $p) 'Verified archive was not reused'
    }
    Test-Case 'Skill repair restores missing originals and preserves user-edited files' {
        $r = Join-Path $scratch 'skill-restore'; New-PortableDirectories $r
        $name='windows-diagnostics'; $path='windows-diagnostics/scripts/helper.ps1'
        $original = Join-Path (Join-Path $r 'updater/resources/skills') $path
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $original))
        [IO.File]::WriteAllText($original, '# original helper')
        Write-AtomicJson (Join-Path $r 'updater/skills-manifest.json') ([pscustomobject]@{files=@([pscustomobject]@{path=$path;sha256=(Get-FileHash -LiteralPath $original).Hash.ToLowerInvariant()})})
        Repair-PortableSkills $r
        $dest = Join-Path (Join-Path $r 'data/agent/skills') $path
        Assert-True (Test-Path -LiteralPath $dest) 'Missing original was not restored'
        [IO.File]::WriteAllText($dest, '# USER CUSTOMIZATION')
        Repair-PortableSkills $r
        Assert-True ([IO.File]::ReadAllText($dest) -eq '# USER CUSTOMIZATION') 'User skill customization overwritten'
    }
    # Fault-injection tests mock network, extraction and Windows executable probes.
    # Filesystem renames, journals, metadata, manifests and rollback are REAL operations.
    $originals = @{}
    foreach ($fn in @('Save-VerifiedDownload','Expand-ComponentArchive','Test-ComponentRuntime','Invoke-PortableNative','Assert-NoPortableProcesses','Get-ComponentCatalog')) { $originals[$fn] = (Get-Item "Function:$fn").ScriptBlock }
    try {
        $script:DownloadCalls = 0
        Set-Item Function:script:Save-VerifiedDownload -Value { param($Spec,$Directory) $script:DownloadCalls++; return 'mock-verified-archive' }
        Set-Item Function:script:Expand-ComponentArchive -Value {
            param($Spec,$Archive,$Destination)
            [void][IO.Directory]::CreateDirectory($Destination)
            [IO.File]::WriteAllText((Join-Path $Destination 'program.bin'), 'NEW-' + $Spec.name)
            if ($Spec.name -eq 'pi') { Write-AtomicJson (Join-Path $Destination 'package.json') ([pscustomobject]@{engines=[pscustomobject]@{node='>=22.19.0'}}) }
        }
        Set-Item Function:script:Test-ComponentRuntime -Value { param($Name,$Path) if (-not (Test-Path -LiteralPath (Join-Path $Path 'program.bin'))) { throw 'mock program missing' }; return '1.1.0' }
        Set-Item Function:script:Invoke-PortableNative -Value { param($File,$Arguments,$TimeoutSeconds,$WorkingDirectory) [pscustomobject]@{Stdout='v24.22.0';Stderr='';ExitCode=0} }
        Set-Item Function:script:Assert-NoPortableProcesses -Value { param($Root) }
        $script:FixtureCatalog = [ordered]@{}
        foreach ($name in @('pi','node','git')) { $script:FixtureCatalog[$name] = [pscustomobject]@{name=$name;version='1.1.0';sha256=('0' * 64);size=1;nodeRequirement='>=22.19.0'} }
        Set-Item Function:script:Get-ComponentCatalog -Value { param($Root) [pscustomobject]@{Components=$script:FixtureCatalog;Errors=@()} }
        function New-TransactionFixture([string]$Name) {
            $r = Join-Path $scratch $Name; New-PortableDirectories $r
            $versions = [pscustomobject]@{schemaVersion=1;components=[pscustomobject]@{}}
            foreach ($n in @('pi','node','git')) {
                $dir = Get-ComponentPath $r $n; [void][IO.Directory]::CreateDirectory($dir)
                [IO.File]::WriteAllText((Join-Path $dir 'program.bin'), "OLD-$n")
                if ($n -eq 'pi') { Write-AtomicJson (Join-Path $dir 'package.json') ([pscustomobject]@{engines=[pscustomobject]@{node='>=22.19.0'}}) }
                Write-AtomicJson (Join-Path $r "updater/manifests/$n.json") (New-ComponentManifest $dir '1.0.0')
                Set-ObjectProperty $versions.components $n ([pscustomobject]@{version='1.0.0'})
            }
            Write-AtomicJson (Join-Path $r 'updater/versions.json') $versions
            [IO.File]::WriteAllText((Join-Path $r 'data/agent/settings.json'), '{"defaultModel":"keep-me","shellPath":"old"}')
            [IO.File]::WriteAllText((Join-Path $r 'data/sessions/keep.jsonl'), 'SESSION-SENTINEL')
            [IO.File]::WriteAllText((Join-Path $r 'workspace/keep.txt'), 'WORKSPACE-SENTINEL')
            return $r
        }
        Test-Case 'Local component edits require explicit replacement and keep user data' {
            $r = New-TransactionFixture 'component-edits'
            $program = Join-Path (Get-ComponentPath $r 'pi') 'program.bin'
            [IO.File]::WriteAllText($program, 'USER-EDITED-CORE')
            $extra = Join-Path (Get-ComponentPath $r 'pi') 'user-added.txt'
            [IO.File]::WriteAllText($extra, 'USER-ADDED-CORE-FILE')
            $before = $script:DownloadCalls
            $blocked=$false; try { Invoke-PortableUpdate $r -Repair } catch { $blocked=$_.Exception.Message -match 'AllowComponentReplacement' }
            Assert-True $blocked 'Modified component was silently replaced'
            Assert-True ($script:DownloadCalls -eq $before) 'Blocked replacement downloaded a component'
            Assert-True ([IO.File]::ReadAllText($program) -eq 'USER-EDITED-CORE') 'Local bytes lost despite refusal'
            Invoke-PortableUpdate $r -Repair -AllowComponentReplacement
            Assert-True (Get-ComponentIntegrity $r 'pi').Healthy 'Explicit repair did not restore the component'
            Assert-True ([IO.File]::ReadAllText((Join-Path $r 'data/sessions/keep.jsonl')) -eq 'SESSION-SENTINEL') 'Explicit core repair changed user sessions'
        }
        Test-Case 'Transaction: all components roll back after post-swap failure' {
            $r = New-TransactionFixture 'rollback'
            $before = (Get-FileHash -LiteralPath (Join-Path $r 'updater/versions.json')).Hash
            $failed = $false
            try { Install-PortableTransaction $r @($script:FixtureCatalog.Values) { throw 'Injected post-swap validation failure' } } catch { $failed = $true }
            Assert-True $failed 'Fault injection did not fail'
            foreach ($n in @('pi','node','git')) {
                Assert-True ([IO.File]::ReadAllText((Join-Path (Get-ComponentPath $r $n) 'program.bin')) -eq "OLD-$n") "Rollback lost $n"
                Assert-True (Get-ComponentIntegrity $r $n).Healthy "Rollback manifest mismatch: $n"
            }
            Assert-True ((Get-FileHash -LiteralPath (Join-Path $r 'updater/versions.json')).Hash -eq $before) 'Version record not restored'
            Assert-True ([IO.File]::ReadAllText((Join-Path $r 'data/sessions/keep.jsonl')) -eq 'SESSION-SENTINEL') 'Session changed'
            Assert-True ([IO.File]::ReadAllText((Join-Path $r 'workspace/keep.txt')) -eq 'WORKSPACE-SENTINEL') 'Workspace changed'
            Assert-True (-not (Test-Path -LiteralPath (Join-Path $r 'updater/transaction.json'))) 'Journal not completed'
        }
        Test-Case 'Transaction: successful commit retains old binaries and settings' {
            $r = New-TransactionFixture 'commit'
            $settingsHash = (Get-FileHash -LiteralPath (Join-Path $r 'data/agent/settings.json')).Hash
            Install-PortableTransaction $r @($script:FixtureCatalog.Values)
            foreach ($n in @('pi','node','git')) {
                Assert-True ([IO.File]::ReadAllText((Join-Path (Get-ComponentPath $r $n) 'program.bin')) -eq "NEW-$n") "New $n missing"
                Assert-True (Get-ComponentIntegrity $r $n).Healthy "New manifest invalid: $n"
            }
            Assert-True ((Read-PortableJson (Join-Path $r 'updater/versions.json')).components.pi.version -eq '1.1.0') 'Version not committed'
            Assert-True ((Get-FileHash -LiteralPath (Join-Path $r 'data/agent/settings.json')).Hash -eq $settingsHash) 'User config overwritten'
            $old = @(Get-ChildItem -LiteralPath (Join-Path $r 'updater/backups') -Filter program.bin -Recurse | Where-Object { [IO.File]::ReadAllText($_.FullName) -like 'OLD-*' })
            Assert-True ($old.Count -eq 3) 'Old binaries not retained'
        }
        Test-Case 'Interrupted rename recovers missing active component on next run' {
            $r = New-TransactionFixture 'interrupted'
            $id = '20261016T000000-01234567'
            $backup = Join-Path $r "updater/backups/$id"; [void][IO.Directory]::CreateDirectory($backup)
            Copy-Item -LiteralPath (Join-Path $r 'updater/versions.json') -Destination (Join-Path $backup 'versions.before.json')
            Copy-Item -LiteralPath (Join-Path $r 'updater/manifests/pi.json') -Destination (Join-Path $backup 'pi.manifest.json')
            Move-Item -LiteralPath (Get-ComponentPath $r 'pi') -Destination (Join-Path $backup 'pi')
            Write-AtomicJson (Join-Path $r 'updater/transaction.json') ([pscustomobject]@{id=$id;phase='Prepared';hadVersions=$true;entries=@([pscustomobject]@{name='pi';hadOld=$true;hadManifest=$true;state='MovingNew'})})
            Resume-PortableTransaction $r
            Assert-True (Get-ComponentIntegrity $r 'pi').Healthy 'Interrupted component not restored'
        }
        Test-Case 'Update selection: no new versions means zero archive downloads' {
            $r = New-TransactionFixture 'no-update'
            $v = Read-PortableJson (Join-Path $r 'updater/versions.json')
            foreach ($n in @('pi','node','git')) { $v.components.$n.version = '1.1.0' }
            Write-AtomicJson (Join-Path $r 'updater/versions.json') $v
            $before = $script:DownloadCalls
            Invoke-PortableUpdate $r
            Assert-True ($script:DownloadCalls -eq $before) 'An up-to-date component was downloaded'
        }
        Test-Case 'Update selection changes only components with newer official versions' {
            $versions = [pscustomobject]@{ components=[pscustomobject]@{
                pi=[pscustomobject]@{version='1.0.0'}
                node=[pscustomobject]@{version='2.0.0'}
                git=[pscustomobject]@{version='3.0.0'}
            }}
            $catalog = [ordered]@{
                pi=[pscustomobject]@{name='pi';version='1.1.0';nodeRequirement='>=22.19.0'}
                node=[pscustomobject]@{name='node';version='2.0.0'}
                git=[pscustomobject]@{name='git';version='3.0.0'}
            }
            $selected = @(Get-UpdateSelection $catalog $versions)
            Assert-True ($selected.Count -eq 1 -and $selected[0].name -eq 'pi') 'Up-to-date Node or Git was selected with Pi'
        }
        Test-Case 'Pi update adds Node only when its requirement is unmet' {
            $versions = [pscustomobject]@{ components=[pscustomobject]@{
                pi=[pscustomobject]@{version='1.0.0'}
                node=[pscustomobject]@{version='2.0.0'}
                git=[pscustomobject]@{version='3.0.0'}
            }}
            $catalog = [ordered]@{
                pi=[pscustomobject]@{name='pi';version='1.1.0';nodeRequirement='>=22.19.0'}
                node=[pscustomobject]@{name='node';version='2.0.0'}
                git=[pscustomobject]@{name='git';version='3.0.0'}
            }
            $originalNative = (Get-Item Function:Invoke-PortableNative).ScriptBlock
            $originalLog = (Get-Item Function:Write-UpdateLog).ScriptBlock
            try {
                Set-Item Function:Invoke-PortableNative -Value { param($File,$Arguments,$TimeoutSeconds,$WorkingDirectory) [pscustomobject]@{Stdout='v22.18.0';Stderr='';ExitCode=0} }
                Set-Item Function:Write-UpdateLog -Value { param($Message) }
                $selected = @(Get-UpdateSelection $catalog $versions)
                Assert-True ($selected.Count -eq 1 -and $selected[0].name -eq 'pi') 'Base selection unexpectedly included Node or Git'
                $selected = @(Add-RequiredNodeUpdate $scratch $selected $catalog)
                Assert-True (@($selected | Where-Object name -eq 'node').Count -eq 1) 'Required Node update was not selected'
                Assert-True (@($selected | Where-Object name -eq 'git').Count -eq 0) 'Git was selected as an unrelated dependency'
            } finally {
                Set-Item Function:Invoke-PortableNative -Value $originalNative
                Set-Item Function:Write-UpdateLog -Value $originalLog
            }
        }
        Test-Case 'Repair: missing core restored without changing model or sessions' {
            $r = New-TransactionFixture 'repair'
            Remove-Item -LiteralPath (Join-Path (Get-ComponentPath $r 'pi') 'program.bin')
            $before = $script:DownloadCalls
            Invoke-PortableUpdate $r -Repair
            Assert-True (Get-ComponentIntegrity $r 'pi').Healthy 'Missing core was not repaired'
            Assert-True ($script:DownloadCalls -eq ($before + 1)) 'Healthy components were downloaded during repair'
            Assert-True ((Read-PortableJson (Join-Path $r 'data/agent/settings.json')).defaultModel -eq 'keep-me') 'Model config lost'
            Assert-True ([IO.File]::ReadAllText((Join-Path $r 'data/sessions/keep.jsonl')) -eq 'SESSION-SENTINEL') 'Session lost'
        }
    } finally { foreach ($fn in $originals.Keys) { Set-Item "Function:script:$fn" -Value $originals[$fn] } }
} finally {
    $result = [pscustomobject]@{ suite='core'; executedAt=(Get-Date -Format o); platform=[Environment]::OSVersion.ToString(); powerShell=$PSVersionTable.PSVersion.ToString();
        note='Network, extraction and Windows executables are mocked ONLY in transaction fault-injection cases; no Windows runtime pass is implied.'; results=@($script:CoreResults.ToArray()) }
    $output = Join-Path $OutputDirectory 'test-core.json'
    Write-AtomicJson $output $result
    Write-Host "Test results: $output"
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force }
}
if (@($script:CoreResults | Where-Object status -eq 'failed').Count -gt 0) { exit 1 }

