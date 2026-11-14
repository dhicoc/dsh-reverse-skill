<#
.SYNOPSIS
  Verify doc fact tables (capability lists, MCP ports, Burp tool count)
  against source-of-truth (bootstrap-manifest.json / McpHttpServer.java).

.DESCRIPTION
  P1-4 guard: RULES.md / RULES_zh.md / skills/SKILL.md fact tables must not
  drift from the manifest and the Burp extension source. Exit 1 on mismatch.

  Layout note: this repository is the dsh packaging of reverse-skill and ships
  only `skills/` and `CTF-Sandbox-Orchestrator/` (package.json `files`). The
  upstream-only sources `burp-mcp-full/` and root `RULES_zh.md` are therefore
  absent here. Checks whose source-of-truth is absent are reported as [N/A]
  and listed in the summary instead of being silently skipped or counted as
  passes; every check that CAN run still runs and still fails on drift.
#>
$ErrorActionPreference = 'Stop'
$Root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$SkillsRoot = Join-Path $Root 'skills'
$fail = 0
$na = New-Object System.Collections.Generic.List[string]

function Check([string]$Name, [bool]$Ok, [string]$Detail) {
  if ($Ok) { Write-Host "OK   $Name" } else { $script:fail++; Write-Host "FAIL $Name : $Detail" }
}
function Skip([string]$Name, [string]$Why) {
  [void]$na.Add("$Name ($Why)")
  Write-Host "N/A  $Name : $Why"
}
# 包根优先、skills/ 兜底：本 port 把规则文档放在 skills/ 下。
function Resolve-Doc([string]$Leaf) {
  foreach ($r in @($Root, $SkillsRoot)) {
    $p = Join-Path $r $Leaf
    if (Test-Path -LiteralPath $p -PathType Leaf) { return $p }
  }
  return $null
}

# --- Source of truth: manifest ---
$manifestPath = Join-Path $Root 'skills\scripts\bootstrap-manifest.json'
$manifest = Get-Content $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$capNames = @($manifest.capabilities | ForEach-Object { $_.name } | Sort-Object)

