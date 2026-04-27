# derekh/tests/test-layout.ps1
. "$PSScriptRoot/../lib/theme.ps1"
. "$PSScriptRoot/../lib/layout.ps1"

$failures = 0
function Assert-Equal($expected, $actual, $message) {
    if ($expected -ne $actual) {
        Write-Host "FAIL: $message — expected '$expected' got '$actual'" -ForegroundColor Red
        $script:failures++
    } else {
        Write-Host "PASS: $message" -ForegroundColor Green
    }
}
function Assert-True($condition, $message) {
    if (-not $condition) {
        Write-Host "FAIL: $message" -ForegroundColor Red
        $script:failures++
    } else {
        Write-Host "PASS: $message" -ForegroundColor Green
    }
}

$theme = Get-DhTheme -Name "twilight"

# --- Test-DhLayoutFits ---
Assert-Equal $true  (Test-DhLayoutFits -Width 60  -Height 15) "60x15 fits (minimum)"
Assert-Equal $true  (Test-DhLayoutFits -Width 120 -Height 30) "120x30 fits"
Assert-Equal $false (Test-DhLayoutFits -Width 59  -Height 15) "59x15 too narrow"
Assert-Equal $false (Test-DhLayoutFits -Width 60  -Height 14) "60x14 too short"
Assert-Equal $false (Test-DhLayoutFits -Width 40  -Height 10) "40x10 too small"
Assert-Equal $false (Test-DhLayoutFits -Width 0   -Height 0 ) "0x0 does not fit"

# --- Get-DhLayout: returns hashtable with 5 keys ---
$layout = Get-DhLayout -Width 120 -Height 40 -Theme $theme
Assert-True ($layout -is [hashtable]) "Get-DhLayout returns hashtable"
foreach ($region in @('Header','PhasesPane','ActivePane','IssuesPane','Footer')) {
    Assert-True ($layout.ContainsKey($region)) "Layout has key: $region"
}

# --- Each rectangle has X, Y, Width, Height ---
foreach ($region in @('Header','PhasesPane','ActivePane','IssuesPane','Footer')) {
    $r = $layout[$region]
    Assert-True ($r -is [hashtable]) "$region is hashtable"
    foreach ($k in @('X','Y','Width','Height')) {
        Assert-True ($r.ContainsKey($k)) "$region has key $k"
        Assert-True ($r[$k] -is [int]) "$region.$k is int"
        Assert-True ($r[$k] -ge 0) "$region.$k is non-negative"
    }
}

# --- Header occupies row 1, full width ---
$h = $layout.Header
Assert-Equal 1 $h.X "Header.X = 1"
Assert-Equal 1 $h.Y "Header.Y = 1"
Assert-Equal 120 $h.Width "Header.Width = terminal width"
Assert-Equal 1 $h.Height "Header.Height = 1"

# --- Footer occupies last row, full width ---
$f = $layout.Footer
Assert-Equal 1 $f.X "Footer.X = 1"
Assert-Equal 40 $f.Y "Footer.Y = terminal height"
Assert-Equal 120 $f.Width "Footer.Width = terminal width"
Assert-Equal 1 $f.Height "Footer.Height = 1"

# --- PhasesPane is in left column, rows 2..(H-1) ---
$pp = $layout.PhasesPane
Assert-Equal 1 $pp.X "PhasesPane.X = 1"
Assert-Equal 2 $pp.Y "PhasesPane.Y = 2"
Assert-Equal 38 $pp.Height "PhasesPane.Height = H - 2 (rows 2..39)"
Assert-True ($pp.Width -ge 24) "PhasesPane.Width >= min_width 24"
Assert-True ($pp.Width -le 32) "PhasesPane.Width <= max_width 32"

# --- ActivePane and IssuesPane are in right column ---
$ap = $layout.ActivePane
$ip = $layout.IssuesPane
$rightX = $pp.Width + 1
Assert-Equal $rightX $ap.X "ActivePane.X = PhasesPane.Width + 1"
Assert-Equal $rightX $ip.X "IssuesPane.X = PhasesPane.Width + 1"
Assert-Equal 2 $ap.Y "ActivePane.Y = 2"

$rightWidth = 120 - $pp.Width
Assert-Equal $rightWidth $ap.Width "ActivePane.Width = W - PhasesPane.Width"
Assert-Equal $rightWidth $ip.Width "IssuesPane.Width = W - PhasesPane.Width"

# ActivePane bottom row + 1 = IssuesPane top row
Assert-Equal ($ap.Y + $ap.Height) $ip.Y "IssuesPane starts immediately after ActivePane"

# IssuesPane bottom row = H - 1 (row 39 for 40-tall)
Assert-Equal 39 ($ip.Y + $ip.Height - 1) "IssuesPane bottom = H-1"

# ActivePane height is at least 3
Assert-True ($ap.Height -ge 3) "ActivePane.Height >= 3"

# Total right column height = ActivePane.Height + IssuesPane.Height
$totalRight = $ap.Height + $ip.Height
Assert-Equal 38 $totalRight "ActivePane + IssuesPane = H - 2 rows"

# --- Minimum terminal (60x15) — layout still valid ---
$minLayout = Get-DhLayout -Width 60 -Height 15 -Theme $theme
Assert-True ($minLayout -is [hashtable]) "60x15 layout returns hashtable"
Assert-Equal 60 $minLayout.Header.Width "60x15 Header.Width = 60"
Assert-Equal 15 $minLayout.Footer.Y "60x15 Footer.Y = 15"

$minPP = $minLayout.PhasesPane
Assert-True ($minPP.Width -ge 24) "60x15 PhasesPane.Width >= min_width"
Assert-True ($minPP.Width -le 32) "60x15 PhasesPane.Width <= max_width"

# Right pane is at least 1 column wide
$minRightWidth = 60 - $minPP.Width
Assert-True ($minRightWidth -ge 1) "60x15 right pane has at least 1 column"

# ActivePane height at minimum
Assert-True ($minLayout.ActivePane.Height -ge 3) "60x15 ActivePane.Height >= 3"

# --- PhasesPane width clamping: very wide terminal uses max_width ---
$wideLayout = Get-DhLayout -Width 200 -Height 50 -Theme $theme
Assert-Equal 32 $wideLayout.PhasesPane.Width "200-wide terminal uses max_width = 32"

# --- PhasesPane width clamping: narrow terminal uses min_width ---
$narrowLayout = Get-DhLayout -Width 60 -Height 20 -Theme $theme
Assert-Equal 24 $narrowLayout.PhasesPane.Width "60-wide terminal uses min_width = 24"

# --- No overlapping regions ---
# All regions are non-overlapping by construction: header=row1, panes=rows2..(H-1), footer=rowH
# Verify by checking Y ranges don't conflict between phases and active panes
Assert-True ($layout.PhasesPane.Y -eq $layout.ActivePane.Y) "PhasesPane and ActivePane start at same row"
Assert-True ($layout.PhasesPane.X -ne $layout.ActivePane.X) "PhasesPane and ActivePane are in different columns"

if ($failures -eq 0) {
    Write-Host "`nAll layout tests passed." -ForegroundColor Green
    exit 0
} else {
    Write-Host "`n$failures layout test(s) failed." -ForegroundColor Red
    exit 1
}
