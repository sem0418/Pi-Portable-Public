#requires -Version 5.1
[CmdletBinding()]
param([int]$MaxNewLfsMiB = 512)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $root 'updater/scripts/Portable.Release.ps1')
$git = (Get-Command git.exe -CommandType Application | Select-Object -First 1).Source
if ($env:GITHUB_ACTIONS -ne 'true' -or $env:GITHUB_EVENT_NAME -ne 'workflow_dispatch') { throw 'Publishing is restricted to explicit workflow_dispatch runs.' }
if ($env:GITHUB_REF_NAME -ne $env:PORTABLE_DEFAULT_BRANCH) { throw 'Dispatch from the default branch after reviewing/merging this implementation PR.' }
Assert-PortableDistribution $root -Native
$stage = Stage-PortableDistribution $root $git $MaxNewLfsMiB
if ($stage.ChangedFiles -eq 0) { Write-Host 'No release payload changes; no branch or PR created.'; exit 0 }
$branch = "portable-update/$($env:GITHUB_RUN_ID)-$($env:GITHUB_RUN_ATTEMPT)"
[void](Invoke-ReleaseGit $root @('switch','-c',$branch) $git)
[void](Invoke-ReleaseGit $root @('config','user.name','github-actions[bot]') $git)
[void](Invoke-ReleaseGit $root @('config','user.email','41898282+github-actions[bot]@users.noreply.github.com') $git)
[void](Invoke-ReleaseGit $root @('commit','-m','Update portable components using the existing Windows updater') $git)
# Upload LFS objects first. A failed transfer cannot publish a dangling branch.
[void](Invoke-ReleaseGit $root @('lfs','fsck','--objects','HEAD') $git)
[void](Invoke-ReleaseGit $root @('lfs','push','origin',$branch) $git)
[void](Invoke-ReleaseGit $root @('push','--set-upstream','origin',$branch) $git)
$run = "$($env:GITHUB_SERVER_URL)/$($env:GITHUB_REPOSITORY)/actions/runs/$($env:GITHUB_RUN_ID)"
$body = @"
Existing Entry.ps1 -Action Update ran on a native Windows runner. It alone selected/downloaded/installed upstream versions.

Validation: Windows PowerShell 5.1, exact file manifests, native Pi/Node/Git, repair entry, relocation, existing core/rollback tests, LFS and safe-sync/staging tests. See the run and JSON artifacts for individual results, partial results and skipped cases.

Run: $run
Changed files: $($stage.ChangedFiles); conservative changed LFS bytes: $($stage.ChangedLfsBytes).

No public release is authorized. Corresponding-source preparation remains a separate public-distribution gate in licenses/SOURCE-COMPLIANCE.md.
"@
$headers = @{Authorization="Bearer $($env:GH_TOKEN)";Accept='application/vnd.github+json';'X-GitHub-Api-Version'='2022-11-28'}
$payload = @{title='Update portable components (manual Windows updater)';head=$branch;base=$env:PORTABLE_DEFAULT_BRANCH;body=$body;draft=$true} | ConvertTo-Json
try {
    $pr = Invoke-RestMethod -Uri "$($env:GITHUB_API_URL)/repos/$($env:GITHUB_REPOSITORY)/pulls" -Method Post -Headers $headers -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($payload)) -TimeoutSec 45
    "Created draft PR: $($pr.html_url)" | Tee-Object -FilePath $env:GITHUB_STEP_SUMMARY -Append
} catch {
    "Validated branch uploaded: $branch. PR creation failed; check Actions pull-request permission. $run" | Add-Content $env:GITHUB_STEP_SUMMARY
    throw 'Validated branch uploaded but PR creation failed. Enable GitHub Actions to create pull requests; do not merge without review.'
}
