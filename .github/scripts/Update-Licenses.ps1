#requires -Version 5.1
[CmdletBinding()]
param([string]$Root)
$ErrorActionPreference = 'Stop'
if (-not $Root) { $Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot) }
. (Join-Path $Root 'updater/scripts/Portable.Common.ps1')
$v = Read-PortableJson (Join-Path $Root 'updater/versions.json')
if ($v.components.pi.tag -notmatch '^v\d+\.\d+\.\d+$') { throw 'Unsafe Pi license ref' }
$uri = "https://raw.githubusercontent.com/earendil-works/pi/$($v.components.pi.tag)/LICENSE"
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
$piLicense = (Invoke-WebRequest -Uri $uri -UseBasicParsing -TimeoutSec 45).Content
if ($piLicense -notmatch 'MIT License' -or $piLicense -notmatch 'Copyright') { throw 'Pi license changed; maintainer review required before publishing an update.' }
[IO.File]::WriteAllText((Join-Path $Root 'licenses/Pi-MIT.txt'), $piLicense, (New-Object Text.UTF8Encoding($false)))
Copy-Item -LiteralPath (Join-Path $Root 'tools/node/LICENSE') -Destination (Join-Path $Root 'licenses/Node-LICENSE.txt') -Force
Copy-Item -LiteralPath (Join-Path $Root 'tools/git/LICENSE.txt') -Destination (Join-Path $Root 'licenses/Git-GPLv2.txt') -Force
Copy-Item -LiteralPath (Join-Path $Root 'tools/git/etc/package-versions.txt') -Destination (Join-Path $Root 'licenses/PortableGit-package-versions.txt') -Force
$records = @()
foreach ($name in @('pi','node','git')) {
    $spec = $v.components.$name
    $source = switch ($name) {
        'pi' { "https://github.com/earendil-works/pi/tree/$($spec.tag)" }
        'node' { "https://nodejs.org/dist/v$($spec.version)/node-v$($spec.version).tar.gz" }
        'git' { "https://github.com/git-for-windows/git/tree/$($spec.tag)" }
    }
    $records += [pscustomobject]@{ name=$name; version=$spec.version; tag=$spec.tag; archiveUrl=$spec.url; archiveSHA256=$spec.sha256; sourceReference=$source }
}
$sourceInventoryPath = Join-Path $Root 'licenses/corresponding-source.json'
$sourceInventory = Read-PortableJson $sourceInventoryPath
$sourceState = 'not-current-public-distribution-blocked'
$sourceHash = ''
$sourceMatches = $false
if ($sourceInventory -and $sourceInventory.schemaVersion -eq 2) {
    $sourceMatches = $true
    foreach ($name in @('pi','node','git')) {
        if ($sourceInventory.components.$name.version -ne $v.components.$name.version -or
            $sourceInventory.components.$name.archiveSHA256 -ne $v.components.$name.sha256) { $sourceMatches = $false }
    }
    if ($sourceInventory.gitPackageListSHA256 -ne (Get-FileHash -LiteralPath (Join-Path $Root 'tools/git/etc/package-versions.txt') -Algorithm SHA256).Hash.ToLowerInvariant()) { $sourceMatches = $false }
    $sourceHash = (Get-FileHash -LiteralPath $sourceInventoryPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($sourceMatches) { $sourceState = 'exact-inventory-pinned-source-bytes-and-public-candidate-validation-required' }
}
Write-AtomicJson (Join-Path $Root 'licenses/component-provenance.json') ([pscustomobject]@{schemaVersion=1;components=$records;gitPackageListSHA256=(Get-FileHash -LiteralPath (Join-Path $Root 'licenses/PortableGit-package-versions.txt') -Algorithm SHA256).Hash.ToLowerInvariant();correspondingSourceStatus=$sourceState;sourceInventorySHA256=$sourceHash})
$lines = @('# Third-party notices / 第三方声明','','Pi-Portable is an independent aggregation. Its original scripts use the root MIT license; bundled programs keep their own licenses. No upstream program is relicensed.','','| Component | Installed version | Preserved notices |','|---|---|---|',
    "| Pi | $($v.components.pi.version) | Pi-MIT.txt (exact release tag); runtime/pi package docs and dependency notices |",
    "| Node.js | $($v.components.node.version) | Node-LICENSE.txt; tools/node/LICENSE; original npm/Corepack dependency notices |",
    "| PortableGit | $($v.components.git.version) | Git-GPLv2.txt; tools/git/LICENSE.txt; usr/share/licenses and ucrt64/share/licenses |",'',
    'Exact binary URLs, release tags, archive hashes and source references: component-provenance.json and ../updater/versions.json. PortableGit-package-versions.txt records every shipped package version. All original license directories remain in the payload.','',
    'Public distribution requires the complete source-bearing candidate ZIP and a successful full source/Windows/privacy check. The locked snapshot includes Bun/JavaScriptCore LGPL, Rust MPL dependencies, and PortableGit GPL/LGPL/AGPL packages (including Berkeley DB). Full original licenses and matching source archives are supplied with that candidate. Metadata alone is not a source-byte check. Read SOURCE-COMPLIANCE.md and ../SOURCE-ACCESS.md. No written three-year offer is issued.','',
    '原始项目代码适用根目录 MIT；第三方 GPL/LGPL/AGPL/MPL 及宽松许可证保持原条款。只有源码、版权声明和二进制同包且完整验证通过的候选包才能用于后续公开分发；新组件版本必须重新核对源码，不能仅提供链接。', '', 'BUNDLED-DEPENDENCY-NOTICES.txt is an exact-version snapshot bound by corresponding-source.json. It is not evidence for a newer component until that source inventory is refreshed.', '',
    "Source preparation state: $sourceState. Inventory SHA-256: $sourceHash.", '',
    'Files named original-* and Pi-SHA256SUMS.txt are historical evidence for the original 1.0.0 build only. They are not the current-version authority. Every cloud update regenerates this notice and the current provenance from installed metadata.','')
[IO.File]::WriteAllText((Join-Path $Root 'licenses/THIRD-PARTY-NOTICES.md'), ($lines -join "`n"), (New-Object Text.UTF8Encoding($false)))
