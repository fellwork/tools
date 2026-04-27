#Requires -Version 7
# test-input.ps1 — Unit tests for input.ps1.
#
# Test-DhKeyAvailable and Read-DhKey wrap [Console] I/O and cannot be unit-
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

$manifestPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../derekh.psd1'))
Import-Module $manifestPath -Force -ErrorAction Stop

# ── SKIP: terminal-dependent functions ───────────────────────────────────────

Skip-Test 'Test-DhKeyAvailable returns bool'   'requires real TTY input — see F5 manual smoke test'
Skip-Test 'Read-DhKey returns ConsoleKeyInfo'  'requires real TTY input — see F5 manual smoke test'

# ── Registry: Register-DhKeyHandler ──────────────────────────────────────────

Clear-DhKeyHandlers

$fired = $false
Register-DhKeyHandler -Key 'Q' -Action { $script:fired = $true }
$handlers = Get-DhKeyHandlers

Assert-True 'Register-DhKeyHandler: key added to registry' `
    ($handlers.ContainsKey('Q')) "registry keys: $($handlers.Keys -join ', ')"

Assert-True 'Register-DhKeyHandler: value is scriptblock' `
    ($handlers['Q'] -is [scriptblock]) "got: $($handlers['Q'].GetType().Name)"

# ── Registry: case normalization ──────────────────────────────────────────────

Clear-DhKeyHandlers
Register-DhKeyHandler -Key 'escape' -Action { }
$handlers = Get-DhKeyHandlers

Assert-True 'Register-DhKeyHandler: lowercase key normalized to uppercase' `
    ($handlers.ContainsKey('ESCAPE')) "keys: $($handlers.Keys -join ', ')"

# ── Registry: overwrite existing binding ──────────────────────────────────────

Clear-DhKeyHandlers
Register-DhKeyHandler -Key 'Q' -Action { 'first' }
Register-DhKeyHandler -Key 'Q' -Action { 'second' }
$handlers = Get-DhKeyHandlers

Assert-Equal 'Register-DhKeyHandler: second registration overwrites first' `
    1 $handlers.Count

# ── Unregister-DhKeyHandler ───────────────────────────────────────────────────

Clear-DhKeyHandlers
Register-DhKeyHandler -Key 'Enter' -Action { }
Unregister-DhKeyHandler -Key 'Enter'
$handlers = Get-DhKeyHandlers

Assert-True 'Unregister-DhKeyHandler: key removed' `
    (-not $handlers.ContainsKey('ENTER')) "keys still present: $($handlers.Keys -join ', ')"

Assert-NoThrow 'Unregister-DhKeyHandler: removing non-existent key does not throw' {
    Unregister-DhKeyHandler -Key 'Z'
}

# ── Clear-DhKeyHandlers ───────────────────────────────────────────────────────

Clear-DhKeyHandlers
Register-DhKeyHandler -Key 'Q'      -Action { }
Register-DhKeyHandler -Key 'Escape' -Action { }
Clear-DhKeyHandlers
$handlers = Get-DhKeyHandlers

Assert-Equal 'Clear-DhKeyHandlers: empties registry' 0 $handlers.Count

# ── Invoke-DhKeyDispatch: matching handler fires ───────────────────────────────

Clear-DhKeyHandlers
$dispatchResult = 0
Register-DhKeyHandler -Key 'Q' -Action { $script:dispatchResult += 1 }

# Simulate a ConsoleKeyInfo for 'Q'.
# [ConsoleKeyInfo]::new(char, ConsoleKey, shift, alt, control)
$fakeKey = [System.ConsoleKeyInfo]::new('q', [System.ConsoleKey]::Q, $false, $false, $false)

Invoke-DhKeyDispatch -KeyInfo $fakeKey

Assert-Equal 'Invoke-DhKeyDispatch: handler fires on matching key' 1 $script:dispatchResult

# ── Invoke-DhKeyDispatch: unregistered key does nothing ──────────────────────

Clear-DhKeyHandlers
$unexpectedFire = $false
$fakeEscape = [System.ConsoleKeyInfo]::new([char]27, [System.ConsoleKey]::Escape, $false, $false, $false)

Assert-NoThrow 'Invoke-DhKeyDispatch: unregistered key does not throw' {
    Invoke-DhKeyDispatch -KeyInfo $fakeEscape
}

Assert-True 'Invoke-DhKeyDispatch: unregistered key fires no handler' `
    (-not $unexpectedFire)

# ── Invoke-DhKeyDispatch: handler exception is swallowed (not rethrown) ───────

Clear-DhKeyHandlers
Register-DhKeyHandler -Key 'Q' -Action { throw 'handler error' }
$fakeQ = [System.ConsoleKeyInfo]::new('q', [System.ConsoleKey]::Q, $false, $false, $false)

