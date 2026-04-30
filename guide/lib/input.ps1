#Requires -Version 7
# input.ps1 — Non-blocking key polling and handler registry.
#
# Public surface:
#   Test-GuideKeyAvailable          — is a key waiting in the console input buffer?
#   Read-GuideKey                   — read one key (non-echo, non-blocking)
#   Register-GuideKeyHandler        — add a key→scriptblock binding
#   Unregister-GuideKeyHandler      — remove a binding
#   Get-GuideKeyHandlers            — return the full handler table (for testing)
#   Invoke-GuideKeyDispatch         — dispatch one KeyInfo to its handler (if any)
#
# The event loop pattern (used in plan.ps1 F5):
#
#   while (-not $shouldQuit) {
#       if (Test-GuideKeyAvailable) {
#           $key = Read-GuideKey
#           Invoke-GuideKeyDispatch $key
#       }
#       Start-Sleep -Milliseconds 50
#   }
#
# Key strings match [System.ConsoleKey] enum names: 'Q', 'Escape', 'Enter', etc.
# Lowercase and uppercase chars are normalized to their ConsoleKey name
# (e.g. 'q' and 'Q' both match ConsoleKey 'Q').

$ErrorActionPreference = 'Stop'

# ── Handler registry ──────────────────────────────────────────────────────────

# Registry: ConsoleKey-name → scriptblock
# e.g. @{ 'Q' = { $script:shouldQuit = $true } }
$script:_keyHandlers = @{}

function Register-GuideKeyHandler {
    <#
    .SYNOPSIS
        Register a scriptblock to run when a specific key is pressed.
    .PARAMETER Key
        ConsoleKey name (e.g. 'Q', 'Escape', 'Enter', 'D1' for digit 1).
        Case-insensitive. To match any digit 1-9, register 'D1' through 'D9'.
    .PARAMETER Action
        Scriptblock to invoke. Receives the [ConsoleKeyInfo] as $args[0].
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][scriptblock]$Action
    )
    $script:_keyHandlers[$Key.ToUpperInvariant()] = $Action
}

function Unregister-GuideKeyHandler {
    <#
    .SYNOPSIS
        Remove a key binding from the registry.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Key
    )
    $script:_keyHandlers.Remove($Key.ToUpperInvariant())
}

function Get-GuideKeyHandlers {
    <#
    .SYNOPSIS
        Return the full handler registry hashtable (primarily for testing).
    #>
    [CmdletBinding()]
    param()
    return $script:_keyHandlers.Clone()
}

function Clear-GuideKeyHandlers {
    <#
    .SYNOPSIS
        Remove all registered key handlers (useful for test isolation).
    #>
    [CmdletBinding()]
    param()
    $script:_keyHandlers = @{}
}

# ── Key polling ───────────────────────────────────────────────────────────────

function Test-GuideKeyAvailable {
    <#
    .SYNOPSIS
        Returns $true if a key is waiting in the console input buffer.
    .DESCRIPTION
        Wraps [Console]::KeyAvailable. Safe to call in a tight loop — does not block.
        Returns $false and emits a warning if the console input is not available
        (e.g. stdin redirected), rather than throwing.
    #>
    [CmdletBinding()]
    param()
    try {
        return [Console]::KeyAvailable
    } catch {
        Write-Verbose "Test-GuideKeyAvailable: console input unavailable — $_"
        return $false
    }
}

function Read-GuideKey {
    <#
    .SYNOPSIS
        Read one key from the console without echoing it.
    .DESCRIPTION
        Wraps [Console]::ReadKey($true) — intercept=true, so the key is not
        printed to the terminal. Returns a [ConsoleKeyInfo] object with:
          .Key         — [ConsoleKey] enum value
          .KeyChar     — char typed
          .Modifiers   — [ConsoleModifiers] (Alt, Shift, Control)
        IMPORTANT: Only call this after Test-GuideKeyAvailable returns $true,
        otherwise it blocks until a key is pressed.
    #>
    [CmdletBinding()]
    param()
    return [Console]::ReadKey($true)
}

