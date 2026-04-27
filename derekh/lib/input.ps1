#Requires -Version 7
# input.ps1 — Non-blocking key polling and handler registry.
#
# Public surface:
#   Test-DhKeyAvailable          — is a key waiting in the console input buffer?
#   Read-DhKey                   — read one key (non-echo, non-blocking)
#   Register-DhKeyHandler        — add a key→scriptblock binding
#   Unregister-DhKeyHandler      — remove a binding
#   Get-DhKeyHandlers            — return the full handler table (for testing)
#   Invoke-DhKeyDispatch         — dispatch one KeyInfo to its handler (if any)
#
# The event loop pattern (used in plan.ps1 F5):
#
#   while (-not $shouldQuit) {
#       if (Test-DhKeyAvailable) {
#           $key = Read-DhKey
#           Invoke-DhKeyDispatch $key
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

function Register-DhKeyHandler {
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

function Unregister-DhKeyHandler {
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

function Get-DhKeyHandlers {
    <#
    .SYNOPSIS
        Return the full handler registry hashtable (primarily for testing).
    #>
    [CmdletBinding()]
    param()
    return $script:_keyHandlers.Clone()
}

function Clear-DhKeyHandlers {
    <#
    .SYNOPSIS
        Remove all registered key handlers (useful for test isolation).
    #>
    [CmdletBinding()]
    param()
    $script:_keyHandlers = @{}
}

# ── Key polling ───────────────────────────────────────────────────────────────

function Test-DhKeyAvailable {
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
        Write-Verbose "Test-DhKeyAvailable: console input unavailable — $_"
        return $false
    }
}

function Read-DhKey {
    <#
    .SYNOPSIS
        Read one key from the console without echoing it.
    .DESCRIPTION
        Wraps [Console]::ReadKey($true) — intercept=true, so the key is not
        printed to the terminal. Returns a [ConsoleKeyInfo] object with:
          .Key         — [ConsoleKey] enum value
          .KeyChar     — char typed
          .Modifiers   — [ConsoleModifiers] (Alt, Shift, Control)
        IMPORTANT: Only call this after Test-DhKeyAvailable returns $true,
        otherwise it blocks until a key is pressed.
    #>
    [CmdletBinding()]
    param()
    return [Console]::ReadKey($true)
}

# ── Dispatch ──────────────────────────────────────────────────────────────────

function Invoke-DhKeyDispatch {
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
        A [ConsoleKeyInfo] returned by Read-DhKey.
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
            Write-Verbose "Invoke-DhKeyDispatch: handler for '$keyName' threw — $_"
        }
    }
}