Assert-NoThrow 'Invoke-DhKeyDispatch: handler exception does not propagate' {
    Invoke-DhKeyDispatch -KeyInfo $fakeQ
}

# ── Invoke-DhKeyDispatch: multiple handlers registered, correct one fires ──────

Clear-DhKeyHandlers
$qFired     = $false
$enterFired = $false
Register-DhKeyHandler -Key 'Q'     -Action { $script:qFired     = $true }
Register-DhKeyHandler -Key 'Enter' -Action { $script:enterFired = $true }

$fakeEnter = [System.ConsoleKeyInfo]::new([char]13, [System.ConsoleKey]::Enter, $false, $false, $false)
Invoke-DhKeyDispatch -KeyInfo $fakeEnter

Assert-True  'Invoke-DhKeyDispatch: Enter handler fires'          $script:enterFired
Assert-True  'Invoke-DhKeyDispatch: Q handler does not fire for Enter' (-not $script:qFired)

# ── Invoke-DhKeyDispatch: handler receives KeyInfo as argument ────────────────

Clear-DhKeyHandlers
$receivedKey = $null
Register-DhKeyHandler -Key 'Q' -Action { param($k) $script:receivedKey = $k }

$fakeQ2 = [System.ConsoleKeyInfo]::new('q', [System.ConsoleKey]::Q, $false, $false, $false)
Invoke-DhKeyDispatch -KeyInfo $fakeQ2

Assert-True 'Invoke-DhKeyDispatch: handler receives KeyInfo as argument' `
    ($null -ne $script:receivedKey -and $script:receivedKey.Key -eq [System.ConsoleKey]::Q)

# ── Get-DhKeyHandlers returns a CLONE (mutation doesn't affect registry) ──────

Clear-DhKeyHandlers
Register-DhKeyHandler -Key 'Q' -Action { }
$clone = Get-DhKeyHandlers
$clone['FAKE'] = { }

$fresh = Get-DhKeyHandlers
Assert-True 'Get-DhKeyHandlers returns clone, not live reference' `
    (-not $fresh.ContainsKey('FAKE'))

# ── Phase G: Enter-DhInteractiveMode ─────────────────────────────────────────
# Test that the function is defined and that the digit-handler registration
# loop properly captures values (not references). Terminal-touching behavior
# is verified by the manual smoke test.

Assert-True 'Enter-DhInteractiveMode is defined' `
    ($null -ne (Get-Command -Name 'Enter-DhInteractiveMode' -ErrorAction SilentlyContinue)) `
    'function not found in session'

# Test the digit handler capture-by-value mechanic independent of Enter-DhInteractiveMode.
# Register D1-D9 using [scriptblock]::Create (same technique as Enter-DhInteractiveMode).
Clear-DhKeyHandlers
for ($n = 1; $n -le 9; $n++) {
    $captured = $n
    # Each handler stores its captured value in a shared array (module-safe approach)
    $h = [scriptblock]::Create("param(`$k) " + '$script:_G_captureArr[' + $($captured - 1) + "] = $($captured)")
    Register-DhKeyHandler -Key "D$captured" -Action $h
}
$registeredHandlers = Get-DhKeyHandlers

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

Clear-DhKeyHandlers

# ── Phase G: Invoke-DhFooterFlash sets FooterFlash on state ──────────────────
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
    Assert-NoThrow 'Invoke-DhFooterFlash does not throw in TTY' {
        Invoke-DhFooterFlash -Message 'Test flash' -State $flashState -Layout $flashLayout
    }
    Assert-True 'Invoke-DhFooterFlash sets FooterFlash on state' `
        ($null -ne $flashState.FooterFlash) 'FooterFlash was null'
    Assert-True 'Invoke-DhFooterFlash FooterFlash has correct Message' `
        ($flashState.FooterFlash.Message -eq 'Test flash') "got: $($flashState.FooterFlash.Message)"
    Assert-True 'Invoke-DhFooterFlash FooterFlash has running Stopwatch' `
        ($flashState.FooterFlash.SW -is [System.Diagnostics.Stopwatch]) 'SW not a Stopwatch'
} else {
    Skip-Test 'Invoke-DhFooterFlash does not throw in TTY'              'requires TTY for Set-DhFooter'
    Skip-Test 'Invoke-DhFooterFlash sets FooterFlash on state'          'requires TTY for Set-DhFooter'
    Skip-Test 'Invoke-DhFooterFlash FooterFlash has correct Message'    'requires TTY'
    Skip-Test 'Invoke-DhFooterFlash FooterFlash has running Stopwatch'  'requires TTY'
}

# ── Summary ───────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "Input: $passCount pass, $failCount fail"

if ($failCount -gt 0) { exit 1 } else { exit 0 }
