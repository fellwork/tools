# Derekh — TUI framework for Fellwork CLI tools.
# Module entry: dot-sources every file in lib/ and re-exports the public API.

# Dot-source lib files in dependency order.
$_libDir = Join-Path $PSScriptRoot 'lib'
if (Test-Path $_libDir) {
    Get-ChildItem -Path $_libDir -Filter '*.ps1' -File | ForEach-Object {
        . $_.FullName
    }
}

# Get-DhVersion is the only Phase A function — gives the test suite a real
# passing assertion before any Phase B logic exists.

function Get-DhVersion {
    $manifestPath = Join-Path $PSScriptRoot 'derekh.psd1'
    if (-not (Test-Path $manifestPath)) {
        throw "Module manifest missing at $manifestPath"
    }
    $data = Import-PowerShellDataFile -Path $manifestPath
    return $data.ModuleVersion
}

function Invoke-DhPlan {
    <#
    .SYNOPSIS
        Run a Derekh plan. The primary public entry point for all consumers.

    .PARAMETER Plan
        A hashtable describing the plan: Title, Subtitle, Theme, Phases.
        Each phase must have: Name, Type ("loop"|"single"), Action (scriptblock).
        Loop phases also require: Items (array).

    .PARAMETER Theme
        Optional theme name override. Overrides plan's Theme field.

    .PARAMETER Headless
        Emit JSON to stdout. No TUI or streaming output. Auto-engaged when
        stdout is redirected and -NoTui was not explicitly passed.

    .PARAMETER NoTui
        Use the streaming (non-TUI) renderer. Auto-engaged when stdout is
        not a TTY. Overrides auto-headless detection.

    .PARAMETER Ascii
        Force ASCII glyph fallback (no Unicode glyphs). Passed through to
        the theme system.

    .PARAMETER FixedTimeForTests
        ISO 8601 UTC string. When supplied, overrides all timestamps in
        headless JSON output. Used only in test scenarios.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Plan,

        [Parameter()]
        [string]$Theme = '',

        [Parameter()]
        [switch]$Headless,

        [Parameter()]
        [switch]$NoTui,

        [Parameter()]
        [switch]$Ascii,

        [Parameter()]
        [string]$FixedTimeForTests = ''
    )

    # ── Mode resolution ───────────────────────────────────────────────────────
    # Auto-detect headless: stdout redirected AND -NoTui not explicitly passed.
    $autoHeadless = ([Console]::IsOutputRedirected) -and (-not $NoTui)
    $useHeadless  = $Headless -or $autoHeadless

    # ── Validate plan ─────────────────────────────────────────────────────────
    $validation = Test-DhPlan -Plan $Plan
    if (-not $validation.Valid) {
        $msg = "Invoke-DhPlan: plan validation failed:`n" + ($validation.Errors -join "`n")
        throw $msg
    }

    # ── Build initial state ───────────────────────────────────────────────────
    $title    = if ($Plan.ContainsKey('Title'))    { $Plan.Title }    else { '' }
    $subtitle = if ($Plan.ContainsKey('Subtitle')) { $Plan.Subtitle } else { '' }
    $state    = New-DhState -Title $title -Subtitle $subtitle

    # Record start time now (before phases run)
    $state.StartedAt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')

    # Pre-register all phases in state so Invoke-DhPlanPhases can find them
    foreach ($phase in $Plan.Phases) {
        $phaseType = if ($phase.ContainsKey('Type')) { $phase.Type } else { 'loop' }
        Add-DhStatePhase -State $state -Name $phase.Name -Type $phaseType
    }

    # ── Headless path ─────────────────────────────────────────────────────────
    if ($useHeadless) {
        # Run all phases; plan.ps1 records everything into state.
        # Pipe return value to $null — Invoke-DhPlanPhases returns an exit code
        # integer that must not appear in headless JSON stdout.
        Invoke-DhPlanPhases -Plan $Plan -State $state | Out-Null

        # Record completion time
        $state.CompletedAt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')

        # Recompute exit code with spec-correct mapping:
        #   0 = no issues, 1 = warnings only, 2 = any hard failure
        $hasFail    = ($state.Issues | Where-Object { $_.Severity -eq 'fail' }).Count -gt 0
        $hasWarning = ($state.Issues | Where-Object { $_.Severity -eq 'warning' }).Count -gt 0
        $state.ExitCode = if ($hasFail) { 2 } elseif ($hasWarning) { 1 } else { 0 }

        # Serialize to JSON; -FixedTimeForTests overrides timestamps for stable test output
        $overrideStart = if ($FixedTimeForTests) { $FixedTimeForTests } else { '' }
        $overrideEnd   = if ($FixedTimeForTests) { $FixedTimeForTests } else { '' }
        $json = ConvertTo-DhStateJson -State $state `
                    -OverrideStartedAt  $overrideStart `
                    -OverrideCompletedAt $overrideEnd

        Write-Output $json
        exit $state.ExitCode
    }

    # ── NoTui (streaming) path — Phase E stub ─────────────────────────────────
    if ($NoTui) {
        throw "Invoke-DhPlan -NoTui: Phase E (streaming renderer) not yet implemented."
    }

    # ── Default TUI path — Phase F stub ──────────────────────────────────────
    throw "Invoke-DhPlan (TUI): Phase F (TUI renderer) not yet implemented."
}

function Test-DhEnvironment { throw [System.NotImplementedException]::new("Test-DhEnvironment: implemented in Phase F") }
