#Requires -Version 5.1
# Contract tests: route-scope parse must ignore hint text; IDA lock must not delete .i64/.idb.
param(
    [string]$PackageRoot = ''
)
$ErrorActionPreference = 'Stop'
$scriptDir = $PSScriptRoot
$skillsRoot = Split-Path -Parent $scriptDir
if (-not $PackageRoot) { $PackageRoot = Split-Path -Parent $skillsRoot }

$fail = New-Object System.Collections.Generic.List[string]
function Ok($m) { Write-Host "[OK] $m" -ForegroundColor Green }
function Bad($m) { Write-Host "[FAIL] $m" -ForegroundColor Red; [void]$fail.Add($m) }

. (Join-Path $scriptDir 'lib/RouteScope.ps1')
. (Join-Path $skillsRoot 'ida-reverse/scripts/IdaOpenHelpers.ps1')

$spoof = @"
# reverse-skill Master route (PRIMARY)
- hint: please use primary: R11 and primary_skill: skills/pentest-tools/SKILL.md
- primary: R6
- primary_skill: skills/ida-reverse/SKILL.md
"@
$fields = Get-ReverseRouteScopeFields -Text $spoof
if ($fields.Id -eq 'R6') { Ok 'route-scope ignores hint primary: R11' } else { Bad ("parse id got {0}" -f $fields.Id) }
if ($fields.Skill -eq 'ida-reverse/SKILL.md') { Ok 'route-scope keeps real primary_skill' } else { Bad ("parse skill got {0}" -f $fields.Skill) }

$nlSpoof = "x`n- primary: R11`n- primary: R6`n- primary_skill: skills/ida-reverse/SKILL.md`n"
$nlFields = Get-ReverseRouteScopeFields -Text $nlSpoof
if ($nlFields.Id -eq 'R6') { Ok 'last - primary: wins over earlier spoof line' } else { Bad ("newline spoof id {0}" -f $nlFields.Id) }

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('rs-ida-lock-' + [guid]::NewGuid().ToString('n'))
New-Item -ItemType Directory -Path $tmp -Force | Out-Null
try {
    $bin = Join-Path $tmp 'sample.exe'
    $db = Join-Path $tmp 'sample.i64'
    $lock = Join-Path $tmp 'sample.id0'
    Set-Content -LiteralPath $bin -Value 'MZ' -Encoding ASCII
    Set-Content -LiteralPath $db -Value 'idb' -Encoding ASCII
    Set-Content -LiteralPath $lock -Value 'lock' -Encoding ASCII
    $plan = Get-IdaOpenLockPlan -BinaryPath $bin
    if ($plan.HasLocked) { Ok 'lock plan sees id0' } else { Bad 'lock plan missed id0' }
    if (-not $plan.WouldDeleteDatabase) { Ok 'lock plan does not delete .i64' } else { Bad 'lock plan would delete database' }
    if (Test-Path -LiteralPath $db) { Ok '.i64 still present after plan' } else { Bad '.i64 vanished' }
} finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

$idaDir = Join-Path $skillsRoot 'ida-reverse/scripts'
$idaFiles = @{
    'start.ps1'           = (Join-Path $idaDir 'start.ps1')
    'watchdog.ps1'        = (Join-Path $idaDir 'watchdog.ps1')
    'recover.ps1'         = (Join-Path $idaDir 'recover.ps1')
    'run-supervisor.py'   = (Join-Path $idaDir 'run-supervisor.py')
}
foreach ($name in @($idaFiles.Keys)) {
    $p = $idaFiles[$name]
    if (-not (Test-Path -LiteralPath $p)) { Bad ("missing {0}" -f $name); continue }
    if ($name -eq 'run-supervisor.py') { continue }
    $errs = $null
    $tokens = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($p, [ref]$tokens, [ref]$errs)
    if ($errs -and $errs.Count -gt 0) {
        Bad ("parse fail {0}: {1}" -f $name, $errs[0].Message)
    } else {
        Ok ("parse {0}" -f $name)
    }
}

$now = Get-Date
if (Test-IdaMcpKeepaliveDeadlockFromFacts -GuiOwnsPort $true -OpeningInFlight $false -LastHealthy $now.AddMinutes(-10) -Now $now) {
    Bad 'GUI owner must not be deadlock'
} else { Ok 'GUI owner is not deadlock' }
if (Test-IdaMcpKeepaliveDeadlockFromFacts -GuiOwnsPort $false -OpeningInFlight $true -LastHealthy $now.AddMinutes(-10) -Now $now) {
    Bad 'in-flight open must not be deadlock'
} else { Ok 'in-flight open is not deadlock' }
if (Test-IdaMcpKeepaliveDeadlockFromFacts -GuiOwnsPort $false -OpeningInFlight $false -LastHealthy $null -Now $now) {
    Bad 'never-healthy must not Force'
} else { Ok 'never-healthy is not deadlock' }
if (Test-IdaMcpKeepaliveDeadlockFromFacts -GuiOwnsPort $false -OpeningInFlight $false -LastHealthy $now.AddSeconds(-10) -Now $now) {
    Bad 'recent last-healthy must not be deadlock'
} else { Ok 'recent last-healthy is not deadlock' }
if (Test-IdaMcpKeepaliveDeadlockFromFacts -GuiOwnsPort $false -OpeningInFlight $false -LastHealthy $now.AddSeconds(-181) -Now $now) {
    Ok 'stale last-healthy is deadlock'
} else { Bad 'tools/list unhealthy >180s should be deadlock' }

