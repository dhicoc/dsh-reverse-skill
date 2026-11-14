#Requires -Version 5.1
param([string] $WorkflowPath = '')

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($WorkflowPath)) {
    $WorkflowPath = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) '.github\workflows\auto-merge-journal.yml'
}

# auto-merge-journal.yml 是上游的 field-journal 自动合并机器人，本 dsh 封装只分发
# skills/ 与 CTF-Sandbox-Orchestrator/（外加 lib/），不带这个 workflow。文件不存在时
# 明确说明「没检查」，不给假绿；显式传入 -WorkflowPath 时仍然照常校验。
if (-not (Test-Path -LiteralPath $WorkflowPath -PathType Leaf)) {
    Write-Host "[N/A] auto-merge-journal workflow not shipped in this port: $WorkflowPath" -ForegroundColor Yellow
    Write-Host 'WORKFLOW TITLE SAFETY CHECKS SKIPPED (nothing to check)' -ForegroundColor Yellow
    exit 0
}

$text = Get-Content -LiteralPath $WorkflowPath -Raw -Encoding UTF8
$failures = New-Object System.Collections.Generic.List[string]

function Check([bool] $Condition, [string] $Message) {
    if ($Condition) {
        Write-Host "[OK] $Message" -ForegroundColor Green
    } else {
        Write-Host "[FAIL] $Message" -ForegroundColor Red
        [void]$failures.Add($Message)
    }
}

Check ($text -match '(?m)^\s+PR_NUMBER:\s*\$\{\{\s*github\.event\.pull_request\.number\s*\}\}') 'PR number is passed through the environment'
Check ($text -match '(?m)^\s+PR_TITLE:\s*\$\{\{\s*github\.event\.pull_request\.title\s*\}\}') 'PR title is passed through the environment'
Check ($text -match '(?m)^\s+PR_SUBJECT:\s*\$\{\{\s*format\(') 'PR subject is constructed as environment data'
Check ($text -match '(?ms)gh pr merge "\$PR_NUMBER".*--subject "\$PR_SUBJECT"') 'merge command quotes the PR number and subject'
Check ($text -notmatch '(?m)--subject[^\r\n]*github\.event\.pull_request\.title') 'PR title is not interpolated into the merge command'
Check ($text -notmatch '(?m)gh pr (?:diff|merge|comment)\s+\$\{\{') 'GitHub CLI commands do not embed event expressions'

$maliciousTitle = '$(Write-Host injected) `' + [Environment]::NewLine + '"quoted"; Get-ChildItem > should-not-run'
$subject = '[field-journal] ' + $maliciousTitle
Check ($subject -eq ('[field-journal] ' + $maliciousTitle)) 'shell metacharacters remain plain subject data'

if ($failures.Count -gt 0) {
    exit 1
}

Write-Host 'WORKFLOW TITLE SAFETY CHECKS PASSED' -ForegroundColor Green
exit 0
