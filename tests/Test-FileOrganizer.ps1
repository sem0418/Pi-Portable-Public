#requires -Version 5.1
[CmdletBinding()]
param([string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
. (Join-Path $project 'updater/scripts/Portable.Common.ps1')
$helper = Join-Path $project 'data/agent/skills/file-organizer/scripts/Invoke-FileOrganizer.ps1'
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $project 'data/reports' }
[void][IO.Directory]::CreateDirectory($OutputDirectory)
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('PiPortable-Organizer-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($testRoot)
$reports = Join-Path $testRoot 'reports'
[void][IO.Directory]::CreateDirectory($reports)
$oldRoot = $env:PI_PORTABLE_ROOT; $env:PI_PORTABLE_ROOT = $null
$script:OrganizerResults = New-Object Collections.ArrayList
function Assert-True($Condition,[string]$Message) { if (-not $Condition) { throw $Message } }
function Test-Case([string]$Name,[scriptblock]$Body) {
    try { & $Body; [void]$script:OrganizerResults.Add([pscustomobject]@{name=$Name;status='passed'}); Write-Host "[PASS] $Name" }
    catch { [void]$script:OrganizerResults.Add([pscustomobject]@{name=$Name;status='failed';error=$_.Exception.Message}); Write-Host "[FAIL] ${Name}: $($_.Exception.Message)" -ForegroundColor Red }
}
function New-Files([string]$Case) {
    $r = Join-Path $testRoot $Case
    [void][IO.Directory]::CreateDirectory((Join-Path $r '源目录 空格/子目录'))
    [IO.File]::WriteAllText((Join-Path $r '源目录 空格/甲.txt'), 'DUPLICATE-CONTENT')
    [IO.File]::WriteAllText((Join-Path $r '源目录 空格/子目录/乙.txt'), 'DUPLICATE-CONTENT')
    [IO.File]::WriteAllText((Join-Path $r '源目录 空格/照片.jpg'), 'FAKE-PHOTO-FIXTURE')
    return $r
}
try {
    Test-Case 'Read-only scan hashes duplicates and preserves Unicode files' {
        $r = New-Files 'scan'; $src = Join-Path $r '源目录 空格'
        $report = & $helper -Mode Scan -Path $src -FindDuplicates -OutputDirectory $reports -PassThru
        Assert-True $report.RequiredSucceeded 'Inventory failed'
        $dup = @($report.Report.sections | Where-Object name -eq 'duplicate-content')[0]
        Assert-True ($dup.data.Count -eq 1 -and $dup.data[0].Files.Count -eq 2) 'Duplicate detection incorrect'
        Assert-True (@(Get-ChildItem -LiteralPath $src -File -Recurse).Count -eq 3) 'Scan modified files'
    }
    foreach ($operation in @('Move','Copy','Rename')) {
        Test-Case "$operation preview, apply and content-verified undo" {
            $r = New-Files $operation; $src = Join-Path $r '源目录 空格'; $dest = Join-Path $r '分类结果'
            $planPath = Join-Path $r 'plan.json'
            [void](& $helper -Mode Plan -Path $src -Destination $dest -Operation $operation -RenamePrefix '整理后' -PlanPath $planPath -OutputDirectory $reports)
            Assert-True (@(Get-ChildItem -LiteralPath $src -File -Recurse).Count -eq 3) 'Preview changed files'
            $plan = Read-PortableJson $planPath
            [void](& $helper -Mode Apply -PlanPath $planPath -OutputDirectory $reports)
            foreach ($entry in $plan.entries) { Assert-True (Test-Path -LiteralPath $entry.destination) 'Destination missing after apply' }
            [void](& $helper -Mode Undo -JournalPath "$planPath.journal.json" -OutputDirectory $reports)
            foreach ($entry in $plan.entries) {
                Assert-True (Test-Path -LiteralPath $entry.source) 'Original not restored'
                Assert-True ((Get-FileHash -LiteralPath $entry.source).Hash -eq $entry.sha256) 'Content changed on undo'
                Assert-True (-not (Test-Path -LiteralPath $entry.destination)) 'New destination left after undo'
            }
        }
    }
    Test-Case 'Existing destination collision is preserved and renamed in preview' {
        $r = New-Files 'collision'; $src = Join-Path $r '源目录 空格'; $dest = Join-Path $r 'target'
        [void][IO.Directory]::CreateDirectory((Join-Path $dest 'txt'))
        $existing = Join-Path $dest 'txt/甲.txt'; [IO.File]::WriteAllText($existing,'PREEXISTING')
        $p = Join-Path $r 'plan.json'
        [void](& $helper -Mode Plan -Path $src -Destination $dest -PlanPath $p -OutputDirectory $reports)
        $plan = Read-PortableJson $p
        Assert-True (@($plan.entries | Where-Object destination -eq $existing).Count -eq 0) 'Preview would overwrite a file'
        [void](& $helper -Mode Apply -PlanPath $p -OutputDirectory $reports)
        Assert-True ([IO.File]::ReadAllText($existing) -eq 'PREEXISTING') 'Existing file overwritten'
    }
    Test-Case 'Changed source rejects whole plan before the first move' {
        $r = New-Files 'changed'; $src = Join-Path $r '源目录 空格'; $p = Join-Path $r 'plan.json'
        [void](& $helper -Mode Plan -Path $src -Destination (Join-Path $r 'target') -PlanPath $p -OutputDirectory $reports)
        $plan = Read-PortableJson $p; [IO.File]::AppendAllText($plan.entries[-1].source,'CHANGED')
        $blocked = $false; try { [void](& $helper -Mode Apply -PlanPath $p -OutputDirectory $reports) } catch { $blocked=$true }
        Assert-True $blocked 'Changed source accepted'
        Assert-True (@(Get-ChildItem -LiteralPath $src -File -Recurse).Count -eq 3) 'Partial move happened before validation finished'
    }
    Test-Case 'User-modified destination is never overwritten during undo' {
        $r = New-Files 'undo-changed'; $src = Join-Path $r '源目录 空格'; $p = Join-Path $r 'plan.json'
        [void](& $helper -Mode Plan -Path $src -Destination (Join-Path $r 'target') -PlanPath $p -OutputDirectory $reports)
        [void](& $helper -Mode Apply -PlanPath $p -OutputDirectory $reports)
        $plan = Read-PortableJson $p; $modified = $plan.entries[-1].destination
        [IO.File]::WriteAllText($modified,'USER-EDIT')
        $blocked = $false; try { [void](& $helper -Mode Undo -JournalPath "$p.journal.json" -OutputDirectory $reports) } catch { $blocked=$true }
        Assert-True $blocked 'Modified destination accepted'
        Assert-True ([IO.File]::ReadAllText($modified) -eq 'USER-EDIT') 'User edit lost'
    }
    Test-Case 'Tampered out-of-scope plan is rejected' {
        $r = New-Files 'tampered'; $p = Join-Path $r 'plan.json'
        [void](& $helper -Mode Plan -Path (Join-Path $r '源目录 空格') -Destination (Join-Path $r 'target') -PlanPath $p -OutputDirectory $reports)
        $plan = Read-PortableJson $p; $plan.entries[0].destination = Join-Path $testRoot 'escape.txt'
        Write-AtomicJson $p $plan
        $blocked = $false; try { [void](& $helper -Mode Apply -PlanPath $p -OutputDirectory $reports) } catch { $blocked=$true }
        Assert-True $blocked 'Tampered plan accepted'
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $testRoot 'escape.txt'))) 'File escaped scope'
    }
} finally {
    $env:PI_PORTABLE_ROOT = $oldRoot
    $output = Join-Path $OutputDirectory 'test-file-organizer.json'
    Write-AtomicJson $output ([pscustomobject]@{suite='file-organizer';executedAt=(Get-Date -Format o);platform=[Environment]::OSVersion.ToString();results=@($script:OrganizerResults.ToArray())})
    Write-Host "Test results: $output"
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
if (@($script:OrganizerResults | Where-Object status -eq 'failed').Count -gt 0) { exit 1 }
