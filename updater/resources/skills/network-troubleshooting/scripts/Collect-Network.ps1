#requires -Version 5.1
[CmdletBinding()]
param([ValidatePattern('^[A-Za-z0-9.:-]+$')][string]$Target = 'example.com', [ValidateRange(1,65535)][int]$Port = 443, [string]$OutputDirectory, [switch]$PassThru)
. (Join-Path $PSScriptRoot 'Report.Common.ps1')
Initialize-SkillReport 'network-troubleshooting' $OutputDirectory
Add-ReportSection 'adapters' { Get-NetAdapter | Select-Object Name,InterfaceDescription,Status,LinkSpeed,MacAddress,ifIndex } -Required
Add-ReportSection 'ip-configuration' { Get-NetIPConfiguration | Select-Object InterfaceAlias,InterfaceIndex,IPv4Address,IPv6Address,IPv4DefaultGateway,DNSServer }
Add-ReportSection 'dns-servers' { Get-DnsClientServerAddress | Select-Object InterfaceAlias,AddressFamily,ServerAddresses }
Add-ReportSection 'routes' { Get-NetRoute | Where-Object { $_.DestinationPrefix -in @('0.0.0.0/0','::/0') } | Select-Object InterfaceAlias,DestinationPrefix,NextHop,RouteMetric }
Add-ReportSection 'dns-resolution' {
    if (Get-Command Resolve-DnsName -ErrorAction SilentlyContinue) { Resolve-DnsName -Name $Target -DnsOnly -QuickTimeout | Select-Object Name,Type,IPAddress,NameHost }
    else { Invoke-SystemCommand (Join-Path $env:SystemRoot 'System32/nslookup.exe') @($Target) 20 }
}
Add-ReportSection 'tcp-connectivity' {
    $client = New-Object Net.Sockets.TcpClient
    try {
        $pending = $client.BeginConnect($Target, $Port, $null, $null)
        if (-not $pending.AsyncWaitHandle.WaitOne(4000)) { throw 'TCP connection timed out. This does not distinguish proxy/firewall/server failures.' }
        $client.EndConnect($pending)
        [pscustomobject]@{ Target=$Target; Port=$Port; Connected=$client.Connected; Note='Direct TCP; may fail on networks requiring an HTTP proxy.' }
    } finally { $client.Close() }
}
Add-ReportSection 'user-proxy' {
    Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' | Select-Object ProxyEnable,ProxyServer,AutoConfigURL,AutoDetect
}
Add-ReportSection 'winhttp-proxy' { Invoke-SystemCommand (Join-Path $env:SystemRoot 'System32/netsh.exe') @('winhttp','show','proxy') 20 }
Add-ReportSection 'connections' { Get-NetTCPConnection -State Established | Select-Object -First 80 LocalAddress,LocalPort,RemoteAddress,RemotePort,OwningProcess }
Add-ReportSection 'network-events' {
    Get-WinEvent -FilterHashtable @{ LogName='System'; StartTime=(Get-Date).AddDays(-2) } -MaxEvents 300 |
        Where-Object { $_.ProviderName -match 'DNS|Dhcp|Tcpip|NDIS|WLAN|Network' } | Select-Object -First 25 TimeCreated,ProviderName,Id,Message
}
Save-SkillReport -PassThru:$PassThru
