#Requires -Version 7
# render.ps1 — TUI rendering primitives and region drawers.
#
# F1: Low-level primitives (lifecycle, cursor, region clear, positioned write)
# F2: Per-region drawers (header, phases pane, active pane, issues pane, footer)
#
# Nothing in this file calls plan.ps1, state.ps1, or input.ps1.
# Callers supply all data; this file only knows how to draw.

$ErrorActionPreference = 'Stop'

# ── ANSI escape helpers ───────────────────────────────────────────────────────

# Raw escape character (ESC = \x1b = decimal 27)
$script:ESC = [char]27

function script:Esc { param([string]$seq) "$($script:ESC)[$seq" }

# ── Lifecycle ─────────────────────────────────────────────────────────────────

function Initialize-GuideTui {
    <#
    .SYNOPSIS
        Enter the TUI: switch to alternate screen buffer, hide cursor, set UTF-8.
    .DESCRIPTION
        Sends \e[?1049h (alternate buffer), \e[?25l (hide cursor).
        Sets [Console]::OutputEncoding to UTF-8 so glyphs render correctly
        on Windows Terminal. Saves original encoding to restore on Stop-GuideTui.
    #>
    [CmdletBinding()]
    param()

    # Save original encoding so Stop-GuideTui can restore it.
    $script:_originalEncoding = [Console]::OutputEncoding

    # UTF-8 for glyph support (Windows Terminal handles this natively, but
    # older hosts need the explicit set).
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8

    # Enter alternate screen buffer.
    [Console]::Write("$(Esc '?1049h')")

    # Hide cursor to avoid flicker during draws.
    [Console]::Write("$(Esc '?25l')")

    # Reset any lingering ANSI state from the caller's terminal.
    [Console]::Write("$(Esc '0m')")

    # Explicit clear after entering alt buffer — defends against terminals
    # that don't fully blank the alt buffer on \e[?1049h. Without this,
    # leftover output from the calling shell can bleed through at column 0.
    [Console]::Write("$(Esc '2J')$(Esc '3J')$(Esc 'H')")
}

function Resize-GuideWindow {
    <#
    .SYNOPSIS
        Best-effort enlarge the host window/buffer to a target minimum size.
    .DESCRIPTION
        Only enlarges — never shrinks — so a user who deliberately maximized
        their terminal isn't shrunk down. Fails silently in hosts that don't
        support setting WindowSize (ISE, redirected, some embedded terminals).
    #>
    [CmdletBinding()]
    param(
        [int]$MinWidth  = 120,
        [int]$MinHeight = 35
    )
    try {
        $rawUI    = $Host.UI.RawUI
        $curBuf   = $rawUI.BufferSize
        $curWin   = $rawUI.WindowSize
        $maxPhys  = $rawUI.MaxPhysicalWindowSize

        $targetW = [Math]::Min($MinWidth,  $maxPhys.Width)
        $targetH = [Math]::Min($MinHeight, $maxPhys.Height)

        # Buffer must be at least as wide as the window. Grow buffer first if
        # needed; never shrink the buffer (preserves scrollback width).
        if ($curBuf.Width -lt $targetW) {
            $rawUI.BufferSize = New-Object Management.Automation.Host.Size $targetW, $curBuf.Height
        }
        # Grow window if smaller than target on either axis.
        if ($curWin.Width -lt $targetW -or $curWin.Height -lt $targetH) {
            $newW = [Math]::Max($curWin.Width,  $targetW)
            $newH = [Math]::Max($curWin.Height, $targetH)
            $rawUI.WindowSize = New-Object Management.Automation.Host.Size $newW, $newH
        }
    } catch {
        # WindowSize setting unavailable (ISE, non-TTY, some embedded hosts).
        Write-Verbose "Resize-GuideWindow: window resize unavailable — $_"
    }
}

function Stop-GuideTui {
    <#
    .SYNOPSIS
        Exit the TUI cleanly: restore cursor, exit alternate buffer, reset ANSI.
    .DESCRIPTION
        MUST be idempotent — called from trap{} and from normal completion.
        Restores: cursor visibility, alternate buffer exit, ANSI reset, encoding.
    #>
    [CmdletBinding()]
    param()

    # Show cursor.
    [Console]::Write("$(Esc '?25h')")

    # Exit alternate screen buffer, returning user to their prior scrollback.
    [Console]::Write("$(Esc '?1049l')")

    # Reset all ANSI attributes.
    [Console]::Write("$(Esc '0m')")

    # Re-enable echo if it was disabled (defensive — PS doesn't normally disable it).
    # No direct PS API for this; the ANSI reset above covers most terminals.

    # Restore original encoding.
    if ($null -ne $script:_originalEncoding) {
        [Console]::OutputEncoding = $script:_originalEncoding
        $script:_originalEncoding = $null
    }
}

# ── Cursor positioning ────────────────────────────────────────────────────────

function Set-GuideCursor {
    <#
    .SYNOPSIS
        Move the cursor to column X, row Y (1-indexed, matching layout convention).
    .DESCRIPTION
        Uses [Console]::SetCursorPosition which is 0-indexed; we translate by -1
        so callers can pass layout values (Header.X=1, Footer.Y=$Height) directly.
        X=1 Y=1 is the top-left corner. Guards against out-of-bounds and non-TTY.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$X,
        [Parameter(Mandatory)][int]$Y
    )
    try {
        # Translate layout 1-indexed → console 0-indexed, clamping to ≥0.
        $cx = [Math]::Max(0, $X - 1)
        $cy = [Math]::Max(0, $Y - 1)
        [Console]::SetCursorPosition($cx, $cy)
    } catch {
        # In non-TTY contexts (redirected output, CI), SetCursorPosition throws.
        # Silently swallow — drawing calls are no-ops in non-interactive mode.
        Write-Verbose "Set-GuideCursor: cursor positioning unavailable — $_"
    }
}

# ── Region clearing ───────────────────────────────────────────────────────────

function Clear-GuideRegion {
    <#
    .SYNOPSIS
        Overwrite a rectangular region with spaces (no full-screen clear).
    .DESCRIPTION
        Moves to each row of the region and writes Width spaces.
        Leaves the cursor at (X, Y+Height) — callers should reposition.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$X,
        [Parameter(Mandatory)][int]$Y,
        [Parameter(Mandatory)][int]$Width,
        [Parameter(Mandatory)][int]$Height
    )

    $blank = ' ' * $Width
    for ($row = $Y; $row -lt ($Y + $Height); $row++) {
        Set-GuideCursor -X $X -Y $row
        [Console]::Write($blank)
    }
}

