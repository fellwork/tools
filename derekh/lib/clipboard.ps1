#Requires -Version 7
# clipboard.ps1 — Cross-platform copy-to-clipboard.
#
# Platform detection order:
#   1. Windows  → Set-Clipboard (built-in PS 5.1+/7+)
#   2. macOS    → pbcopy (via pipe)
#   3. Linux    → xclip -selection clipboard (try first)
#              → wl-copy (fallback for Wayland)
#
# Public surface:
#   Test-DhClipboardAvailable [-Platform <string>]  — capability check
#   Set-DhClipboard -Text <string> [-Platform <string>]  — copy to clipboard
#
# Both functions accept an optional -Platform override ('Windows'|'macOS'|'Linux')
# for testing without actually switching OS. Defaults to $IsWindows/$IsMacOS/$IsLinux.
#
# Set-DhClipboard returns $true on success, $false if no clipboard tool is available.
# It never throws — clipboard failure is degraded UX, not a fatal error.

$ErrorActionPreference = 'Stop'

# ── Helpers ───────────────────────────────────────────────────────────────────

function script:_Resolve-DhPlatform {
    param([string]$Platform)
    if ($Platform) { return $Platform }
    if ($IsWindows) { return 'Windows' }
    if ($IsMacOS)   { return 'macOS' }
    return 'Linux'
}

function script:_Command-Exists {
    param([string]$Name)
    return ($null -ne (Get-Command -Name $Name -CommandType Application -ErrorAction SilentlyContinue))
}

# ── Public API ────────────────────────────────────────────────────────────────

function Test-DhClipboardAvailable {
    <#
    .SYNOPSIS
        Returns $true if a clipboard mechanism is available on this platform.
    .PARAMETER Platform
        Optional override: 'Windows' | 'macOS' | 'Linux'. Defaults to current OS.
    #>
    [CmdletBinding()]
    param(
        [string]$Platform = ''
    )

    $os = _Resolve-DhPlatform $Platform

    switch ($os) {
        'Windows' {
            # Set-Clipboard is always available in PS 7 on Windows.
            return $true
        }
        'macOS' {
            return (_Command-Exists 'pbcopy')
        }
        'Linux' {
            return ((_Command-Exists 'xclip') -or (_Command-Exists 'wl-copy'))
        }
        default {
            return $false
        }
    }
}

function Set-DhClipboard {
    <#
    .SYNOPSIS
        Copy text to the system clipboard.
    .DESCRIPTION
        Windows: uses Set-Clipboard cmdlet.
        macOS:   pipes text to pbcopy.
        Linux:   tries xclip -selection clipboard, then wl-copy.
        Returns $true on success, $false if no tool available (never throws).
    .PARAMETER Text
        The string to copy.
    .PARAMETER Platform
        Optional override: 'Windows' | 'macOS' | 'Linux'. Defaults to current OS.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [string]$Platform = ''
    )

    $os = _Resolve-DhPlatform $Platform

    try {
        switch ($os) {
            'Windows' {
                Set-Clipboard -Value $Text
                return $true
            }
            'macOS' {
                if (_Command-Exists 'pbcopy') {
                    $Text | pbcopy
                    return $true
                }
                return $false
            }
            'Linux' {
                if (_Command-Exists 'xclip') {
                    $Text | xclip -selection clipboard
                    return $true
                }
                if (_Command-Exists 'wl-copy') {
                    $Text | wl-copy
                    return $true
                }
                return $false
            }
            default {
                return $false
            }
        }
    } catch {
        Write-Verbose "Set-DhClipboard: clipboard operation failed — $_"
        return $false
    }
}
