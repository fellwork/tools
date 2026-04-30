# guide/lib/layout.ps1
# Owns: pure layout math — (W, H, theme) → 5 region rectangles.
# Does NOT know: cursor positioning, escape codes.

function Test-GuideLayoutFits {
    param(
        [Parameter(Mandatory)]
        [int]$Width,
        [Parameter(Mandatory)]
        [int]$Height
    )
    return ($Width -ge 60 -and $Height -ge 10)
}

function Get-GuideLayout {
    param(
        [Parameter(Mandatory)]
        [int]$Width,
        [Parameter(Mandatory)]
        [int]$Height,
        [Parameter(Mandatory)]
        [hashtable]$Theme
    )

    # Phases pane width clamping per spec §"Section widths are constraints"
    $minW = [int]$Theme.sections.phases_pane.min_width
    $maxW = [int]$Theme.sections.phases_pane.max_width

    # Use max_width if the right pane still has at least 40 columns; otherwise min_width
    $phasesWidth = if (($Width - $maxW) -ge 40) {
        $maxW
    } else {
        $minW
    }

    # Clamp to [minW .. maxW] in all cases
    if ($phasesWidth -lt $minW) { $phasesWidth = $minW }
    if ($phasesWidth -gt $maxW) { $phasesWidth = $maxW }

    $rightX     = $phasesWidth + 1
    $rightWidth = $Width - $phasesWidth

    # Inner rows: rows 2..(H-1), count = H - 2
    $innerRows = $Height - 2

    # ActivePane takes top 40% of inner rows, minimum 3
    $activeHeight = [Math]::Max(3, [int]([Math]::Floor($innerRows * 0.4)))
    # Cap so IssuesPane gets at least 1 row
    if ($activeHeight -ge $innerRows) { $activeHeight = $innerRows - 1 }
    $issuesHeight = $innerRows - $activeHeight

    $issuesY = 2 + $activeHeight   # starts immediately after ActivePane

    return @{
        Header = @{
            X      = 1
            Y      = 1
            Width  = $Width
            Height = 1
        }
        PhasesPane = @{
            X      = 1
            Y      = 2
            Width  = $phasesWidth
            Height = $innerRows
        }
        ActivePane = @{
            X      = $rightX
            Y      = 2
            Width  = $rightWidth
            Height = $activeHeight
        }
        IssuesPane = @{
            X      = $rightX
            Y      = $issuesY
            Width  = $rightWidth
            Height = $issuesHeight
        }
        Footer = @{
            X      = 1
            Y      = $Height
            Width  = $Width
            Height = 1
        }
    }
}
