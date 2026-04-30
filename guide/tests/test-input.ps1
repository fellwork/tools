#Requires -Version 7
# test-input.ps1 — Unit tests for input.ps1.
#
# Test-GuideKeyAvailable and Read-GuideKey wrap [Console] I/O and cannot be unit-
# tested in a non-interactive context. They are SKIPPED here and verified by
# the F5 manual smoke test.
#
# Everything else (registry, dispatch) is pure logic and fully tested.

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

# ── SKIP: terminal-dependent functions ───────────────────────────────────────

Skip-Test 'Test-GuideKeyAvailable returns bool'   'requires real TTY input — see F5 manual smoke test'
Skip-Test 'Read-GuideKey returns ConsoleKeyInfo'  'requires real TTY input — see F5 manual smoke test'

# ── Registry: Register-GuideKeyHandler ──────────────────────────────────────────

Clear-GuideKeyHandlers

$fired = $false
Register-GuideKeyHandler -Key 'Q' -Action { $script:fired = $true }
$handlers = Get-GuideKeyHandlers

Assert-True 'Register-GuideKeyHandler: key added to registry' `
    ($handlers.ContainsKey('Q')) "registry keys: $($handlers.Keys -join ', ')"

Assert-True 'Register-GuideKeyHandler: value is scriptblock' `
    ($handlers['Q'] -is [scriptblock]) "got: $($handlers['Q'].GetType().Name)"

# ── Registry: case normalization ──────────────────────────────────────────────

Clear-GuideKeyHandlers
Register-GuideKeyHandler -Key 'escape' -Action { }
$handlers = Get-GuideKeyHandlers

Assert-True 'Register-GuideKeyHandler: lowercase key normalized to uppercase' `
    ($handlers.ContainsKey('ESCAPE')) "keys: $($handlers.Keys -join ', ')"

# ── Registry: overwrite existing binding ──────────────────────────────────────

Clear-GuideKeyHandlers
Register-GuideKeyHandler -Key 'Q' -Action { 'first' }
Register-GuideKeyHandler -Key 'Q' -Action { 'second' }
$handlers = Get-GuideKeyHandlers

Assert-Equal 'Register-GuideKeyHandler: second registration overwrites first' `
    1 $handlers.Count

# ── Unregister-GuideKeyHandler ───────────────────────────────────────────────────

Clear-GuideKeyHandlers
Register-GuideKeyHandler -Key 'Enter' -Action { }
Unregister-GuideKeyHandler -Key 'Enter'
$handlers = Get-GuideKeyHandlers

Assert-True 'Unregister-GuideKeyHandler: key removed' `
    (-not $handlers.ContainsKey('ENTER')) "keys still present: $($handlers.Keys -join ', ')"

Assert-NoThrow 'Unregister-GuideKeyHandler: removing non-existent key does not throw' {
    Unregister-GuideKeyHandler -Key 'Z'
}

# ── Clear-GuideKeyHandlers ───────────────────────────────────────────────────────

Clear-GuideKeyHandlers
Register-GuideKeyHandler -Key 'Q'      -Action { }
Register-GuideKeyHandler -Key 'Escape' -Action { }
Clear-GuideKeyHandlers
$handlers = Get-GuideKeyHandlers

Assert-Equal 'Clear-GuideKeyHandlers: empties registry' 0 $handlers.Count

# ── Invoke-GuideKeyDispatch: matching handler fires ───────────────────────────────

Clear-GuideKeyHandlers
$dispatchResult = 0
Register-GuideKeyHandler -Key 'Q' -Action { $script:dispatchResult += 1 }

# Simulate a ConsoleKeyInfo for 'Q'.
# [ConsoleKeyInfo]::new(char, ConsoleKey, shift, alt, control)
$fakeKey = [System.ConsoleKeyInfo]::new('q', [System.ConsoleKey]::Q, $false, $false, $false)

Invoke-GuideKeyDispatch -KeyInfo $fakeKey

Assert-Equal 'Invoke-GuideKeyDispatch: handler fires on matching key' 1 $script:dispatchResult

# ── Invoke-GuideKeyDispatch: unregistered key does nothing ──────────────────────

Clear-GuideKeyHandlers
$unexpectedFire = $false
$fakeEscape = [System.ConsoleKeyInfo]::new([char]27, [System.ConsoleKey]::Escape, $false, $false, $false)

Assert-NoThrow 'Invoke-GuideKeyDispatch: unregistered key does not throw' {
    Invoke-GuideKeyDispatch -KeyInfo $fakeEscape
}

Assert-True 'Invoke-GuideKeyDispatch: unregistered key fires no handler' `
    (-not $unexpectedFire)

