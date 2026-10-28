#requires -Version 5.1
[CmdletBinding()]
param([string]$OutputDirectory, [switch]$PassThru)
. (Join-Path $PSScriptRoot 'Report.Common.ps1')
Initialize-SkillReport 'disk-health' $OutputDirectory
Add-ReportSection 'logical-volumes' {
    Get-CimInstance Win32_LogicalDisk | Select-Object DeviceID,VolumeName,DriveType,FileSystem,Size,FreeSpace
} -Required
Add-ReportSection 'disks' { Get-Disk | Select-Object Number,FriendlyName,BusType,PartitionStyle,OperationalStatus,HealthStatus,Size,IsBoot,IsSystem,IsReadOnly }
Add-ReportSection 'partitions' { Get-Partition | Select-Object DiskNumber,PartitionNumber,DriveLetter,Type,Size,IsActive,IsBoot,IsSystem }
Add-ReportSection 'physical-disk-health' { Get-PhysicalDisk | Select-Object FriendlyName,MediaType,BusType,HealthStatus,OperationalStatus,Size }
Add-ReportSection 'storage-reliability' {
    $rows = @()
    foreach ($disk in Get-PhysicalDisk) {
        try {
            $counter = $disk | Get-StorageReliabilityCounter
            $rows += $counter | Select-Object @{n='Disk';e={$disk.FriendlyName}},Temperature,Wear,PowerOnHours,ReadErrorsTotal,WriteErrorsTotal,ReadErrorsUncorrected,WriteErrorsUncorrected
        } catch { $rows += [pscustomobject]@{ Disk=$disk.FriendlyName; Status='Unavailable'; Reason=$_.Exception.Message } }
    }
    $rows
}
Add-ReportSection 'legacy-smart-prediction' {
    Get-CimInstance -Namespace root/wmi -ClassName MSStorageDriver_FailurePredictStatus | Select-Object InstanceName,PredictFailure,Reason
}
Add-ReportSection 'filesystem-dirty-flags' {
    foreach ($volume in Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3') {
        $r = Invoke-SystemCommand (Join-Path $env:SystemRoot 'System32/fsutil.exe') @('dirty','query',$volume.DeviceID) 15
        [pscustomobject]@{ Volume=$volume.DeviceID; Result=$r }
    }
}
Add-ReportSection 'disk-activity-sample' {
    Get-CimInstance Win32_PerfFormattedData_PerfDisk_PhysicalDisk | Select-Object Name,DiskBytesPersec,PercentDiskTime,AvgDisksecPerRead,AvgDisksecPerWrite,CurrentDiskQueueLength
}
Add-ReportSection 'storage-error-events' {
    Get-WinEvent -FilterHashtable @{ LogName='System'; StartTime=(Get-Date).AddDays(-7); Level=1,2,3 } -MaxEvents 400 |
        Where-Object { $_.ProviderName -match 'disk|ntfs|stor|volmgr|WHEA' } | Select-Object -First 60 TimeCreated,ProviderName,Id,Message
}
Save-SkillReport -PassThru:$PassThru
