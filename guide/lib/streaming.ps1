#Requires -Version 7
# streaming.ps1 -- Guide streaming fallback renderer.
#
# Renders plan execution events as sequential Write-Host output.
# No cursor positioning. Theme-driven ANSI truecolor colors.
#
# Public API: Invoke-GuideStreamingRender
# Private:    Format-GuideAnsi, Format-GuideStreamBanner, Format-GuideStreamSection,
#             Format-GuideStreamTreeLine, Format-GuideStreamSummary

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Private: ANSI helper
# ---------------------------------------------------------------------------

function Format-GuideAnsi {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory)]$Rgb,   # @{R=int;G=int;B=int} hashtable from Get-GuideThemeColor
        [bool]$Bold = $false,
        [bool]$Enabled = $true
    )
    if (-not $Enabled -or $null -eq $Rgb) { return $Text }
    # Support both hashtable @{R=;G=;B=} and legacy array @(R,G,B)
    $r = if ($Rgb -is [hashtable]) { $Rgb.R } else { $Rgb[0] }
    $g = if ($Rgb -is [hashtable]) { $Rgb.G } else { $Rgb[1] }
    $b = if ($Rgb -is [hashtable]) { $Rgb.B } else { $Rgb[2] }
    if ($null -eq $r -or $null -eq $g -or $null -eq $b) { return $Text }
    $boldCode = if ($Bold) { '1;' } else { '' }
    return "`e[${boldCode}38;2;${r};${g};${b}m$Text`e[0m"
}

# ---------------------------------------------------------------------------
# Private: rendering sub-functions
# ---------------------------------------------------------------------------

function Format-GuideStreamBanner {
    param(
        [hashtable]$Theme,
        [string]$Title,
        [string]$Subtitle,
        [bool]$ColorEnabled
    )
    $ruleChar  = if ($Theme.glyphs.ContainsKey('frame_h') -and $Theme.glyphs.frame_h) { $Theme.glyphs.frame_h } else { '-' }
    $icon      = if ($Theme.glyphs.ContainsKey('icon_title') -and $Theme.glyphs.icon_title) { "$($Theme.glyphs.icon_title) " } else { '' }
    $rule      = $ruleChar * 60
    $titleStr  = "  $icon$Title"
    # Right-align subtitle so total line is <= 60 chars
    $pad       = [Math]::Max(0, 60 - $titleStr.Length - $Subtitle.Length)
    $accentRgb = Get-GuideThemeColor -Theme $Theme -Key 'accent'
    $titleRgb  = Get-GuideThemeColor -Theme $Theme -Key 'title'
    $dimRgb    = Get-GuideThemeColor -Theme $Theme -Key 'dim'
    $ruleOut   = Format-GuideAnsi -Text $rule -Rgb $accentRgb -Bold $true -Enabled $ColorEnabled
    $titleOut  = Format-GuideAnsi -Text $titleStr -Rgb $titleRgb -Bold $true -Enabled $ColorEnabled
    $subOut    = Format-GuideAnsi -Text $Subtitle -Rgb $dimRgb -Enabled $ColorEnabled
    $lineOut   = "$titleOut$(' ' * $pad)$subOut"
    return @($ruleOut, $lineOut, $ruleOut)
}

function Format-GuideStreamSection {
    param(
        [hashtable]$Theme,
        [string]$Title,
        [int]$Width = 60,
        [bool]$ColorEnabled
    )
    $ruleChar  = if ($Theme.glyphs.ContainsKey('frame_h') -and $Theme.glyphs.frame_h) { $Theme.glyphs.frame_h } else { '-' }
    $prefix    = "$ruleChar$ruleChar $Title "
    $remaining = [Math]::Max(0, $Width - $prefix.Length)
    $line      = $prefix + ($ruleChar * $remaining)
    $frameRgb  = Get-GuideThemeColor -Theme $Theme -Key 'frame'
    return Format-GuideAnsi -Text $line -Rgb $frameRgb -Enabled $ColorEnabled
}

