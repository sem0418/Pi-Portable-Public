# Changelog / 版本说明

## 1.1.1 — Source-bearing distribution / 完整源码分发准备

- Document the complete Release ZIP as the ordinary user install path, with first-run/account/troubleshooting guidance. Exclude private execution and audit records from public exports; privately audit all history refs and prepare a scanned parentless bootstrap snapshot before publication.
- Prepare the final `main` commit with read-only Windows CI and a release handoff: versioned ZIP, generated bilingual release notes, SHA-256 list and build-bound asset metadata. Corrupt, mismatched, duplicate or incomplete files block handoff. No tag or Release is created.
- Existing updater actually installed Pi 1.4.0, Node 24.22.1 and PortableGit 2.56.0.3 on native Windows, including the October Node/Git security fixes. No second upstream updater was added.
- Added an exact source inventory covering 171 Git package/version pairs, 147 original package source recipes, Pi/Bun/WebKit/ICU and locked npm/Rust/Go sources: 398 delivered files in total.
- Recorded the real bundled Git LFS 3.8.1 / Go 1.27.3 executable and preserved the supplier's stale package-list row with explicit source supplementation.
- Added a private preparation workflow: clean tracked-file export, PS5.1/native tests, full source hashes, redacted secret scan and a verified single binary+source ZIP. No public Release or visibility action.
- Kept original private history private. Public imports use a fresh reviewed export; no user data, private project history, backups or old diagnostic reports enter the candidate.
- Added source/relinking instructions, MPL notices, refreshed attribution, bilingual use/community documentation and publication negative tests. Full third-party recompilation, physical USB/filesystem and live-account tests are not claimed.

## 1.1.0 — Private release preparation / 私有发布准备

- Added manual native-Windows execution of the existing upstream updater, with read-only PR validation and reviewed draft update PRs.
- Kept official release checks, downloads, SHA-256 verification, compatibility, staging, backups and rollback in the existing updater.
- Fixed the existing PortableGit SFX arguments and rebuilt its recorded official package on native Windows after detecting a stale pre-initialization manifest.
- Added complete payload inventory checks, LFS restoration/upload checks, controlled staging of additions/modifications/deletions and a changed-LFS size guard.
- Added protected fast-forward local sync with explicit legacy-data backup/migration and ignored-file collision checks.
- Removed user data, diagnostics, caches, partial downloads and logs from the new tracked tree. Previously committed credentials must be revoked/rotated; history is preserved.
- Added missing-only default resource initialization. Local component edits require explicit replacement authorization.
- Added bilingual operation/release documentation and installed-version license/provenance regeneration. Public PortableGit redistribution remains blocked pending complete corresponding-source preparation.
- Tests distinguish native execution, synthetic protocol/network fixtures and unexecuted real-device/model cases; see docs/VALIDATION.md.

本版本只增加云端编排、完整性验证、安全同步和发布准备。原有更新器继续承担全部上游更新职责；没有定时同步、自动写 main、仓库公开或公开 Release。

## 1.0.0

Original portable distribution, four main launchers, transactional updater/repair, history maintenance and six Windows skills. Original build evidence remains under tests/build-results and tests/BUILD-REPORT.md and does not certify later commits.