# ── Positioned text write ─────────────────────────────────────────────────────

function Write-GuideAt {
    <#
    .SYNOPSIS
        Write text at (X, Y) with optional truecolor and bold.
    .DESCRIPTION
        Color is a 6-char hex RGB string (e.g. 'f8e0a0') or $null for default.
        Bold=$true wraps text in \e[1m...\e[22m.
        Always resets color after the write so subsequent calls start clean.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$X,
        [Parameter(Mandatory)][int]$Y,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [string]$Color = $null,
        [bool]$Bold = $false
    )

    Set-GuideCursor -X $X -Y $Y

    $prefix = ''
    $suffix = "$(Esc '0m')"    # reset after every write

    if ($Bold) {
        $prefix += "$(Esc '1m')"
    }

    if ($Color) {
        # Parse hex: 'rrggbb' → r, g, b integers
        $hex = $Color -replace '^#', ''
        if ($hex.Length -ne 6 -or $hex -notmatch '^[0-9A-Fa-f]{6}$') {
            throw "Write-GuideAt: invalid hex color '$Color' (expected 6-char rrggbb)"
        }
        $r = [Convert]::ToInt32($hex.Substring(0, 2), 16)
        $g = [Convert]::ToInt32($hex.Substring(2, 2), 16)
        $b = [Convert]::ToInt32($hex.Substring(4, 2), 16)
        $prefix += "$(Esc "38;2;${r};${g};${b}m")"
    }

    [Console]::Write("${prefix}${Text}${suffix}")
}

# ── Region drawers ────────────────────────────────────────────────────────────
#
# Each drawer signature: -State <hashtable> -Theme <hashtable> -Layout <hashtable>
# Layout rect keys expected per region: X, Y, Width, Height
# Drawers return nothing; side-effect is terminal output.

function Show-GuideHeader {
    <#
    .SYNOPSIS
        Draw the header region: title, subtitle, and overall progress bar.
    .DESCRIPTION
        Layout rect: $Layout.Header = @{ X; Y; Width; Height }
        Draws on rows Y..(Y+Height-1), columns X..(X+Width-1).
        Uses theme palette: title, fg, accent, frame colors.
        Progress bar uses glyphs: progress_filled, progress_empty.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$State,
        [Parameter(Mandatory)][hashtable]$Theme,
        [Parameter(Mandatory)][hashtable]$Layout
    )

    $rect = $Layout.Header
    $pal  = $Theme.palette
    $gl   = $Theme.glyphs

    # Clear the region first.
    Clear-GuideRegion -X $rect.X -Y $rect.Y -Width $rect.Width -Height $rect.Height

    # Row 0: title (icon + title text) and subtitle right-aligned.
    $titleIcon = if ($gl.icon_title) { $gl.icon_title } else { '' }
    $titleText = "$titleIcon $($State.Title)"
    $subtitle  = if ($State.Subtitle) { $State.Subtitle } else { '' }

    Write-GuideAt -X $rect.X -Y $rect.Y -Text $titleText `
               -Color $pal.title -Bold $true

    if ($subtitle) {
        $subtitleX = $rect.X + $rect.Width - $subtitle.Length
        if ($subtitleX -gt $rect.X) {
            Write-GuideAt -X $subtitleX -Y $rect.Y -Text $subtitle `
                       -Color $pal.dim
        }
    }

    # Row 1: overall progress bar (if height >= 2).
    if ($rect.Height -ge 2) {
        $barRow   = $rect.Y + 1
        $phasesOk = ($State.Phases | Where-Object { $_.Status -eq 'ok' }).Count
        $total    = $State.Phases.Count
        $barWidth = $Theme.sections.header.progress_bar_width
        if (-not $barWidth) { $barWidth = 20 }

        $filled = if ($total -gt 0) { [int][math]::Round($barWidth * $phasesOk / $total) } else { 0 }
        $empty  = $barWidth - $filled

        $bar = ($gl.progress_filled * $filled) + ($gl.progress_empty * $empty)
        $pct = if ($total -gt 0) { [int]($phasesOk / $total * 100) } else { 0 }
        $progressText = " $bar $pct% ($phasesOk/$total phases)"

        Write-GuideAt -X $rect.X -Y $barRow -Text $progressText -Color $pal.accent
    }
}

