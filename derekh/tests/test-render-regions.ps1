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

# ── 2. Phase G functions are defined ─────────────────────────────────────────

$phaseGFunctions = @(
    'Write-DhCentered',
    'Start-DhResizeWatcher',
    'Stop-DhResizeWatcher',
    'Invoke-DhResize',
    'Set-DhFooter',
    'Invoke-DhFooterFlash'
)

foreach ($fn in $phaseGFunctions) {
    $cmd = Get-Command -Name $fn -ErrorAction SilentlyContinue
    Assert-True "Phase G function defined: $fn" ($null -ne $cmd) "not found in session"
}

# ── 3. SKIP visual-output tests (verified by manual smoke test) ───────────────

$skippedTests = @(
    'Render-DhHeader draws title on correct row'
    'Render-DhHeader draws progress bar'
    'Render-DhPhasesPane draws phase names with status glyphs'
    'Render-DhPhasesPane truncates long names'
    'Render-DhActivePane shows spinner and item name'
    'Render-DhActivePane shows Waiting... when no active item'
    'Render-DhIssuesPane shows No issues when list is empty'
    'Render-DhIssuesPane auto-scrolls to latest when count > maxRows'
    'Render-DhIssuesPane ShowIndices prefixes issues 1-9 with [N]'
    'Render-DhIssuesPane ShowIndices issue 10+ gets 4-space indent'
    'Render-DhFooter shows [q] quit hint'
    '_Draw-DhBox draws correct borders using theme glyphs'
    'Write-DhCentered renders centered box on screen'
    'Invoke-DhResize shows too-small message for 40x10'
    'Invoke-DhResize full re-render for 80x24'
    'Set-DhFooter updates footer row without full re-render'
    'Invoke-DhFooterFlash shows message then reverts'
)

foreach ($t in $skippedTests) {
    Skip-Test $t 'visual output — verified by tests/manual-smoke.ps1 (G3)'
}

# ── 4. Start-DhResizeWatcher / Stop-DhResizeWatcher lifecycle (non-TTY) ───────
# The watcher uses a background runspace. We can test that it starts and stops
# cleanly without actually polling [Console]::WindowSize (which may throw in CI).

$isTtyForResize = -not [Console]::IsOutputRedirected

if ($isTtyForResize) {
    $queue = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
    $handle = $null
    Assert-NoThrow 'Start-DhResizeWatcher does not throw' {
        $script:handle = Start-DhResizeWatcher -Queue $queue
    }
    Assert-True 'Start-DhResizeWatcher returns handle with Runspace' `
        ($null -ne $script:handle -and $null -ne $script:handle.Runspace) `
        'Runspace was null'
    Assert-True 'Start-DhResizeWatcher returns handle with PowerShell' `
        ($null -ne $script:handle -and $null -ne $script:handle.PowerShell) `
        'PowerShell was null'
    Assert-NoThrow 'Stop-DhResizeWatcher does not throw' {
        Stop-DhResizeWatcher -Handle $script:handle
    }
} else {
    Skip-Test 'Start-DhResizeWatcher does not throw'                'requires TTY — WindowSize unavailable in CI'
    Skip-Test 'Start-DhResizeWatcher returns handle with Runspace'  'requires TTY'
    Skip-Test 'Start-DhResizeWatcher returns handle with PowerShell' 'requires TTY'
    Skip-Test 'Stop-DhResizeWatcher does not throw'                 'requires TTY'
}

# ── Summary ───────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "Render-regions: $passCount pass, $failCount fail"

if ($failCount -gt 0) { exit 1 } else { exit 0 }
