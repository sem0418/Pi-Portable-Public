---
name: network-troubleshooting
description: Diagnose Windows disconnects, DNS failures, wrong IP/gateway settings, proxies and unreachable services using native adapters, routes, resolver, TCP and event queries. Use before changing DNS or resetting networking.
license: MIT
compatibility: Windows 10/11, Windows PowerShell 5.1, native NetTCPIP/NetAdapter/DnsClient commands with command-line fallbacks.
---

# Windows 网络诊断

适用于断网、部分网站打不开、DNS 故障、代理与网络中断。区分本机链路、网关、DNS、TCP 服务和应用代理，不把“ping 不通”直接解释为完全断网。

```powershell
$skill = Join-Path $env:PI_CODING_AGENT_DIR 'skills/network-troubleshooting'
$r = & (Join-Path $skill 'scripts/Collect-Network.ps1') -Target 'example.com' -Port 443 -PassThru
Get-Content -LiteralPath $r.Path -Raw -Encoding UTF8
```

把 Target/Port 换成用户实际失败服务；该脚本会向目标发起 DNS 查询和一次直接 TCP 握手，不发送用户文件或凭证。TCP 连接观察超时为 4 秒。受代理网络中，直接 TCP 失败并不表示浏览器经代理也失败。

## 分层验证

1. 适配器是否 Up、是否插线/连 Wi-Fi；IP 是否为 APIPA `169.254.*`，是否有默认路由。先记录接口名/索引，不盲猜要操作哪个适配器。
2. 比较默认网关连通性、IP 连通性、名称解析。命令示例（`$gateway` 取实际默认路由）：

```powershell
ipconfig.exe /all
ping.exe -n 3 $gateway
Resolve-DnsName -Name 'example.com' -DnsOnly -QuickTimeout
nslookup.exe example.com
tracert.exe -d -h 12 -w 700 example.com
netsh.exe winhttp show proxy
Get-Process -Id 1234 # 用报告的 OwningProcess，PID 可能已退出或复用
```

3. 对照 HKCU 用户代理、PAC 和 WinHTTP 代理。它们作用范围不同，应用也可能使用环境变量或自己的代理。排查代理变量时仅显示是否设置和去凭证后的主机，不回显完整含用户名密码的 URL。
4. 对照故障时间的 System/WLAN 日志。无事件或 cmdlet 缺失时使用 ipconfig、route print、netstat -ano 等只读回退，并说明未采集到的字段。
5. 给出与证据对应的结论，以及下一项最小验证。ICMP 可能被防火墙拦截；一次 DNS 成功或一次握手成功不保证所有网络正常。

## 修复边界

默认脚本完全不重置网络。`ipconfig /release`、禁用网卡、修改 DNS/路由/代理、`netsh winsock reset` 和 `netsh int ip reset` 会改变系统或中断现有连接，有的需要重启。先说明受影响接口、现有值、恢复命令和重启需求，并在有相应授权时执行。不要清除用户代理配置来“试试”。`Clear-DnsClientCache` 也应说明会清除缓存，不能冒充只读诊断。
