#Requires -Version 7
# test-clipboard.ps1 — Unit tests for clipboard.ps1.
#
# Platform-detection logic and capability-check paths are fully testable
# via the -Platform override parameter on both public functions.
#
# Tests that actually write to the live clipboard are run only on the current
# platform (guarded by platform checks). They verify the real path works.
# All other-platform paths are tested via the -Platform override.

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

function Assert-Equal {
    param([string]$Name, $Expected, $Actual)
    $ok = ($Expected -eq $Actual)
    if ($ok) {
        Write-Host "PASS: $Name"
        $script:passCount++
    } else {
        Write-Host "FAIL: $Name — expected '$Expected', got '$Actual'"
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

$manifestPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../guide.psd1'))
Import-Module $manifestPath -Force -ErrorAction Stop

# ── Test-GuideClipboardAvailable: platform-specific ──────────────────────────────

# Windows always returns $true (Set-Clipboard is built in).
Assert-True 'Test-GuideClipboardAvailable: Windows always available' `
    (Test-GuideClipboardAvailable -Platform 'Windows')

# macOS availability depends on pbcopy being on PATH — unknown in test env.
# We just assert the function returns a boolean without throwing.
Assert-NoThrow 'Test-GuideClipboardAvailable: macOS returns bool without throw' {
    $result = Test-GuideClipboardAvailable -Platform 'macOS'
    if ($result -isnot [bool]) { throw "Expected bool, got $($result.GetType().Name)" }
}

# Linux availability depends on xclip or wl-copy.
Assert-NoThrow 'Test-GuideClipboardAvailable: Linux returns bool without throw' {
    $result = Test-GuideClipboardAvailable -Platform 'Linux'
    if ($result -isnot [bool]) { throw "Expected bool, got $($result.GetType().Name)" }
}

# Unknown platform returns $false.
Assert-True 'Test-GuideClipboardAvailable: unknown platform returns false' `
    (-not (Test-GuideClipboardAvailable -Platform 'Amiga'))

# No -Platform arg uses current OS without throwing.
Assert-NoThrow 'Test-GuideClipboardAvailable: no Platform arg does not throw' {
    $null = Test-GuideClipboardAvailable
}

# ── Set-GuideClipboard: never throws ────────────────────────────────────────────

# Set-GuideClipboard on an OS with no tools returns $false cleanly.
Assert-NoThrow 'Set-GuideClipboard: unknown platform does not throw' {
    $result = Set-GuideClipboard -Text 'test' -Platform 'Amiga'
    if ($result -ne $false) { throw "Expected false, got '$result'" }
}

Assert-True 'Set-GuideClipboard: unknown platform returns false' `
    (-not (Set-GuideClipboard -Text 'test' -Platform 'Amiga'))

# ── Set-GuideClipboard: Windows live path ───────────────────────────────────────

if ($IsWindows) {
    $result = Set-GuideClipboard -Text 'guide-clipboard-test'
    Assert-True 'Set-GuideClipboard: Windows returns true on success' ($result -eq $true)

    $got = Get-Clipboard
    Assert-True 'Set-GuideClipboard: Windows actually wrote to clipboard' `
        ($got -eq 'guide-clipboard-test') "Got: '$got'"
} else {
    Skip-Test 'Set-GuideClipboard: Windows returns true on success' 'not running on Windows'
    Skip-Test 'Set-GuideClipboard: Windows actually wrote to clipboard' 'not running on Windows'
}

# ── Set-GuideClipboard: macOS live path ─────────────────────────────────────────

if ($IsMacOS) {
    $result = Set-GuideClipboard -Text 'guide-clipboard-test'
    Assert-True 'Set-GuideClipboard: macOS returns true when pbcopy available' ($result -eq $true)
} else {
    Skip-Test 'Set-GuideClipboard: macOS live path' 'not running on macOS'
}

# ── Set-GuideClipboard: return type is always bool ───────────────────────────────

$r1 = Set-GuideClipboard -Text 'type-test' -Platform 'Windows'
Assert-True 'Set-GuideClipboard: return is [bool] on Windows' ($r1 -is [bool])

$r2 = Set-GuideClipboard -Text 'type-test' -Platform 'Amiga'
Assert-True 'Set-GuideClipboard: return is [bool] on unknown platform' ($r2 -is [bool])

# ── Set-GuideClipboard: empty string does not throw ──────────────────────────────

Assert-NoThrow 'Set-GuideClipboard: empty string does not throw' {
    $null = Set-GuideClipboard -Text '' -Platform 'Windows'
}

# ── Set-GuideClipboard: very long string does not throw ─────────────────────────

Assert-NoThrow 'Set-GuideClipboard: 10k char string does not throw' {
    $null = Set-GuideClipboard -Text ('x' * 10000) -Platform 'Windows'
}

# ── Summary ───────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "Clipboard: $passCount pass, $failCount fail"

if ($failCount -gt 0) { exit 1 } else { exit 0 }
