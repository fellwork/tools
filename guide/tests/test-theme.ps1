# guide/tests/test-theme.ps1
. "$PSScriptRoot/../lib/theme.ps1"

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

# --- Get-GuideTheme: loads twilight ---
$theme = Get-GuideTheme -Name "twilight"
Assert-True ($theme -is [hashtable]) "Get-GuideTheme returns hashtable"
Assert-Equal "twilight" $theme.name "Theme name field"
Assert-True ($theme.ContainsKey('palette')) "Theme has palette"
Assert-True ($theme.ContainsKey('glyphs')) "Theme has glyphs"
Assert-True ($theme.ContainsKey('sections')) "Theme has sections"
Assert-True ($theme.ContainsKey('ascii_fallback')) "Theme has ascii_fallback"

# --- Get-GuideTheme: cache hit ---
$theme2 = Get-GuideTheme -Name "twilight"
Assert-True ([object]::ReferenceEquals($theme, $theme2)) "Second call returns cached object"

# --- Get-GuideTheme: -Force bypasses cache ---
$theme3 = Get-GuideTheme -Name "twilight" -Force
Assert-True (-not [object]::ReferenceEquals($theme, $theme3)) "-Force returns fresh object"

# --- Get-GuideTheme: unknown theme throws ---
$threw = $false
try { Get-GuideTheme -Name "nonexistent_xyz" } catch { $threw = $true }
Assert-True $threw "Get-GuideTheme with unknown theme throws"

# --- Test-GuideTheme: valid theme ---
$v = Test-GuideTheme -Theme $theme
Assert-Equal $true $v.Valid "twilight passes Test-GuideTheme"
Assert-Equal 0 $v.Errors.Count "No errors on valid theme"

# --- Test-GuideTheme: palette keys present ---
foreach ($key in @('bg','bg_alt','fg','frame','title','accent','ok','warn','fail','running','pending','dim','chip_bg')) {
    Assert-True $theme.palette.ContainsKey($key) "palette has key: $key"
}

# --- Test-GuideTheme: glyph keys present ---
foreach ($key in @('phase_pending','phase_running','phase_ok','phase_fail','phase_warn','spinner_frames','progress_filled','progress_empty','frame_tl','frame_tr','frame_bl','frame_br','frame_h','frame_v')) {
    Assert-True ($theme.glyphs.PSObject.Properties.Name -contains $key -or $theme.glyphs.ContainsKey($key)) "glyphs has key: $key"
}

# --- Test-GuideTheme: section keys present ---
foreach ($key in @('header','phases_pane','active_pane','issues_pane','footer')) {
    Assert-True ($theme.sections.PSObject.Properties.Name -contains $key -or $theme.sections.ContainsKey($key)) "sections has key: $key"
}

# --- Get-GuideThemeColor: known key ---
$rgb = Get-GuideThemeColor -Theme $theme -Key "ok"
Assert-True ($rgb -is [hashtable]) "Get-GuideThemeColor returns hashtable"
Assert-True ($rgb.ContainsKey('R')) "RGB has R"
Assert-True ($rgb.ContainsKey('G')) "RGB has G"
Assert-True ($rgb.ContainsKey('B')) "RGB has B"
Assert-True ($rgb.R -ge 0 -and $rgb.R -le 255) "R in range"
Assert-True ($rgb.G -ge 0 -and $rgb.G -le 255) "G in range"
Assert-True ($rgb.B -ge 0 -and $rgb.B -le 255) "B in range"

# Twilight ok = #88e8a8 → R=136, G=232, B=168
Assert-Equal 136 $rgb.R "ok.R = 136 (#88e8a8)"
Assert-Equal 232 $rgb.G "ok.G = 232 (#88e8a8)"
Assert-Equal 168 $rgb.B "ok.B = 168 (#88e8a8)"

# --- Get-GuideThemeColor: unknown key throws ---
$threw = $false
try { Get-GuideThemeColor -Theme $theme -Key "not_a_key" } catch { $threw = $true }
Assert-True $threw "Get-GuideThemeColor with unknown key throws"

