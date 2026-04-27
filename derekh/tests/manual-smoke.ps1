#Requires -Version 7
# manual-smoke.ps1 — Manual TUI smoke test for Phase F.
#
# Run this INTERACTIVELY in a real terminal (not in a pipe, not in CI):
#
#   pwsh tests/manual-smoke.ps1
#
# What to verify visually:
#   [ ] Terminal switches to alternate screen buffer (prior content hidden)
#   [ ] Header shows title "Derekh Smoke Test" and subtitle (time)
#   [ ] Phases pane shows two phases with correct status glyphs:
#         Phase 1 completes ok (✓ green), Phase 2 completes ok (✓ green)
#   [ ] Active pane shows spinner during each phase, then goes idle
#   [ ] Issues pane stays empty (no failures expected in smoke test)
#   [ ] Footer shows "[q] quit"
#   [ ] After both phases complete, pressing q returns to normal terminal
#   [ ] No garbage ANSI codes visible; cursor hidden during run
#   [ ] Terminal cursor restored on exit; scrollback buffer intact
#   [ ] Ctrl+C during a phase returns to normal terminal (exit 130)
#
# This script is NOT run by tests/run-all.ps1. It is a human-in-the-loop check.
# It verifies the visual correctness of render.ps1 F2 region drawers.

[CmdletBinding()]
param(
    [switch]$Quick   # Skip the artificial delays if you just want a fast check
)

$ErrorActionPreference = 'Stop'

$manifestPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../derekh.psd1'))
Import-Module $manifestPath -Force -ErrorAction Stop

Write-Host ""
Write-Host "Derekh Phase F — Manual TUI Smoke Test" -ForegroundColor Cyan
Write-Host "Starting TUI in 2 seconds. Press q to quit when phases complete." -ForegroundColor DarkGray
Write-Host ""

if (-not $Quick) { Start-Sleep -Seconds 2 }

# Build a plan with two fast phases.
$plan = New-DhPlan -Title 'Derekh Smoke Test' `
                   -Subtitle (Get-Date -Format 'HH:mm:ss')

$plan = Add-DhLoopPhase -Plan $plan -Name 'Phase One' `
    -Items @('item-a', 'item-b', 'item-c') `
    -Action {
        param($item)
        if (-not $using:Quick) { Start-Sleep -Milliseconds 400 }
        return New-DhResult -Success $true -Message "$item processed"
    }

$plan = Add-DhSinglePhase -Plan $plan -Name 'Phase Two' `
    -Action {
        if (-not $using:Quick) { Start-Sleep -Milliseconds 600 }
        return New-DhResult -Success $true -Message 'Final check passed'
    }

# Run via TUI path (no -NoTui, no -Headless).
Invoke-DhPlan -Plan $plan

# If we get here the user pressed q.
Write-Host ""
Write-Host "Smoke test exited cleanly." -ForegroundColor Green
