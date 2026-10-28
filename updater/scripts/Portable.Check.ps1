#requires -Version 5.1
function Show-PortableCheck([string]$Root) {
    $healthy = $true
    Write-Host 'Pi-Portable environment check (no API key required)' -ForegroundColor Cyan
    Write-Host "Root:     $Root"
    Write-Host "Agent:    $env:PI_CODING_AGENT_DIR"
    Write-Host "Sessions: $env:PI_CODING_AGENT_SESSION_DIR"
    Write-Host "npm cache: $env:NPM_CONFIG_CACHE"
    Write-Host "npm global: $env:NPM_CONFIG_PREFIX"
    foreach ($name in @('pi','node','git')) {
        try { Write-Host ("[OK] {0}: {1}" -f $name, (Test-ComponentRuntime $name (Get-ComponentPath $Root $name))) }
        catch { Write-Host "[FAIL] ${name}: $($_.Exception.Message)" -ForegroundColor Red; $healthy = $false }
    }
    try {
        $bashVersion = (Invoke-PortableNative (Join-Path $Root 'tools/git/bin/bash.exe') @('--version')).Stdout -split "`n"
        Write-Host "[OK] Git Bash: $($bashVersion[0].Trim())"
        $node = Join-Path $Root 'tools/node/node.exe'
        foreach ($cli in @('npm','npx')) {
            $v = (Invoke-PortableNative $node @((Join-Path $Root "tools/node/node_modules/npm/bin/$cli-cli.js"),'--version')).Stdout.Trim()
            Write-Host "[OK] ${cli}: $v"
        }
        $shell = Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
        $r = Invoke-PortableNative $shell @('-NoProfile','-NonInteractive','-Command','$PSVersionTable.PSVersion.ToString()')
        Write-Host "[OK] Windows PowerShell: $($r.Stdout.Trim())"
        foreach ($command in @('node.exe','npm.cmd','npx.cmd','git.exe','bash.exe')) {
            $resolved = (Get-Command $command -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
            if (-not $resolved.StartsWith($Root.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw "Host program selected for $command" }
            Write-Host "[OK] portable PATH resolution: $command"
        }
    } catch { Write-Host "[FAIL] $($_.Exception.Message)" -ForegroundColor Red; $healthy = $false }
    try {
        $exe = Join-Path $Root 'runtime/pi/pi.exe'
        $running = @(Get-CimInstance Win32_Process -Filter "Name='pi.exe'" | Where-Object { $_.ExecutablePath -eq $exe })
        Write-Host "Pi process state: $($running.Count) running instance(s) from this folder; --version probe is separate from interactive UI acceptance."
    } catch { Write-Host '[WARN] Could not query the current Pi process state.' -ForegroundColor Yellow }
    foreach ($skill in @(Get-SkillStatus $Root)) {
        if ($skill.Healthy) {
            Write-Host "[OK] Skill manifest: $($skill.Name)"
            if ($skill.UserChanges.Count -gt 0) { Write-Host '     User changes present and preserved.' -ForegroundColor Yellow }
        } else { Write-Host "[FAIL] Skill $($skill.Name): $($skill.Issues -join '; ')" -ForegroundColor Red; $healthy = $false }
    }
    Write-Host 'Skill auto-selection needs a model. Run tests/Test-Windows.ps1 for RPC discovery and real read-only workflows.'
    try {
        $model = Get-ModelConfigurationStatus $Root
        Write-Host "Default provider/model: $($model.DefaultProvider) / $($model.DefaultModel)"
        Write-Host "Stored credentials present: $($model.StoredAuthPresent); custom providers: $($model.CustomProvidersPresent)"
        Write-Host $model.Note
    } catch { Write-Host "[FAIL] Configuration JSON invalid; preserved. $($_.Exception.Message)" -ForegroundColor Red; $healthy = $false }
    foreach ($p in @(Find-ConfigurationPathIssues $Root)) {
        Write-Host "[WARN] $($p.File) $($p.Property): $($p.Issue)" -ForegroundColor Yellow
    }
    if (Test-Path -LiteralPath (Join-Path $Root 'updater/transaction.json')) {
        Write-Host '[FAIL] Incomplete update journal. Run Repair before launching Pi.' -ForegroundColor Red; $healthy = $false
    }
    Write-Host 'API keys and OAuth token values were not displayed.'
    return $healthy
}