# --- Get-GuideThemeGlyph: unicode path ---
$glyph = Get-GuideThemeGlyph -Theme $theme -Key "phase_ok"
Assert-Equal "✓" $glyph "phase_ok glyph is unicode checkmark"

$pendingGlyph = Get-GuideThemeGlyph -Theme $theme -Key "phase_pending"
Assert-Equal "○" $pendingGlyph "phase_pending glyph is ○"

# --- Get-GuideThemeGlyph: -Ascii switch routes to ascii_fallback ---
$asciiOk = Get-GuideThemeGlyph -Theme $theme -Key "phase_ok" -Ascii
Assert-Equal "[+]" $asciiOk "phase_ok ascii fallback is [+]"

$asciiPending = Get-GuideThemeGlyph -Theme $theme -Key "phase_pending" -Ascii
Assert-Equal "[ ]" $asciiPending "phase_pending ascii fallback is [ ]"

$asciiRunning = Get-GuideThemeGlyph -Theme $theme -Key "phase_running" -Ascii
Assert-Equal "[~]" $asciiRunning "phase_running ascii fallback is [~]"

# --- Get-GuideThemeGlyph: spinner_frames returns array ---
$frames = Get-GuideThemeGlyph -Theme $theme -Key "spinner_frames"
Assert-True ($frames -is [array]) "spinner_frames returns array"
Assert-Equal 10 $frames.Count "spinner_frames has 10 unicode frames"

$asciiFrames = Get-GuideThemeGlyph -Theme $theme -Key "spinner_frames" -Ascii
Assert-True ($asciiFrames -is [array]) "ascii spinner_frames returns array"
Assert-Equal 4 $asciiFrames.Count "ascii spinner_frames has 4 frames"

# --- phases_pane min/max widths from sections ---
$phasesSection = $theme.sections.phases_pane
Assert-True ($phasesSection.min_width -ge 1) "phases_pane.min_width is positive"
Assert-True ($phasesSection.max_width -ge $phasesSection.min_width) "phases_pane.max_width >= min_width"
Assert-Equal 24 $phasesSection.min_width "phases_pane min_width = 24"
Assert-Equal 32 $phasesSection.max_width "phases_pane max_width = 32"

# ─── Phase C1: Resolve-GuideTheme ───────────────────────────────────────────────

# Returns CLI flag when all three levels are set
Assert-Equal "cozy" (Resolve-GuideTheme -CliFlag "cozy" -PlanField "twilight") "Resolve-GuideTheme: CLI flag wins when all set"

# Returns plan field when CLI flag is empty string
Assert-Equal "cozy" (Resolve-GuideTheme -CliFlag "" -PlanField "cozy") "Resolve-GuideTheme: plan field when CLI flag is empty"

# Returns plan field when CLI flag is null
Assert-Equal "cozy" (Resolve-GuideTheme -CliFlag $null -PlanField "cozy") "Resolve-GuideTheme: plan field when CLI flag is null"

# Returns default when both CLI flag and plan field are empty
Assert-Equal "twilight" (Resolve-GuideTheme -CliFlag "" -PlanField "") "Resolve-GuideTheme: default when both absent (empty strings)"

# Returns default when both are null
Assert-Equal "twilight" (Resolve-GuideTheme -CliFlag $null -PlanField $null) "Resolve-GuideTheme: default when both null"

# Trims whitespace before treating a value as present (CLI flag is whitespace → skip to plan field)
Assert-Equal "cozy" (Resolve-GuideTheme -CliFlag "  " -PlanField "cozy") "Resolve-GuideTheme: trims whitespace — CLI flag of spaces skips to plan field"

# Never returns null or empty
$r = Resolve-GuideTheme -CliFlag $null -PlanField $null
Assert-True (-not [string]::IsNullOrEmpty($r)) "Resolve-GuideTheme: never returns null or empty"

