#requires -Version 5.1
# Dot-source Portable.Common.ps1 before this module.
$script:UpdateLog = $null

function Write-UpdateLog([string]$Message) {
    $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssK'), $Message
    Write-Host $line
    if ($script:UpdateLog) { [IO.File]::AppendAllText($script:UpdateLog, "$line`r`n", (New-Object Text.UTF8Encoding($false))) }
}
function Get-OfficialJson([string]$Uri) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    Invoke-RestMethod -Uri $Uri -UseBasicParsing -TimeoutSec 45 -Headers @{ 'User-Agent' = 'Pi-Portable/1.0'; 'Accept' = 'application/json' }
}
function Test-NodeRequirement([string]$Version, [string]$Range) {
    $v = [version]($Version.Trim().TrimStart('v'))
    # Official Pi currently declares >=22.19.0. Fail closed on an unfamiliar range.
    $clauses = @($Range.Trim() -split '\s+')
    foreach ($clause in $clauses) {
        if ($clause -notmatch '^(>=|>|<=|<|=)?(\d+\.\d+\.\d+)$') { throw "Unsupported Pi Node.js requirement: $Range. Updater needs review; nothing installed." }
        $op = $Matches[1]; $required = [version]$Matches[2]
        switch ($op) {
            '>=' { if ($v -lt $required) { return $false } }
            '>'  { if ($v -le $required) { return $false } }
            '<=' { if ($v -gt $required) { return $false } }
            '<'  { if ($v -ge $required) { return $false } }
            default { if ($v -ne $required) { return $false } }
        }
    }
    return $true
}
function Get-ReleaseAsset($Release, [string]$Pattern) {
    if ($Release.draft -or $Release.prerelease) { throw 'Official API returned a prerelease/draft; refusing it.' }
    $assets = @($Release.assets | Where-Object { $_.name -match $Pattern })
    if ($assets.Count -ne 1) { throw "Expected exactly one stable Windows x64 asset matching $Pattern" }
    return $assets[0]
}
function Get-AssetSHA256($Release, $Asset) {
    $digest = Get-PropertyValue $Asset 'digest' ''
    if ($digest -match '^sha256:([a-fA-F0-9]{64})$') { return $Matches[1].ToLowerInvariant() }
    $sumAsset = @($Release.assets | Where-Object { $_.name -match '^(SHA256SUMS|sha256sum\.txt|SHA256SUMS\.txt)$' })
    if ($sumAsset.Count -ne 1) { throw "Official SHA-256 unavailable for $($Asset.name); refusing unverified download." }
    $raw = (Invoke-WebRequest -Uri $sumAsset[0].browser_download_url -UseBasicParsing -TimeoutSec 45 -Headers @{ 'User-Agent' = 'Pi-Portable' }).Content
    foreach ($line in ($raw -split "`n")) {
        if ($line -match '^([a-fA-F0-9]{64})\s+\*?(.+?)\r?$' -and $Matches[2] -eq $Asset.name) { return $Matches[1].ToLowerInvariant() }
    }
    throw "Official checksum entry missing: $($Asset.name)"
}
function Get-ComponentCatalog([string]$Root) {
    $catalog = [ordered]@{}
    $errors = @()
    $installedPi = $null
    try { $installedPi = Read-PortableJson (Join-Path $Root 'runtime/pi/package.json') } catch { }
    $range = '>=22.19.0'
    if ($installedPi) { $range = [string]$installedPi.engines.node }
    try {
        $r = Get-OfficialJson 'https://api.github.com/repos/earendil-works/pi/releases/latest'
        if ($r.tag_name -notmatch '^v\d+\.\d+\.\d+$') { throw 'Unexpected Pi stable tag format' }
        $a = Get-ReleaseAsset $r '^pi-windows-x64\.zip$'
        $pkg = Get-OfficialJson "https://raw.githubusercontent.com/earendil-works/pi/$($r.tag_name)/packages/coding-agent/package.json"
        $range = [string]$pkg.engines.node
        [void](Test-NodeRequirement '999.0.0' $range)
        $catalog.pi = [pscustomobject]@{ name = 'pi'; version = $r.tag_name.TrimStart('v'); tag = $r.tag_name;
            url = $a.browser_download_url; filename = $a.name; sha256 = Get-AssetSHA256 $r $a;
            size = [long]$a.size; nodeRequirement = $range }
    } catch { $errors += "pi: $($_.Exception.Message)" }
    try {
        $index = Get-OfficialJson 'https://nodejs.org/dist/index.json'
        $candidates = @($index | Where-Object { $_.lts -and $_.lts -ne $false -and $_.version -match '^v\d+\.\d+\.\d+$' -and $_.files -contains 'win-x64-zip' } | Sort-Object { [version]$_.version.TrimStart('v') } -Descending)
        $n = $null
        foreach ($candidate in $candidates) {
            if (Test-NodeRequirement $candidate.version $range) { $n = $candidate; break }
        }
        if (-not $n) { throw "No official Windows x64 LTS meets $range" }
        $filename = "node-$($n.version)-win-x64.zip"
        $url = "https://nodejs.org/dist/$($n.version)"
        $sums = (Invoke-WebRequest -Uri "$url/SHASUMS256.txt" -UseBasicParsing -TimeoutSec 45).Content
        $sha = $null
        foreach ($line in ($sums -split "`n")) {
            if ($line -match '^([a-fA-F0-9]{64})\s+\*?(.+?)\r?$' -and $Matches[2] -eq $filename) { $sha = $Matches[1].ToLowerInvariant(); break }
        }
        if (-not $sha) { throw 'Official Node SHA-256 entry missing' }
        # index.json has no package sizes; reserve a conservative download allowance.
        $catalog.node = [pscustomobject]@{ name = 'node'; version = $n.version.TrimStart('v'); tag = $n.version;
            url = "$url/$filename"; filename = $filename; sha256 = $sha; size = 60MB; npm = $n.npm }
    } catch { $errors += "node: $($_.Exception.Message)" }
    try {
        $r = Get-OfficialJson 'https://api.github.com/repos/git-for-windows/git/releases/latest'
        $a = Get-ReleaseAsset $r '^PortableGit-[0-9.]+-64-bit\.7z\.exe$'
        $version = [regex]::Match($a.name, '^PortableGit-([0-9.]+)-64-bit').Groups[1].Value
        $catalog.git = [pscustomobject]@{ name = 'git'; version = $version; tag = $r.tag_name;
            url = $a.browser_download_url; filename = $a.name; sha256 = Get-AssetSHA256 $r $a; size = [long]$a.size }
    } catch { $errors += "git: $($_.Exception.Message)" }
    return [pscustomobject]@{ Components = $catalog; Errors = $errors }
}
function Save-VerifiedDownload($Spec, [string]$Directory) {
    if ($Spec.filename -notmatch '^[A-Za-z0-9._-]+$' -or $Spec.sha256 -notmatch '^[a-f0-9]{64}$') { throw 'Invalid official asset metadata' }
    if ($Spec.url -notmatch '^https://(github\.com/|nodejs\.org/dist/)') { throw 'Unexpected download origin' }
    $path = Join-Path $Directory ("$($Spec.name)-$($Spec.version)-$($Spec.filename)")
    if (Test-Path -LiteralPath $path) {
        if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -eq $Spec.sha256) {
            Write-UpdateLog "Reusing verified archive: $($Spec.name) $($Spec.version)"; return $path
        }
        Move-Item -LiteralPath $path -Destination "$path.bad-$([guid]::NewGuid().ToString('N'))"
    }
    $tmp = "$path.partial"
    Write-UpdateLog "Downloading official $($Spec.name) $($Spec.version)"
    try {
        $oldProgress = $ProgressPreference
        try {
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -Uri $Spec.url -OutFile $tmp -UseBasicParsing -TimeoutSec 300 -Headers @{ 'User-Agent'='Pi-Portable/1.0' }
        } finally { $ProgressPreference = $oldProgress }
        $hash = (Get-FileHash -LiteralPath $tmp -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($hash -ne $Spec.sha256) { throw "SHA-256 mismatch for $($Spec.name). Nothing installed." }
        Move-Item -LiteralPath $tmp -Destination $path
        return $path
    } finally { if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force } }
}
function Expand-SafeZip([string]$Archive, [string]$Destination) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [void][IO.Directory]::CreateDirectory($Destination)
    $prefix = [IO.Path]::GetFullPath($Destination).TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
    $zip = [IO.Compression.ZipFile]::OpenRead($Archive)
    try {
        foreach ($entry in $zip.Entries) {
            $full = [IO.Path]::GetFullPath((Join-Path $Destination $entry.FullName))
            if (-not $full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe archive entry rejected' }
            if ($entry.FullName.EndsWith('/')) { [void][IO.Directory]::CreateDirectory($full); continue }
            [void][IO.Directory]::CreateDirectory((Split-Path -Parent $full))
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $full, $true)
        }
    } finally { $zip.Dispose() }
}
function Expand-ComponentArchive($Spec, [string]$Archive, [string]$Destination) {
    if ($Spec.name -eq 'git') {
        [void][IO.Directory]::CreateDirectory($Destination)
        # Official PortableGit self-extractor; no system installer or third-party extractor.
        $savedPath = $env:PATH; $savedSystem = $env:GIT_CONFIG_SYSTEM; $savedMsystem = $env:MSYSTEM
        try {
            $env:PATH = ((@('cmd','bin','ucrt64/bin','usr/bin') | ForEach-Object { Join-Path $Destination $_ }) -join ';') + ';' + $savedPath
            $env:GIT_CONFIG_SYSTEM = Join-Path $Destination 'etc/gitconfig'
            $env:MSYSTEM = 'UCRT64'
            # Git for Windows' SFX parser recognizes -y and -o. An unknown
            # -gm2 stops parsing before -o and silently uses its default folder.
            # Official extraction runs post-install; Complete below is idempotent.
            [void](Invoke-PortableNative $Archive @('-y',"-o$Destination") 240)
            if (-not (Test-Path -LiteralPath (Join-Path $Destination 'cmd/git.exe'))) {
                throw 'PortableGit self-extractor did not populate the requested staging directory.'
            }
            Complete-PortableGitSetup $Destination
        } finally { $env:PATH = $savedPath; $env:GIT_CONFIG_SYSTEM = $savedSystem; $env:MSYSTEM = $savedMsystem }
    } elseif ($Spec.name -eq 'node') {
        $unpack = "$Destination.unpack"
        Expand-SafeZip $Archive $unpack
        $nested = Join-Path $unpack "node-v$($Spec.version)-win-x64"
        if (-not (Test-Path -LiteralPath (Join-Path $nested 'node.exe'))) { throw 'Unexpected Node archive layout' }
        Move-Item -LiteralPath $nested -Destination $Destination
        Remove-Item -LiteralPath $unpack -Recurse -Force
    } else {
        Expand-SafeZip $Archive $Destination
        if (-not (Test-Path -LiteralPath (Join-Path $Destination 'pi.exe'))) { throw 'Unexpected Pi archive layout; review required' }
    }
}
function Assert-NoPortableProcesses([string]$Root) {
    $prefix = $Root.TrimEnd('\') + '\'
    $busy = @(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {
        $_.ExecutablePath -and $_.ExecutablePath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)
    })
    if ($busy.Count -gt 0) { throw 'Programs in this portable directory are still running. Close Pi, Node, Git and Bash before updating.' }
}
function Assert-FreeSpace([string]$Root, [long]$RequiredBytes) {
    $drive = New-Object IO.DriveInfo([IO.Path]::GetPathRoot($Root))
    if ($drive.AvailableFreeSpace -lt $RequiredBytes) { throw "Insufficient free space: need at least $([math]::Ceiling($RequiredBytes / 1MB)) MiB for staging and backups." }
}
function Get-UpdateSelection($Catalog, $Versions, [string[]]$RepairNames = @(), [switch]$Repair) {
    foreach ($name in @('pi','node','git')) {
        if (-not $Catalog.Contains($name)) { continue }
        $installed = Get-PropertyValue (Get-PropertyValue $Versions 'components') $name
        $local = [string](Get-PropertyValue $installed 'version' '')
        if ($Repair) {
            if ($RepairNames -contains $name) { $Catalog[$name] }
        } elseif (-not $local -or [version]$Catalog[$name].version -gt [version]$local) { $Catalog[$name] }
    }
}
function Add-RequiredNodeUpdate([string]$Root, $Specs, $Catalog, [switch]$Repair) {
    $output = @($Specs)
    if (@($output | Where-Object { $_.name -eq 'pi' }).Count -eq 0) { return $output }
    if (@($output | Where-Object { $_.name -eq 'node' }).Count -gt 0) { return $output }
    $piSpec = @($output | Where-Object { $_.name -eq 'pi' })[0]
    try {
        $nodeVersion = (Invoke-PortableNative (Join-Path $Root 'tools/node/node.exe') @('--version')).Stdout.Trim()
        if (-not (Test-NodeRequirement $nodeVersion $piSpec.nodeRequirement)) {
            if (-not $Catalog.Contains('node')) { throw 'No compatible LTS metadata available' }
            Write-UpdateLog "Node selected because Pi $($piSpec.version) requires $($piSpec.nodeRequirement); current Node is $nodeVersion."
            $output += $Catalog.node
        }
    } catch {
        if ($Repair) { throw "Repair requires a compatible portable Node.js: $($_.Exception.Message)" }
        throw "Pi update requires a compatible portable Node.js: $($_.Exception.Message)"
    }
    return $output
}
function Repair-PortableSkills([string]$Root) {
    $manifest = Read-PortableJson (Join-Path $Root 'updater/skills-manifest.json')
    if (-not $manifest) { Write-UpdateLog 'Skill manifest unavailable; no skill files changed.'; return }
    foreach ($file in @($manifest.files)) {
        $destination = Join-Path (Join-Path $Root 'data/agent/skills') $file.path
        if (Test-Path -LiteralPath $destination) { continue }
        $original = Join-Path (Join-Path $Root 'updater/resources/skills') $file.path
        if (-not (Test-Path -LiteralPath $original) -or (Get-FileHash -LiteralPath $original -Algorithm SHA256).Hash.ToLowerInvariant() -ne $file.sha256) {
            Write-UpdateLog "Cannot restore missing skill resource $($file.path): original missing or changed. No existing user files touched."
            continue
        }
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $destination))
        Copy-Item -LiteralPath $original -Destination $destination
        Write-UpdateLog "Restored missing skill resource: $($file.path). Existing user files preserved."
    }
}
function Restore-PortableTransaction([string]$Root, $Journal) {
    if ($Journal.id -notmatch '^\d{8}T\d{6}-[a-f0-9]{8}$') { throw 'Invalid transaction ID; automatic recovery refused to preserve files.' }
    $backup = Join-Path $Root "updater/backups/$($Journal.id)"
    $stage = Join-Path $Root "updater/staging/$($Journal.id)"
    $entries = @($Journal.entries)
    [array]::Reverse($entries)
    foreach ($entry in $entries) {
        $dest = Get-ComponentPath $Root $entry.name
        $old = Join-Path $backup $entry.name
        $prepared = Join-Path $stage $entry.name
        if (Test-Path -LiteralPath $old) {
            if (Test-Path -LiteralPath $dest) { Move-Item -LiteralPath $dest -Destination (Join-Path $backup ("failed-$($entry.name)-$([guid]::NewGuid().ToString('N'))")) }
            Move-Item -LiteralPath $old -Destination $dest
        } elseif (-not $entry.hadOld -and -not (Test-Path -LiteralPath $prepared) -and (Test-Path -LiteralPath $dest)) {
            Move-Item -LiteralPath $dest -Destination (Join-Path $backup ("failed-$($entry.name)-$([guid]::NewGuid().ToString('N'))"))
        }
        $oldManifest = Join-Path $backup "$($entry.name).manifest.json"
        $manifest = Join-Path $Root "updater/manifests/$($entry.name).json"
        if (Test-Path -LiteralPath $oldManifest) { Copy-Item -LiteralPath $oldManifest -Destination $manifest -Force }
        elseif (-not $entry.hadManifest -and (Test-Path -LiteralPath $manifest)) { Remove-Item -LiteralPath $manifest -Force }
    }
    $versions = Join-Path $Root 'updater/versions.json'
    $oldVersions = Join-Path $backup 'versions.before.json'
    if (Test-Path -LiteralPath $oldVersions) { Copy-Item -LiteralPath $oldVersions -Destination $versions -Force }
    elseif (-not $Journal.hadVersions -and (Test-Path -LiteralPath $versions)) { Remove-Item -LiteralPath $versions -Force }
    Set-ObjectProperty $Journal 'phase' 'RolledBack'
    Write-AtomicJson (Join-Path $backup 'transaction-result.json') $Journal
    Remove-Item -LiteralPath (Join-Path $Root 'updater/transaction.json') -Force -ErrorAction SilentlyContinue
    Write-UpdateLog 'Rollback completed. User data and workspace were not touched.'
}
function Resume-PortableTransaction([string]$Root) {
    $path = Join-Path $Root 'updater/transaction.json'
    $journal = Read-PortableJson $path
    if (-not $journal) { return }
    if ($journal.phase -eq 'Committed') {
        Write-UpdateLog 'Previous transaction committed; clearing its journal.'
        Remove-Item -LiteralPath $path -Force
    } else {
        Write-UpdateLog 'Interrupted transaction found; restoring the previous complete environment.'
        Restore-PortableTransaction $Root $journal
    }
}
function Install-PortableTransaction([string]$Root, [object[]]$Specs, [scriptblock]$AfterValidation = {}) {
    # Test hook is local-only: used by failure-injection tests, not exposed by the launcher.
    $id = (Get-Date -Format 'yyyyMMddTHHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8)
    $stage = Join-Path $Root "updater/staging/$id"
    $backup = Join-Path $Root "updater/backups/$id"
    [void][IO.Directory]::CreateDirectory($stage)
    [void][IO.Directory]::CreateDirectory($backup)
    $journal = $null
    try {
        $manifests = @{}
        foreach ($spec in $Specs) {
            $archive = Save-VerifiedDownload $spec (Join-Path $Root 'updater/downloads')
            $dest = Join-Path $stage $spec.name
            Expand-ComponentArchive $spec $archive $dest
            $actual = Test-ComponentRuntime $spec.name $dest
            $actualNumeric = ConvertTo-ComponentVersion $spec.name $actual
            if ([version]$actualNumeric -ne [version]$spec.version) { throw "Staged $($spec.name) version mismatch: expected $($spec.version), got $actual" }
            $manifests[$spec.name] = New-ComponentManifest $dest $spec.version
            Write-UpdateLog "Staged and verified: $($spec.name) $($spec.version)"
        }
        # Check the resulting pair, including components which are not being updated.
        $piDir = Get-ComponentPath $Root 'pi'
        $nodeDir = Get-ComponentPath $Root 'node'
        if (Test-Path -LiteralPath (Join-Path $stage 'pi')) { $piDir = Join-Path $stage 'pi' }
        if (Test-Path -LiteralPath (Join-Path $stage 'node')) { $nodeDir = Join-Path $stage 'node' }
        $pkg = Read-PortableJson (Join-Path $piDir 'package.json')
        $nodeVersion = (Invoke-PortableNative (Join-Path $nodeDir 'node.exe') @('--version')).Stdout.Trim()
        if (-not (Test-NodeRequirement $nodeVersion $pkg.engines.node)) { throw 'Pi and Node versions would be incompatible. Active components unchanged.' }
        $versionsPath = Join-Path $Root 'updater/versions.json'
        $hadVersions = Test-Path -LiteralPath $versionsPath
        $versions = Read-PortableJson $versionsPath
        if (-not $versions) { $versions = [pscustomobject]@{ schemaVersion = 1; components = [pscustomobject]@{} } }
        if ($hadVersions) { Copy-Item -LiteralPath $versionsPath -Destination (Join-Path $backup 'versions.before.json') }
        $entries = @()
        foreach ($spec in $Specs) {
            $mp = Join-Path $Root "updater/manifests/$($spec.name).json"
            $hadManifest = Test-Path -LiteralPath $mp
            if ($hadManifest) { Copy-Item -LiteralPath $mp -Destination (Join-Path $backup "$($spec.name).manifest.json") }
            $entries += [pscustomobject]@{ name = $spec.name; hadOld = [bool](Test-Path -LiteralPath (Get-ComponentPath $Root $spec.name)); hadManifest = [bool]$hadManifest; state = 'Pending' }
        }
        $journal = [pscustomobject]@{ id = $id; phase = 'Prepared'; hadVersions = [bool]$hadVersions; entries = $entries }
        $journalPath = Join-Path $Root 'updater/transaction.json'
        Write-AtomicJson $journalPath $journal
        foreach ($entry in $entries) {
            $dest = Get-ComponentPath $Root $entry.name
            $entry.state = 'MovingOld'; Write-AtomicJson $journalPath $journal
            if ($entry.hadOld) { Move-Item -LiteralPath $dest -Destination (Join-Path $backup $entry.name) }
            $entry.state = 'MovingNew'; Write-AtomicJson $journalPath $journal
            Move-Item -LiteralPath (Join-Path $stage $entry.name) -Destination $dest
            $entry.state = 'Installed'; Write-AtomicJson $journalPath $journal
        }
        foreach ($spec in $Specs) { [void](Test-ComponentRuntime $spec.name (Get-ComponentPath $Root $spec.name)) }
        & $AfterValidation
        foreach ($spec in $Specs) {
            Write-AtomicJson (Join-Path $Root "updater/manifests/$($spec.name).json") $manifests[$spec.name]
            Set-ObjectProperty $versions.components $spec.name $spec
        }
        Set-ObjectProperty $versions 'updatedAt' (Get-Date -Format o)
        Write-AtomicJson $versionsPath $versions
        $journal.phase = 'Committed'; Write-AtomicJson $journalPath $journal
        Copy-Item -LiteralPath $journalPath -Destination (Join-Path $backup 'transaction-result.json')
        Remove-Item -LiteralPath $journalPath -Force
        Write-UpdateLog "Committed. Previous components retained in updater/backups/$id"
    } catch {
        Write-UpdateLog "Update failed: $($_.Exception.Message)"
        if ($journal -and $journal.phase -ne 'Committed') {
            try { Restore-PortableTransaction $Root $journal }
            catch { throw "Automatic rollback could not finish. Keep this entire folder and run Repair again. $($_.Exception.Message)" }
        }
        throw
    } finally {
        if (-not (Test-Path -LiteralPath (Join-Path $Root 'updater/transaction.json')) -and (Test-Path -LiteralPath $stage)) {
            Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
function Invoke-PortableUpdate([string]$Root, [switch]$Repair, [switch]$CheckOnly, [switch]$AllowComponentReplacement) {
    $script:UpdateLog = Join-Path $Root ("updater/logs/{0}-{1}.log" -f $(if ($Repair) { 'repair' } else { 'update' }), (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Assert-NoPortableProcesses $Root
    Resume-PortableTransaction $Root
    $versions = Read-PortableJson (Join-Path $Root 'updater/versions.json')
    $damaged = @()
    if (-not $Repair) {
        if (-not $versions) { $versions = [pscustomobject]@{schemaVersion=1;components=[pscustomobject]@{}} }
        foreach ($name in @('pi','node','git')) {
            $local = Get-PropertyValue $versions.components $name
            if (-not $local) { $local = [pscustomobject]@{version=''}; Set-ObjectProperty $versions.components $name $local }
            try {
                if ($name -eq 'git') { Initialize-PortableGit $Root }
                $actual = Test-ComponentRuntime $name (Get-ComponentPath $Root $name)
                $numeric = ConvertTo-ComponentVersion $name $actual
                Set-ObjectProperty $local 'version' $numeric
                Write-UpdateLog "Installed $name reports $actual"
            } catch {
                Set-ObjectProperty $local 'version' ''
                Write-UpdateLog "Installed $name is missing or unusable; replacement needed. $($_.Exception.Message)"
            }
        }
    }
    if (-not $CheckOnly -and -not $AllowComponentReplacement) {
        foreach ($name in @('pi','node','git')) {
            $manifest = Read-PortableJson (Join-Path $Root "updater/manifests/$name.json")
            if (-not $manifest) { continue }
            $integrity = Get-ComponentIntegrity $Root $name
            $edited = @($integrity.Issues | Where-Object { $_ -like 'Changed:*' })
            $known = @{}
            foreach ($f in @($manifest.files)) { $known[$f.path] = $true }
            $base = Get-ComponentPath $Root $name
            if (Test-Path -LiteralPath $base) {
                foreach ($f in @(Get-ChildItem -LiteralPath $base -File -Recurse -Force)) {
                    $relative = $f.FullName.Substring($base.TrimEnd('\','/').Length + 1).Replace('\','/')
                    if (-not $known.ContainsKey($relative)) { $edited += "Additional: $relative" }
                }
            }
            if ($edited.Count -gt 0) {
                throw "Local $name files were modified or added. Back them up first; explicit -AllowComponentReplacement is required to replace managed components. User data is not included."
            }
        }
    }
    if ($Repair) {
        foreach ($name in @('pi','node','git')) {
            try {
                $integrity = Get-ComponentIntegrity $Root $name
                if ($name -eq 'git' -and $integrity.Healthy) { Initialize-PortableGit $Root }
                [void](Test-ComponentRuntime $name (Get-ComponentPath $Root $name))
                if (-not $integrity.Healthy) { throw ($integrity.Issues -join '; ') }
                Write-UpdateLog "$name integrity and runtime OK"
            } catch { $damaged += $name; Write-UpdateLog "$name requires repair: $($_.Exception.Message)" }
        }
        Repair-PortableSkills $Root
        foreach ($skill in @(Get-SkillStatus $Root)) {
            if (-not $skill.Healthy) { Write-UpdateLog "Skill $($skill.Name): $($skill.Issues -join '; '). Preserved; restore manually from the original ZIP." }
            if ($skill.UserChanges.Count -gt 0) { Write-UpdateLog "User-modified skill preserved: $($skill.Name)" }
        }
        foreach ($problem in @(Find-ConfigurationPathIssues $Root)) { Write-UpdateLog "Config $($problem.File) $($problem.Property): $($problem.Issue)" }
        foreach ($file in @('settings.json','models.json','auth.json')) {
            try { [void](Read-PortableJson (Join-Path $Root "data/agent/$file")) }
            catch { Write-UpdateLog "User configuration invalid and preserved: $file. Core repair can continue." }
        }
        if ($damaged.Count -eq 0) { Update-PortableSettings $Root; Write-UpdateLog 'Core repair complete; no downloads needed.'; return }
    }
    $result = Get-ComponentCatalog $Root
    foreach ($problem in @($result.Errors)) { Write-UpdateLog "Official query failed: $problem" }
    $specs = @(Get-UpdateSelection $result.Components $versions $damaged -Repair:$Repair)
    # Node is coupled only when the selected Pi release requires it.
    $specs = @(Add-RequiredNodeUpdate $Root $specs $result.Components -Repair:$Repair)
    foreach ($name in @('pi','node','git')) {
        if ($result.Components.Contains($name) -and @($specs | Where-Object { $_.name -eq $name }).Count -eq 0) { Write-UpdateLog "${name}: no download required" }
    }
    foreach ($spec in $specs) { Write-UpdateLog "Selected $($spec.name) -> $($spec.version)" }
    if ($CheckOnly) { Write-UpdateLog 'Check-only: no archives downloaded and no components replaced.' }
    elseif ($specs.Count -gt 0) {
        $bytes = 256MB
        foreach ($spec in $specs) { $bytes += [long]$spec.size * 8 }
        Assert-FreeSpace $Root $bytes
        Install-PortableTransaction $Root $specs
        Update-PortableSettings $Root
    } else { Write-UpdateLog 'No component updates needed.' }
    if ($result.Errors.Count -gt 0) { throw 'Some official queries failed. Other independent components were processed; see the log for details.' }
}
