# Corresponding sources / 对应源码与分发条件

Use only the complete source-bearing candidate produced by **Prepare source-bearing distribution**. A successful run delivers the application, matching source bytes, original licenses and build instructions in the same ZIP. Neither the repository's ordinary source ZIP nor the inner application directory alone is this complete distribution.

## Recorded snapshot

The reviewed inventory binds Pi **1.4.0**, Node **24.22.1** and PortableGit **2.56.0.3** to their original binary archive hashes. It covers **171** distinct PortableGit package/version pairs through **147** original source packages. Those archives contain upstream source payloads, original `.SRCINFO`, `PKGBUILD`, patches and installation/build recipes. Split binary packages share their actual source package; the mapping is checked against names and versions.

Pi is MIT licensed, but its compiled executable also contains Bun and statically linked JavaScriptCore/WebKit. The inventory supplies Bun 1.3.14, its exact WebKit revision, ICU 73.2, fixed dependency archives, npm production lock closure and lol-html's locked Rust crates. Original notices and full MPL-2.0 text accompany the sources. Berkeley DB in PortableGit carries AGPL obligations; the collection includes its source and original recipes. GPL/LGPL/AGPL/MPL components keep their own terms; the root MIT license applies to this project's original code only.

PortableGit's original package list contains a stale Git LFS 3.8.0-1 row. Native Windows execution confirmed that its actual binary is **3.8.1**, Go **1.27.3**, commit `a662a6db`. The original supplier file is preserved. Additional exact LFS, Go and module sources are bound to that executable's SHA-256 under `effectiveComponents`. No standalone binary replacement or second updater was introduced.

The full source kit contains **398** archives/files, **1,699,649,188 bytes** before outer packaging. SHA-256 and size are pinned individually in `corresponding-source.json`. Original Go module `h1` and npm SRI values were checked during preparation. `BUNDLED-DEPENDENCY-NOTICES.txt`, the original notice directories and [BUILDING-SOURCES.md](BUILDING-SOURCES.md) explain attribution and rebuilding/relinking. Some supplied source closures include optional platform/build/test dependencies beyond the Windows runtime.

## Delivery and verification

The preparation workflow (also available as read-only main and same-repository PR checks) downloads **only those reviewed source versions**. It does not select or install newer Pi/Node/Git versions. The existing updater remains the sole upstream implementation.

The collector verifies every source byte, every recorded package recipe and the presence of declared upstream source payloads. Windows PowerShell 5.1 then verifies real LFS objects, every installed file, native versions, original updater/repair behavior, Chinese/space paths and existing tests. Packaging runs the full Windows source gate and a pinned, redacted secret scan, and reads back every ZIP entry to verify its hash. Seven upstream-data scanner matches were manually inspected: libmagic private-key format signatures and six Vim keyboard-encoding names. The scanner still scans those files; only the exact original file hash/size, rule and line can match the reviewed exceptions in `.github/scripts/secret-scan-reviewed.json`. Changed bytes, other lines/rules and all new findings remain blocking. A failed source, runtime, privacy or size check prevents a distributable artifact from being saved.

The resulting ZIP contains `Pi-Portable/`, `corresponding-source/` and `DISTRIBUTION.json`. Keep them together when distributing. Providing the source directly with the binary is the chosen delivery route; no written three-year source offer is issued. Do not remove source or license files from copies redistributed as this bundle. There is no restriction on modification or reverse engineering needed to debug LGPL library changes.

Normal private component updates remain possible when source evidence becomes stale. Public packaging fails until exact source records and notices are refreshed for the new installed versions. Metadata-only checks in ordinary private CI explicitly do **not** verify source delivery. Hashes and native tests do not claim legal advice, bit-for-bit third-party reproducibility or a completed rebuild of every third-party program.

## Privacy and publication

The export uses the current tracked file allowlist and excludes project `.git`, user `data`, workspace, sessions, API/OAuth secrets, maintenance downloads/backups/logs and old diagnostic reports. Tests run on a separate disposable copy so their generated data cannot enter the pristine export. Source archives may retain original upstream Git objects where required by a package recipe; these are third-party source material, not this project's private history.

Public repositories must start with a fresh reviewed history. Never mirror unrelated private branches, tags or pull-request refs. A clean export does not revoke credentials in other copies; revoke exposed credentials at their provider. Server cache/PR-ref removal and external clones are separate from checking this ZIP.

Preparation creates verified artifacts and does not itself change repository visibility or create a GitHub Release. Actual publication is a separate authorized action. Physical USB/filesystem/drive-letter tests, real model/OAuth tests and full third-party recompilation remain outside the automated acceptance evidence; see [VALIDATION.md](../docs/VALIDATION.md).

中文：精确源码、版权声明和二进制同包交付；只认完整检查成功后产生的候选包。当前源码清单覆盖实际安装版本，新版本必须重新核对。公开仓库从干净导出建立新历史，不能镜像私人引用。本工作流没有公开仓库或发布 Release 的功能。

