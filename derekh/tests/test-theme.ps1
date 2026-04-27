# derekh/tests/test-theme.ps1
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

# --- Get-DhTheme: loads twilight ---
$theme = Get-DhTheme -Name "twilight"
Assert-True ($theme -is [hashtable]) "Get-DhTheme returns hashtable"
Assert-Equal "twilight" $theme.name "Theme name field"
Assert-True ($theme.ContainsKey('palette')) "Theme has palette"
Assert-True ($theme.ContainsKey('glyphs')) "Theme has glyphs"
Assert-True ($theme.ContainsKey('sections')) "Theme has sections"
Assert-True ($theme.ContainsKey('ascii_fallback')) "Theme has ascii_fallback"

# --- Get-DhTheme: cache hit ---
$theme2 = Get-DhTheme -Name "twilight"
Assert-True ([object]::ReferenceEquals($theme, $theme2)) "Second call returns cached object"

# --- Get-DhTheme: -Force bypasses cache ---
$theme3 = Get-DhTheme -Name "twilight" -Force
Assert-True (-not [object]::ReferenceEquals($theme, $theme3)) "-Force returns fresh object"

# --- Get-DhTheme: unknown theme throws ---
$threw = $false
try { Get-DhTheme -Name "nonexistent_xyz" } catch { $threw = $true }
Assert-True $threw "Get-DhTheme with unknown theme throws"

# --- Test-DhTheme: valid theme ---
$v = Test-DhTheme -Theme $theme
Assert-Equal $true $v.Valid "twilight passes Test-DhTheme"
Assert-Equal 0 $v.Errors.Count "No errors on valid theme"

# --- Test-DhTheme: palette keys present ---
foreach ($key in @('bg','bg_alt','fg','frame','title','accent','ok','warn','fail','running','pending','dim','chip_bg')) {
    Assert-True $theme.palette.ContainsKey($key) "palette has key: $key"
}

# --- Test-DhTheme: glyph keys present ---
foreach ($key in @('phase_pending','phase_running','phase_ok','phase_fail','phase_warn','spinner_frames','progress_filled','progress_empty','frame_tl','frame_tr','frame_bl','frame_br','frame_h','frame_v')) {
    Assert-True ($theme.glyphs.PSObject.Properties.Name -contains $key -or $theme.glyphs.ContainsKey($key)) "glyphs has key: $key"
}

# --- Test-DhTheme: section keys present ---
foreach ($key in @('header','phases_pane','active_pane','issues_pane','footer')) {
    Assert-True ($theme.sections.PSObject.Properties.Name -contains $key -or $theme.sections.ContainsKey($key)) "sections has key: $key"
}

# --- Get-DhThemeColor: known key ---
$rgb = Get-DhThemeColor -Theme $theme -Key "ok"
Assert-True ($rgb -is [hashtable]) "Get-DhThemeColor returns hashtable"
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

# --- Get-DhThemeColor: unknown key throws ---
$threw = $false
try { Get-DhThemeColor -Theme $theme -Key "not_a_key" } catch { $threw = $true }
Assert-True $threw "Get-DhThemeColor with unknown key throws"

# --- Get-DhThemeGlyph: unicode path ---
$glyph = Get-DhThemeGlyph -Theme $theme -Key "phase_ok"
Assert-Equal "✓" $glyph "phase_ok glyph is unicode checkmark"

$pendingGlyph = Get-DhThemeGlyph -Theme $theme -Key "phase_pending"
Assert-Equal "○" $pendingGlyph "phase_pending glyph is ○"

# --- Get-DhThemeGlyph: -Ascii switch routes to ascii_fallback ---
$asciiOk = Get-DhThemeGlyph -Theme $theme -Key "phase_ok" -Ascii
Assert-Equal "[+]" $asciiOk "phase_ok ascii fallback is [+]"

$asciiPending = Get-DhThemeGlyph -Theme $theme -Key "phase_pending" -Ascii
Assert-Equal "[ ]" $asciiPending "phase_pending ascii fallback is [ ]"

$asciiRunning = Get-DhThemeGlyph -Theme $theme -Key "phase_running" -Ascii
Assert-Equal "[~]" $asciiRunning "phase_running ascii fallback is [~]"

# --- Get-DhThemeGlyph: spinner_frames returns array ---
$frames = Get-DhThemeGlyph -Theme $theme -Key "spinner_frames"
Assert-True ($frames -is [array]) "spinner_frames returns array"
Assert-Equal 10 $frames.Count "spinner_frames has 10 unicode frames"

$asciiFrames = Get-DhThemeGlyph -Theme $theme -Key "spinner_frames" -Ascii
Assert-True ($asciiFrames -is [array]) "ascii spinner_frames returns array"
Assert-Equal 4 $asciiFrames.Count "ascii spinner_frames has 4 frames"

# --- phases_pane min/max widths from sections ---
$phasesSection = $theme.sections.phases_pane
Assert-True ($phasesSection.min_width -ge 1) "phases_pane.min_width is positive"
Assert-True ($phasesSection.max_width -ge $phasesSection.min_width) "phases_pane.max_width >= min_width"
Assert-Equal 24 $phasesSection.min_width "phases_pane min_width = 24"
Assert-Equal 32 $phasesSection.max_width "phases_pane max_width = 32"

if ($failures -eq 0) {
    Write-Host "`nAll theme tests passed." -ForegroundColor Green
    exit 0
} else {
    Write-Host "`n$failures theme test(s) failed." -ForegroundColor Red
    exit 1
}