function Show-GuidePhasesPane {
    <#
    .SYNOPSIS
        Draw the left phases pane: phase list with status glyphs.
    .DESCRIPTION
        Layout rect: $Layout.PhasesPane = @{ X; Y; Width; Height }
        Draws a framed box. Inside: one row per phase showing status glyph + name.
        Status → glyph mapping: pending, running, ok, fail, warn.
        Currently-running phase highlighted in theme.running color.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$State,
        [Parameter(Mandatory)][hashtable]$Theme,
        [Parameter(Mandatory)][hashtable]$Layout
    )

    $rect = $Layout.PhasesPane
    $pal  = $Theme.palette
    $gl   = $Theme.glyphs

    Clear-GuideRegion -X $rect.X -Y $rect.Y -Width $rect.Width -Height $rect.Height

    # Draw border.
    _Draw-GuideBox -X $rect.X -Y $rect.Y -Width $rect.Width -Height $rect.Height `
                -Theme $Theme -Title 'Phases'

    # Inner area: X+1, Y+1, Width-2, Height-2.
    $innerX = $rect.X + 1
    $innerY = $rect.Y + 1
    $innerW = $rect.Width - 2
    $maxRows = $rect.Height - 2

    $glyphMap = @{
        pending = $gl.phase_pending
        running = $gl.phase_running
        ok      = $gl.phase_ok
        fail    = $gl.phase_fail
        warn    = $gl.phase_warn
    }
    $colorMap = @{
        pending = $pal.pending
        running = $pal.running
        ok      = $pal.ok
        fail    = $pal.fail
        warn    = $pal.warn
    }

    for ($i = 0; $i -lt [math]::Min($State.Phases.Count, $maxRows); $i++) {
        $phase  = $State.Phases[$i]
        $status = if ($phase.Status) { $phase.Status } else { 'pending' }
        $glyph  = if ($glyphMap[$status]) { $glyphMap[$status] } else { '?' }
        $color  = if ($colorMap[$status]) { $colorMap[$status] } else { $pal.dim }

        # Glyph.
        Write-GuideAt -X $innerX -Y ($innerY + $i) -Text $glyph -Color $color

        # Name (truncated to fit).
        $name = $phase.Name
        if ($name.Length -gt ($innerW - 2)) {
            $name = $name.Substring(0, $innerW - 3) + '…'
        }
        $nameColor = if ($status -eq 'running') { $pal.running } else { $pal.fg }
        Write-GuideAt -X ($innerX + 2) -Y ($innerY + $i) -Text $name -Color $nameColor
    }
}

function Show-GuideActivePane {
    <#
    .SYNOPSIS
        Draw the active sub-pane: currently-running item + spinner.
    .DESCRIPTION
        Layout rect: $Layout.ActivePane = @{ X; Y; Width; Height }
        Shows the active item name, elapsed time, and spinner frame.
        When no item is active, shows "Waiting..." in dim color.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$State,
        [Parameter(Mandatory)][hashtable]$Theme,
        [Parameter(Mandatory)][hashtable]$Layout
    )

    $rect = $Layout.ActivePane
    $pal  = $Theme.palette
    $gl   = $Theme.glyphs

    Clear-GuideRegion -X $rect.X -Y $rect.Y -Width $rect.Width -Height $rect.Height
    _Draw-GuideBox -X $rect.X -Y $rect.Y -Width $rect.Width -Height $rect.Height `
                -Theme $Theme -Title 'Active'

    $innerX = $rect.X + 1
    $innerY = $rect.Y + 1
    $innerW = $rect.Width - 2

    $active = $State.ActiveItem

    if ($active) {
        # Spinner glyph.
        $frames      = $gl.spinner_frames
        $frameIdx    = $State.SpinnerFrame % $frames.Count
        $spinnerChar = $frames[$frameIdx]

        Write-GuideAt -X $innerX -Y $innerY -Text $spinnerChar -Color $pal.running

        # Item name.
        $name = $active.Name
        if ($name.Length -gt ($innerW - 3)) {
            $name = $name.Substring(0, $innerW - 4) + '…'
        }
        Write-GuideAt -X ($innerX + 2) -Y $innerY -Text $name -Color $pal.running

        # Elapsed time (row 2 if height permits).
        if ($rect.Height -ge 4 -and $active.StartedAt) {
            $elapsed = (Get-Date) - $active.StartedAt
            $elapsedText = '{0:F1}s' -f $elapsed.TotalSeconds
            Write-GuideAt -X $innerX -Y ($innerY + 1) -Text "Elapsed: $elapsedText" `
                       -Color $pal.dim
        }
    } else {
        Write-GuideAt -X $innerX -Y $innerY -Text 'Waiting...' -Color $pal.dim
    }
}

function Show-GuideIssuesPane {
    <#
    .SYNOPSIS
        Draw the issues pane: chronological list of warnings and failures.
    .DESCRIPTION
        Layout rect: $Layout.IssuesPane = @{ X; Y; Width; Height }
        Each issue gets one row. Issues are color-coded by severity.
        When -ShowIndices is set (Phase G interactive mode), issues 1-9 get
        [N] accent-colored prefixes; issues 10+ get 4-space indent.
        Auto-scrolls to show the most recent issues when count exceeds max_visible.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$State,
        [Parameter(Mandatory)][hashtable]$Theme,
        [Parameter(Mandatory)][hashtable]$Layout,
        [switch]$ShowIndices
    )

    $rect = $Layout.IssuesPane
    $pal  = $Theme.palette
    $gl   = $Theme.glyphs

    Clear-GuideRegion -X $rect.X -Y $rect.Y -Width $rect.Width -Height $rect.Height
    _Draw-GuideBox -X $rect.X -Y $rect.Y -Width $rect.Width -Height $rect.Height `
                -Theme $Theme -Title 'Issues'

    $innerX   = $rect.X + 1
    $innerY   = $rect.Y + 1
    $innerW   = $rect.Width - 2
    $maxRows  = $rect.Height - 2

    $issues = $State.Issues
    if (-not $issues -or $issues.Count -eq 0) {
        Write-GuideAt -X $innerX -Y $innerY -Text 'No issues' -Color $pal.dim
        return
    }

    # Auto-scroll: show the last $maxRows issues.
    $start = [math]::Max(0, $issues.Count - $maxRows)

    for ($i = $start; $i -lt $issues.Count; $i++) {
        $issue    = $issues[$i]
        $row      = $innerY + ($i - $start)
        $severity = if ($issue.Severity) { $issue.Severity } else { 'info' }
        $color    = switch ($severity) {
            'fail'    { $pal.fail }
            'warning' { $pal.warn }
            default   { $pal.dim }
        }

        $n = $i + 1  # 1-based index

        if ($ShowIndices) {
            if ($n -le 9) {
                # Accent-colored [N] prefix (write separately for color control)
                $indexText = "[$n] "
                Write-GuideAt -X $innerX -Y $row -Text $indexText -Color $pal.accent
                $msgX = $innerX + $indexText.Length
                $availW = $innerW - $indexText.Length
                $msg = $issue.Message
                if ($msg.Length -gt $availW) {
                    $msg = $msg.Substring(0, $availW - 1) + '…'
                }
                Write-GuideAt -X $msgX -Y $row -Text $msg -Color $color
            } else {
                # Issues 10+: 4-space indent, no hotkey
                $msg = '    ' + $issue.Message
                if ($msg.Length -gt $innerW) {
                    $msg = $msg.Substring(0, $innerW - 1) + '…'
                }
                Write-GuideAt -X $innerX -Y $row -Text $msg -Color $color
            }
        } else {
            $prefix  = if ($gl.icon_alert -and $severity -ne 'info') { "$($gl.icon_alert) " } else { '  ' }
            $msg     = "$prefix$($issue.Message)"
            if ($msg.Length -gt $innerW) {
                $msg = $msg.Substring(0, $innerW - 1) + '…'
            }
            Write-GuideAt -X $innerX -Y $row -Text $msg -Color $color
        }
    }
}

function Show-GuideFooter {
    <#
    .SYNOPSIS
        Draw the footer: key-binding hints and status line.
    .DESCRIPTION
        Layout rect: $Layout.Footer = @{ X; Y; Width; Height }
        During run: shows "[q] quit" only.
        Post-completion (Phase G): shows "[q] quit  [1-9] copy fix command".
        Phase F: only renders the run-time footer ("press q to quit").
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$State,
        [Parameter(Mandatory)][hashtable]$Theme,
        [Parameter(Mandatory)][hashtable]$Layout
    )

    $rect = $Layout.Footer
    $pal  = $Theme.palette

    Clear-GuideRegion -X $rect.X -Y $rect.Y -Width $rect.Width -Height $rect.Height

    $hint = '[q] quit'
    Write-GuideAt -X $rect.X -Y $rect.Y -Text $hint -Color $pal.dim
}

