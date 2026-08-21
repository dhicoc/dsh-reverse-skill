<#
.SYNOPSIS
Launch portable IDA Pro GUI (with MCP plugin). Prefer this when headless idalib license fails.

.DESCRIPTION
1. Resolve IDADIR
2. Optionally open a binary path
3. Start IDA GUI so the ida_mcp plugin can autostart HTTP on 127.0.0.1:13337

Usage:
  powershell -File start-gui.ps1
  powershell -File start-gui.ps1 -Path C:\target.exe
#>

param(
    [string]$Path,
    [string]$IdaDir,
    [switch]$UsePortableLauncher
)

$ErrorActionPreference = 'Stop'

function Test-IdaInstallDir {
    param([string]$Candidate)
    if ([string]::IsNullOrWhiteSpace($Candidate)) { return $false }
    if (-not (Test-Path -LiteralPath $Candidate)) { return $false }
    $idaExe = Join-Path $Candidate 'ida.exe'
    $idaDll = Join-Path $Candidate 'ida.dll'
    return (Test-Path -LiteralPath $idaExe) -or (Test-Path -LiteralPath $idaDll)
}

if ([string]::IsNullOrWhiteSpace($IdaDir)) {
    if (-not [string]::IsNullOrWhiteSpace($env:IDADIR) -and (Test-IdaInstallDir $env:IDADIR)) {
        $IdaDir = $env:IDADIR
    } else {
        $persisted = [Environment]::GetEnvironmentVariable('IDADIR', 'User')
        if (Test-IdaInstallDir $persisted) {
            $IdaDir = $persisted
        } else {
            $candidates = @(
                'C:\Program Files\IDA Professional 9.4',
                'C:\Program Files\IDA Pro 9.4',
                'C:\Program Files\IDA Pro',
                (Join-Path $env:USERPROFILE 'Tools\IDAPro94'),
                (Join-Path $env:USERPROFILE 'Tools\IDA Pro 9.4\App\IDA Pro'),
                (Join-Path ([Environment]::GetFolderPath('Desktop')) 'IDA Pro 9.4\App\IDA Pro'),
                (Join-Path $env:USERPROFILE 'Desktop\IDA Pro 9.4\App\IDA Pro')
            )
            $IdaDir = $candidates | Where-Object { Test-IdaInstallDir $_ } | Select-Object -First 1
        }
    }
}

if (-not (Test-IdaInstallDir $IdaDir)) {
    Write-Output 'ERR:IDADIR_not_found'
    exit 1
}

$env:IDADIR = [System.IO.Path]::GetFullPath($IdaDir)
$portableRoot = Split-Path (Split-Path $env:IDADIR -Parent) -Parent
# Desktop\IDA Pro 9.4\App\IDA Pro -> Desktop\IDA Pro 9.4
if ((Split-Path $env:IDADIR -Leaf) -eq 'IDA Pro') {
    $maybe = Split-Path (Split-Path $env:IDADIR -Parent) -Parent
    if (Test-Path (Join-Path $maybe 'Launch-IDA-Pro.cmd')) {
        $portableRoot = $maybe
    }
}

Write-Output "INFO:IDADIR=$env:IDADIR"

if ($UsePortableLauncher -or (Test-Path (Join-Path $portableRoot 'Launch-IDA-Pro.cmd'))) {
    $launcher = Join-Path $portableRoot 'Launch-IDA-Pro.cmd'
    if (Test-Path -LiteralPath $launcher) {
        Write-Output "INFO:launcher=$launcher"
        if (-not [string]::IsNullOrWhiteSpace($Path)) {
            if (-not (Test-Path -LiteralPath $Path)) {
                Write-Output 'ERR:file_not_found'
                exit 1
            }
            # Portable launcher starts IDA; then user/file can be passed to ida.exe directly instead
            $target = [System.IO.Path]::GetFullPath($Path)
            Start-Process -FilePath (Join-Path $env:IDADIR 'ida.exe') -ArgumentList @('"' + $target + '"') -WorkingDirectory $env:IDADIR
        } else {
            Start-Process -FilePath $launcher -WorkingDirectory $portableRoot
        }
        Write-Output 'OK:gui_started'
        Write-Output 'HINT: Open a binary in IDA, confirm Output shows [MCP] port=13337, then use idapro MCP tools.'
        exit 0
    }
}

$idaExe = Join-Path $env:IDADIR 'ida.exe'
if (-not [string]::IsNullOrWhiteSpace($Path)) {
    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Output 'ERR:file_not_found'
        exit 1
    }
    $target = [System.IO.Path]::GetFullPath($Path)
    Start-Process -FilePath $idaExe -ArgumentList @('"' + $target + '"') -WorkingDirectory $env:IDADIR
} else {
    Start-Process -FilePath $idaExe -WorkingDirectory $env:IDADIR
}

Write-Output 'OK:gui_started'
Write-Output 'HINT: Open a binary in IDA, confirm Output shows [MCP] port=13337, then use idapro MCP tools.'
