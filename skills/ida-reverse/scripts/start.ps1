<#
.SYNOPSIS
Start IDA Pro MCP HTTP server (background, non-blocking)

.DESCRIPTION
1. Resolve IDADIR (env / portable IDA / registry / common paths)
2. Resolve idalib-mcp (PATH, IDA Python314 Scripts, or python -m)
3. If HTTP already healthy, reuse it (unless -Force)
4. Otherwise kill stale listeners and start a logged supervisor
5. Wait for service ready (max 30 seconds)
6. Output OK:<tool_count>, OK:<tool_count>:reuse, or ERR:...

Usage: run without parameters
#>

param(
    [string]$IdaDir,
    [int]$Port = 13337,
    [string]$ServerPath,
    [int]$WaitSeconds = 30,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

function Get-IdaMcpLogDir {
    $dir = Join-Path $env:LOCALAPPDATA 'reverse-skill\ida-mcp'
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    return $dir
}

function Rotate-IdaMcpLog {
    param(
        [string]$Path,
        [int]$MaxBytes = 5MB
    )
    if (-not (Test-Path -LiteralPath $Path)) { return }
    if ((Get-Item -LiteralPath $Path).Length -le $MaxBytes) { return }
    $bak = "$Path.1"
    if (Test-Path -LiteralPath $bak) {
        Remove-Item -LiteralPath $bak -Force
    }
    Move-Item -LiteralPath $Path -Destination $bak -Force
}

function Test-IdaMcpHealth {
    param([int]$Port)
    $probe = Probe-IdaMcp -Port $Port
    if ($probe.Status -eq 'healthy') { return $probe.Count }
    return 0
}

function Probe-IdaMcp {
    param([int]$Port)
    $owners = @(Get-IdaMcpPortOwners -Port $Port)
    $guiOwners = @($owners | Where-Object { Test-IdaGuiProcess -ProcessId $_ })
    $listening = $owners.Count -gt 0

    try {
        $r = Invoke-RestMethod "http://127.0.0.1:$Port/mcp" -Method Post `
            -Body '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' `
            -ContentType 'application/json' -TimeoutSec 3 -ErrorAction Stop
        $tools = @($r.result.tools)
        $count = $tools.Count
        $names = @($tools | ForEach-Object { $_.name })
        # Supervisor without --unsafe is "up" but missing py_eval. Treat as stale.
        if ($count -gt 0 -and ($names -contains 'py_eval')) {
            return @{ Status = 'healthy'; Count = $count; Owners = $owners; GuiOwners = $guiOwners }
        }
        if ($count -gt 0) {
            return @{ Status = 'stale'; Count = $count; Owners = $owners; GuiOwners = $guiOwners }
        }
    } catch {}

    if ($guiOwners.Count -gt 0) {
        return @{ Status = 'gui_busy'; Count = 0; Owners = $owners; GuiOwners = $guiOwners }
    }
    # Single-threaded supervisor cannot answer tools/list during idb_open.
    # A listen socket is busy, not dead — never taskkill on RPC timeout.
    if ($listening) {
        return @{ Status = 'busy'; Count = 0; Owners = $owners; GuiOwners = $guiOwners }
    }
    return @{ Status = 'down'; Count = 0; Owners = $owners; GuiOwners = $guiOwners }
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

function Get-IdaMcpProcessInfo {
    param([int]$ProcessId)
    return Get-CimInstance Win32_Process -Filter "ProcessId=$ProcessId" -ErrorAction SilentlyContinue
}

function Test-IdaGuiProcess {
    param([int]$ProcessId)
    $proc = Get-IdaMcpProcessInfo -ProcessId $ProcessId
    if (-not $proc) { return $false }
    return [string]$proc.Name -match '(?i)^(ida|ida64|idaq|idaq64)\.exe$'
}

function Test-ManagedSupervisorProcess {
    param([int]$ProcessId)
    $proc = Get-IdaMcpProcessInfo -ProcessId $ProcessId
    if (-not $proc) { return $false }
    $name = [string]$proc.Name
    $cmd = [string]$proc.CommandLine
    if ($name -match '(?i)^(ida|ida64|idaq|idaq64)\.exe$') { return $false }
    if ($name -match '(?i)^(python|pythonw|cmd)\.exe$') {
        return $cmd -match '(?i)(run-supervisor\.py|idalib_supervisor|idalib-mcp|ida-pro-mcp)'
    }
    return $name -match '(?i)^(idalib-mcp|ida-pro-mcp|idalib_supervisor)'
}

function Get-ManagedSupervisorProcessIds {
    $ids = New-Object System.Collections.Generic.List[int]
    foreach ($proc in @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)) {
        if (-not $proc.ProcessId) { continue }
        $candidateId = [int]$proc.ProcessId
        if (Test-ManagedSupervisorProcess -ProcessId $candidateId) {
            [void]$ids.Add($candidateId)
        }
    }
    return @($ids | Select-Object -Unique)
}

function Stop-IdaMcpManagedProcess {
    param([int]$ProcessId)
    if ($ProcessId -le 0) { return }
    if (Test-IdaGuiProcess -ProcessId $ProcessId) { return }
    # No /T: force_gui may have spawned ida.exe as a child of the supervisor.
    & taskkill.exe /F /PID $ProcessId 2>$null | Out-Null
}

function Get-PortableIdaCandidates {
    $desktop = [Environment]::GetFolderPath('Desktop')
    $userProfile = $env:USERPROFILE
    return @(
        (Join-Path $desktop 'IDA Pro 9.4\App\IDA Pro'),
        (Join-Path $desktop 'IDA Pro\App\IDA Pro'),
        (Join-Path $userProfile 'Desktop\IDA Pro 9.4\App\IDA Pro'),
        (Join-Path $userProfile 'Tools\IDA Pro 9.4\App\IDA Pro'),
        (Join-Path $userProfile 'Tools\IDA Pro\App\IDA Pro'),
        (Join-Path $userProfile 'Tools\IDA'),
        'C:\Program Files\IDA Professional 9.4',
        'C:\Program Files\IDA Pro 9.4',
        'C:\Program Files\IDA Pro',
        'C:\Program Files\IDA',
        'C:\IDA Pro',
        'C:\IDA',
        'D:\IDA',
        'D:\Tools\IDA Pro 9.4\App\IDA Pro',
        'E:\Program Files\IDA'
    )
}

function Test-IdaInstallDir {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $idaExe = Join-Path $Path 'ida.exe'
    $idaDll = Join-Path $Path 'ida.dll'
    return (Test-Path -LiteralPath $idaExe) -or (Test-Path -LiteralPath $idaDll)
}

function Get-InstalledIdaDir {
    $registryPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    $fromRegistry = $registryPaths |
        ForEach-Object {
            Get-ItemProperty $_ -ErrorAction SilentlyContinue
        } |
        Where-Object {
            ($_.DisplayName -match 'IDA|Hex-Rays') -and
            -not [string]::IsNullOrWhiteSpace($_.InstallLocation) -and
            (Test-IdaInstallDir -Path $_.InstallLocation)
        } |
        Select-Object -ExpandProperty InstallLocation -First 1

    if ($fromRegistry) {
        return $fromRegistry
    }

    return Get-PortableIdaCandidates | Where-Object { Test-IdaInstallDir -Path $_ } | Select-Object -First 1
}

function Resolve-IdaDir {
    param([string]$Preferred)

    if (-not [string]::IsNullOrWhiteSpace($Preferred) -and (Test-IdaInstallDir -Path $Preferred)) {
        return [System.IO.Path]::GetFullPath($Preferred)
    }

    if (-not [string]::IsNullOrWhiteSpace($env:IDADIR) -and (Test-IdaInstallDir -Path $env:IDADIR)) {
        return [System.IO.Path]::GetFullPath($env:IDADIR)
    }

    foreach ($scope in @('User', 'Machine')) {
        $persisted = [Environment]::GetEnvironmentVariable('IDADIR', $scope)
        if (-not [string]::IsNullOrWhiteSpace($persisted) -and (Test-IdaInstallDir -Path $persisted)) {
            return [System.IO.Path]::GetFullPath($persisted)
        }
    }

    $found = Get-InstalledIdaDir
    if ($found) {
        return [System.IO.Path]::GetFullPath($found)
    }

    return $null
}

function Test-PythonHasIdaProMcp {
    param([string]$PythonExe)
    if ([string]::IsNullOrWhiteSpace($PythonExe) -or -not (Test-Path -LiteralPath $PythonExe)) {
        return $false
    }
    # pythonw.exe has no console — probe with sibling python.exe when possible
    $probeExe = $PythonExe
    if ($PythonExe -match '(?i)pythonw\.exe$') {
        $sibling = Join-Path (Split-Path $PythonExe -Parent) 'python.exe'
        if (Test-Path -LiteralPath $sibling) { $probeExe = $sibling }
    }
    try {
        $check = & $probeExe -c "import ida_pro_mcp; print('ok')" 2>$null
        return ($LASTEXITCODE -eq 0) -or ($check -match 'ok')
    } catch {
        return $false
    }
}

function Get-WindowlessPythonPath {
    param([string]$PythonExe)
    if ([string]::IsNullOrWhiteSpace($PythonExe)) { return $PythonExe }
    if ($PythonExe -match '(?i)pythonw\.exe$') { return $PythonExe }
    if ($PythonExe -match '(?i)python\.exe$') {
        $pythonw = Join-Path (Split-Path $PythonExe -Parent) 'pythonw.exe'
        if (Test-Path -LiteralPath $pythonw) { return $pythonw }
    }
    return $PythonExe
}

function Find-IdalibServer {
    param(
        [string]$IdaDirPath,
        [string]$PreferredServerPath
    )

    if (-not [string]::IsNullOrWhiteSpace($PreferredServerPath) -and (Test-Path -LiteralPath $PreferredServerPath)) {
        return @{ Mode = 'exe'; Path = $PreferredServerPath }
    }

    # Prefer direct `pythonw -m ida_pro_mcp.idalib_supervisor` (no console window; more stable than .cmd)
    $pythonCandidates = @(
        (Join-Path $IdaDirPath 'Python314\pythonw.exe'),
        (Join-Path $IdaDirPath 'Python314\python.exe'),
        (Join-Path $IdaDirPath 'python\pythonw.exe'),
        (Join-Path $IdaDirPath 'python\python.exe'),
        (Join-Path $env:LOCALAPPDATA 'Python\pythoncore-3.14-64\pythonw.exe'),
        (Join-Path $env:LOCALAPPDATA 'Python\pythoncore-3.14-64\python.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python314\pythonw.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python314\python.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python312\pythonw.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python312\python.exe'),
        (Get-Command pythonw -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -First 1),
        (Get-Command python -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -First 1)
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique

    foreach ($py in $pythonCandidates) {
        # `py` launcher is not a real interpreter for -m in Start-Process; skip bare py.exe
        if ($py -match '\\py\.exe$') { continue }
        if (Test-PythonHasIdaProMcp -PythonExe $py) {
            $launch = Get-WindowlessPythonPath -PythonExe $py
            return @{ Mode = 'module'; Path = $launch; Module = 'ida_pro_mcp.idalib_supervisor' }
        }
    }

    # Prefer native .exe entrypoints over .cmd wrappers
    $scriptCandidates = @(
        (Join-Path $env:LOCALAPPDATA 'Python\pythoncore-3.14-64\Scripts\idalib-mcp.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python312\Scripts\idalib-mcp.exe'),
        (Join-Path $IdaDirPath 'Python314\Scripts\idalib-mcp.exe'),
        (Join-Path $IdaDirPath 'Python314\Scripts\ida-pro-mcp.exe')
    )
    foreach ($candidate in $scriptCandidates) {
        if (Test-Path -LiteralPath $candidate) {
            return @{ Mode = 'exe'; Path = $candidate }
        }
    }

    foreach ($name in @('idalib-mcp', 'ida-pro-mcp')) {
        $resolved = Get-Command $name -ErrorAction SilentlyContinue
        if ($resolved) {
            return @{ Mode = 'exe'; Path = $resolved.Source }
        }
    }

    foreach ($candidate in @(
        (Join-Path $env:USERPROFILE 'Tools\bin\idalib-mcp.cmd'),
        (Join-Path $env:USERPROFILE 'Tools\bin\ida-pro-mcp.cmd')
    )) {
        if (Test-Path -LiteralPath $candidate) {
            return @{ Mode = 'exe'; Path = $candidate }
        }
    }

    $roamingPython = Join-Path $env:APPDATA 'Python'
    if (Test-Path -LiteralPath $roamingPython) {
        $candidate = Get-ChildItem -LiteralPath $roamingPython -Directory -ErrorAction SilentlyContinue |
            ForEach-Object {
                $scripts = Join-Path $_.FullName 'Scripts'
                @('idalib-mcp.exe', 'ida-pro-mcp.exe') | ForEach-Object { Join-Path $scripts $_ }
            } |
            Where-Object { Test-Path -LiteralPath $_ } |
            Select-Object -First 1
        if ($candidate) {
            return @{ Mode = 'exe'; Path = $candidate }
        }
    }

    return $null
}

$probe = Probe-IdaMcp -Port $Port
$guiOwners = @($probe.GuiOwners)

if ($guiOwners.Count -gt 0) {
    Write-Output ("WARN:gui_busy:port={0} pid={1}" -f $Port, ($guiOwners -join ','))
    Write-Output 'HINT: IDA GUI owns 13337; not killing ida.exe. Wait for analysis or close IDA.'
    exit 0
}

if (-not $Force) {
    if ($probe.Status -eq 'healthy') {
        Write-Output "OK:$($probe.Count)`:reuse"
        exit 0
    }
    if ($probe.Status -eq 'busy') {
        Write-Output ("WARN:busy:port={0} pid={1}" -f $Port, ($probe.Owners -join ','))
        Write-Output 'HINT: 13337 is listening but tools/list timed out (likely idb_open). Not killing supervisor.'
        exit 0
    }
}

$resolvedIdaDir = Resolve-IdaDir -Preferred $IdaDir
if (-not $resolvedIdaDir) {
    Write-Output "ERR:IDADIR not set and IDA Pro not found. Set IDADIR to your IDA install dir (folder containing ida.exe)."
    exit 1
}

$IdaDir = $resolvedIdaDir
$env:IDADIR = $IdaDir

# Ensure IDA bins + bundled Python are visible to the child process
$idaPythonDir = Join-Path $IdaDir 'Python314'
if (-not (Test-Path -LiteralPath $idaPythonDir)) {
    $idaPythonDir = Join-Path $IdaDir 'python'
}
$env:PATH = "$IdaDir;$idaPythonDir;$(Join-Path $idaPythonDir 'Scripts');$env:PATH"

$server = Find-IdalibServer -IdaDirPath $IdaDir -PreferredServerPath $ServerPath

# Auto-bootstrap only if still missing
if (-not $server) {
    $bootstrapScript = Join-Path $PSScriptRoot '..\..\scripts\bootstrap-reverse.ps1'
    if (Test-Path -LiteralPath $bootstrapScript) {
        Write-Output "INFO: ida-pro-mcp not found, attempting auto-bootstrap (installing mrexodia/ida-pro-mcp)..."
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $bootstrapScript -Capability @('idalib-mcp') -SkipRefresh
        $server = Find-IdalibServer -IdaDirPath $IdaDir -PreferredServerPath $ServerPath
    }
}

if (-not $server) {
    Write-Output 'ERR:Missing idalib-mcp — install into IDA Python: <IDADIR>\Python314\python.exe -m pip install git+https://github.com/mrexodia/ida-pro-mcp.git'
    exit 1
}

# Replace only when down or stale (no py_eval). Busy/gui already exited above
# unless -Force. Never taskkill ida.exe; never use /T.
foreach ($procName in @('ida-pro-mcp', 'idalib-mcp', 'idalib_supervisor')) {
    $old = Get-Process -Name $procName -ErrorAction SilentlyContinue
    if ($old) {
        foreach ($process in @($old)) {
            Stop-IdaMcpManagedProcess -ProcessId $process.Id
        }
    }
}
foreach ($managedPid in @(Get-ManagedSupervisorProcessIds)) {
    Stop-IdaMcpManagedProcess -ProcessId $managedPid
}
Start-Sleep -Seconds 1

$wrapper = Join-Path $PSScriptRoot 'run-supervisor.py'
# --unsafe exposes py_eval / py_exec_file. dbg_* stay hidden (need ?ext=dbg; do not add).
$argList = @('--host', '127.0.0.1', '--port', "$Port", '--unsafe')
if (Test-Path -LiteralPath $wrapper) {
    $filePath = $server.Path
    if ($filePath -match '(?i)python\.exe$') {
        $pythonw = Join-Path (Split-Path $filePath -Parent) 'pythonw.exe'
        if (Test-Path -LiteralPath $pythonw) { $filePath = $pythonw }
    }
    if ($filePath -notmatch '(?i)pythonw?\.exe$') {
        $filePath = $server.Path
        if ($server.Mode -eq 'module') {
            $argList = @('-u', '-m', $server.Module) + $argList
        }
    } else {
        $argList = @('-u', $wrapper) + $argList
    }
} elseif ($server.Mode -eq 'module') {
    $filePath = $server.Path
    $argList = @('-u', '-m', $server.Module) + $argList
} else {
    $filePath = $server.Path
}

$logDir = Get-IdaMcpLogDir
$logFile = Join-Path $logDir 'supervisor.log'
Rotate-IdaMcpLog -Path $logFile

Write-Output "INFO:IDADIR=$IdaDir"
Write-Output "INFO:server=$filePath $($argList -join ' ')"
Write-Output "INFO:log=$logFile"
Write-Output 'INFO:window=hidden (pythonw / no console)'

# Detached + hidden start:
# pythonw + run-supervisor.py keeps logs without a cmd.exe window.
# Win32_Process.Create so the server survives agent/terminal Job Objects.
$quotedArgs = foreach ($a in $argList) {
    if ($a -match '[\s"]') { '"' + ($a -replace '"', '\"') + '"' } else { $a }
}
$useCmd = $filePath -match '(?i)\.cmd$'
if ($useCmd) {
    $commandLine = 'cmd.exe /d /c "' + $filePath + '" ' + ($quotedArgs -join ' ')
} else {
    $commandLine = '"' + $filePath + '" ' + ($quotedArgs -join ' ')
}
$procId = 0

try {
    $create = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{
        CommandLine      = $commandLine
        CurrentDirectory = $IdaDir
    }
    if ($create -and $create.ReturnValue -eq 0 -and $create.ProcessId) {
        $procId = [int]$create.ProcessId
    }
} catch {}

if ($procId -le 0) {
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        if ($useCmd) {
            $psi.FileName = 'cmd.exe'
            $psi.Arguments = '/d /c "' + $filePath + '" ' + ($quotedArgs -join ' ')
        } else {
            $psi.FileName = $filePath
            $psi.Arguments = ($quotedArgs -join ' ')
        }
        $psi.WorkingDirectory = $IdaDir
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
        $p = [System.Diagnostics.Process]::Start($psi)
        if ($p) { $procId = $p.Id }
    } catch {}
}

if ($procId -le 0) {
    Write-Output 'ERR:failed_to_start_process'
    exit 1
}
Write-Output "INFO:pid=$procId"

# Wait for readiness via MCP tools/list
$ready = $false
$toolCount = 0
for ($i = 0; $i -lt $WaitSeconds; $i++) {
    Start-Sleep -Seconds 1
    $toolCount = Test-IdaMcpHealth -Port $Port
    if ($toolCount -gt 0) {
        Write-Output "OK:$toolCount"
        $ready = $true
        break
    }
}

if (-not $ready) {
    Write-Output "ERR:timeout"
    Write-Output "HINT:check $logFile"
    exit 1
}
