#requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet('Scan','Plan','Apply','Undo')][string]$Mode = 'Scan',
    [string]$Path, [string]$Destination,
    [ValidateSet('Move','Copy','Rename')][string]$Operation = 'Move',
    [ValidateSet('Type','Date')][string]$Category = 'Type',
    [string]$RenamePrefix = 'file', [string]$PlanPath, [string]$JournalPath,
    [ValidateRange(1,1000000)][int]$MaxFiles = 30000,
    [switch]$FindDuplicates, [string]$OutputDirectory, [switch]$PassThru
)
. (Join-Path $PSScriptRoot 'Report.Common.ps1')
Initialize-SkillReport 'file-organizer' $OutputDirectory

function Write-OrganizerJson([string]$File, $Value) {
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent ([IO.Path]::GetFullPath($File))))
    $tmp = "$File.tmp-$([guid]::NewGuid().ToString('N'))"
    try {
        [IO.File]::WriteAllText($tmp, (ConvertTo-Json -InputObject $Value -Depth 20), (New-Object Text.UTF8Encoding($false)))
        if ([IO.File]::Exists($File)) {
            try { [IO.File]::Replace($tmp, $File, "$File.previous", $true) }
            catch {
                if ($env:OS -ne 'Windows_NT') { throw }
                if (-not ('PiPortable.AtomicFile' -as [type])) {
                    Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; namespace PiPortable { public static class AtomicFile { [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] public static extern bool MoveFileEx(string source, string destination, int flags); } }'
                }
                [IO.File]::Copy($File, "$File.previous", $true)
                if (-not [PiPortable.AtomicFile]::MoveFileEx($tmp, $File, 9)) { throw (New-Object ComponentModel.Win32Exception) }
            }
        }
        else { [IO.File]::Move($tmp, $File) }
    } finally { if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force } }
}
function Test-PathWithin([string]$Child, [string]$Parent) {
    $c = [IO.Path]::GetFullPath($Child).TrimEnd('\','/')
    $p = [IO.Path]::GetFullPath($Parent).TrimEnd('\','/')
    return $c.Equals($p, [StringComparison]::OrdinalIgnoreCase) -or $c.StartsWith($p + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
}
function Assert-NoReparseAncestor([string]$File) {
    $current = [IO.Path]::GetFullPath($File)
    while ($current) {
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Reparse point/symlink/junction refused: $current" }
        }
        $parent = Split-Path -Parent $current
        if ($parent -eq $current) { break }
        $current = $parent
    }
}
function Get-SafeInventory([string]$RootPath, [string]$Exclude) {
    $rootItem = Get-Item -LiteralPath $RootPath -Force
    if (-not $rootItem.PSIsContainer) { throw 'Path must be a directory.' }
    Assert-NoReparseAncestor $rootItem.FullName
    $queue = New-Object 'Collections.Generic.Queue[string]'
    $queue.Enqueue($rootItem.FullName)
    $files = New-Object 'Collections.Generic.List[object]'
    $errors = New-Object 'Collections.Generic.List[object]'
    while ($queue.Count -gt 0) {
        $dir = $queue.Dequeue()
        try { $items = @(Get-ChildItem -LiteralPath $dir -Force -ErrorAction Stop) }
        catch { $errors.Add([pscustomobject]@{ Path=$dir; Error=$_.Exception.Message }); continue }
        foreach ($item in $items) {
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
            if ($Exclude -and (Test-PathWithin $item.FullName $Exclude)) { continue }
            if ($item.PSIsContainer) { $queue.Enqueue($item.FullName) }
            else {
                $files.Add($item)
                if ($files.Count -gt $MaxFiles) { throw "File limit $MaxFiles exceeded. Narrow the scope or explicitly raise MaxFiles. No plan applied." }
            }
        }
    }
    return [pscustomobject]@{ Files=$files.ToArray(); Errors=$errors.ToArray() }
}
function Assert-SafeOrganizerPlan($Plan) {
    if ($Plan.schemaVersion -ne 1 -or $Plan.operation -notin @('Move','Copy','Rename')) { throw 'Unsupported plan.' }
    $seen = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $sourceSeen = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in @($Plan.entries)) {
        if (-not (Test-PathWithin $entry.source $Plan.root) -or -not (Test-PathWithin $entry.destination $Plan.destinationRoot)) { throw 'Plan contains a path outside its declared scope.' }
        Assert-NoReparseAncestor $entry.source
        Assert-NoReparseAncestor $entry.destination
        foreach ($protected in @($env:SystemRoot,$env:ProgramFiles,${env:ProgramFiles(x86)})) {
            if ($protected -and (Test-PathWithin $entry.source $protected)) { throw 'System/program directories cannot be reorganized with this helper.' }
        }
        if ($env:PI_PORTABLE_ROOT -and (Test-PathWithin $entry.source $env:PI_PORTABLE_ROOT) -and -not (Test-PathWithin $entry.source (Join-Path $env:PI_PORTABLE_ROOT 'workspace'))) {
            throw 'Pi-Portable runtime/data directories are protected. Use a user workspace.'
        }
        if (-not $sourceSeen.Add($entry.source) -or -not $seen.Add($entry.destination)) { throw 'Duplicate source/destination in plan.' }
        if (Test-Path -LiteralPath $entry.destination) { throw "Destination already exists; no overwrite allowed: $($entry.destination)" }
        $file = Get-Item -LiteralPath $entry.source -Force
        if ($file.PSIsContainer -or $file.Length -ne $entry.length -or (Get-FileHash -LiteralPath $entry.source -Algorithm SHA256).Hash -ne $entry.sha256) {
            throw "Source changed since preview: $($entry.source). Generate a new plan."
        }
    }
}
function Undo-OrganizerJournal($Journal, [string]$File) {
    if ($Journal.schemaVersion -ne 1 -or $Journal.operation -notin @('Move','Copy','Rename')) { throw 'Invalid journal.' }
    $reverse = @($Journal.entries); [array]::Reverse($reverse)
    foreach ($entry in $reverse) {
        if ($entry.state -notin @('Done','Applying')) { continue }
        if (-not (Test-PathWithin $entry.source $Journal.root) -or -not (Test-PathWithin $entry.destination $Journal.destinationRoot)) { throw 'Journal path outside declared scope.' }
        Assert-NoReparseAncestor $entry.source
        Assert-NoReparseAncestor $entry.destination
        if (Test-Path -LiteralPath $entry.destination -PathType Leaf) {
            if ((Get-FileHash -LiteralPath $entry.destination -Algorithm SHA256).Hash -ne $entry.sha256) { throw "Destination modified; preserved for manual recovery: $($entry.destination)" }
            if ($Journal.operation -eq 'Copy' -or (Test-Path -LiteralPath $entry.source)) {
                if (-not (Test-Path -LiteralPath $entry.source -PathType Leaf) -or (Get-FileHash -LiteralPath $entry.source -Algorithm SHA256).Hash -ne $entry.sha256) {
                    throw 'Original source is absent or changed. Both paths preserved; automatic undo stopped.'
                }
                Remove-Item -LiteralPath $entry.destination -Force
            } else {
                [void][IO.Directory]::CreateDirectory((Split-Path -Parent $entry.source))
                Move-Item -LiteralPath $entry.destination -Destination $entry.source
            }
        } elseif (-not (Test-Path -LiteralPath $entry.source -PathType Leaf)) { throw 'Both original and destination are missing; manual recovery required.' }
        $entry.state = 'Undone'
        Write-OrganizerJson $File $Journal
    }
    $Journal.status = 'Undone'
    Write-OrganizerJson $File $Journal
}

if ($Mode -in @('Scan','Plan')) {
    if (-not $Path) { throw 'Scan/Plan requires -Path.' }
    $Path = (Get-Item -LiteralPath $Path -Force).FullName
    $exclude = $null
    if ($Mode -eq 'Plan' -and $Operation -ne 'Rename') {
        if (-not $Destination) { throw 'Move/Copy preview requires -Destination.' }
        $Destination = [IO.Path]::GetFullPath($Destination)
        if ($Destination.TrimEnd('\','/') -eq $Path.TrimEnd('\','/')) { throw 'Destination must differ from source.' }
        if (Test-PathWithin $Destination $Path) { $exclude = $Destination }
    }
    $inventory = Get-SafeInventory $Path $exclude
    Add-ReportSection 'file-inventory' { $inventory.Files | Select-Object FullName,Length,Extension,LastWriteTimeUtc } -Required
    Add-ReportSection 'unreadable-directories' { $inventory.Errors }
    Add-ReportSection 'largest-files' { $inventory.Files | Sort-Object Length -Descending | Select-Object -First 30 FullName,Length }
    Add-ReportSection 'directory-sizes' {
        $inventory.Files | Group-Object DirectoryName | ForEach-Object { [pscustomobject]@{ Directory=$_.Name; Files=$_.Count; Bytes=($_.Group | Measure-Object Length -Sum).Sum } } | Sort-Object Bytes -Descending
    }
    if ($FindDuplicates) {
        Add-ReportSection 'duplicate-content' {
            foreach ($group in $inventory.Files | Group-Object Length | Where-Object { $_.Count -gt 1 }) {
                $hashed = @($group.Group | ForEach-Object { [pscustomobject]@{ Path=$_.FullName; Length=$_.Length; SHA256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash } })
                $hashed | Group-Object SHA256 | Where-Object { $_.Count -gt 1 } | ForEach-Object { [pscustomobject]@{ SHA256=$_.Name; Files=$_.Group } }
            }
        }
    }
    if ($Mode -eq 'Plan') {
        if ($inventory.Errors.Count -gt 0) { throw 'Some directories could not be read. Narrow the scope before generating an executable plan.' }
        if ($RenamePrefix.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0 -or $RenamePrefix -match '[\\/:*?"<>|]' -or $RenamePrefix -match '[. ]$') { throw 'Invalid RenamePrefix.' }
        $reserved = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        $entries = @(); $sequence = 0
        foreach ($file in @($inventory.Files | Sort-Object FullName)) {
            $sequence++
            if ($Operation -eq 'Rename') {
                $folder = $file.DirectoryName
                $baseName = '{0}-{1:D5}' -f $RenamePrefix,$sequence
            } else {
                $groupName = $file.Extension.TrimStart('.').ToLowerInvariant()
                if (-not $groupName) { $groupName = 'no-extension' }
                if ($Category -eq 'Date') { $groupName = $file.LastWriteTime.ToString('yyyy-MM') }
                $folder = Join-Path $Destination $groupName
                $baseName = $file.BaseName
            }
            $dest = Join-Path $folder ($baseName + $file.Extension)
            $suffix = 1
            while ((Test-Path -LiteralPath $dest) -or $reserved.Contains($dest)) {
                $suffix++; $dest = Join-Path $folder ("${baseName}_$suffix" + $file.Extension)
            }
            [void]$reserved.Add($dest)
            $entries += [pscustomobject]@{ source=$file.FullName; destination=$dest; length=$file.Length; sha256=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash; state='Pending' }
        }
        if (-not $PlanPath) { $PlanPath = Join-Path $script:SkillOutputDirectory ("organizer-plan-$([guid]::NewGuid().ToString('N')).json") }
        if (Test-Path -LiteralPath $PlanPath) { throw 'PlanPath already exists; choose a new path.' }
        $destinationRoot = $Destination
        if ($Operation -eq 'Rename') { $destinationRoot = $Path }
        $plan = [pscustomobject]@{ schemaVersion=1; operation=$Operation; root=$Path; destinationRoot=$destinationRoot; createdAt=(Get-Date -Format o); entries=$entries }
        Write-OrganizerJson $PlanPath $plan
        Write-Host "Preview plan: $PlanPath ($($entries.Count) files). Nothing moved or copied."
        $script:SkillReport['planPath'] = $PlanPath
    }
} elseif ($Mode -eq 'Apply') {
    if (-not $PlanPath) { throw 'Apply requires -PlanPath.' }
    $plan = [IO.File]::ReadAllText($PlanPath) | ConvertFrom-Json
    Assert-SafeOrganizerPlan $plan
    if (-not $JournalPath) { $JournalPath = "$PlanPath.journal.json" }
    if (Test-Path -LiteralPath $JournalPath) { throw 'Journal already exists. Inspect/undo it; do not replay a plan.' }
    $journal = [pscustomobject]@{ schemaVersion=1; operation=$plan.operation; root=$plan.root; destinationRoot=$plan.destinationRoot; status='Applying'; entries=@($plan.entries) }
    Write-OrganizerJson $JournalPath $journal
    try {
        foreach ($entry in $journal.entries) {
            # Re-check immediately before each operation. Never overwrite a new collision.
            Assert-NoReparseAncestor $entry.source; Assert-NoReparseAncestor $entry.destination
            if (Test-Path -LiteralPath $entry.destination) { throw 'A destination appeared after validation.' }
            if ((Get-FileHash -LiteralPath $entry.source -Algorithm SHA256).Hash -ne $entry.sha256) { throw 'A source changed after validation.' }
            [void][IO.Directory]::CreateDirectory((Split-Path -Parent $entry.destination))
            $entry.state = 'Applying'; Write-OrganizerJson $JournalPath $journal
            if ($plan.operation -eq 'Copy') { Copy-Item -LiteralPath $entry.source -Destination $entry.destination }
            else { Move-Item -LiteralPath $entry.source -Destination $entry.destination }
            $entry.state = 'Done'; Write-OrganizerJson $JournalPath $journal
        }
        $journal.status = 'Done'; Write-OrganizerJson $JournalPath $journal
    } catch {
        $failure = $_.Exception.Message
        try { Undo-OrganizerJournal $journal $JournalPath }
        catch { throw "Apply failed: $failure. Automatic undo incomplete; keep journal $JournalPath. $($_.Exception.Message)" }
        throw "Apply failed and was undone: $failure. Journal retained: $JournalPath"
    }
    $script:SkillReport.mode = 'applied-plan'
    Add-ReportSection 'applied-plan' { [pscustomobject]@{ Plan=$PlanPath; Journal=$JournalPath; Files=$journal.entries.Count } } -Required
} else {
    if (-not $JournalPath) { throw 'Undo requires -JournalPath.' }
    $journal = [IO.File]::ReadAllText($JournalPath) | ConvertFrom-Json
    Undo-OrganizerJournal $journal $JournalPath
    $script:SkillReport.mode = 'undo'
    Add-ReportSection 'undo' { [pscustomobject]@{ Journal=$JournalPath; Status=$journal.status } } -Required
}
Save-SkillReport -PassThru:$PassThru
