<#
.SYNOPSIS
Ensure IDA Pro MCP HTTP is healthy; start it only when down.

.DESCRIPTION
One-shot health check used by the scheduled task. Safe to run every minute:
a live server is reused, a dead listener is replaced via start.ps1.

Usage:
  powershell -File watchdog.ps1
#>

param(
    [int]$Port = 13337
)

$ErrorActionPreference = 'Stop'

$logDir = Join-Path $env:LOCALAPPDATA 'reverse-skill\ida-mcp'
if (-not (Test-Path -LiteralPath $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}
$logFile = Join-Path $logDir 'watchdog.log'
if ((Test-Path -LiteralPath $logFile) -and ((Get-Item -LiteralPath $logFile).Length -gt 2MB)) {
    $bak = "$logFile.1"
    if (Test-Path -LiteralPath $bak) { Remove-Item -LiteralPath $bak -Force }
    Move-Item -LiteralPath $logFile -Destination $bak -Force
}

function Write-WatchLog {
    param([string]$Message)
    $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8
    Write-Output $Message
}

function Get-IdaMcpPortOwners {
    param([int]$Port)
    try {
        return @(
            Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
                Select-Object -ExpandProperty OwningProcess -Unique |
                Where-Object { $_ -and $_ -gt 0 }
        )
    } catch {
        return @()
    }
}

function Probe-IdaMcp {
    param([int]$Port)
    $owners = @(Get-IdaMcpPortOwners -Port $Port)
    try {
        $r = Invoke-RestMethod "http://127.0.0.1:$Port/mcp" -Method Post `
            -Body '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' `
            -ContentType 'application/json' -TimeoutSec 3 -ErrorAction Stop
        $tools = @($r.result.tools)
        $count = $tools.Count
        $names = @($tools | ForEach-Object { $_.name })
        if ($count -gt 0 -and ($names -contains 'py_eval')) {
            return @{ Status = 'healthy'; Count = $count }
        }
        if ($count -gt 0) {
            return @{ Status = 'stale'; Count = $count }
        }
    } catch {}
    # Listen + RPC timeout = busy (single-threaded supervisor during idb_open).
    # Only "nothing listening" or a quick stale (no py_eval) list is down.
    if ($owners.Count -gt 0) {
        return @{ Status = 'busy'; Count = 0 }
    }
    return @{ Status = 'down'; Count = 0 }
}

$probe = Probe-IdaMcp -Port $Port
if ($probe.Status -eq 'healthy') {
    Write-WatchLog "OK:$($probe.Count)`:reuse"
    exit 0
}
if ($probe.Status -eq 'busy') {
    Write-WatchLog 'OK:busy:reuse'
    exit 0
}

Write-WatchLog ("INFO:{0}, calling start.ps1" -f $probe.Status)
$startScript = Join-Path $PSScriptRoot 'start.ps1'
$startOutput = & $startScript -Port $Port
foreach ($line in @($startOutput)) {
    Write-WatchLog "START:$line"
}

$last = (@($startOutput) | Where-Object { $_ -match '^(OK|ERR|WARN):' } | Select-Object -Last 1)
if ($last -match '^(OK:|WARN:gui_busy|WARN:busy)') {
    exit 0
}
exit 1
