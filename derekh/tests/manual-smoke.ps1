#Requires -Version 7
# tests/manual-smoke.ps1 — Derekh Phase G manual TUI smoke test.
#
# ══════════════════════════════════════════════════════════════════════════════
# MANUAL RUN ONLY — do NOT add to run-all.ps1 or CI.
# This script launches the full TUI and requires a human to visually verify.
#
# Usage:
#   pwsh tests/manual-smoke.ps1
#
# Requirements:
#   - Terminal at least 80x24 (wider is fine; resize testing starts bigger)
#   - UTF-8 capable terminal (Windows Terminal, iTerm2, Ghostty, etc.)
#   - Module imported from ../derekh.psd1 (script does this automatically)
#
# ══════════════════════════════════════════════════════════════════════════════
#
# WHAT TO CHECK (go through each item in order):
#
#   [ ] 1. INITIAL RENDER
#         The TUI opens in an alternate screen buffer.
#         Header shows: "Derekh Smoke Test" + timestamp subtitle.
#         Left pane shows 4 phases: all start in pending (○) state.
#         Right pane (issues) is empty.
#         Footer shows: "[q] quit"
#         Spinner is visible and animating in the active pane.
#
#   [ ] 2. LOOP PHASE — "Clone repos" (phase 1)
#         Items appear one by one: "api", "web", "ops".
#         "api" and "web" complete with ✓ (ok).
#         "ops" completes with ⚠ (warning) and appears in the issues pane
#         as issue [1] (after interactive mode) with the message
#         "ops clone slow — retried once".
#         Phase 1 finishes with a ⚠ glyph (has warning).
#
#   [ ] 3. SINGLE PHASE — "Check prerequisites" (phase 2)
#         Active pane shows "Check prerequisites" for ~0.5s.
#         Phase completes with ⚠; two alerts land in the issues pane:
#         Issue [2]: "wrangler not installed" (FixCommand present)
#         Issue [3]: "node version is 18, recommend 20" (no FixCommand)
#         Issues pane auto-scrolls to show all 3 issues.
#
#   [ ] 4. SINGLE PHASE — "Run migrations" (phase 3)
#         Completes with ✓ (success). No new issues.
#
#   [ ] 5. SINGLE PHASE — "Verify env" (phase 4)
#         Completes with ✗ (failure). Issue [4] appears:
#         "DATABASE_URL missing" with FixCommand "cp .env.example .env".
#         The overall plan header progress bar reaches 100%.
#
#   [ ] 6. POST-COMPLETION INTERACTIVE MODE
#         After all phases finish, TUI freezes (does NOT auto-exit).
#         Issues pane now shows [1] through [4] numeric prefixes in accent color.
#         All issues get a prefix [1]-[4] regardless of whether they have a FixCommand.
#         Footer changes to: "[q] quit  [1-9] copy fix command"
#
#   [ ] 7. COPY WITH FIX COMMAND — press "2"
#         Issue [2] has FixCommand "npm install -g wrangler".
#         Footer flashes "Copied to clipboard" for ~1 second.
#         Footer then reverts to "[q] quit  [1-9] copy fix command".
#         Open a new terminal and paste — should see: npm install -g wrangler
#
#   [ ] 8. COPY WITHOUT FIX COMMAND — press "3"
#         Issue [3] has NO FixCommand.
#         Footer flashes "No command to copy" for ~1 second, then reverts.
#         No crash; footer returns to "[q] quit  [1-9] copy fix command".
#
#   [ ] 9. OUT-OF-RANGE KEY — press "9"
#         Only 4 issues exist; pressing "9" should flash "No command to copy"
#         (issue index 9 does not exist).
#         Does NOT crash or leave the footer in a broken state.
#
#   [ ] 10. RESIZE — make terminal SMALLER (below 60x15)
#         Drag or resize terminal window to below 60 columns or 15 rows.
#         Within ~200ms, screen should clear and show centered message:
#         "Terminal too small / Resize to at least 60x15 to resume"
#         The TUI pauses — key "q" still exits cleanly from this state.
#
#   [ ] 11. RESIZE — restore terminal size
#         Drag terminal back to ≥80x24.
#         Within ~200ms, full TUI redraws with correct layout.
#         All 4 issues still visible with [1]-[4] prefixes.
#         Footer shows "[q] quit  [1-9] copy fix command".
#
#   [ ] 12. QUIT — press "q"
#         Alternate buffer dismissed; normal terminal restored.
#         Cursor is visible. No garbage characters on screen.
#         Script exits with code 2 (plan had hard failures — DATABASE_URL missing).
#
# ══════════════════════════════════════════════════════════════════════════════