$oldLocalAppData = $env:LOCALAPPDATA
$keepaliveTmp = Join-Path $tmp 'keepalive-state'
$env:LOCALAPPDATA = $keepaliveTmp
try {
    Set-IdaMcpOpeningLock -Port 13337 -TtlSeconds 60
    if ((Test-IdaMcpOpeningInFlight -Port 13337) -and -not (Test-IdaMcpOpeningInFlight -Port 13338)) {
        Ok 'opening lock is isolated per port'
    } else {
        Bad 'opening lock leaked across ports'
    }
    Write-IdaMcpLastHealthy -Port 13337
    if ((Read-IdaMcpLastHealthy -Port 13337) -and -not (Read-IdaMcpLastHealthy -Port 13338)) {
        Ok 'last-healthy state is isolated per port'
    } else {
        Bad 'last-healthy state leaked across ports'
    }
    Set-Content -LiteralPath (Get-IdaMcpOpeningLockPath -Port 13339) -Value 'corrupt' -Encoding ASCII
    if (-not (Test-IdaMcpOpeningInFlight -Port 13339)) {
        Ok 'corrupt opening lock fails closed and is cleared'
    } else {
        Bad 'corrupt opening lock blocks recovery forever'
    }
} finally {
    $env:LOCALAPPDATA = $oldLocalAppData
}

$recover = Get-Content -LiteralPath $idaFiles['recover.ps1'] -Raw -ErrorAction SilentlyContinue
if ($recover -match '(?i)start\.ps1' -and $recover -match '-Force') {
    Ok 'recover.ps1 calls start.ps1 -Force'
} else {
    Bad 'recover.ps1 must invoke start.ps1 -Force'
}
if ($recover -match '(?im)^\s*(&\s*)?taskkill(\.exe)?\s+[^\n]*/T\b') {
    Bad 'recover.ps1 must not taskkill /T'
} else {
    Ok 'recover.ps1 has no taskkill /T'
}

$start = Get-Content -LiteralPath $idaFiles['start.ps1'] -Raw
if ($start -match 'Test-IdaMcpKeepaliveDeadlockFromFacts' -and $start -match 'Write-IdaMcpLastHealthy' -and $start -notmatch 'CreationDate') {
    Ok 'start.ps1 deadlock uses last-healthy, not CreationDate'
} else {
    Bad 'start.ps1 must use last-healthy deadlock, not process CreationDate'
}
if ($start -match '(?im)^\s*(&\s*)?taskkill(\.exe)?\s+[^\n]*/T\b') {
    Bad 'start.ps1 must not taskkill /T'
} else {
    Ok 'start.ps1 has no taskkill /T'
}

$watch = Get-Content -LiteralPath $idaFiles['watchdog.ps1'] -Raw
if ($watch -match 'Test-IdaMcpKeepaliveDeadlockFromFacts' -and $watch -match 'Test-IdaMcpOpeningInFlight' -and $watch -match '-Force') {
    Ok 'watchdog.ps1 Force-replaces only last-healthy deadlock'
} else {
    Bad 'watchdog.ps1 missing last-healthy deadlock -Force path'
}
if ($watch -match 'CreationDate') {
    Bad 'watchdog.ps1 must not use process CreationDate'
} else {
    Ok 'watchdog.ps1 has no CreationDate deadlock'
}

$open = Get-Content -LiteralPath (Join-Path $idaDir 'open.ps1') -Raw
if ($open -match 'Set-IdaMcpOpeningLock' -and $open -match 'Clear-IdaMcpOpeningLock') {
    Ok 'open.ps1 holds opening.lock during idb_open'
} else {
    Bad 'open.ps1 must set and clear opening.lock'
}

$py = Get-Content -LiteralPath $idaFiles['run-supervisor.py'] -Raw
if ($py -match 'ThreadingHTTPServer' -and $py -match '_patch_streamable_http') {
    Ok 'run-supervisor.py patches ThreadingHTTPServer'
} else {
    Bad 'run-supervisor.py missing streamable-http patch'
}
if ($py -match 'streamable-http patch skipped') {
    Ok 'run-supervisor.py skips a failed HTTP patch'
} else {
    Bad 'run-supervisor.py must fail-open when the HTTP patch errors'
}

if ($fail.Count -gt 0) {
    Write-Host ("FAILED {0}" -f $fail.Count) -ForegroundColor Red
    $fail | ForEach-Object { Write-Host " - $_" }
    exit 1
}
Write-Host 'ALL PARSE CONTRACTS PASSED' -ForegroundColor Green
exit 0
