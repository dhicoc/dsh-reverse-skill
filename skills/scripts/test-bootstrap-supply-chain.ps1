$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('reverse-bootstrap-ps-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch | Out-Null

function Ensure-DownloadDirectory { param([string]$Path) New-Item -ItemType Directory -Path $Path -Force | Out-Null }
function Get-FirstCommandPath { param([string[]]$Names) return (Get-Command $Names[0]).Source }
function Ensure-NodeRuntime {}
function Get-NodeCommandPath { param([string]$Name) $command = Get-Command $Name -ErrorAction SilentlyContinue; if ($command) { return $command.Source } }
function Get-BootstrapDependency { return [pscustomobject]@{ package = 'pnpm@10.24.0'; version = '10.24.0' } }
function Approve-AnythingAnalyzerBuildScripts { param([string]$RepoDir) Set-Content (Join-Path $RepoDir 'pnpm-workspace.yaml') 'generated' }
function Test-AnythingAnalyzerElectronHealthy { return $true }

. (Join-Path $PSScriptRoot 'lib/BootstrapSupplyChain.ps1')

function Assert-True { param([bool]$Condition, [string]$Message) if (-not $Condition) { throw $Message } }
function Invoke-Git { param([string[]]$Arguments) & git @Arguments; if ($LASTEXITCODE -ne 0) { throw "git failed: $Arguments" } }
function Write-UnixExecutable {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )
    $normalized = ($Content -replace "`r`n", "`n") -replace "`r", "`n"
    if (-not $normalized.EndsWith("`n")) { $normalized += "`n" }
    [IO.File]::WriteAllText($Path, $normalized, [Text.UTF8Encoding]::new($false))
    & chmod +x $Path
}

