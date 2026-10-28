---
name: file-organizer
description: Inventory and organize Windows user files by type or date, find large files and SHA-256 duplicates, and preview bulk moves, copies or renames before applying a journaled, reversible plan. Use for folder cleanup and space analysis.
license: MIT
compatibility: Windows PowerShell 5.1; no third-party dependencies. Reparse points and protected system/program directories are excluded from bulk changes.
---

# 智能文件整理

适用于用户文件分类、空间分析、重复文件、批量重命名和搬移。文件名相同不是内容相同；默认不删重复文件，不扫描整个系统盘后直接搬移。每个操作以用户明确的目录为范围。

## 读取与预览

```powershell
$skill = Join-Path $env:PI_CODING_AGENT_DIR 'skills/file-organizer'
$helper = Join-Path $skill 'scripts/Invoke-FileOrganizer.ps1'
# 用用户提供的实际目录赋值，不使用示例路径直接操作：
$source = 'D:\资料\待整理'
& $helper -Mode Scan -Path $source -FindDuplicates -PassThru
$plan = Join-Path $env:PI_PORTABLE_ROOT 'data/reports/my-plan.json'
& $helper -Mode Plan -Path $source -Destination 'D:\资料\分类结果' -Operation Move -Category Type -PlanPath $plan
Get-Content -LiteralPath $plan -Raw -Encoding UTF8
```

`Scan` 输出文件清单、大文件、每个目录的文件字节总和，可选先按长度缩小范围再算 SHA-256 查重复；不把硬链接逻辑字节总和当作实际磁盘已用空间。访问失败被记录。扫描跳过符号链接、junction 和其他 reparse point；超过 `MaxFiles` 明确停止，不默默漏文件。

`Plan` 只写预览 JSON，不搬移文件。支持 `-Operation Copy`、`-Category Date`（按本地修改月份），或 `-Operation Rename -RenamePrefix '照片'`。重命名保留扩展名，原目录内按排序编号。目标重名自动加后缀，绝不覆盖已存在的文件。目标在源目录内时扫描排除该目标树。

向用户展示源/目标、数量、主要分类、重名处理、是否跨盘及恢复方法。用户已明确授权具体整理规则时，展示计划后可继续；仍缺少目标目录或规则时先询问，勿替用户猜选目录。批量删除是另一项操作，需明确确认。

## 执行与恢复

```powershell
& $helper -Mode Apply -PlanPath $plan
# 日志默认在 "$plan.journal.json"；恢复：
& $helper -Mode Undo -JournalPath "$plan.journal.json"
```

执行前对所有源文件重新验证长度及 SHA-256；执行时逐项记录状态，并再次检查目标碰撞与链接。计划过期、源变化或目标已有文件时拒绝覆盖。中途失败自动尝试反向恢复，保留 journal 和 `.previous`；恢复不完整时报告具体路径并停止。不要删除 journal。

撤销移动/重命名时，只有目标内容仍匹配才移回；撤销复制时，仅在原件仍存在且哈希匹配时删除本次新建的副本。任何目标被用户修改都保留，交给用户决定。空目标文件夹可能保留。断电后使用 journal 撤销；不要重放原计划。

跨设备移动受到设备拔出、硬件写入故障影响，重要资料优先 Copy 并验证后再决定删除原件。计划和 journal 记录这次操作所在电脑的绝对路径；换电脑后先生成新计划，不自动重写恢复记录的盘符。文件内容复制不保证保留所有 NTFS ACL/备用数据流语义；这些有要求时单独选择 Windows 原生备份流程。
