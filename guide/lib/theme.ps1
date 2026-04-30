# guide/lib/theme.ps1
# Owns: JSON theme loading, theme cache, color hex→RGB, glyph lookup with ASCII fallback.
# Does NOT know: what anything is drawn.

$script:_GuideThemeCache = @{}

function Get-GuideTheme {
    param(
        [string]$Name  = "twilight",
        [switch]$Force
    )

    if (-not $Force -and $script:_GuideThemeCache.ContainsKey($Name)) {
        return $script:_GuideThemeCache[$Name]
    }

    $themePath = Join-Path $PSScriptRoot "../themes/$Name.json"
    if (-not (Test-Path $themePath)) {
        throw "Guide theme not found: '$Name' (looked at: $themePath)"
    }

    $json  = Get-Content -Path $themePath -Raw -Encoding UTF8
    $theme = $json | ConvertFrom-Json -AsHashtable

    $script:_GuideThemeCache[$Name] = $theme
    return $theme
}

function Get-GuideThemeColor {
    param(
        [Parameter(Mandatory)]
        [hashtable]$Theme,
        [Parameter(Mandatory)]
        [string]$Key
    )

    if (-not $Theme.palette.ContainsKey($Key)) {
        throw "Guide theme palette has no key '$Key'"
    }

    $hex = $Theme.palette[$Key] -replace '^#', ''
    if ($hex.Length -ne 6) {
        throw "Guide theme palette '$Key' has invalid hex value: #$hex"
    }

    return @{
        R = [Convert]::ToInt32($hex.Substring(0, 2), 16)
        G = [Convert]::ToInt32($hex.Substring(2, 2), 16)
        B = [Convert]::ToInt32($hex.Substring(4, 2), 16)
    }
}

function Get-GuideThemeGlyph {
    param(
        [Parameter(Mandatory)]
        [hashtable]$Theme,
        [Parameter(Mandatory)]
        [string]$Key,
        [switch]$Ascii
    )

    if ($Ascii) {
        # Route to ascii_fallback table
        if ($Theme.ascii_fallback.ContainsKey($Key)) {
            $val = $Theme.ascii_fallback[$Key]
            # Arrays come back from ConvertFrom-Json -AsHashtable as arrays
            return $val
        }
        # Not in ascii_fallback — fall through to unicode glyphs
    }

    if ($Theme.glyphs.ContainsKey($Key)) {
        return $Theme.glyphs[$Key]
    }

    throw "Guide theme has no glyph key '$Key'"
}

function Test-GuideTheme {
    param(
        [hashtable]$Theme,
        [string]$Name
    )

    # If -Name is supplied, load the theme by name and return a simple bool
    if (-not [string]::IsNullOrEmpty($Name)) {
        $loaded = Get-GuideTheme -Name $Name
        $result = Test-GuideTheme -Theme $loaded
        return $result.Valid
    }

    if ($null -eq $Theme) {
        throw "Test-GuideTheme: Either -Theme or -Name must be provided"
    }

    $errors = [System.Collections.ArrayList]@()

    # Top-level keys
    foreach ($k in @('name','palette','glyphs','sections','ascii_fallback')) {
        if (-not $Theme.ContainsKey($k)) {
            $null = $errors.Add("Theme missing top-level key: $k")
        }
    }

    if ($Theme.ContainsKey('palette')) {
        foreach ($k in @('bg','bg_alt','fg','frame','title','accent','ok','warn','fail','running','pending','dim','chip_bg')) {
            if (-not $Theme.palette.ContainsKey($k)) {
                $null = $errors.Add("Theme palette missing key: $k")
            }
        }
    }

    if ($Theme.ContainsKey('glyphs')) {
        foreach ($k in @('phase_pending','phase_running','phase_ok','phase_fail','phase_warn','spinner_frames','progress_filled','progress_empty','frame_tl','frame_tr','frame_bl','frame_br','frame_h','frame_v')) {
            if (-not $Theme.glyphs.ContainsKey($k)) {
                $null = $errors.Add("Theme glyphs missing key: $k")
            }
        }
    }

    if ($Theme.ContainsKey('sections')) {
        foreach ($k in @('header','phases_pane','active_pane','issues_pane','footer')) {
            if (-not $Theme.sections.ContainsKey($k)) {
                $null = $errors.Add("Theme sections missing key: $k")
            }
        }
    }

    return @{
        Valid  = ($errors.Count -eq 0)
        Errors = @($errors)
    }
}

function Resolve-GuideTheme {
    <#
    .SYNOPSIS
        Resolves the effective theme name from a three-level precedence chain.
    .DESCRIPTION
        Precedence (highest to lowest):
          1. -CliFlag   (e.g. -Theme passed to Invoke-GuidePlan)
          2. -PlanField (plan.Theme set via New-GuidePlan -Theme)
          3. -Default   (built-in fallback, defaults to "twilight")
        An empty or whitespace-only value at any level is treated as absent.
    .OUTPUTS
        [string] — the resolved theme name; never null or empty.
    #>
    [CmdletBinding()]
    param(
        [string]$CliFlag,
        [string]$PlanField,
        [string]$Default = "twilight"
    )

    if (-not [string]::IsNullOrWhiteSpace($CliFlag)) {
        return $CliFlag.Trim()
    }
    if (-not [string]::IsNullOrWhiteSpace($PlanField)) {
        return $PlanField.Trim()
    }
    return $Default
}

function Get-GuideAvailableThemes {
    <#
    .SYNOPSIS
        Returns the names of all themes discoverable in the themes/ directory.
    .OUTPUTS
        [string[]] — sorted array of theme names (filename without .json extension)
    #>
    [CmdletBinding()]
    param()

    $themesDir = Join-Path $PSScriptRoot ".." "themes"
    if (-not (Test-Path $themesDir)) {
        return @()
    }
    Get-ChildItem -Path $themesDir -Filter "*.json" |
        Sort-Object Name |
        ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Name) }
}