function Format-GuideStreamTreeLine {
    param(
        [hashtable]$Theme,
        [string]$ItemName,
        [string]$Message,
        [string]$Severity,   # 'ok' | 'warning' | 'fail'
        [bool]$IsLast,
        [bool]$ColorEnabled
    )
    # Glyph selection
    $glyph = switch ($Severity) {
        'ok'      { if ($Theme.glyphs.ContainsKey('phase_ok')   -and $Theme.glyphs.phase_ok)   { $Theme.glyphs.phase_ok }   else { '+' } }
        'warning' { if ($Theme.glyphs.ContainsKey('phase_warn') -and $Theme.glyphs.phase_warn) { $Theme.glyphs.phase_warn } else { '?' } }
        default   { if ($Theme.glyphs.ContainsKey('phase_fail') -and $Theme.glyphs.phase_fail) { $Theme.glyphs.phase_fail } else { '!' } }
    }
    $colorKey = switch ($Severity) {
        'ok'      { 'ok' }
        'warning' { 'warn' }
        default   { 'fail' }
    }
    $rgb = Get-GuideThemeColor -Theme $Theme -Key $colorKey
    # Box-drawing branch chars
    $branch = if ($IsLast) { 'L-' } else { '+-' }
    if ($Theme.glyphs.ContainsKey('frame_bl') -and $Theme.glyphs.frame_bl -and
        $Theme.glyphs.ContainsKey('frame_l')  -and $Theme.glyphs.frame_l  -and
        $Theme.glyphs.ContainsKey('frame_h')  -and $Theme.glyphs.frame_h) {
        $branch = if ($IsLast) { "$($Theme.glyphs.frame_bl)$($Theme.glyphs.frame_h)" } else { "$($Theme.glyphs.frame_l)$($Theme.glyphs.frame_h)" }
    }
    $truncLen = [Math]::Min(16, $ItemName.Length)
    $nameCol  = $ItemName.Substring(0, $truncLen).PadRight(16)
    $text     = "$branch $glyph $nameCol  $Message"
    return Format-GuideAnsi -Text $text -Rgb $rgb -Enabled $ColorEnabled
}