# ── Internal helpers ──────────────────────────────────────────────────────────

function script:_Draw-GuideBox {
    <#
    .SYNOPSIS
        Draw a single-line Unicode box at (X, Y) with dimensions (Width x Height).
        Optionally renders a title centered on the top border.
    #>
    [CmdletBinding()]
    param(
        [int]$X, [int]$Y, [int]$Width, [int]$Height,
        [hashtable]$Theme,
        [string]$Title = ''
    )

    $pal = $Theme.palette
    $gl  = $Theme.glyphs
    $c   = $pal.frame

    $tl = $gl.frame_tl; $tr = $gl.frame_tr
    $bl = $gl.frame_bl; $br = $gl.frame_br
    $h  = $gl.frame_h;  $v  = $gl.frame_v

    # Top border.
    $topBar = $h * ($Width - 2)
    if ($Title) {
        $pad  = [math]::Max(0, ($Width - 2 - $Title.Length - 2))
        $lPad = [int][math]::Floor($pad / 2)
        $rPad = $pad - $lPad
        $topBar = ($h * $lPad) + " $Title " + ($h * $rPad)
    }
    Write-GuideAt -X $X -Y $Y -Text "${tl}${topBar}${tr}" -Color $c

    # Side borders.
    for ($row = $Y + 1; $row -lt ($Y + $Height - 1); $row++) {
        Write-GuideAt -X $X -Y $row -Text $v -Color $c
        Write-GuideAt -X ($X + $Width - 1) -Y $row -Text $v -Color $c
    }

    # Bottom border.
    $bottomBar = $h * ($Width - 2)
    Write-GuideAt -X $X -Y ($Y + $Height - 1) -Text "${bl}${bottomBar}${br}" -Color $c
}

