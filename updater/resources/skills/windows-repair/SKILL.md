---
name: windows-repair
description: Diagnose Windows Update, servicing, system file corruption and service failures, then guide native SFC and DISM verification or repair with explicit privilege and impact handling. Use for Windows maintenance after collecting evidence.
license: MIT
compatibility: Native Windows 10/11 and Windows PowerShell 5.1; SFC/DISM maintenance needs an administrator and may require Windows Update or a matching repair source.
---

# Windows 维护与修复

适用于更新失败、系统文件损坏、组件存储错误、系统服务异常。先诊断再修复。脚本默认 `Inspect`，不修改系统；管理员命令仅在用户所授权的维护任务范围内执行。

```powershell
$skill = Join-Path $env:PI_CODING_AGENT_DIR 'skills/windows-repair'
$helper = Join-Path $skill 'scripts/Invoke-WindowsRepair.ps1'
$r = & $helper -Action Inspect -PassThru
Get-Content -LiteralPath $r.Path -Raw -Encoding UTF8
```

报告包含系统版本、更新/组件服务、待重启标志、更新事件、CBS/DISM 日志尾部和权限状态。日志缺失或无权访问要说明。BITS/wuauserv 等服务可以按触发启动，单凭未运行不判断故障。待重启应结合用户当前工作决定重启时机，不强制重启。

## 建议顺序

1. 确定错误代码、发生时间、剩余空间、最近更改、是否待重启和联网/代理情况。
2. 普通用户可完成 Inspect；需要提升时说明要运行的具体命令，由用户以管理员身份打开启动器或 PowerShell。不自动改 UAC 或执行策略。
3. 管理员只读/检查路径：

```powershell
& $helper -Action DismCheck  # DISM /Online /Cleanup-Image /CheckHealth
& $helper -Action DismScan   # DISM /Online /Cleanup-Image /ScanHealth
& $helper -Action SfcVerify  # sfc /verifyonly
```

4. 已授权修复且证据指向组件或系统文件时：

```powershell
& $helper -Action DismRestore # DISM /Online /Cleanup-Image /RestoreHealth
& $helper -Action SfcRepair   # sfc /scannow，通常在组件修复之后
```

这些操作可能耗时、联网下载修复源并写系统文件。不要并行运行多个 DISM/SFC，不中途终止或自动重试。脚本保留原始退出码；0 通常成功，3010 通常表示需要重启，其他代码按输出和 CBS/DISM 日志核实。SFC 不能只凭退出码就判定“全部修好”，必须读取它的结论。观察超时标记 TimedOut 时操作可能仍在运行，先检查进程和日志。

5. `0x800f081f` 等源文件问题需要匹配版本、版本类型和语言的合法修复源；不随便下载镜像，不在没有源的情况下循环重试。具体 `Source` 路径只能由当前电脑/用户提供的实际镜像决定。
6. 修复后重新检查相关日志、状态和原始症状，报告“执行了什么、返回了什么、哪些仍未解决”。

## 服务与配置

只读示例：`Get-Service -Name wuauserv,bits,cryptsvc,TrustedInstaller`；`sc.exe qc wuauserv`（使用 sc.exe，避免 PowerShell 的 sc 别名）。需要启动/重启服务时说明作用和依赖，保留原状态。

不要默认删除 SoftwareDistribution/Catroot2、清空组件存储、重置权限或注册表。此类操作需具体证据、影响说明和相应授权；批量删除、格式化及重大系统修改必须确认。对于用户文件和应用故障，避免用系统级大范围修复碰运气。