function Format-GuideStreamSummary {
    param(
        [hashtable]$Theme,
        [hashtable]$State,
        [bool]$ColorEnabled
    )
    $lines = [System.Collections.Generic.List[string]]::new()

    # Counts
    $totalPhases = $State.Phases.Count
    $okPhases    = @($State.Phases | Where-Object { $_.Status -eq 'ok' }).Count
    $warnCount   = @($State.Issues | Where-Object { $_.Severity -eq 'warning' }).Count
    $failCount   = @($State.Issues | Where-Object { $_.Severity -eq 'fail' }).Count

    $okRgb   = Get-GuideThemeColor -Theme $Theme -Key 'ok'
    $warnRgb = Get-GuideThemeColor -Theme $Theme -Key 'warn'
    $failRgb = Get-GuideThemeColor -Theme $Theme -Key 'fail'
    $dimRgb  = Get-GuideThemeColor -Theme $Theme -Key 'dim'

    $okGlyph   = if ($Theme.glyphs.ContainsKey('phase_ok')   -and $Theme.glyphs.phase_ok)   { $Theme.glyphs.phase_ok }   else { '+' }
    $warnGlyph = if ($Theme.glyphs.ContainsKey('phase_warn') -and $Theme.glyphs.phase_warn) { $Theme.glyphs.phase_warn } else { '?' }
    $failGlyph = if ($Theme.glyphs.ContainsKey('phase_fail') -and $Theme.glyphs.phase_fail) { $Theme.glyphs.phase_fail } else { '!' }

    $countColor = if ($failCount -gt 0) { $failRgb } elseif ($warnCount -gt 0) { $warnRgb } else { $okRgb }
    $countGlyph = if ($failCount -gt 0) { $failGlyph } elseif ($warnCount -gt 0) { $warnGlyph } else { $okGlyph }

    $line1 = Format-GuideAnsi -Text "  $countGlyph  $okPhases / $totalPhases phases completed" -Rgb $countColor -Enabled $ColorEnabled
    $null = $lines.Add($line1)

    if ($warnCount -gt 0) {
        $lineW = Format-GuideAnsi -Text "  $warnGlyph  $warnCount warning(s)" -Rgb $warnRgb -Enabled $ColorEnabled
        $null = $lines.Add($lineW)
    }
    if ($failCount -gt 0) {
        $lineF = Format-GuideAnsi -Text "  $failGlyph  $failCount failure(s)" -Rgb $failRgb -Enabled $ColorEnabled
        $null = $lines.Add($lineF)
    }

    # Issues section
    if ($State.Issues.Count -gt 0) {
        $null = $lines.Add('')
        $null = $lines.Add((Format-GuideStreamSection -Theme $Theme -Title 'Issues' -ColorEnabled $ColorEnabled))
        $null = $lines.Add('')
        $idx = 1
        foreach ($issue in $State.Issues) {
            $iSev   = if ($issue.Severity) { $issue.Severity } else { 'fail' }
            $iGlyph = switch ($iSev) {
                'warning' { $warnGlyph }
                'info'    { $okGlyph }
                default   { $failGlyph }
            }
            $iRgb   = switch ($iSev) {
                'warning' { $warnRgb }
                'info'    { $okRgb }
                default   { $failRgb }
            }
            $label  = Format-GuideAnsi -Text "  [$idx]" -Rgb $dimRgb -Enabled $ColorEnabled
            $header = Format-GuideAnsi -Text " $iGlyph $($issue.Message)  ($iSev)" -Rgb $iRgb -Enabled $ColorEnabled
            $null = $lines.Add("$label$header")
            if ($issue.Animal -and $issue.ContainsKey('AnimalPhrase') -and $issue.AnimalPhrase) {
                $null = $lines.Add("      $($issue.Animal)  $($issue.AnimalPhrase)")
            }
            if ($issue.FixCommand) {
                $fixOut = Format-GuideAnsi -Text "      Fix: $($issue.FixCommand)" -Rgb $dimRgb -Enabled $ColorEnabled
                $null = $lines.Add($fixOut)
            }
            $null = $lines.Add('')
            $idx++
        }
    }

    # Suggested next steps
    $actionable = @($State.Issues | Where-Object { $_.FixCommand })
    if ($actionable.Count -gt 0) {
        $null = $lines.Add((Format-GuideStreamSection -Theme $Theme -Title 'Suggested next steps' -ColorEnabled $ColorEnabled))
        $null = $lines.Add('')
        $dimLine = Format-GuideAnsi -Text '  Run these commands, then rerun to verify:' -Rgb $dimRgb -Enabled $ColorEnabled
        $null = $lines.Add($dimLine)
        $null = $lines.Add('')
        $step = 1
        foreach ($item in $actionable) {
            $iSev   = if ($item.Severity) { $item.Severity } else { 'fail' }
            $iGlyph = switch ($iSev) { 'warning' { $warnGlyph } 'info' { $okGlyph } default { $failGlyph } }
            $iRgb   = switch ($iSev) { 'warning' { $warnRgb } 'info' { $okRgb } default { $failRgb } }
            $numOut = Format-GuideAnsi -Text ("  {0,2}. $iGlyph  $($item.Message)" -f $step) -Rgb $iRgb -Enabled $ColorEnabled
            $fixOut = Format-GuideAnsi -Text "      $($item.FixCommand)" -Rgb $dimRgb -Enabled $ColorEnabled
            $null = $lines.Add($numOut)
            $null = $lines.Add($fixOut)
            $null = $lines.Add('')
            $step++
        }
    }

    # Closing phrase
    $animal    = if ($failCount -gt 0) { 'owl' } else { 'otter' }
    $situation = if ($failCount -gt 0) { 'pro-tip' } else { 'celebrate' }
    $phrase    = $null
    if (Get-Command 'Get-GuideAnimalPhrase' -ErrorAction SilentlyContinue) {
        $phrase = Get-GuideAnimalPhrase -Animal $animal -Situation $situation
    }
    if ($phrase) {
        $emoji = if ($failCount -gt 0) { '🦉' } else { '🦦' }
        $null = $lines.Add("$emoji  $phrase")
    }

    return $lines
}

# ---------------------------------------------------------------------------
# Public: Invoke-GuideStreamingRender
# ---------------------------------------------------------------------------