# ── Dispatch ──────────────────────────────────────────────────────────────────

function Invoke-GuideKeyDispatch {
    <#
    .SYNOPSIS
        Look up the pressed key in the handler registry and invoke its action.
    .DESCRIPTION
        Resolves the key name from the ConsoleKeyInfo's .Key property.
        If a handler is registered for that key name, invokes it with the
        ConsoleKeyInfo as the first argument.
        If no handler is registered, the key is silently ignored.
        All handler exceptions are caught and written to Verbose.
    .PARAMETER KeyInfo
        A [ConsoleKeyInfo] returned by Read-GuideKey.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$KeyInfo
    )

    $keyName = $KeyInfo.Key.ToString().ToUpperInvariant()
    $handler = $script:_keyHandlers[$keyName]

    if ($null -ne $handler) {
        try {
            & $handler $KeyInfo
        } catch {
            Write-Verbose "Invoke-GuideKeyDispatch: handler for '$keyName' threw — $_"
        }
    }
}

# ── Phase G: Post-completion interactive mode ─────────────────────────────────

function Enter-GuideInteractiveMode {
    <#
    .SYNOPSIS
        Enter post-completion interactive mode after all phases have finished.
    .DESCRIPTION
        1. Re-renders the issues pane with [1]-[9] numeric prefixes.
        2. Updates the footer to show [q] quit  [1-9] copy fix command.
        3. Registers digit key handlers (1-9) that copy FixCommands to clipboard.
        4. Enters an idle key loop that exits when q/Esc/Enter is pressed.
    .PARAMETER State
        The GuideState hashtable.
    .PARAMETER Theme
        The resolved theme hashtable.
    .PARAMETER Layout
        The current layout hashtable.
    .PARAMETER ShouldQuitRef
        A [ref] to the $shouldQuit boolean in the caller's scope.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$State,
        [Parameter(Mandatory)][hashtable]$Theme,
        [Parameter(Mandatory)][hashtable]$Layout,
        [Parameter(Mandatory)][ref]$ShouldQuitRef
    )

    # Mark state as interactive so resize re-renders use ShowIndices
    $State.InteractiveMode = $true
    $State.FooterText = '[q] quit  [1-9] copy fix command'

    # Re-render issues pane with numeric indices
    Show-GuideIssuesPane -State $State -Theme $Theme -Layout $Layout -ShowIndices

    # Update footer
    Set-GuideFooter -Text '[q] quit  [1-9] copy fix command' -Layout $Layout

    # Register digit key handlers for issues 1-9
    # Use [scriptblock]::Create with string interpolation to force capture-by-value.
    # $script:GuideState is set in guide.psm1 before Invoke-GuidePlan enters the TUI path.
    for ($n = 1; $n -le 9; $n++) {
        $captured = $n
        $handler = [scriptblock]::Create("
            param(`$keyInfo)
            `$_st = `$script:GuideState
            if (`$null -eq `$_st) { return }
            `$idx = $($captured) - 1
            if (`$idx -ge `$_st.Issues.Count) {
                Invoke-GuideFooterFlash -Message 'No command to copy' ``
                    -State `$_st -Layout `$_st.CurrentLayout
                return
            }
            `$issue = `$_st.Issues[`$idx]
            if (`$issue.FixCommand) {
                Set-GuideClipboard -Text `$issue.FixCommand | Out-Null
                Invoke-GuideFooterFlash -Message 'Copied to clipboard' ``
                    -State `$_st -Layout `$_st.CurrentLayout
            } else {
                Invoke-GuideFooterFlash -Message 'No command to copy' ``
                    -State `$_st -Layout `$_st.CurrentLayout
            }
        ")
        Register-GuideKeyHandler -Key "D$captured" -Action $handler
    }

    # The caller's key loop continues with the updated handlers and ShouldQuitRef
    # — this function just sets up the mode; the main loop in guide.psm1 does the polling.
}