# --- Source of truth: Burp getToolList() (upstream-only directory; absent here) ---
$javaPath = Join-Path $Root 'burp-mcp-full\src\main\java\com\burpmcp\McpHttpServer.java'
$burpCount = $null
if (Test-Path -LiteralPath $javaPath -PathType Leaf) {
  $java = Get-Content $javaPath -Raw
  $def = [regex]::Match($java, 'String\s+getToolList\s*\([^)]*\)\s*\{')
  if (-not $def.Success) { throw 'getToolList() not found in McpHttpServer.java' }
  $endIdx = $java.IndexOf("`n    }", $def.Index)
  $body = $java.Substring($def.Index, $endIdx - $def.Index)
  $burpTools = @([regex]::Matches($body, '\\"([a-z_0-9]+)\\"') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
  $burpCount = $burpTools.Count
}

if ($null -ne $burpCount) {
  Write-Host "source-of-truth: $($capNames.Count) capabilities, Burp getToolList = $burpCount tools"
} else {
  Write-Host "source-of-truth: $($capNames.Count) capabilities, Burp getToolList = N/A (burp-mcp-full/ not shipped)"
}

# --- Doc helpers ---
function Get-ListLine([string]$Text, [string]$Marker) {
  $lines = $Text -split "`r?`n"
  for ($i = 0; $i -lt $lines.Count; $i++) {
    if ($lines[$i] -match [regex]::Escape($Marker)) {
      $inline = [regex]::Match($lines[$i], '）：(.+?)\s*$')
      if ($inline.Success) { return $inline.Groups[1].Value }
      if ($i + 1 -lt $lines.Count) { return $lines[$i + 1] }
    }
  }
  return ''
}

function Test-ListHasAll([string]$ListText, [string[]]$Names) {
  $tokens = @($ListText -split '[、,]+' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
  if ($tokens.Count -ne $Names.Count) { return $false }
  foreach ($n in $Names) { if ($tokens -notcontains $n) { return $false } }
  return $true
}

$rulesEnPath = Resolve-Doc 'RULES.md'
$rulesZhPath = Resolve-Doc 'RULES_zh.md'
$rulesEn = if ($rulesEnPath) { Get-Content $rulesEnPath -Raw -Encoding UTF8 } else { $null }
$rulesZh = if ($rulesZhPath) { Get-Content $rulesZhPath -Raw -Encoding UTF8 } else { $null }
$skillMd = Get-Content (Join-Path $SkillsRoot 'reverse-skill-router/SKILL.md') -Raw -Encoding UTF8

if ($rulesEn) {
  $enList = Get-ListLine $rulesEn 'Supported capability names'
  Check 'RULES.md capability list' (Test-ListHasAll $enList $capNames) "expected $($capNames.Count) capabilities: $($capNames -join ', ')"
} else {
  Skip 'RULES.md capability list' 'RULES.md not shipped (searched package root and skills/)'
}
if ($rulesZh) {
  $zhList = Get-ListLine $rulesZh '支持的能力名'
  Check 'RULES_zh.md capability list' (Test-ListHasAll $zhList $capNames) "expected $($capNames.Count) capabilities"
} else {
  Skip 'RULES_zh.md capability list' 'RULES_zh.md not shipped (one client-neutral rulebook at skills/RULES.md)'
}
$skList = Get-ListLine $skillMd '支持的能力'
Check 'SKILL.md capability list' (Test-ListHasAll $skList $capNames) "expected $($capNames.Count) capabilities"
if ($rulesZh) {
  Check 'RULES_zh.md count text' ($rulesZh.Contains("共 $($capNames.Count) 项")) "expected 共 $($capNames.Count) 项"
} else {
  Skip 'RULES_zh.md count text' 'RULES_zh.md not shipped'
}

# --- MCP ports from manifest servicePort / servicePortRange ---
foreach ($c in $manifest.capabilities) {
  if (-not $c.PSObject.Properties['servicePort']) { continue }
  $port = [string]$c.servicePort
  if ($rulesEn) {
    Check "RULES.md port $($c.name)=$port" ($rulesEn.Contains($port)) "missing port $port for $($c.name)"
  } else {
    Skip "RULES.md port $($c.name)=$port" 'RULES.md not shipped'
  }
  if ($rulesZh) {
    Check "RULES_zh.md port $($c.name)=$port" ($rulesZh.Contains($port)) "missing port $port for $($c.name)"
  } else {
    Skip "RULES_zh.md port $($c.name)=$port" 'RULES_zh.md not shipped'
  }
  if ($c.PSObject.Properties['servicePortRange']) {
    $range = @($c.servicePortRange) -join '-'
    if ($rulesEn) {
      Check "RULES.md range $($c.name)=$range" ($rulesEn.Contains($range)) "missing range $range for $($c.name)"
    } else {
      Skip "RULES.md range $($c.name)=$range" 'RULES.md not shipped'
    }
    if ($rulesZh) {
      Check "RULES_zh.md range $($c.name)=$range" ($rulesZh.Contains($range)) "missing range $range for $($c.name)"
    } else {
      Skip "RULES_zh.md range $($c.name)=$range" 'RULES_zh.md not shipped'
    }
  }
}

# --- Burp tool count ---
if ($null -ne $burpCount) {
  if ($rulesEn) {
    Check 'RULES.md burp tool count' ($rulesEn.Contains("$burpCount-tool")) "expected '$burpCount-tool' in RULES.md"
  } else {
    Skip 'RULES.md burp tool count' 'RULES.md not shipped'
  }
  if ($rulesZh) {
    Check 'RULES_zh.md burp tool count' ($rulesZh.Contains("$burpCount 工具全控制")) "expected '$burpCount 工具全控制' in RULES_zh.md"
  } else {
    Skip 'RULES_zh.md burp tool count' 'RULES_zh.md not shipped'
  }
} else {
  Skip 'burp tool count' 'burp-mcp-full/ not shipped (upstream-only)'
}

if ($na.Count -gt 0) {
  Write-Host "not-applicable: $($na.Count) check(s) skipped because their source-of-truth is not shipped in this port"
}
Write-Host "verify-doc-facts: $fail failure(s)"
if ($fail -gt 0) { exit 1 }
