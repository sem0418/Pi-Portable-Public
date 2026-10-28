#requires -Version 5.1
[CmdletBinding()]
param([ValidateSet('Inspect','SfcVerify','DismCheck','DismScan','DismRestore','SfcRepair')][string]$Action = 'Inspect', [string]$OutputDirectory, [switch]$PassThru)
. (Join-Path $PSScriptRoot 'Report.Common.ps1')
Initialize-SkillReport 'windows-repair' $OutputDirectory
Add-ReportSection 'system-build' { Get-CimInstance Win32_OperatingSystem | Select-Object Caption,Version,BuildNumber,LastBootUpTime } -Required
Add-ReportSection 'update-and-repair-services' { Get-Service -Name wuauserv,bits,cryptsvc,TrustedInstaller | Select-Object Name,Status,StartType }
Add-ReportSection 'pending-reboot' {
    [pscustomobject]@{
        ComponentServicing=Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
        WindowsUpdate=Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    }
}
Add-ReportSection 'update-errors' {
    Get-WinEvent -FilterHashtable @{ LogName='Microsoft-Windows-WindowsUpdateClient/Operational'; Level=1,2,3; StartTime=(Get-Date).AddDays(-7) } -MaxEvents 40 | Select-Object TimeCreated,Id,Message
}
Add-ReportSection 'cbs-log-tail' { Get-Content -LiteralPath (Join-Path $env:SystemRoot 'Logs/CBS/CBS.log') -Tail 70 }
Add-ReportSection 'dism-log-tail' { Get-Content -LiteralPath (Join-Path $env:SystemRoot 'Logs/DISM/dism.log') -Tail 70 }
if ($Action -ne 'Inspect') {
    $script:SkillReport.mode = $Action
    Add-ReportSection 'requested-system-operation' {
        Assert-SkillAdministrator
        $system = Join-Path $env:SystemRoot 'System32'
        switch ($Action) {
            'SfcVerify' { $exe = Join-Path $system 'sfc.exe'; $arguments = @('/verifyonly') }
            'SfcRepair' { $exe = Join-Path $system 'sfc.exe'; $arguments = @('/scannow') }
            'DismCheck' { $exe = Join-Path $system 'Dism.exe'; $arguments = @('/Online','/Cleanup-Image','/CheckHealth') }
            'DismScan' { $exe = Join-Path $system 'Dism.exe'; $arguments = @('/Online','/Cleanup-Image','/ScanHealth') }
            'DismRestore' { $exe = Join-Path $system 'Dism.exe'; $arguments = @('/Online','/Cleanup-Image','/RestoreHealth') }
        }
        # Long operations are intentionally observed to completion; do not terminate repairs.
        Invoke-SystemCommand $exe $arguments 14400
    } -Required
}
Save-SkillReport -PassThru:$PassThru
