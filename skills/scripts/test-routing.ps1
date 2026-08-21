#Requires -Version 5.1
# reverse-skill 路由回归测试器：跑 routing-benchmark.json 全部用例，比对 PRIMARY 期望。
# 用法：
#   powershell -NoProfile -ExecutionPolicy Bypass -File skills/scripts/test-routing.ps1
#   powershell -File skills/scripts/test-routing.ps1 -Quick          # 只跑 quick 最小回归集
#   powershell -File skills/scripts/test-routing.ps1 -Benchmark <path> -LogDir <dir>
# 退出码：0 全绿 / 1 有用例失败（failures 详情写入 LogDir）
param(
    [string] $Benchmark = '',
    [switch] $Quick,
    [string] $LogDir = '',
    [string] $PackageRoot = ''
)
$ErrorActionPreference = 'Stop'

$scriptDir = $PSScriptRoot
. (Join-Path $scriptDir 'lib/RouteScope.ps1')
if (-not $scriptDir) { $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path }
$skillsRoot = Split-Path -Parent $scriptDir
if (-not $PackageRoot) { $PackageRoot = Split-Path -Parent $skillsRoot }

. (Join-Path (Join-Path $scriptDir 'lib') 'HostRuntime.ps1')
$HostExe = Resolve-ReverseHostExe

if ([string]::IsNullOrWhiteSpace($Benchmark)) {
    $Benchmark = Join-Path $skillsRoot 'tests/routing-benchmark.json'
}
if (-not (Test-Path -LiteralPath $Benchmark)) {
    Write-Host ("ERROR: benchmark not found: {0}" -f $Benchmark) -ForegroundColor Red
    exit 2
}
$bm = Get-Content -LiteralPath $Benchmark -Raw -Encoding UTF8 | ConvertFrom-Json

# $env:TEMP 在 Linux/macOS runner 上可能未设置，统一用 GetTempPath fallback
$tmpBase = if ($env:TEMP) { $env:TEMP } else { [System.IO.Path]::GetTempPath() }

if ([string]::IsNullOrWhiteSpace($LogDir)) {
    $LogDir = Join-Path $tmpBase ("rs-routing-test-{0}" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

$masterRoute = Join-Path $scriptDir 'master-route.ps1'
$cases = @($bm.cases)
if ($Quick) { $cases = @($cases | Where-Object { $_.quick }) }

$fail = New-Object System.Collections.Generic.List[string]
$pass = 0
$failCount = 0
$detail = New-Object System.Collections.Generic.List[string]

Write-Host ("=== test-routing | {0} cases (quick={1}) ===" -f $cases.Count, [bool]$Quick)

foreach ($c in $cases) {
    $tmp = Join-Path $tmpBase ("rs-rt-{0}" -f [guid]::NewGuid().ToString('n'))
    $got = 'ERR'
    try {
        $null = & $HostExe -NoProfile -ExecutionPolicy Bypass -File $masterRoute -Hint $c.hint -OutDir $tmp 2>&1
        $scope = Join-Path $tmp 'route-scope.md'
        if (Test-Path -LiteralPath $scope) {
            $text = Get-Content -LiteralPath $scope -Raw -Encoding UTF8
            $parsed = Get-ReverseRouteScopeFields -Text $text
            if ($parsed.Id) { $got = $parsed.Id }
        }
    } catch {
        $got = 'EXC:' + $_.Exception.Message
    } finally {
        Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
    }

    if ($got -eq $c.expect) {
        $pass++
        [void]$detail.Add(("PASS {0} -> {1}" -f $c.expect, $c.hint))
    } else {
        $failCount++
        $msg = ("FAIL hint='{0}' expect={1} got={2}" -f $c.hint, $c.expect, $got)
        Write-Host ("[FAIL] {0}" -f $msg) -ForegroundColor Red
        [void]$fail.Add($msg)
        [void]$detail.Add($msg)
    }
}

$detail -join [Environment]::NewLine | Set-Content -LiteralPath (Join-Path $LogDir 'cases.txt') -Encoding UTF8

$summary = @(
    "TOTAL=$($cases.Count)",
    "PASS=$pass",
    "FAIL=$failCount",
    "QUICK=$([bool]$Quick)",
    "LogDir=$LogDir"
)
$summary -join [Environment]::NewLine | Set-Content -LiteralPath (Join-Path $LogDir 'SUMMARY.txt') -Encoding UTF8
Write-Host ('=== ROUTING TEST SUMMARY ===')
$summary | ForEach-Object { Write-Host $_ }
if ($failCount -gt 0) {
    $fail | Set-Content -LiteralPath (Join-Path $LogDir 'failures.txt') -Encoding UTF8
    Write-Host "OVERALL: FAIL ($failCount)" -ForegroundColor Red
    exit 1
}
Write-Host "OVERALL: ALL PASS ($pass)" -ForegroundColor Green
exit 0