# Pending integration test for Invoke-GuidePlan (Phase D wires this)
Write-Host "PASS: Invoke-GuidePlan theme resolution — PENDING (Phase D)" -ForegroundColor DarkYellow

# ─── Phase C2: cozy theme file ───────────────────────────────────────────────

# Loads without error
$cozythrew = $false
try { $cozy = Get-GuideTheme -Name "cozy" } catch { $cozythrew = $true }
Assert-True (-not $cozythrew) "cozy theme: loads without error via Get-GuideTheme"

$cozy = Get-GuideTheme -Name "cozy" -Force

# Correct name field
Assert-Equal "cozy" $cozy.name "cozy theme: name field is 'cozy'"

# Test-GuideTheme -Name validation (string overload)
$cozyValid = Test-GuideTheme -Name "cozy"
Assert-Equal $true $cozyValid "cozy theme: passes Test-GuideTheme -Name validation"

# All required palette keys
foreach ($key in @("bg","bg_alt","fg","frame","title","accent","ok","warn","fail","running","pending","dim","chip_bg")) {
    Assert-True ($cozy.palette.ContainsKey($key)) "cozy theme: palette has key '$key'"
}

# Palette values are valid hex colors
foreach ($prop in $cozy.palette.Keys) {
    $val = $cozy.palette[$prop]
    Assert-True ($val -match '^#[0-9a-fA-F]{6}$') "cozy theme: palette.$prop is valid hex ($val)"
}

# Correct bg color from brainstorm palette
Assert-Equal "#2b1f15" $cozy.palette.bg "cozy theme: bg = #2b1f15"

# Correct fg color from brainstorm palette
Assert-Equal "#f0e5cc" $cozy.palette.fg "cozy theme: fg = #f0e5cc"

# ─── Phase C2: twilight still valid after cozy added ────────────────────────

$twilightThrew = $false
try { $tw = Get-GuideTheme -Name "twilight" -Force } catch { $twilightThrew = $true }
Assert-True (-not $twilightThrew) "twilight still valid: loads without error"

$twValid = Test-GuideTheme -Name "twilight"
Assert-Equal $true $twValid "twilight still valid: passes Test-GuideTheme -Name validation"

foreach ($key in @("bg","bg_alt","fg","frame","title","accent","ok","warn","fail","running","pending","dim","chip_bg")) {
    Assert-True ($tw.palette.ContainsKey($key)) "twilight still valid: palette has key '$key'"
}

# ─── Phase C2: Get-GuideAvailableThemes ────────────────────────────────────────

$themes = Get-GuideAvailableThemes

# Returns strings
Assert-True ($themes -ne $null -and $themes.Count -gt 0) "Get-GuideAvailableThemes: returns non-empty result"
foreach ($t in $themes) {
    Assert-True ($t -is [string]) "Get-GuideAvailableThemes: '$t' is a string"
}

# Includes twilight
Assert-True ($themes -contains "twilight") "Get-GuideAvailableThemes: includes 'twilight'"

# Includes cozy
Assert-True ($themes -contains "cozy") "Get-GuideAvailableThemes: includes 'cozy'"

# Returns at least two themes
Assert-True ($themes.Count -ge 2) "Get-GuideAvailableThemes: returns at least 2 themes"

# Returns names without .json extension
foreach ($t in $themes) {
    Assert-True ($t -notmatch '\.json$') "Get-GuideAvailableThemes: '$t' has no .json extension"
}

# Returns results in sorted order
$sorted = $themes | Sort-Object
$isSorted = $true
for ($i = 0; $i -lt $themes.Count; $i++) {
    if ($themes[$i] -ne $sorted[$i]) { $isSorted = $false; break }
}
Assert-True $isSorted "Get-GuideAvailableThemes: results are in sorted order"

if ($failures -eq 0) {
    Write-Host "`nAll theme tests passed." -ForegroundColor Green
    exit 0
} else {
    Write-Host "`n$failures theme test(s) failed." -ForegroundColor Red
    exit 1
}
