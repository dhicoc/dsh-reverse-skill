<#
.SYNOPSIS
Register a keep-alive scheduled task for IDA Pro MCP HTTP.

.DESCRIPTION
Replaces the old logon-only reverse-skill-ida-mcp task with:
- At logon + 30s delay
- Once-from-now trigger repeating every 1 minute for 3650 days
  (this host cannot write -Daily.Repetition)
- Restart the task up to 3 times if the script itself fails
- Action runs watchdog.ps1 (reuse if healthy, start only if down;
  never kill ida.exe when the GUI plugin owns 13337)

Usage:
  powershell -File install-autostart.ps1
  powershell -File install-autostart.ps1 -Unregister
#>

param(
    [switch]$Unregister
)

$ErrorActionPreference = 'Stop'

$taskName = 'reverse-skill-ida-mcp'
$watchdog = Join-Path $PSScriptRoot 'watchdog.ps1'
if (-not (Test-Path -LiteralPath $watchdog)) {
    Write-Output "ERR:missing $watchdog"
    exit 1
}

if ($Unregister) {
    $existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($existing) {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    }
    Write-Output 'OK:unregistered'
    exit 0
}

$arg = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$watchdog`""
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arg -WorkingDirectory $PSScriptRoot

$logon = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$logon.Delay = 'PT30S'

# -Daily.Repetition is not writable on this host; -Once + long duration is.
$repeat = New-ScheduledTaskTrigger -Once -At (Get-Date) `
    -RepetitionInterval (New-TimeSpan -Minutes 1) `
    -RepetitionDuration (New-TimeSpan -Days 3650)

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 5) `
    -MultipleInstances IgnoreNew `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1)
$settings.Hidden = $true

$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited

Register-ScheduledTask `
    -TaskName $taskName `
    -Action $action `
    -Trigger @($logon, $repeat) `
    -Settings $settings `
    -Principal $principal `
    -Force `
    -Description 'Keep IDA Pro MCP HTTP (127.0.0.1:13337) alive. Reuses a healthy server; starts idalib_supervisor only when down.' `
    | Out-Null

Start-ScheduledTask -TaskName $taskName
Write-Output "OK:registered:$taskName"
Write-Output 'INFO:triggers=AtLogOn+30s, every 1 min'
Write-Output ("INFO:watchdog={0}" -f $watchdog)
