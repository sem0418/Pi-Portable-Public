---
name: windows-diagnostics
description: Diagnose Windows 10/11 slowness, crashes, unexpected restarts, slow startup, CPU or memory pressure, services and faulty devices. Collect read-only evidence and Windows event logs before proposing changes.
license: MIT
compatibility: Native Windows x64, Windows PowerShell 5.1 or later; administrative access improves some event and process queries.
---

# Windows 综合系统诊断

当用户描述卡顿、启动慢、蓝屏、异常重启、内存或 CPU 异常、设备或服务故障时使用。优先调用 Pi 原生 `powershell` 工具。`scripts/` 路径相对于本 SKILL.md 所在目录，不相对于当前工作目录。

## 先收集，再验证

1. 从用户描述提取出现时间、复现操作、近期安装或驱动变化；已有信息够用就直接收集，不为收集基础信息阻断诊断。
2. 运行以下脚本（`$skill` 必须取 Pi 提供的当前技能绝对路径；也可从环境变量动态构建）：

```powershell
$skill = Join-Path $env:PI_CODING_AGENT_DIR 'skills/windows-diagnostics'
$r = & (Join-Path $skill 'scripts/Collect-Diagnostics.ps1') -Days 3 -PassThru
Get-Content -LiteralPath $r.Path -Raw -Encoding UTF8
```

3. 检查每节 `status`、`error`、`administrator`。报告包含系统版本、启动时间、CPU 和内存采样、占内存进程、自动服务、启动项、设备错误、近期事件。`CPU` 是进程累计 CPU 秒数，不是瞬时占用率；自动服务未运行也可能属于正常延迟/触发启动。
4. 对照症状时间提出最多三个假设，并用第二次采样或针对性查询验证。例：

```powershell
1..3 | ForEach-Object {
    Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'" |
        Select-Object Name,PercentProcessorTime,PercentInterruptTime
    Start-Sleep -Seconds 2
}
Get-CimInstance Win32_Service -Filter "Name='wuauserv'" |
    Select-Object Name,State,StartMode,ExitCode,PathName
Get-WinEvent -FilterHashtable @{LogName='System';Id=41,6008,1001;StartTime=(Get-Date).AddDays(-7)} -MaxEvents 25 |
    Select-Object TimeCreated,Id,ProviderName,Message
```

5. 输出“已观察事实—可能原因—验证结果—建议”。Kernel-Power 41 仅表示上次关机不正常，不能单凭它认定电源损坏。设备错误码需要按具体设备核实；不自动卸载驱动、停用服务或终止进程。

## 错误与转接

- 日志没有匹配记录、日志未启用、权限不足分别报告；无记录不等于没有故障。默认脚本只读，不为查看日志修改系统审计设置。
- CIM 故障时用 `systeminfo.exe`、`tasklist.exe /v`、`Get-Process` 和 `Get-Service` 获取局部证据；明确哪些信息缺失。
- 可疑程序转 `malware-triage`；DNS/断网转 `network-troubleshooting`；存储延迟转 `disk-health`；组件损坏转 `windows-repair`。
- 报告默认写入便携根目录 `data/reports/`，保留原始时间与错误，避免仅给主观“健康分”。
