#requires -Version 5.1
[CmdletBinding()]
param([switch]$Preview)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$operationLock = $null
$exitCode = 0
try {
    $root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
    $sessions = Join-Path $root 'data\sessions'
    Write-Host "对话历史目录：$sessions"
    # Refuse junctions/symlinks so cleanup cannot follow a redirected history path.
    foreach ($path in @((Join-Path $root 'data'), $sessions)) {
        if (Test-Path -LiteralPath $path) {
            $item = Get-Item -LiteralPath $path -Force
            if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                throw "目录无效或属于链接，已停止：$path"
            }
        }
    }
    if (-not (Test-Path -LiteralPath $sessions)) {
        Write-Host '没有保存的对话历史。'
    } else {
        if (-not $Preview) {
            # Share the launcher's lock: Pi cannot start while cleanup holds it.
            $lockPath = Join-Path $root 'updater\operation.lock'
            try {
                $operationLock = [IO.File]::Open($lockPath, 'OpenOrCreate', 'ReadWrite', 'None')
            } catch {
                throw 'Pi 或维护程序正在运行，或锁文件无法访问。请先关闭本便携包的 Pi 后重试。'
            }
        }
        function Get-HistoryItems([string]$Directory) {
            foreach ($entry in @(Get-ChildItem -LiteralPath $Directory -Force)) {
                if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                    throw "历史目录中存在链接，已停止：$($entry.FullName)"
                }
                if ($entry.PSIsContainer) { Get-HistoryItems $entry.FullName }
                $entry
            }
        }
        # Collect and validate everything before deleting any file.
        $items = @(Get-HistoryItems $sessions)
        $files = @($items | Where-Object { -not $_.PSIsContainer })
        $bytes = ($files | Measure-Object -Property Length -Sum).Sum
        Write-Host ('共 {0} 个文件，约 {1:N2} MB。' -f $files.Count, ($bytes / 1MB))
        if ($Preview) {
            $files | Select-Object FullName, Length
            Write-Host '预览完成，未删除文件。'
        } elseif ($items.Count -eq 0) {
            Write-Host '没有保存的对话历史。'
        } else {
            Write-Host '将永久删除该目录内的全部历史及附属文件，无法撤销；不创建备份。' -ForegroundColor Yellow
            Write-Host 'API Key、模型配置、Skills 和 workspace 文件会保留。'
            $answer = Read-Host '输入 Y 并回车确认删除，其他输入取消'
            if ($answer -ceq 'Y') {
                # Children are collected before parents; do not recurse at deletion time.
                foreach ($item in $items) {
                    Remove-Item -LiteralPath $item.FullName -Force -ErrorAction Stop
                }
                Write-Host '对话历史已清空。' -ForegroundColor Green
            } else {
                Write-Host '已取消，未删除文件。'
            }
        }
    }
} catch {
    Write-Host "清理未完成：$($_.Exception.Message)" -ForegroundColor Red
    $exitCode = 1
} finally {
    if ($operationLock) { $operationLock.Dispose() }
}
exit $exitCode
