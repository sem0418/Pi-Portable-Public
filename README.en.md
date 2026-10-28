# Pi-Portable

[简体中文](README.md) · [Quick start](docs/QUICKSTART.md) · [Validation scope](docs/VALIDATION.md) · [Sources and licenses](SOURCE-ACCESS.md)

Portable Pi for Windows x64, with Pi, Node.js, PortableGit/Git Bash and six Windows skills. A complete release ZIP runs without installing Node.js, Git or Python on the destination computer.

Project **1.1.1** contains Pi **1.4.0**, Node.js **24.22.1** and PortableGit **2.56.0.3**. This is an independent community distribution.

## Start here

1. Download `Pi-Portable-1.1.1-win-x64.zip` and `SHA256SUMS.txt` from this project's **Releases**. GitHub's automatic **Source code** archives are not the runnable distribution.
2. Extract the entire ZIP to a writable directory. Keep the sibling `Pi-Portable/`, `corresponding-source/` and `DISTRIBUTION.json`. Do not run from an archive preview.
3. Open the inner `Pi-Portable` directory and run **启动 Pi.bat**.
4. Use `/login` for your own model account and `/model` to select a model. Ctrl+S in the selector saves the default.

Requires Windows 10/11 x64, its 64-bit Windows PowerShell 5.1, a writable directory and access to your selected provider. Provider accounts, network access, quotas and charges are your own. No shared API key, OAuth credentials or user sessions are included. The approximately 1.95 GB full ZIP includes matching source; allow sufficient disk space for extraction and personal data.

## Launchers

| Launcher | Purpose |
|---|---|
| 启动 Pi.bat | Start Pi using the bundled environment |
| 检查环境.bat | Check programs, configuration paths and skills |
| 一键更新.bat | Original official-version updater, verified downloads, backup and rollback |
| 一键修复.bat | Repair missing components and restore missing default resources |
| 一键删除对话历史.bat | Separate local conversation-history maintenance |
| 一键同步.bat | Git distribution sync for real clones with an origin; not used by ordinary ZIP installs |

The existing updater remains the sole upstream Pi/Node/Git implementation. There are no scheduled upstream checks or Release watchers. Custom provider configuration is documented in `runtime/pi/docs/models.md`, with a non-secret example under `updater/resources/defaults/`.

## Data and maintenance

Personal configuration, Key/OAuth, sessions, custom skills and reports belong under `data/`; work belongs under `workspace/`. They are created as needed and must not be redistributed or committed.

Close portable programs and wait for writes before moving the whole directory. Launchers change only the process environment. External absolute paths, host credentials and system keychains are not automatically portable; OAuth may require renewed login.

Modified managed components block update/repair until replacement is explicitly authorized. Preserve your edits and recovery journals. See [quick start and troubleshooting](docs/QUICKSTART.md).

Included skills: `windows-diagnostics`, `malware-triage`, `file-organizer`, `network-troubleshooting`, `disk-health`, `windows-repair`. Use `/skill:NAME`. Diagnostic defaults are read-only, and file operations use previews/journals/undo. No automatic Defender disabling, formatting or elevation occurs.

## Integrity and licensing

Verify the ZIP's SHA-256 against `SHA256SUMS.txt`. Native Windows CI, real programs, full inventories, Chinese/space paths, exact source bytes and ZIP entries are checked. [Validation scope](docs/VALIDATION.md) distinguishes fixtures and unexecuted physical-device/live-account tests.

Keep the exact corresponding source, notices and build materials with redistributed copies. The root MIT license covers original project code; bundled works keep their own terms. See [source access](SOURCE-ACCESS.md) and [third-party notices](licenses/THIRD-PARTY-NOTICES.md).


Download the complete runnable bundle from [Releases](https://github.com/sem0418/Pi-Portable-Public/releases/latest).
