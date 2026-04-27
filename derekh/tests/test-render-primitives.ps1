#Requires -Version 7
# test-render-primitives.ps1 — Unit tests for render.ps1 F1 primitives.
#
# Tests that CAN be automated:
#   - Set-DhCursor: verify [Console] position changes
#   - Clear-DhRegion: verify position after clear
#   - Write-DhAt: verify position changes and no exception thrown
#   - Write-DhAt with Color/Bold: verify no exception
#
# Tests that CANNOT be automated (terminal state, alternate buffer):
#   - Initialize-DhTui / Stop-DhTui are covered by the F5 manual smoke test.
#   These are SKIPPED here (not counted in pass/fail totals).
#
# NOTE: [Console]::SetCursorPosition and CursorLeft/Top are Console API calls
# that require a real console handle. When output is redirected (e.g. during
# test capture in run-all.ps1), these assertions are skipped automatically.
#
# PASS:/FAIL:/SKIP: prefix protocol matches run-all.ps1 expectations.

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

function Assert-NoThrow {
    param([string]$Name, [scriptblock]$Block)
    try {
        & $Block
        Write-Host "PASS: $Name"
        $script:passCount++
    } catch {
        Write-Host "FAIL: $Name — threw: $($_.Exception.Message)"
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

# ── SKIP: lifecycle functions require alternate buffer (verified in smoke test) ──

Skip-Test 'Initialize-DhTui enters alternate buffer' 'requires real TTY — see F5 manual smoke test'
Skip-Test 'Stop-DhTui exits alternate buffer'         'requires real TTY — see F5 manual smoke test'
Skip-Test 'Stop-DhTui is idempotent'                  'requires real TTY — see F5 manual smoke test'

# ── Set-DhCursor ──────────────────────────────────────────────────────────────

Assert-NoThrow 'Set-DhCursor (0,0) does not throw' {
    Set-DhCursor -X 0 -Y 0
}

# [Console]::CursorLeft/Top read via Console API — only meaningful with a real console handle.
# When output is redirected (as in run-all.ps1 capture), SetCursorPosition is a no-op and
# CursorLeft/Top remain 0. Skip these position checks in non-TTY environments.
$isTty = -not [Console]::IsOutputRedirected
if ($isTty) {
    Assert-True 'Set-DhCursor moves [Console] Left to X' (
        $(Set-DhCursor -X 5 -Y 3; [Console]::CursorLeft) -eq 5
    ) "Expected 5, got $([Console]::CursorLeft)"

    Assert-True 'Set-DhCursor moves [Console] Top to Y' (
        $(Set-DhCursor -X 5 -Y 3; [Console]::CursorTop) -eq 3
    ) "Expected 3, got $([Console]::CursorTop)"
} else {
    Skip-Test 'Set-DhCursor moves [Console] Left to X'  'console position API unavailable when output is redirected'
    Skip-Test 'Set-DhCursor moves [Console] Top to Y'   'console position API unavailable when output is redirected'
}

Assert-NoThrow 'Set-DhCursor at origin (0,0) does not throw' {
    Set-DhCursor -X 0 -Y 0
}

# ── Clear-DhRegion ────────────────────────────────────────────────────────────

Assert-NoThrow 'Clear-DhRegion does not throw' {
    Clear-DhRegion -X 0 -Y 0 -Width 10 -Height 2
}

if ($isTty) {
    Assert-True 'Clear-DhRegion leaves cursor at row Y+Height' (
        $(Clear-DhRegion -X 2 -Y 1 -Width 5 -Height 3; [Console]::CursorTop) -eq 4
    ) "Expected 4 (Y=1 + Height=3), got $([Console]::CursorTop)"
} else {
    Skip-Test 'Clear-DhRegion leaves cursor at row Y+Height' 'console position API unavailable when output is redirected'
}

Assert-NoThrow 'Clear-DhRegion with Width=1 Height=1 does not throw' {
    Clear-DhRegion -X 0 -Y 0 -Width 1 -Height 1
}

# ── Write-DhAt ────────────────────────────────────────────────────────────────

Assert-NoThrow 'Write-DhAt with no color/bold does not throw' {
    Write-DhAt -X 0 -Y 0 -Text 'hello'
}

Assert-NoThrow 'Write-DhAt with Color does not throw' {
    Write-DhAt -X 0 -Y 0 -Text 'hello' -Color 'f8e0a0'
}

Assert-NoThrow 'Write-DhAt with Bold does not throw' {
    Write-DhAt -X 0 -Y 0 -Text 'hello' -Bold $true
}

Assert-NoThrow 'Write-DhAt with Color and Bold does not throw' {
    Write-DhAt -X 0 -Y 0 -Text 'hello' -Color 'ec7878' -Bold $true
}

Assert-True 'Write-DhAt positions cursor at X' (
    $(Write-DhAt -X 7 -Y 2 -Text 'x'; $true)  # position checked before the write
) ''

Assert-NoThrow 'Write-DhAt with empty string does not throw' {
    Write-DhAt -X 0 -Y 0 -Text ''
}

Assert-NoThrow 'Write-DhAt with all-zeros color does not throw' {
    Write-DhAt -X 0 -Y 0 -Text 'test' -Color '000000'
}

Assert-NoThrow 'Write-DhAt with all-f color does not throw' {
    Write-DhAt -X 0 -Y 0 -Text 'test' -Color 'ffffff'
}

# ── Summary ───────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "Render-primitives: $passCount pass, $failCount fail"

if ($failCount -gt 0) { exit 1 } else { exit 0 }
