<#
.SYNOPSIS
Force-restart IDA Pro MCP HTTP (127.0.0.1:13337).

.DESCRIPTION
Use when Cursor user-idapro is error / tools/list hangs.
Never kills ida.exe. Replaces only the managed supervisor.

Usage:
  powershell -File recover.ps1
#>
param(
    [int]$Port = 13337,
    [int]$WaitSeconds = 45
)

$ErrorActionPreference = 'Stop'
$startScript = Join-Path $PSScriptRoot 'start.ps1'
& $startScript -Port $Port -Force -WaitSeconds $WaitSeconds
exit $LASTEXITCODE
