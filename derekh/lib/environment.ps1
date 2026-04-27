#Requires -Version 7
# environment.ps1 — Terminal capability detection.
#
# Test-DhEnvironment returns a hashtable describing whether the current
# terminal is capable of hosting the TUI: IsTty, IsUtf8, HasColor, Fits,
# Width, Height.

$ErrorActionPreference = 'Stop'

function Test-DhEnvironment {
    <#
    .SYNOPSIS
        Probe the current terminal for TUI capability.
    .DESCRIPTION
        Returns a hashtable:
          IsTty    — stdin and stdout are not redirected
          IsUtf8   — OutputEncoding is UTF-8 (code page 65001)
          HasColor — VT/ANSI color support detected
          Fits     — terminal is at least 60 columns x 15 rows
          Width    — current terminal width
          Height   — current terminal height
    #>
    [CmdletBinding()]
    param()

    $isTty = -not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected

    $isUtf8 = ([Console]::OutputEncoding.CodePage -eq 65001)

    # Check VT support: PS 7 on Windows Terminal sets SupportsVirtualTerminal.
    # Fallback: check environment variables COLORTERM or TERM.
    $hasColor = $false
    try {
        $hasColor = $Host.UI.SupportsVirtualTerminal
    } catch { }
    if (-not $hasColor) {
        $ct = $env:COLORTERM
        $t  = $env:TERM
        $hasColor = ($ct -eq 'truecolor' -or $ct -eq '24bit' -or
                     $t  -match 'color' -or $t -eq 'xterm-256color')
    }

    $w = 0; $h = 0
    try {
        $size = $Host.UI.RawUI.WindowSize
        $w = $size.Width
        $h = $size.Height
    } catch { }

    $fits = ($w -ge 60 -and $h -ge 15)

    return @{
        IsTty    = $isTty
        IsUtf8   = $isUtf8
        HasColor = $hasColor
        Fits     = $fits
        Width    = $w
        Height   = $h
    }
}
