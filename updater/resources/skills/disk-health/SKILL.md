---
name: disk-health
description: Inspect Windows disks, partitions, free space, filesystem dirty flags, storage reliability counters, available SMART prediction and disk error events. Use for slow disks, full volumes or suspected storage failure; missing SMART is not a healthy result.
license: MIT
compatibility: Windows PowerShell 5.1 and Windows native CIM/Storage commands; USB bridges, controllers, drivers and privileges can limit reliability data.
---

# 磁盘与存储诊断

适用于空间不足、磁盘占用高、读写慢、掉盘、坏块/SMART 疑虑。先识别磁盘号、盘符、总线、系统/启动标志。不要把便携 U 盘和被诊断系统盘混淆。

```powershell
$skill = Join-Path $env:PI_CODING_AGENT_DIR 'skills/disk-health'
$r = & (Join-Path $skill 'scripts/Collect-DiskHealth.ps1') -PassThru
Get-Content -LiteralPath $r.Path -Raw -Encoding UTF8
```

脚本只读：Win32_LogicalDisk、Get-Disk/Get-Partition/Get-PhysicalDisk、Get-StorageReliabilityCounter、旧式 SMART 故障预测、fsutil dirty query、性能快照及存储事件。`fsutil` 在非管理员下可能拒绝访问，保留退出码和原始输出。

## 解释规则

- 分别报告卷空间、文件系统状态、设备可靠性与性能；一个维度正常不代表另外三个正常。
- SMART/可靠性信息缺失、USB 转接不透传、权限不足、字段为空/0 必须标为“不支持/未获取/语义待核实”；不能据此写“磁盘健康”。旧式 `PredictFailure=False` 只表示该接口未报告预测故障。
- `HealthStatus=Healthy` 是 Windows 当前状态，并不能排除间歇故障。持续增多的不可纠正错误、磁盘重置、掉盘等更需要备份和进一步检查。
- `PercentDiskTime` 可能超过 100，多设备/多队列不可按简单百分比判坏。用多次采样、队列和读写延迟对照症状；平均延迟为空或零要保留原值。

```powershell
1..3 | ForEach-Object {
    Get-CimInstance Win32_PerfFormattedData_PerfDisk_PhysicalDisk |
        Select-Object Name,DiskBytesPersec,AvgDisksecPerRead,AvgDisksecPerWrite,CurrentDiskQueueLength
    Start-Sleep -Seconds 2
}
# 用户已要求进一步文件系统检查、确认卷标识后，管理员可运行：
# chkdsk.exe D:               # 默认检查，不带 /f /r /x
# Repair-Volume -DriveLetter D -Scan   # 在线检查，可能产生扫描负载
```

容量分析用 `file-organizer` 扫描具体用户目录。发现可能物理故障时优先保存重要资料，避免立即全盘哈希、长时测试或 `chkdsk /r` 增加负荷。

不得自动执行格式化、初始化磁盘、清盘、改分区、强制卸载、`chkdsk /f /r /x` 或文件系统修复。重大或不可逆操作需先说明磁盘身份、影响和备份，再确认。不要为了“优化”对 SSD 或 USB 设备盲目运行碎片整理。
