#requires -Version 5.1
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Get-PortableRoot {
    [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
}
function Get-PropertyValue($Object, [string]$Name, $Default = $null) {
    if ($null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name]) { return $Object.$Name }
    return $Default
}
function Set-ObjectProperty($Object, [string]$Name, $Value) {
    $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
}
function Read-PortableJson([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try { return ([IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8) | ConvertFrom-Json) }
    catch { throw "JSON is invalid; preserved without modification: $Path" }
}
function Write-AtomicJson([string]$Path, $Value) {
    $parent = Split-Path -Parent $Path
    [void][IO.Directory]::CreateDirectory($parent)
    $tmp = "$Path.tmp-$([guid]::NewGuid().ToString('N'))"
    try {
        $text = ConvertTo-Json -InputObject $Value -Depth 80
        [IO.File]::WriteAllText($tmp, $text, (New-Object Text.UTF8Encoding($false)))
        if ([IO.File]::Exists($Path)) {
            # Replace keeps the old file if the operation fails. Same-volume rename.
            try { [IO.File]::Replace($tmp, $Path, "$Path.previous", $true) }
            catch {
                if ($env:OS -ne 'Windows_NT') { throw }
                # FAT/exFAT may not support ReplaceFile. MoveFileEx supports replacing
                # a same-volume filename; preserve the old metadata before the rename.
                if (-not ('PiPortable.AtomicFile' -as [type])) {
                    Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; namespace PiPortable { public static class AtomicFile { [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] public static extern bool MoveFileEx(string source, string destination, int flags); } }'
                }
                [IO.File]::Copy($Path, "$Path.previous", $true)
                if (-not [PiPortable.AtomicFile]::MoveFileEx($tmp, $Path, 9)) { throw (New-Object ComponentModel.Win32Exception) }
            }
        } else { [IO.File]::Move($tmp, $Path) }
    } finally { if ([IO.File]::Exists($tmp)) { [IO.File]::Delete($tmp) } }
}
function New-PortableDirectories([string]$Root) {
    @('runtime','tools/bin','data/agent/skills','data/agent/prompts','data/agent/extensions',
      'data/agent/npm','data/agent/git','data/sessions','data/packages','data/npm-cache',
      'data/npm-global','data/git','data/home','data/home/AppData/Roaming',
      'data/home/AppData/Local','data/temp','data/reports','workspace',
      'updater/downloads','updater/backups','updater/logs','updater/staging','updater/manifests') |
        ForEach-Object { [void][IO.Directory]::CreateDirectory((Join-Path $Root $_)) }
}
function Initialize-PortableDefaults([string]$Root) {
    # Only missing files are seeded; settings, credentials and custom skills win.
    New-PortableDirectories $Root
    $agentRules = Join-Path $Root 'data/agent/AGENTS.md'
    $template = Join-Path $Root 'updater/resources/defaults/AGENTS.md'
    if (-not (Test-Path -LiteralPath $agentRules) -and (Test-Path -LiteralPath $template)) {
        Copy-Item -LiteralPath $template -Destination $agentRules
    }
    $manifest = Read-PortableJson (Join-Path $Root 'updater/skills-manifest.json')
    if ($manifest) {
        foreach ($file in @($manifest.files)) {
            $dest = Join-Path (Join-Path $Root 'data/agent/skills') $file.path
            if (Test-Path -LiteralPath $dest) { continue }
            $src = Join-Path (Join-Path $Root 'updater/resources/skills') $file.path
            if (-not (Test-Path -LiteralPath $src) -or
                (Get-FileHash -LiteralPath $src -Algorithm SHA256).Hash.ToLowerInvariant() -ne $file.sha256) {
                throw "Invalid default skill resource: $($file.path). Existing user files preserved."
            }
            [void][IO.Directory]::CreateDirectory((Split-Path -Parent $dest))
            Copy-Item -LiteralPath $src -Destination $dest
        }
    }
}
function Set-PortableEnvironment([string]$Root) {
    New-PortableDirectories $Root
    Ensure-PortableShims $Root
    $env:PI_PORTABLE_ROOT = $Root
    $env:PI_CODING_AGENT_DIR = Join-Path $Root 'data/agent'
    $env:PI_CODING_AGENT_SESSION_DIR = Join-Path $Root 'data/sessions'
    # Official semantic: runtime assets, NEVER the user package/cache directory.
    $env:PI_PACKAGE_DIR = Join-Path $Root 'runtime/pi'
    $env:NPM_CONFIG_CACHE = Join-Path $Root 'data/npm-cache'
    $env:NPM_CONFIG_PREFIX = Join-Path $Root 'data/npm-global'
    $env:NPM_CONFIG_USERCONFIG = Join-Path $Root 'data/home/.npmrc'
    $env:NPM_CONFIG_UPDATE_NOTIFIER = 'false'
    $env:GIT_CONFIG_GLOBAL = Join-Path $Root 'data/git/config'
    $env:GIT_CONFIG_SYSTEM = Join-Path $Root 'tools/git/etc/gitconfig'
    $env:GIT_TERMINAL_PROMPT = '1'
    $env:HOME = Join-Path $Root 'data/home'
    $env:USERPROFILE = $env:HOME
    $env:HOMEDRIVE = [IO.Path]::GetPathRoot($env:HOME).TrimEnd('\')
    $env:HOMEPATH = $env:HOME.Substring([IO.Path]::GetPathRoot($env:HOME).Length - 1)
    $env:APPDATA = Join-Path $env:HOME 'AppData/Roaming'
    $env:LOCALAPPDATA = Join-Path $env:HOME 'AppData/Local'
    $env:XDG_CONFIG_HOME = Join-Path $env:HOME '.config'
    $env:XDG_CACHE_HOME = Join-Path $env:HOME '.cache'
    $env:XDG_DATA_HOME = Join-Path $env:HOME '.local/share'
    $env:TEMP = Join-Path $Root 'data/temp'
    $env:TMP = $env:TEMP
    $env:COREPACK_HOME = Join-Path $Root 'data/packages/corepack'
    $prefix = @('tools/bin','tools/node','data/npm-global','tools/git/cmd',
        'tools/git/bin','tools/git/usr/bin','tools/git/ucrt64/bin','runtime/pi') |
        ForEach-Object { Join-Path $Root $_ }
    # Machine PATH is never changed. Keep Windows administration commands accessible.
    if ($env:SystemRoot) {
        $prefix += @( (Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0'),
                     (Join-Path $env:SystemRoot 'System32'), $env:SystemRoot )
    }
    $env:PATH = (@($prefix) + @($env:PATH)) -join [IO.Path]::PathSeparator
    [Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
    $global:OutputEncoding = New-Object Text.UTF8Encoding($false)
}
function Ensure-PortableShims([string]$Root) {
    $utf8 = New-Object Text.UTF8Encoding($false)
    foreach ($cli in @('npm','npx')) {
        $path = Join-Path $Root "tools/bin/$cli.cmd"
        if (-not (Test-Path -LiteralPath $path)) {
            $body = "@echo off`r`n`"%~dp0..\node\node.exe`" `"%~dp0..\node\node_modules\npm\bin\$cli-cli.js`" %*`r`nexit /b %ERRORLEVEL%`r`n"
            [IO.File]::WriteAllText($path, $body, $utf8)
        }
    }
    $piShim = Join-Path $Root 'tools/bin/pi.cmd'
    if (-not (Test-Path -LiteralPath $piShim)) {
        [IO.File]::WriteAllText($piShim, "@echo off`r`n`"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe`" -NoLogo -NoProfile -ExecutionPolicy Bypass -File `"%~dp0..\..\updater\scripts\Entry.ps1`" -Action Launch %*`r`nexit /b %ERRORLEVEL%`r`n", $utf8)
    }
}
function Update-PortableSettings([string]$Root) {
    $path = Join-Path $Root 'data/agent/settings.json'
    $settings = Read-PortableJson $path
    if ($null -eq $settings) {
        $settings = [pscustomobject]@{
            defaultTools = @('read','bash','powershell','edit','write')
            enableSkillCommands = $true
        }
    }
    if ($settings -isnot [pscustomobject]) { throw "Expected a JSON object: $path (preserved)" }
    $bash = Join-Path $Root 'tools/git/bin/bash.exe'
    if ((Get-PropertyValue $settings 'shellPath') -ne $bash -or -not (Test-Path -LiteralPath $path)) {
        Set-ObjectProperty $settings 'shellPath' $bash
        Write-AtomicJson $path $settings
    }
}
function Enter-PortableLock([string]$Root, [switch]$Exclusive) {
    $path = Join-Path $Root 'updater/operation.lock'
    if (-not [IO.File]::Exists($path)) {
        $s = [IO.File]::Open($path, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::ReadWrite)
        $s.Dispose()
    }
    try {
        if ($Exclusive) { return [IO.File]::Open($path, 'Open', 'ReadWrite', 'None') }
        return [IO.File]::Open($path, 'Open', 'Read', 'Read')
    } catch { throw 'Pi or another maintenance process is running. Close it, then retry. No files were replaced.' }
}
function ConvertTo-NativeArgument([string]$Value) {
    # CommandLineToArgvW quoting: double backslashes before quotes and at the end.
    if ($Value -notmatch '[\s"]' -and $Value.Length -gt 0) { return $Value }
    return '"' + ([regex]::Replace(([regex]::Replace($Value, '(\\*)"', '$1$1\"')), '(\\+)$', '$1$1')) + '"'
}
function Invoke-PortableNative([string]$File, [string[]]$Arguments = @(), [int]$TimeoutSeconds = 40, [string]$WorkingDirectory = '') {
    if (-not [IO.File]::Exists($File)) { throw "Required program is missing: $File" }
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $File
    $psi.Arguments = (@($Arguments | ForEach-Object { ConvertTo-NativeArgument $_ }) -join ' ')
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = New-Object Text.UTF8Encoding($false)
    $psi.StandardErrorEncoding = New-Object Text.UTF8Encoding($false)
    if ($WorkingDirectory) { $psi.WorkingDirectory = $WorkingDirectory }
    $p = New-Object Diagnostics.Process
    $p.StartInfo = $psi
    try {
        [void]$p.Start()
        $stdout = $p.StandardOutput.ReadToEndAsync()
        $stderr = $p.StandardError.ReadToEndAsync()
        if (-not $p.WaitForExit($TimeoutSeconds * 1000)) {
            try { $p.Kill() } catch { }
            throw "Program timed out after $TimeoutSeconds seconds: $File"
        }
        $p.WaitForExit()
        $result = [pscustomobject]@{ ExitCode = $p.ExitCode; Stdout = $stdout.Result; Stderr = $stderr.Result }
        if ($p.ExitCode -ne 0) { throw "Program failed ($($p.ExitCode)): $File`n$($result.Stderr)" }
        return $result
    } finally { $p.Dispose() }
}
function Get-ComponentPath([string]$Root, [string]$Name) {
    switch ($Name) {
        'pi' { Join-Path $Root 'runtime/pi' }
        'node' { Join-Path $Root 'tools/node' }
        'git' { Join-Path $Root 'tools/git' }
        default { throw "Unknown component: $Name" }
    }
}
function ConvertTo-ComponentVersion([string]$Name, [string]$Output) {
    if ($Name -eq 'git' -and $Output -match '(\d+\.\d+\.\d+)\.windows\.(\d+)') {
        $base = $Matches[1]; $revision = [int]$Matches[2]
        # Official PortableGit omits the .1 suffix for the first Windows release.
        if ($revision -eq 1) { return $base }
        return "$base.$revision"
    }
    $numeric = [regex]::Match($Output, '\d+\.\d+\.\d+(?:\.\d+)?').Value
    if (-not $numeric) { throw "Could not parse installed $Name version" }
    return $numeric
}
function Test-ComponentRuntime([string]$Name, [string]$Path) {
    switch ($Name) {
        'pi' {
            foreach ($file in @('pi.exe','package.json','theme/dark.json','photon_rs_bg.wasm')) {
                if (-not (Test-Path -LiteralPath (Join-Path $Path $file))) { throw "Pi resource missing: $file" }
            }
            # While testing staging, Pi must use STAGING assets as well.
            $saved = $env:PI_PACKAGE_DIR
            try { $env:PI_PACKAGE_DIR = $Path; (Invoke-PortableNative (Join-Path $Path 'pi.exe') @('--version')).Stdout.Trim() }
            finally { $env:PI_PACKAGE_DIR = $saved }
        }
        'node' {
            $exe = Join-Path $Path 'node.exe'
            $v = (Invoke-PortableNative $exe @('--version')).Stdout.Trim()
            [void](Invoke-PortableNative $exe @((Join-Path $Path 'node_modules/npm/bin/npm-cli.js'),'--version'))
            [void](Invoke-PortableNative $exe @((Join-Path $Path 'node_modules/npm/bin/npx-cli.js'),'--version'))
            $v
        }
        'git' {
            $v = (Invoke-PortableNative (Join-Path $Path 'cmd/git.exe') @('--version')).Stdout.Trim()
            [void](Invoke-PortableNative (Join-Path $Path 'bin/bash.exe') @('--noprofile','--norc','-c','printf portable-bash-ok'))
            $v
        }
    }
}
function Complete-PortableGitSetup([string]$Path) {
    $postInstall = Join-Path $Path 'post-install.bat'
    if (-not (Test-Path -LiteralPath $postInstall)) { return }
    $oldPath = $env:PATH; $oldSystemConfig = $env:GIT_CONFIG_SYSTEM; $oldMsystem = $env:MSYSTEM
    try {
        $env:PATH = (@('cmd','bin','ucrt64/bin','usr/bin') | ForEach-Object { Join-Path $Path $_ }) -join ';'
        $env:PATH += ';' + $oldPath
        $env:GIT_CONFIG_SYSTEM = Join-Path $Path 'etc/gitconfig'
        $env:MSYSTEM = 'UCRT64'
        Write-Host 'Completing official PortableGit first-run setup inside the portable folder...'
        [void](Invoke-PortableNative (Join-Path $env:SystemRoot 'System32/cmd.exe') @('/d','/c','call','post-install.bat') 180 $Path)
        if (Test-Path -LiteralPath $postInstall) { throw 'PortableGit post-install did not complete; run Repair.' }
        [void](Test-ComponentRuntime 'git' $Path)
    } finally { $env:PATH = $oldPath; $env:GIT_CONFIG_SYSTEM = $oldSystemConfig; $env:MSYSTEM = $oldMsystem }
}
function Initialize-PortableGit([string]$Root) {
    $path = Get-ComponentPath $Root 'git'
    if (-not (Test-Path -LiteralPath (Join-Path $path 'post-install.bat'))) { return }
    $integrity = Get-ComponentIntegrity $Root 'git'
    if (-not $integrity.Healthy) { throw 'Uninitialized Git files differ from the verified manifest. Run Repair; no post-install script was executed.' }
    Complete-PortableGitSetup $path
    $versions = Read-PortableJson (Join-Path $Root 'updater/versions.json')
    Write-AtomicJson (Join-Path $Root 'updater/manifests/git.json') (New-ComponentManifest $path $versions.components.git.version)
    Write-AtomicJson (Join-Path $Root 'updater/git-initialized.json') ([pscustomobject]@{ initializedAt=(Get-Date -Format o); version=$versions.components.git.version })
}
function Get-ComponentIntegrity([string]$Root, [string]$Name) {
    $manifest = Read-PortableJson (Join-Path $Root "updater/manifests/$Name.json")
    $issues = New-Object 'Collections.Generic.List[string]'
    if ($null -eq $manifest) { $issues.Add('Integrity manifest missing') }
    else {
        $base = Get-ComponentPath $Root $Name
        foreach ($record in @($manifest.files)) {
            $p = Join-Path $base $record.path
            if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { $issues.Add("Missing: $($record.path)"); continue }
            if ((Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant() -ne $record.sha256) {
                $issues.Add("Changed: $($record.path)")
            }
        }
    }
    return [pscustomobject]@{ Name = $Name; Healthy = ($issues.Count -eq 0); Issues = @($issues.ToArray()) }
}
function New-ComponentManifest([string]$Path, [string]$Version) {
    $records = @(Get-ChildItem -LiteralPath $Path -Recurse -File -Force | Sort-Object FullName | ForEach-Object {
        [pscustomobject]@{ path = $_.FullName.Substring($Path.TrimEnd('\','/').Length + 1).Replace('\','/');
            size = $_.Length; sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant() }
    })
    return [pscustomobject]@{ version = $Version; files = $records }
}
function Get-SkillStatus([string]$Root) {
    $manifest = Read-PortableJson (Join-Path $Root 'updater/skills-manifest.json')
    foreach ($name in @('windows-diagnostics','malware-triage','file-organizer','network-troubleshooting','disk-health','windows-repair')) {
        $dir = Join-Path $Root "data/agent/skills/$name"
        $path = Join-Path $dir 'SKILL.md'
        $issues = @()
        if (-not (Test-Path -LiteralPath $path)) { $issues += 'SKILL.md missing' }
        else {
            $text = [IO.File]::ReadAllText($path)
            if ($text -notmatch "(?m)^name: $([regex]::Escape($name))\r?$" -or $text -notmatch '(?m)^description: .+') { $issues += 'Invalid frontmatter' }
        }
        $changed = @()
        if ($manifest) {
            foreach ($f in @($manifest.files | Where-Object { $_.path.StartsWith("$name/") })) {
                $p = Join-Path (Join-Path $Root 'data/agent/skills') $f.path
                if (-not (Test-Path -LiteralPath $p)) { $issues += "Missing: $($f.path)" }
                elseif ((Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant() -ne $f.sha256) { $changed += $f.path }
            }
        }
        [pscustomobject]@{ Name = $name; Healthy = ($issues.Count -eq 0); Issues = $issues; UserChanges = $changed }
    }
}
function Find-ConfigurationPathIssues([string]$Root) {
    # Report only property names and existence, never property values or credentials.
    function Visit-Config($Value, [string]$Key, [string]$FileName) {
        if ($Value -is [string]) {
            if ($Value -match '^[A-Za-z]:[\\/]' -or $Value -match '^\\\\') {
                if (-not (Test-Path -LiteralPath $Value)) {
                    [pscustomobject]@{ File = $FileName; Property = $Key; Issue = 'Absolute path does not exist; value hidden' }
                }
            }
        } elseif ($Value -is [pscustomobject]) {
            foreach ($p in $Value.PSObject.Properties) {
                if ($p.Name -notmatch '(?i)key|token|secret|password|credential|authorization') { Visit-Config $p.Value "$Key.$($p.Name)" $FileName }
            }
        } elseif ($Value -is [System.Collections.IEnumerable]) {
            $i = 0; foreach ($v in $Value) { Visit-Config $v "$Key[$i]" $FileName; $i++ }
        }
    }
    foreach ($name in @('settings.json','models.json')) {
        $p = Join-Path $Root "data/agent/$name"
        try { $json = Read-PortableJson $p; if ($json) { Visit-Config $json '$' $name } }
        catch { [pscustomobject]@{ File = $name; Property = '$'; Issue = 'Invalid JSON; preserved' } }
    }
}
function Get-ModelConfigurationStatus([string]$Root) {
    $s = Read-PortableJson (Join-Path $Root 'data/agent/settings.json')
    $a = Read-PortableJson (Join-Path $Root 'data/agent/auth.json')
    $m = Read-PortableJson (Join-Path $Root 'data/agent/models.json')
    $hasAuth = $null -ne $a -and @($a.PSObject.Properties).Count -gt 0
    $hasModels = $null -ne $m -and $null -ne (Get-PropertyValue $m 'providers')
    [pscustomobject]@{ DefaultProvider = Get-PropertyValue $s 'defaultProvider' '(not selected)';
        DefaultModel = Get-PropertyValue $s 'defaultModel' '(not selected)';
        StoredAuthPresent = $hasAuth; CustomProvidersPresent = $hasModels;
        Note = 'Presence only. Key validity and OAuth renewal require a real model request.' }
}