function Invoke-GuideStreamingRender {
    <#
    .SYNOPSIS
        Handle one plan-execution event by writing themed streaming output.

    .DESCRIPTION
        Called once per event. Renders:
          - Banner on plan-started
          - Section header on phase-started
          - Tree-line item on phase-progress
          - Phase summary line on phase-completed
          - Full summary section on plan-completed

        Issues are NOT rendered inline; they appear in the plan-completed summary.

    .PARAMETER Event
        Hashtable with at minimum a 'Type' key. Additional keys vary by type:
          plan-started    : Title, Subtitle, Theme
          phase-started   : PhaseName, PhaseType, PhaseIndex, PhaseTotal, Theme
          phase-progress  : PhaseName, ItemName, Message, Success, Severity, IsLast, Theme
          phase-completed : PhaseName, OkCount, TotalCount, Status, PhaseType, Theme
          issue-emitted   : (no-op -- collected into state for summary)
          plan-completed  : State, ExitCode, Theme

    .PARAMETER ColorEnabled
        When $false, all ANSI codes are suppressed. Also suppressed when
        the NO_COLOR environment variable is set (regardless of this param).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Event,
        [bool]$ColorEnabled = $true
    )

    # NO_COLOR env var overrides whatever the caller passed
    $colorEnabled = $ColorEnabled -and [string]::IsNullOrEmpty($env:NO_COLOR)

    switch ($Event.Type) {

        'plan-started' {
            $bannerLines = Format-GuideStreamBanner `
                -Theme        $Event.Theme `
                -Title        $Event.Title `
                -Subtitle     $Event.Subtitle `
                -ColorEnabled $colorEnabled
            Write-Host ''
            foreach ($line in $bannerLines) { Write-Host $line }
            Write-Host ''
        }

        'phase-started' {
            Write-Host ''
            $hdr = Format-GuideStreamSection `
                -Theme        $Event.Theme `
                -Title        $Event.PhaseName `
                -ColorEnabled $colorEnabled
            Write-Host $hdr
        }

        'phase-progress' {
            $sev = if ($Event.Severity) {
                $Event.Severity
            } elseif ($Event.Success) {
                'ok'
            } else {
                'fail'
            }
            $line = Format-GuideStreamTreeLine `
                -Theme        $Event.Theme `
                -ItemName     $Event.ItemName `
                -Message      $Event.Message `
                -Severity     $sev `
                -IsLast       $Event.IsLast `
                -ColorEnabled $colorEnabled
            Write-Host $line
        }

        'phase-completed' {
            # Single-phase status line (loop phases already showed tree lines)
            if ($Event.PhaseType -eq 'single') {
                $okGlyph   = if ($Event.Theme.glyphs.ContainsKey('phase_ok')   -and $Event.Theme.glyphs.phase_ok)   { $Event.Theme.glyphs.phase_ok }   else { '+' }
                $failGlyph = if ($Event.Theme.glyphs.ContainsKey('phase_fail') -and $Event.Theme.glyphs.phase_fail) { $Event.Theme.glyphs.phase_fail } else { '!' }
                $glyph  = if ($Event.Status -eq 'ok') { $okGlyph } else { $failGlyph }
                $color  = if ($Event.Status -eq 'ok') { 'ok' } else { 'fail' }
                $rgb    = Get-GuideThemeColor -Theme $Event.Theme -Key $color
                $text   = "  $glyph $($Event.PhaseName)"
                if ($null -ne $Event.OkCount -and $null -ne $Event.TotalCount) {
                    $text += "  ($($Event.OkCount)/$($Event.TotalCount))"
                }
                Write-Host (Format-GuideAnsi -Text $text -Rgb $rgb -Enabled $colorEnabled)
            }
            Write-Host ''
        }

        'issue-emitted' {
            # Issues are collected into state; rendered in plan-completed summary.
        }

        'plan-completed' {
            $theme = $Event.Theme
            Write-Host ''
            Write-Host (Format-GuideStreamSection -Theme $theme -Title 'Summary' -ColorEnabled $colorEnabled)
            Write-Host ''
            $summaryLines = Format-GuideStreamSummary `
                -Theme        $theme `
                -State        $Event.State `
                -ColorEnabled $colorEnabled
            foreach ($line in $summaryLines) { Write-Host $line }
        }

    }
}