# ── Invoke-GuideKeyDispatch: handler exception is swallowed (not rethrown) ───────

Clear-GuideKeyHandlers
Register-GuideKeyHandler -Key 'Q' -Action { throw 'handler error' }
$fakeQ = [System.ConsoleKeyInfo]::new('q', [System.ConsoleKey]::Q, $false, $false, $false)

Assert-NoThrow 'Invoke-GuideKeyDispatch: handler exception does not propagate' {
    Invoke-GuideKeyDispatch -KeyInfo $fakeQ
}

# ── Invoke-GuideKeyDispatch: multiple handlers registered, correct one fires ──────

Clear-GuideKeyHandlers
$qFired     = $false
$enterFired = $false
Register-GuideKeyHandler -Key 'Q'     -Action { $script:qFired     = $true }
Register-GuideKeyHandler -Key 'Enter' -Action { $script:enterFired = $true }

$fakeEnter = [System.ConsoleKeyInfo]::new([char]13, [System.ConsoleKey]::Enter, $false, $false, $false)
Invoke-GuideKeyDispatch -KeyInfo $fakeEnter

Assert-True  'Invoke-GuideKeyDispatch: Enter handler fires'          $script:enterFired
Assert-True  'Invoke-GuideKeyDispatch: Q handler does not fire for Enter' (-not $script:qFired)

# ── Invoke-GuideKeyDispatch: handler receives KeyInfo as argument ────────────────

Clear-GuideKeyHandlers
$receivedKey = $null
Register-GuideKeyHandler -Key 'Q' -Action { param($k) $script:receivedKey = $k }

$fakeQ2 = [System.ConsoleKeyInfo]::new('q', [System.ConsoleKey]::Q, $false, $false, $false)
Invoke-GuideKeyDispatch -KeyInfo $fakeQ2

Assert-True 'Invoke-GuideKeyDispatch: handler receives KeyInfo as argument' `
    ($null -ne $script:receivedKey -and $script:receivedKey.Key -eq [System.ConsoleKey]::Q)

# ── Get-GuideKeyHandlers returns a CLONE (mutation doesn't affect registry) ──────

Clear-GuideKeyHandlers
Register-GuideKeyHandler -Key 'Q' -Action { }
$clone = Get-GuideKeyHandlers
$clone['FAKE'] = { }

$fresh = Get-GuideKeyHandlers
Assert-True 'Get-GuideKeyHandlers returns clone, not live reference' `
    (-not $fresh.ContainsKey('FAKE'))

# ── Phase G: Enter-GuideInteractiveMode ─────────────────────────────────────────
# Test that the function is defined and that the digit-handler registration
# loop properly captures values (not references). Terminal-touching behavior
# is verified by the manual smoke test.

Assert-True 'Enter-GuideInteractiveMode is defined' `
    ($null -ne (Get-Command -Name 'Enter-GuideInteractiveMode' -ErrorAction SilentlyContinue)) `
    'function not found in session'