# ── Phase G: Resize handling ──────────────────────────────────────────────────

function Write-GuideCentered {
    <#
    .SYNOPSIS
        Clear the screen and write each line centered both horizontally and vertically.
    .DESCRIPTION
        Used by Invoke-GuideResize to show the "Terminal too small" message.
        Guards against non-TTY environments (SetCursorPosition may throw).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$Lines,
        [int]$Width  = 80,
        [int]$Height = 24
    )

    try {
        [Console]::Clear()
        $startRow = [Math]::Max(1, [int](($Height - $Lines.Count) / 2))
        for ($i = 0; $i -lt $Lines.Count; $i++) {
            $row = $startRow + $i
            $col = [Math]::Max(1, [int](($Width - $Lines[$i].Length) / 2))
            [Console]::SetCursorPosition($col - 1, $row - 1)
            [Console]::Write($Lines[$i])
        }
    } catch {
        # Non-TTY or console API unavailable — silently skip
        Write-Verbose "Write-GuideCentered: terminal write failed — $_"
    }
}

function Start-GuideResizeWatcher {
    <#
    .SYNOPSIS
        Launch a background runspace that polls terminal size every 200ms.
    .DESCRIPTION
        When a size change is detected, enqueues a resize token into the shared
        ConcurrentQueue. The main event loop drains this queue and calls
        Invoke-GuideResize for each token.
        Returns a handle object: @{ Runspace; PowerShell; AsyncResult }.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.Concurrent.ConcurrentQueue[object]]$Queue
    )

    $initW = 0; $initH = 0
    try {
        $initW = [Console]::WindowWidth
        $initH = [Console]::WindowHeight
    } catch {
        try {
            $sz    = $Host.UI.RawUI.WindowSize
            $initW = $sz.Width
            $initH = $sz.Height
        } catch { }
    }
    if ($initW -le 0) { $initW = 80 }
    if ($initH -le 0) { $initH = 24 }

    # Share the parent's host so $Host.UI.RawUI in the child reflects the real
    # terminal. A default-constructed runspace has an inert host that never
    # sees terminal size changes — that's why resize events used to be missed.
    $rs = [runspacefactory]::CreateRunspace($Host)
    $rs.ApartmentState = 'STA'
    $rs.ThreadOptions   = 'ReuseThread'
    $rs.Open()

    $ps = [powershell]::Create()
    $ps.Runspace = $rs

    $null = $ps.AddScript({
        param($Queue, $InitialW, $InitialH)
        $w = $InitialW
        $h = $InitialH
        while ($true) {
            Start-Sleep -Milliseconds 200
            $newW = 0; $newH = 0
            # Prefer [Console] (reads the underlying terminal directly); fall
            # back to $Host.UI.RawUI for hosts where [Console] handles fail.
            try {
                $newW = [Console]::WindowWidth
                $newH = [Console]::WindowHeight
            } catch {
                try {
                    $sz = $Host.UI.RawUI.WindowSize
                    $newW = $sz.Width
                    $newH = $sz.Height
                } catch { }
            }
            # Ignore obviously-bogus zero readings (transient detection error).
            if ($newW -le 0 -or $newH -le 0) { continue }
            if ($newW -ne $w -or $newH -ne $h) {
                $w = $newW
                $h = $newH
                $null = $Queue.Enqueue([PSCustomObject]@{ Width = $w; Height = $h })
            }
        }
    }).AddParameter('Queue', $Queue).AddParameter('InitialW', $initW).AddParameter('InitialH', $initH)

    $asyncResult = $ps.BeginInvoke()

    return [PSCustomObject]@{
        Runspace    = $rs
        PowerShell  = $ps
        AsyncResult = $asyncResult
    }
}

