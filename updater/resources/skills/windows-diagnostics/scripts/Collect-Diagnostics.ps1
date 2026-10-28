#requires -Version 5.1
[CmdletBinding()]
param([ValidateRange(1,30)][int]$Days = 3, [string]$OutputDirectory, [switch]$PassThru)
. (Join-Path $PSScriptRoot 'Report.Common.ps1')
Initialize-SkillReport 'windows-diagnostics' $OutputDirectory
Add-ReportSection 'operating-system' {
    Get-CimInstance Win32_OperatingSystem | Select-Object Caption,Version,BuildNumber,OSArchitecture,LastBootUpTime,TotalVisibleMemorySize,FreePhysicalMemory
} -Required
Add-ReportSection 'hardware' { Get-CimInstance Win32_ComputerSystem | Select-Object Manufacturer,Model,TotalPhysicalMemory,NumberOfLogicalProcessors }
Add-ReportSection 'cpu-sample' {
    Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'" | Select-Object Name,PercentProcessorTime,PercentPrivilegedTime,PercentInterruptTime
}
Add-ReportSection 'memory-sample' { Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory | Select-Object AvailableMBytes,PercentCommittedBytesInUse,PagesPersec }
Add-ReportSection 'processes-by-working-set' {
    Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 25 Id,ProcessName,CPU,WorkingSet64,Path,StartTime
}
Add-ReportSection 'automatic-services-not-running' {
    Get-CimInstance Win32_Service -Filter "StartMode='Auto' AND State<>'Running'" | Select-Object Name,DisplayName,State,StartMode,ExitCode,PathName
}
Add-ReportSection 'startup-entries' { Get-StartupEntries }
Add-ReportSection 'boot-performance' {
    Get-WinEvent -FilterHashtable @{ LogName='Microsoft-Windows-Diagnostics-Performance/Operational'; Id=100,101,102,103,110; StartTime=(Get-Date).AddDays(-$Days) } -MaxEvents 25 | Select-Object TimeCreated,Id,LevelDisplayName,Message
}
Add-ReportSection 'system-errors-and-restarts' {
    Get-WinEvent -FilterHashtable @{ LogName='System'; Level=1,2; StartTime=(Get-Date).AddDays(-$Days) } -MaxEvents 60 | Select-Object TimeCreated,Id,ProviderName,Message
}
Add-ReportSection 'device-problems' {
    Get-CimInstance Win32_PnPEntity -Filter 'ConfigManagerErrorCode<>0' | Select-Object Name,PNPDeviceID,ConfigManagerErrorCode,Status
}
Save-SkillReport -PassThru:$PassThru
