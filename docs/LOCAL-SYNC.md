# 本地安全同步 / Safe local synchronization

## 新克隆

首次 `git clone` 和 `git lfs pull` 后，日常双击 `一键同步.bat`。它只拉取已合并到 `origin/main` 的发行版本，不检查 Pi/Node/Git 上游。请先关闭本目录中的 Pi、Node、Git 和 Bash。

脚本要求当前本地分支为 `main`、没有暂存改动或发行/源码文件改动、远程是快进。它先抓取目标 Git/LFS 对象并校验，再合并。目标若跟踪用户/临时目录、覆盖本地未跟踪或忽略的同名文件，直接拒绝。不使用 stash/reset/clean/强推。

同步要替换自带 Git 时，Windows 不允许 Git 替换自身正在运行的程序文件。脚本优先使用目录外已有 Git，否则在忽略的 `updater/sync-tools/` 中建立一次性副本，结束后删除这个临时副本。用户数据和保留的备份不清理。

## 旧版克隆首次迁移（必须先备份）

旧提交跟踪了 `data/agent/models.json`、Skills、报告和缓存。直接 pull 这个删除跟踪的提交可能删除 Git 认为未修改的本地数据，或因已修改文件而中止。因此首次迁移不要直接 pull。

1. 关闭所有便携程序，以及正在编辑/同步本目录文件的编辑器和同步软件，将完整目录另存一份。妥善保护其中的 Key/OAuth。
2. 在仓库目录的 Windows PowerShell 中执行以下引导。仅在本实现已合并后使用；它把新同步脚本放到独立 worktree，避免先覆盖当前目录的脚本或用户文件。

```powershell
git fetch --no-tags origin main
if ($LASTEXITCODE -ne 0) { throw 'fetch failed' }
$portableRoot = (Get-Location).Path
$bootstrap = Join-Path $env:TEMP ('PiPortable-sync-' + [guid]::NewGuid().ToString('N'))
$savedSmudge = $env:GIT_LFS_SKIP_SMUDGE
try {
    $env:GIT_LFS_SKIP_SMUDGE = '1'
    git worktree add --detach $bootstrap origin/main
    if ($LASTEXITCODE -ne 0) { throw 'bootstrap worktree failed' }
} finally { $env:GIT_LFS_SKIP_SMUDGE = $savedSmudge }
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$bootstrap\updater\scripts\Sync-Portable.ps1" -Root $portableRoot -MigrateLegacyData
# 成功后再移除只用于引导的 worktree；失败时保留它与备份，先读错误。
if ($LASTEXITCODE -eq 0) { git worktree remove $bootstrap }
```

3. `-MigrateLegacyData` 是明确授权的一次性迁移：复制整个 `data` 到 `updater/sync-backups/<id>/data`，逐文件核验 SHA-256；只有备份验证后，才恢复旧跟踪文件的基准内容以允许快进。合并成功或失败，都会把原始用户字节恢复并再次核验。备份保留，凭证不上传。恢复前若发现编辑器/钩子在合并期间保存了新内容，会保留当前新内容与原始备份并报告冲突，不强制覆盖。
4. `workspace` 不被触碰；若旧库竟跟踪了工作区，脚本拒绝自动迁移。重解析点也要求手工迁移。其他源码/发行改动仍然直接拒绝。

以后无需迁移开关。每次同步创建本地 `sync-backup/<id>` 恢复引用，保留之前的 Git 提交；它不代替独立的数据备份。磁盘故障、断电或异常 Git checkout 若让同步中断，保留整个目录和备份，检查 `git status`，不要用强制清理解决。

## 常见拒绝原因

| 现象 | 安全处理 |
|---|---|
| 本机运行过一键上游更新，发行文件不同 | 保留该副本/改动；在独立干净克隆使用云端同步 |
| 修改过源码或受管组件 | 显式保存/提交并处理分支；同步脚本不代替你放弃改动 |
| 存在忽略文件碰撞 | 将提示的文件另存后再试，不会自动覆盖 |
| LFS 拉取/哈希失败 | 检查认证、配额与网络，完整下载后再试 |
| 分支分叉或当前非 main | 先人工处理分支；没有自动 rebase/merge/reset |
| 锁或便携程序仍运行 | 关闭程序后重试 |

本地 Key、OAuth、会话、用户 Skills、工作区均归用户；默认更新和修复只操作受管组件，不会为迁移去重写历史会话。换盘符后的配置路径检查与运行环境仍由现有启动器负责。

## English

For a fresh clone, run `一键同步.bat` after closing portable programs. Sync only fast-forwards the current `main` branch from `origin/main`. It rejects tracked edits, staged changes, divergent history, ignored/untracked collisions, tracked remote user data and incomplete LFS. It never silently stashes, resets, cleans or force-pushes.

For the first upgrade of an old clone, back up the complete folder and use the PowerShell bootstrap above after this implementation is merged. The detached worktree supplies the new script without overwriting your old checkout. `-MigrateLegacyData` explicitly permits copying all `data`, verifying every hash, restoring the backed-up legacy tracked paths to their baseline for Git, then restoring the original user bytes even if the merge fails. The backup is retained locally. If a hook/editor saves new bytes during the merge, current bytes and the original backup are both retained and the conflict is reported. Close editors and sync tools before migration. Tracked workspaces and reparse points require manual migration.

A host Git outside the portable installation is preferred; otherwise a disposable copy is used so Windows can replace the bundled Git. A local recovery branch retains the preceding Git commit. Keep independent backups for interruption or disk failures; do not force-reset a failed synchronization.