function Stop-GuideResizeWatcher {
    <#
    .SYNOPSIS
        Stop the background resize-polling runspace and dispose resources.
    .DESCRIPTION
        Best-effort — always called in finally blocks during teardown.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][PSCustomObject]$Handle
    )
    try {
        $Handle.PowerShell.Stop()
        $Handle.PowerShell.Dispose()
        $Handle.Runspace.Close()
        $Handle.Runspace.Dispose()
    } catch {
        # Best-effort; teardown is happening anyway
        Write-Verbose "Stop-GuideResizeWatcher: cleanup error (ignored) — $_"
    }
}

function Invoke-GuideResize {
    <#
    .SYNOPSIS
        Handle a terminal resize event: update state, show "too small" or re-render.
    .DESCRIPTION
        Called by the main event loop when a resize token is dequeued.
        Updates $GuideState.TerminalWidth/Height and $GuideState.Paused.
        When below minimum (60×15): shows centered "Terminal too small" message.
        When restoring from too-small: unpauses and triggers a full re-render.
    .PARAMETER NewWidth
        New terminal width in columns.
    .PARAMETER NewHeight
        New terminal height in rows.
    .PARAMETER State
        The GuideState hashtable (carries CurrentLayout, Paused, etc.).
    .PARAMETER Theme
        The resolved theme hashtable.
    .PARAMETER Plan
        The plan hashtable (used to recompute layout).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][int]$NewWidth,
        [Parameter(Mandatory)][int]$NewHeight,
        [Parameter(Mandatory)][hashtable]$State,
        [Parameter(Mandatory)][hashtable]$Theme
    )

    $State.TerminalWidth  = $NewWidth
    $State.TerminalHeight = $NewHeight

    $minW = 60
    $minH = 10

    if ($NewWidth -lt $minW -or $NewHeight -lt $minH) {
        $State.Paused = $true

        $current = "Current: ${NewWidth}x${NewHeight}"
        $needed  = "Resize to at least ${minW}x${minH} to resume"
        $maxLen  = [Math]::Max($current.Length, $needed.Length)
        $bar     = '+' + ('-' * ($maxLen + 4)) + '+'
        $msgLines = @(
            $bar,
            ('|  Terminal too small'.PadRight($bar.Length - 1) + '|'),
            ('|  ' + $current.PadRight($maxLen) + '  |'),
            ('|  ' + $needed.PadRight($maxLen)  + '  |'),
            $bar
        )
        Write-GuideCentered -Lines $msgLines -Width $NewWidth -Height $NewHeight
        return
    }

    # If we were paused (was too-small) and are now large enough, unpause
    if ($State.Paused) {
        $State.Paused = $false
    }

    # Recompute layout and do a full re-render
    $newLayout = Get-GuideLayout -Width $NewWidth -Height $NewHeight -Theme $Theme
    $State.CurrentLayout = $newLayout

    # Full re-render with new layout. ANSI clear is more reliable than
    # [Console]::Clear() under Windows Terminal — the latter sometimes leaves
    # column-0 artifacts when re-entering after a resize.
    # \e[2J = clear screen, \e[3J = clear scrollback, \e[H = cursor home.
    try { [Console]::Write("$(Esc '2J')$(Esc '3J')$(Esc 'H')") } catch { }
    Show-GuideHeader      -State $State -Theme $Theme -Layout $newLayout
    Show-GuidePhasesPane  -State $State -Theme $Theme -Layout $newLayout
    Show-GuideActivePane  -State $State -Theme $Theme -Layout $newLayout

    # In interactive (post-completion) mode, render with indices if that flag was set
    if ($State.ContainsKey('InteractiveMode') -and $State.InteractiveMode) {
        Show-GuideIssuesPane -State $State -Theme $Theme -Layout $newLayout -ShowIndices
    } else {
        Show-GuideIssuesPane -State $State -Theme $Theme -Layout $newLayout
    }
    Show-GuideFooter      -State $State -Theme $Theme -Layout $newLayout

    # Restore footer text appropriate to current mode
    if ($State.ContainsKey('FooterText') -and $State.FooterText) {
        Set-GuideFooter -Text $State.FooterText -Layout $newLayout
    }
}

