# Shared IDA open lock policy. Never delete .i64/.idb.
function Get-IdaOpenLockPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BinaryPath
    )
    $dir = [System.IO.Path]::GetDirectoryName($BinaryPath)
    $base = [System.IO.Path]::GetFileNameWithoutExtension($BinaryPath)
    $lockExts = @('.id0', '.id1', '.id2', '.nam', '.til')
    $dbExts = @('.i64', '.idb')
    $hasLocked = $false
    foreach ($ext in $lockExts) {
        $f = Join-Path $dir ($base + $ext)
        if (Test-Path -LiteralPath $f) { $hasLocked = $true }
    }
    $hasDatabase = $false
    foreach ($ext in $dbExts) {
        $f = Join-Path $dir ($base + $ext)
        if (Test-Path -LiteralPath $f) { $hasDatabase = $true }
    }
    return [pscustomobject]@{
        HasLocked            = $hasLocked
        HasDatabase          = $hasDatabase
        WouldDeleteDatabase  = $false
        PreferTempCopy       = $hasLocked
    }
}

function Get-IdaMcpKeepaliveDir {
    $dir = Join-Path $env:LOCALAPPDATA 'reverse-skill\ida-mcp'
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    return $dir
}

function Get-IdaMcpLastHealthyPath {
    param([int]$Port = 13337)
    return Join-Path (Get-IdaMcpKeepaliveDir) ("last-healthy-{0}.txt" -f $Port)
}

function Get-IdaMcpOpeningLockPath {
    param([int]$Port = 13337)
    return Join-Path (Get-IdaMcpKeepaliveDir) ("opening-{0}.lock" -f $Port)
}

function Write-IdaMcpLastHealthy {
    param([int]$Port = 13337)
    Set-Content -LiteralPath (Get-IdaMcpLastHealthyPath -Port $Port) -Value 'ok' -Encoding ASCII
}

function Read-IdaMcpLastHealthy {
    param([int]$Port = 13337)
    $path = Get-IdaMcpLastHealthyPath -Port $Port
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    return (Get-Item -LiteralPath $path).LastWriteTime
}

function Set-IdaMcpOpeningLock {
    param(
        [int]$Port = 13337,
        [int]$TtlSeconds = 600
    )
    $ttl = [Math]::Max(1, $TtlSeconds)
    $until = (Get-Date).AddSeconds($ttl).ToString('o')
    Set-Content -LiteralPath (Get-IdaMcpOpeningLockPath -Port $Port) -Value $until -Encoding ASCII
}

function Clear-IdaMcpOpeningLock {
    param([int]$Port = 13337)
    $path = Get-IdaMcpOpeningLockPath -Port $Port
    if (Test-Path -LiteralPath $path) {
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    }
}

function Test-IdaMcpOpeningInFlight {
    param(
        [int]$Port = 13337,
        [datetime]$Now = (Get-Date)
    )
    $path = Get-IdaMcpOpeningLockPath -Port $Port
    if (-not (Test-Path -LiteralPath $path)) { return $false }
    $raw = (Get-Content -LiteralPath $path -Raw -ErrorAction SilentlyContinue)
    if ([string]::IsNullOrWhiteSpace($raw)) {
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        return $false
    }
    try {
        $until = [datetime]::Parse($raw.Trim(), $null, [System.Globalization.DateTimeStyles]::RoundtripKind)
    } catch {
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        return $false
    }
    if ($Now -gt $until) {
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        return $false
    }
    return $true
}

function Test-IdaMcpKeepaliveDeadlockFromFacts {
    param(
        [bool]$GuiOwnsPort = $false,
        [bool]$OpeningInFlight = $false,
        $LastHealthy = $null,
        [datetime]$Now = (Get-Date),
        [int]$MaxUnhealthySeconds = 180
    )
    if ($GuiOwnsPort) { return $false }
    if ($OpeningInFlight) { return $false }
    if ($null -eq $LastHealthy) { return $false }
    return ($Now - [datetime]$LastHealthy).TotalSeconds -ge $MaxUnhealthySeconds
}
