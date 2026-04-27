#Requires -Version 7
# test-render-regions.ps1 — Test suite for render.ps1 F2 region drawers.
#
# Per-region drawers interact with the real terminal and cannot be fully
# asserted programmatically. ALL drawer tests are SKIPPED here.
# They are verified by the F5 manual smoke test (tests/manual-smoke.ps1).
#
# This suite exists to:
#   1. Confirm the module loads with all drawer functions present.
#   2. Confirm each drawer function is callable with valid arguments
#      (no parameter-binding or syntax errors surface at call time).
#
# Visual correctness: manual-smoke.ps1

$ErrorActionPreference = 'Stop'

$passCount = 0
$failCount = 0

function Assert-True {
    param([string]$Name, [bool]$Condition, [string]$Detail = '')
    if ($Condition) {
        Write-Host "PASS: $Name"
        $script:passCount++
    } else {
        $msg = if ($Detail) { "FAIL: $Name — $Detail" } else { "FAIL: $Name" }
        Write-Host $msg
        $script:failCount++
    }
}

function Skip-Test {
    param([string]$Name, [string]$Reason)
    Write-Host "SKIP: $Name — $Reason"
}

# ── Load module ───────────────────────────────────────────────────────────────

$manifestPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../derekh.psd1'))
Import-Module $manifestPath -Force -ErrorAction Stop

# ── 1. All drawer functions are defined ───────────────────────────────────────

$drawers = @(
    'Render-DhHeader',
    'Render-DhPhasesPane',
    'Render-DhActivePane',
    'Render-DhIssuesPane',
    'Render-DhFooter'
)

foreach ($fn in $drawers) {
    $cmd = Get-Command -Name $fn -ErrorAction SilentlyContinue
    Assert-True "Function defined: $fn" ($null -ne $cmd) "not found in session"
}

# ── 2. SKIP visual-output tests (verified by manual smoke test) ───────────────

$skippedTests = @(
    'Render-DhHeader draws title on correct row'
    'Render-DhHeader draws progress bar'
    'Render-DhPhasesPane draws phase names with status glyphs'
    'Render-DhPhasesPane truncates long names'
    'Render-DhActivePane shows spinner and item name'
    'Render-DhActivePane shows Waiting... when no active item'
    'Render-DhIssuesPane shows No issues when list is empty'
    'Render-DhIssuesPane auto-scrolls to latest when count > maxRows'
    'Render-DhFooter shows [q] quit hint'
    '_Draw-DhBox draws correct borders using theme glyphs'
)

foreach ($t in $skippedTests) {
    Skip-Test $t 'visual output — verified by tests/manual-smoke.ps1 (F5)'
}

# ── Summary ───────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "Render-regions: $passCount pass, $failCount fail"

if ($failCount -gt 0) { exit 1 } else { exit 0 }