# ── Phase G: Footer management ────────────────────────────────────────────────

function Set-GuideFooter {
    <#
    .SYNOPSIS
        Write a new string to the footer region without a full re-render.
    .DESCRIPTION
        Positions cursor at the footer row, clears the line, writes the text
        in the theme's dim color, then hides cursor again.
        Requires $State.CurrentLayout to be set (done by Invoke-GuideResize or
        the initial layout computation in Invoke-GuidePlan).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Text,
        [hashtable]$Layout = $null
    )

    try {
        $l = if ($null -ne $Layout) { $Layout } else { $null }
        if ($null -eq $l) { return }

        $row = $l.Footer.Y - 1   # 0-indexed
        $col = $l.Footer.X - 1   # 0-indexed (layout uses 1-based)
        if ($col -lt 0) { $col = 0 }

        [Console]::SetCursorPosition($col, $row)
        # Clear line then write text in dim style
        [Console]::Write("`e[2K")
        [Console]::Write("`e[2m$Text`e[0m")
    } catch {
        Write-Verbose "Set-GuideFooter: footer write failed — $_"
    }
}

function Invoke-GuideFooterFlash {
    <#
    .SYNOPSIS
        Flash a message in the footer for ~1 second, then revert — non-blocking.
    .DESCRIPTION
        Sets $State.FooterFlash. The main key loop checks this on each tick and
        calls Set-GuideFooter with the revert text when the duration elapses.
        Does NOT use Start-Sleep.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message,
        [Parameter(Mandatory)][hashtable]$State,
        [Parameter(Mandatory)][hashtable]$Layout,
        [string]$RevertTo  = '[q] quit  [1-9] copy fix command',
        [int]$DurationMs   = 1000
    )

    $State.FooterFlash = [PSCustomObject]@{
        Message    = $Message
        RevertTo   = $RevertTo
        SW         = [System.Diagnostics.Stopwatch]::StartNew()
        DurationMs = $DurationMs
    }

    Set-GuideFooter -Text $Message -Layout $Layout
}