$ErrorActionPreference = 'Stop'

# ── Import the module ─────────────────────────────────────────────────────────
$moduleRoot = Join-Path $PSScriptRoot '..'
$manifest   = Join-Path $moduleRoot 'derekh.psd1'

if (-not (Test-Path $manifest)) {
    Write-Error "Cannot find derekh.psd1 at '$manifest'. Run from derekh/tests/."
    exit 1
}

Import-Module $manifest -Force

# ── Build the fixed smoke-test plan ──────────────────────────────────────────
#
# This plan is deterministic — no real I/O, no external tools.
# All actions use Start-Sleep to simulate work and return known results.
# The exact issues, severities, and FixCommands are part of the fixture.

$plan = New-DhPlan -Title 'Derekh Smoke Test' -Subtitle (Get-Date -Format 'HH:mm:ss')

# ── Phase 1: Loop — "Clone repos" ─────────────────────────────────────────────
# api  → success
# web  → success
# ops  → warning with FixCommand (becomes issue [1] in interactive mode)

$plan = Add-DhLoopPhase -Plan $plan -Name 'Clone repos' -Items @('api', 'web', 'ops') -Action {
    param($repo)
    Start-Sleep -Milliseconds 400   # simulate clone time

    switch ($repo) {
        'api' {
            return New-DhResult -Success $true -Message 'api: already cloned'
        }
        'web' {
            return New-DhResult -Success $true -Message 'web: already cloned'
        }
        'ops' {
            return New-DhResult -Success $true `
                -Severity 'warning' `
                -Message 'ops clone slow — retried once' `
                -FixCommand 'git clone https://github.com/fellwork/ops.git --depth 1'
        }
    }
}

# ── Phase 2: Single — "Check prerequisites" ───────────────────────────────────
# Returns two alerts (warnings).
# Alert 1: wrangler not installed (FixCommand present)    → issue [2]
# Alert 2: node version too old  (no FixCommand)          → issue [3]

$plan = Add-DhSinglePhase -Plan $plan -Name 'Check prerequisites' -Action {
    Start-Sleep -Milliseconds 500   # simulate prerequisite check
    return New-DhResult -Success $true -Alerts @(
        (New-DhAlert -Severity 'warning' `
            -Message 'wrangler not installed' `
            -FixCommand 'npm install -g wrangler'),
        (New-DhAlert -Severity 'warning' `
            -Message 'node version is 18, recommend 20')
            # intentionally NO -FixCommand to exercise "No command to copy" path
    )
}

# ── Phase 3: Single — "Run migrations" ────────────────────────────────────────
# Succeeds with no issues.

$plan = Add-DhSinglePhase -Plan $plan -Name 'Run migrations' -Action {
    Start-Sleep -Milliseconds 300
    return New-DhResult -Success $true -Message 'All migrations applied'
}

# ── Phase 4: Single — "Verify env" ────────────────────────────────────────────
# Fails with a FixCommand. → issue [4]
# This causes plan exit code 2 (hard failure).

$plan = Add-DhSinglePhase -Plan $plan -Name 'Verify env' -Action {
    Start-Sleep -Milliseconds 200
    return New-DhResult -Success $false `
        -Message 'DATABASE_URL missing' `
        -FixCommand 'cp .env.example .env' `
        -Animal 'owl'
}

# ── Run it ────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "Derekh Phase G — Manual TUI Smoke Test" -ForegroundColor Cyan
Write-Host ""
Write-Host "Starting TUI in 1 second. Make sure your terminal is at least 80x24." -ForegroundColor DarkGray
Write-Host "Use the WHAT TO CHECK list at the top of this file to verify." -ForegroundColor DarkGray
Write-Host ""
Start-Sleep -Seconds 1

Invoke-DhPlan -Plan $plan

# The TUI blocks until the user presses q/Esc/Enter.
# $LASTEXITCODE reflects the plan result (2 = had hard failures).
Write-Host ""
Write-Host "Smoke test exited. Exit code: $LASTEXITCODE" -ForegroundColor $(if ($LASTEXITCODE -eq 0) { 'Green' } else { 'Yellow' })
exit $LASTEXITCODE