try {
    $source = Join-Path $scratch 'source'
    New-Item -ItemType Directory -Path $source | Out-Null
    Invoke-Git -Arguments @('-C', $source, 'init', '--quiet')
    Invoke-Git -Arguments @('-C', $source, 'config', 'user.email', 'test@example.invalid')
    Invoke-Git -Arguments @('-C', $source, 'config', 'user.name', 'test')
    Set-Content (Join-Path $source 'package.json') '{}'
    Invoke-Git -Arguments @('-C', $source, 'add', 'package.json')
    Invoke-Git -Arguments @('-C', $source, 'commit', '--quiet', '-m', 'fixture')
    $pin = (& git -C $source rev-parse HEAD).Trim()
    $definition = [pscustomobject]@{ repo = $source; pinnedCommit = $pin }

    $target = Join-Path $scratch 'installed'
    Ensure-GitCloneInstall -Definition $definition -TargetPath $target | Out-Null
    Assert-True ((& git -C $target rev-parse HEAD).Trim() -eq $pin) 'pinned checkout was not promoted'
    Set-Content (Join-Path $target 'package.json') '{"dirty":true}'
    try { Ensure-GitCloneInstall -Definition $definition -TargetPath $target | Out-Null; throw 'dirty checkout accepted' } catch { Assert-True ($_.Exception.Message -match 'local changes') 'dirty rejection reason changed' }

    $failedTarget = Join-Path $scratch 'failed'
    $badDefinition = [pscustomobject]@{ repo = (Join-Path $scratch 'missing'); pinnedCommit = $pin }
    $failedFetchRejected = $false
    try { Ensure-GitCloneInstall -Definition $badDefinition -TargetPath $failedTarget | Out-Null } catch { $failedFetchRejected = $true }
    Assert-True $failedFetchRejected 'failed fetch accepted'
    Assert-True (-not (Test-Path $failedTarget)) 'failed fetch poisoned final path'
    Assert-True (@(Get-ChildItem $scratch -Filter '.reverse-bootstrap-*').Count -eq 0) 'failed fetch left staging path'

    $raceTarget = Join-Path $scratch 'race'
    $raceStage = Join-Path $scratch '.reverse-bootstrap-race'
    New-Item -ItemType Directory -Path $raceTarget, $raceStage | Out-Null
    Set-Content (Join-Path $raceTarget 'owner.txt') owner
    $raceRejected = $false
    try { Move-BootstrapDirectory -Source $raceStage -Destination $raceTarget } catch { $raceRejected = $true }
    Assert-True $raceRejected 'promotion race accepted'
    Assert-True ((Get-Content (Join-Path $raceTarget 'owner.txt')) -eq 'owner') 'promotion race modified concurrent target'
    Remove-Item -LiteralPath $raceStage -Recurse -Force

    $bin = Join-Path $scratch 'bin'
    New-Item -ItemType Directory -Path $bin | Out-Null
    $env:PATH = "$bin$([IO.Path]::PathSeparator)$env:PATH"
    $env:BOOTSTRAP_PS_LOG = Join-Path $scratch 'commands.log'
    $isWindowsHost = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
    $stub = Join-Path $bin ($(if ($isWindowsHost) { 'npm.cmd' } else { 'npm' }))
    if ($isWindowsHost) {
        Set-Content $stub @'
@echo off
echo npm^|%*>>"%BOOTSTRAP_PS_LOG%"
'@
    }
    else {
        Write-UnixExecutable -Path $stub -Content @'
#!/bin/sh
printf "npm|%s\n" "$*" >> "$BOOTSTRAP_PS_LOG"
'@
    }
    $pnpm = Join-Path $bin ($(if ($isWindowsHost) { 'pnpm.cmd' } else { 'pnpm' }))
    if ($isWindowsHost) { Set-Content $pnpm "@echo off`r`necho 0" }
    else { Write-UnixExecutable -Path $pnpm -Content "#!/bin/sh`necho 0" }
    Ensure-Pnpm
    Assert-True ((Get-Content $env:BOOTSTRAP_PS_LOG) -match 'npm\|install -g pnpm@10.24.0') 'pnpm install was not pinned'

    Invoke-Git -Arguments @('-C', $target, 'checkout', '--quiet', '--', 'package.json')
    if ($isWindowsHost) {
        Set-Content $pnpm @'
@echo off
if "%1"=="--version" (echo 10.24.0) else (echo pnpm^|%*>>"%BOOTSTRAP_PS_LOG%")
'@
    }
    else {
        Write-UnixExecutable -Path $pnpm -Content @'
#!/bin/sh
[ "$1" = --version ] && { echo 10.24.0; exit; }
printf "pnpm|%s\n" "$*" >> "$BOOTSTRAP_PS_LOG"
'@
    }
    $commandLogBefore = Get-Content -LiteralPath $env:BOOTSTRAP_PS_LOG -Raw
    Ensure-Pnpm
    $commandLogAfter = Get-Content -LiteralPath $env:BOOTSTRAP_PS_LOG -Raw
    Assert-True ($commandLogAfter -eq $commandLogBefore) 'matching pnpm version triggered reinstall'
    function Approve-AnythingAnalyzerBuildScripts { param([string]$RepoDir) Set-Content (Join-Path $RepoDir 'pnpm-workspace.yaml') 'generated'; Set-Content (Join-Path $RepoDir 'package.json') '{"mutated":true}' }
    $dirtyRejected = $false
    try { Invoke-AnythingAnalyzerPinnedInstall -RepoDir $target -PnpmPath $pnpm -GitPath (Get-Command git).Source -PinnedCommit $pin } catch { $dirtyRejected = $_.Exception.Message -match 'local changes' }
    Assert-True $dirtyRejected 'post-install dirty checkout accepted or rejection reason changed'
    Assert-True (-not (Test-Path (Join-Path $target 'pnpm-workspace.yaml'))) 'generated workspace file was not removed'

    Invoke-Git -Arguments @('-C', $target, 'config', 'user.email', 'test@example.invalid')
    Invoke-Git -Arguments @('-C', $target, 'config', 'user.name', 'test')
    Invoke-Git -Arguments @('-C', $target, 'commit', '--allow-empty', '--quiet', '-m', 'wrong checkout')
    $wrongCommitRejected = $false
    try { Ensure-GitCloneInstall -Definition $definition -TargetPath $target | Out-Null } catch { $wrongCommitRejected = $_.Exception.Message -match 'expected' }
    Assert-True $wrongCommitRejected 'clean wrong-commit checkout accepted'

    $publicProfile = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
    $publicTools = Join-Path $publicProfile 'Tools'
    $publicTarget = Join-Path $publicTools 'SecLists'
    if (Test-Path -LiteralPath $publicTarget) {
        Write-Host 'SKIP: public bootstrap exit regression (existing SecLists checkout)'
    }
    else {
        $createdPublicTools = -not (Test-Path -LiteralPath $publicTools)
        try {
            New-Item -ItemType Directory -Path $publicTarget -Force | Out-Null
            Invoke-Git -Arguments @('-C', $publicTarget, 'init', '--quiet')
            Invoke-Git -Arguments @('-C', $publicTarget, 'config', 'user.email', 'test@example.invalid')
            Invoke-Git -Arguments @('-C', $publicTarget, 'config', 'user.name', 'test')
            Set-Content (Join-Path $publicTarget 'fixture.txt') 'wrong checkout'
            Invoke-Git -Arguments @('-C', $publicTarget, 'add', 'fixture.txt')
            Invoke-Git -Arguments @('-C', $publicTarget, 'commit', '--quiet', '-m', 'fixture')

            $powerShellHost = if ($PSVersionTable.PSEdition -eq 'Desktop') { Join-Path $PSHOME 'powershell.exe' } else { Join-Path $PSHOME 'pwsh' }
            $childOutput = @(& $powerShellHost -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'bootstrap-reverse.ps1') -Capability seclists -SkipRefresh)
            $childExitCode = $LASTEXITCODE
            $global:LASTEXITCODE = 0
            $childResult = ($childOutput -join [Environment]::NewLine) | ConvertFrom-Json
            Assert-True ($childExitCode -ne 0) 'failed public bootstrap exited successfully'
            Assert-True ($childResult.status -eq 'failed') 'failed public bootstrap did not report failed status'
            Assert-True ($childResult.error -match 'Checkout verification failed') 'failed public bootstrap did not report checkout verification'
        }
        finally {
            Remove-Item -LiteralPath $publicTarget -Recurse -Force -ErrorAction SilentlyContinue
            if ($createdPublicTools -and (Test-Path -LiteralPath $publicTools) -and (@(Get-ChildItem -LiteralPath $publicTools -Force).Count -eq 0)) {
                Remove-Item -LiteralPath $publicTools -Force -ErrorAction SilentlyContinue
            }
        }
    }

    . (Join-Path $PSScriptRoot 'bootstrap-reverse.ps1') -Capability '__test_missing__' -SkipRefresh | Out-Null
    $script:gitCloneDefinition = [pscustomobject]@{
        name = 'test-git-clone'
        bootstrapKind = 'git-clone'
        canAutoInstall = $true
        installDir = (Join-Path $scratch 'test-git-clone')
    }
    $script:gitCloneVerifierCalled = $false
    function Get-ReverseBootstrapDefinition { param([string]$Name) return $script:gitCloneDefinition }
    function Get-ReverseCapabilityState { param([string]$Name) return [pscustomobject]@{ Ready = $true } }
    function Resolve-ReverseToolSpec { param([string]$Name) return [pscustomobject]@{ Available = $true } }
    function Ensure-GitCloneInstall {
        param($Definition, [string]$TargetPath)
        $script:gitCloneVerifierCalled = $true
        return [pscustomobject]@{ Verified = $true }
    }
    $gitCloneResult = Ensure-Capability -Name 'test-git-clone'
    Assert-True $script:gitCloneVerifierCalled 'available git-clone capability skipped checkout verification'
    Assert-True $gitCloneResult.Verified 'git-clone capability did not return checkout verification result'

    $script:serviceCheckoutVerifierCalled = $false
    function Ensure-GitCloneInstall {
        param($Definition, [string]$TargetPath)
        $script:serviceCheckoutVerifierCalled = $true
    }
    function Test-ReverseTcpPort { param([int]$Port) return $true }
    Start-AnythingAnalyzerService -Definition ([pscustomobject]@{
        installDir = (Join-Path $scratch 'anything-analyzer')
        repoUrl = $source
        pinnedCommit = $pin
        servicePort = 23816
    }) -AuthToken 'test-token'
    Assert-True $script:serviceCheckoutVerifierCalled 'running Anything Analyzer service skipped checkout verification'

    Write-Host 'PowerShell bootstrap supply-chain regression passed'
}
finally {
    Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
}
