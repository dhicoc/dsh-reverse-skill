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