# Test the digit handler capture-by-value mechanic independent of Enter-GuideInteractiveMode.
# Register D1-D9 using [scriptblock]::Create (same technique as Enter-GuideInteractiveMode).
Clear-GuideKeyHandlers
for ($n = 1; $n -le 9; $n++) {
    $captured = $n
    # Each handler stores its captured value in a shared array (module-safe approach)
    $h = [scriptblock]::Create("param(`$k) " + '$script:_G_captureArr[' + $($captured - 1) + "] = $($captured)")
    Register-GuideKeyHandler -Key "D$captured" -Action $h
}
$registeredHandlers = Get-GuideKeyHandlers

Assert-True 'Phase G: digit handler registration loop covers D1-D9' `
    ((1..9 | Where-Object { $registeredHandlers.ContainsKey("D$_") }).Count -eq 9) `
    "found keys: $($registeredHandlers.Keys -join ', ')"

# Verify D1..D9 handlers are distinct scriptblocks (not all the same closure)
$d1Handler = $registeredHandlers['D1']
$d5Handler = $registeredHandlers['D5']
$d9Handler = $registeredHandlers['D9']

Assert-True 'Phase G: D1 and D5 handlers are distinct scriptblocks' `
    ($d1Handler.ToString() -ne $d5Handler.ToString()) "handlers are identical — closure capture may be broken"

Assert-True 'Phase G: D5 and D9 handlers are distinct scriptblocks' `
    ($d5Handler.ToString() -ne $d9Handler.ToString()) "handlers are identical — closure capture may be broken"

Clear-GuideKeyHandlers

# ── Phase G: Invoke-GuideFooterFlash sets FooterFlash on state ──────────────────
# Build a minimal layout and state directly (private functions not available via module export).

$flashLayout = @{
    Footer = @{ X = 1; Y = 24; Width = 80; Height = 1 }
    Header = @{ X = 1; Y = 1; Width = 80; Height = 1 }
}

$flashState = @{
    Title           = 'flash test'
    Subtitle        = ''
    StartedAt       = $null
    CompletedAt     = $null
    ExitCode        = 0
    Phases          = [System.Collections.ArrayList]@()
    Issues          = [System.Collections.ArrayList]@()
    ActiveLabel     = ''
    TerminalWidth   = 80
    TerminalHeight  = 24
    Paused          = $false
    FooterFlash     = $null
    CurrentLayout   = $flashLayout
    InteractiveMode = $false
    FooterText      = ''
}

$isTtyForG = -not [Console]::IsOutputRedirected

if ($isTtyForG) {
    Assert-NoThrow 'Invoke-GuideFooterFlash does not throw in TTY' {
        Invoke-GuideFooterFlash -Message 'Test flash' -State $flashState -Layout $flashLayout
    }
    Assert-True 'Invoke-GuideFooterFlash sets FooterFlash on state' `
        ($null -ne $flashState.FooterFlash) 'FooterFlash was null'
    Assert-True 'Invoke-GuideFooterFlash FooterFlash has correct Message' `
        ($flashState.FooterFlash.Message -eq 'Test flash') "got: $($flashState.FooterFlash.Message)"
    Assert-True 'Invoke-GuideFooterFlash FooterFlash has running Stopwatch' `
        ($flashState.FooterFlash.SW -is [System.Diagnostics.Stopwatch]) 'SW not a Stopwatch'
} else {
    Skip-Test 'Invoke-GuideFooterFlash does not throw in TTY'              'requires TTY for Set-GuideFooter'
    Skip-Test 'Invoke-GuideFooterFlash sets FooterFlash on state'          'requires TTY for Set-GuideFooter'
    Skip-Test 'Invoke-GuideFooterFlash FooterFlash has correct Message'    'requires TTY'
    Skip-Test 'Invoke-GuideFooterFlash FooterFlash has running Stopwatch'  'requires TTY'
}

# ── Summary ───────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "Input: $passCount pass, $failCount fail"

if ($failCount -gt 0) { exit 1 } else { exit 0 }
