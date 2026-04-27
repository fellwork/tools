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

    .PARAMETER NoColor
        Suppress all ANSI color codes in streaming output.

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
        [switch]$NoColor,

        [Parameter()]
        [switch]$Ascii,

        [Parameter()]
        [string]$FixedTimeForTests = ''
    )

    # Convert switches to bools so they can be reassigned below
    $noTuiBool   = $NoTui.IsPresent
    $headlessBool = $Headless.IsPresent

    # ── Mode resolution ───────────────────────────────────────────────────────
    # Non-TTY auto-detect: if stdout is redirected AND -NoTui was not explicitly
    # passed AND -Headless was not explicitly passed, engage -NoTui streaming.
    $isNonTty = [Console]::IsOutputRedirected
    if ($isNonTty -and -not $headlessBool -and -not $noTuiBool) {
        $noTuiBool = $true
    }

    # Auto-detect headless: stdout redirected AND -NoTui not explicitly passed.
    $autoHeadless = $isNonTty -and (-not $NoTui.IsPresent) -and (-not $noTuiBool)
    $useHeadless  = $headlessBool -or $autoHeadless

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

    # ── NoTui (streaming) path — Phase E ─────────────────────────────────────
    if ($noTuiBool) {
        # Color: disabled by -NoColor flag or NO_COLOR env var
        $colorEnabled = (-not $NoColor.IsPresent) -and [string]::IsNullOrEmpty($env:NO_COLOR)

        # Resolve theme
        $themeName    = Resolve-DhTheme -CliFlag $Theme -PlanField ($Plan.Theme) -Default 'twilight'
        $resolvedTheme = Get-DhTheme -Name $themeName

        # Emit plan-started banner
        Invoke-DhStreamingRender -Event @{
            Type     = 'plan-started'
            Theme    = $resolvedTheme
            Title    = $Plan.Title
            Subtitle = if ($Plan.Subtitle) { $Plan.Subtitle } else { (Get-Date -Format 'HH:mm:ss') }
        } -ColorEnabled $colorEnabled

        # Run each phase with event emission for real-time streaming output
        $phaseIndex = 0
        $phaseTotal = $Plan.Phases.Count

        foreach ($planPhase in $Plan.Phases) {
            $phaseIndex++
            $phaseType = if ($planPhase.ContainsKey('Type')) { $planPhase.Type } else { 'loop' }

            # phase-started event
            Invoke-DhStreamingRender -Event @{
                Type       = 'phase-started'
                Theme      = $resolvedTheme
                PhaseName  = $planPhase.Name
                PhaseType  = $phaseType
                PhaseIndex = $phaseIndex
                PhaseTotal = $phaseTotal
            } -ColorEnabled $colorEnabled

            Set-DhStatePhaseStatus -State $state -PhaseName $planPhase.Name -Status 'running'
            $phaseHadFail = $false

            if ($phaseType -eq 'loop') {
                $items     = $planPhase.Items
                $itemCount = $items.Count
                $itemIdx   = 0

                foreach ($item in $items) {
                    $itemIdx++
                    Set-DhStateActive -State $state -Label $item.ToString()

                    $result = $null
                    try {
                        $result = & $planPhase.Action $item
                        if ($null -eq $result -or $result -isnot [hashtable]) {
                            $result = @{ Success = $true; Message = $item.ToString() }
                        }
                        $result = _Normalize-DhResult -Result $result
                    } catch {
                        $result = _Normalize-DhResult -Result @{
                            Success  = $false
                            Message  = $_.Exception.Message
                            Severity = 'fail'
                            Animal   = 'raccoon'
                            LogTail  = @($_.ScriptStackTrace)
                        }
                    }

                    $itemStatus = if ($result.Success) { 'ok' } else {
                        if ($result.Severity -eq 'warning') { 'warn' } else { 'fail' }
                    }
                    Add-DhStatePhaseItem -State $state -PhaseName $planPhase.Name `
                        -ItemName $item.ToString() -Status $itemStatus -Message $result.Message

                    if (-not $result.Success) {
                        $phaseHadFail = $true
                        Add-DhStateIssue -State $state -Phase $planPhase.Name `
                            -Severity $result.Severity -Message $result.Message `
                            -FixCommand $result.FixCommand -Animal $result.Animal `
                            -LogTail $result.LogTail
                    }

                    # Surface alerts from loop items
                    if ($result.Alerts -and $result.Alerts.Count -gt 0) {
                        foreach ($alert in $result.Alerts) {
                            Add-DhStateIssue -State $state -Phase $planPhase.Name `
                                -Severity $alert.Severity -Message $alert.Message `
                                -FixCommand $alert.FixCommand
                        }
                    }

                    # phase-progress event (per item)
                    $sev    = if ($result.Success) { 'ok' } elseif ($result.Severity -eq 'warning') { 'warning' } else { 'fail' }
                    $isLast = ($itemIdx -eq $itemCount)
                    Invoke-DhStreamingRender -Event @{
                        Type      = 'phase-progress'
                        Theme     = $resolvedTheme
                        PhaseName = $planPhase.Name
                        ItemName  = $item.ToString()
                        Message   = $result.Message
                        Success   = $result.Success
                        Severity  = $sev
                        IsLast    = $isLast
                    } -ColorEnabled $colorEnabled
                }

                Set-DhStateActive -State $state -Label ''
                $statePhase = $state.Phases | Where-Object { $_.Name -eq $planPhase.Name } | Select-Object -First 1
                $okCount    = @($statePhase.Items | Where-Object { $_.Status -eq 'ok' }).Count
                $phaseStatus = if ($phaseHadFail) {
                    if ($okCount -gt 0) { 'warn' } else { 'fail' }
                } else { 'ok' }
                Set-DhStatePhaseStatus -State $state -PhaseName $planPhase.Name -Status $phaseStatus

                # phase-completed event (loop phases don't show a single-line status)
                Invoke-DhStreamingRender -Event @{
                    Type       = 'phase-completed'
                    Theme      = $resolvedTheme
                    PhaseName  = $planPhase.Name
                    PhaseType  = 'loop'
                    Status     = $phaseStatus
                    OkCount    = $okCount
                    TotalCount = $itemCount
                } -ColorEnabled $colorEnabled

            } elseif ($phaseType -eq 'single') {
                Set-DhStateActive -State $state -Label $planPhase.Name

                $result = $null
                try {
                    $result = & $planPhase.Action
                    if ($null -eq $result -or $result -isnot [hashtable]) {
                        $result = @{ Success = $true; Message = $planPhase.Name }
                    }
                    $result = _Normalize-DhResult -Result $result
                } catch {
                    $result = _Normalize-DhResult -Result @{
                        Success  = $false
                        Message  = $_.Exception.Message
                        Severity = 'fail'
                        Animal   = 'raccoon'
                        LogTail  = @($_.ScriptStackTrace)
                    }
                }

                Set-DhStateActive -State $state -Label ''

                if (-not $result.Success) {
                    $phaseHadFail = $true
                    Add-DhStateIssue -State $state -Phase $planPhase.Name `
                        -Severity $result.Severity -Message $result.Message `
                        -FixCommand $result.FixCommand -Animal $result.Animal `
                        -LogTail $result.LogTail
                }

                # Surface alerts even on success
                if ($result.Alerts -and $result.Alerts.Count -gt 0) {
                    foreach ($alert in $result.Alerts) {
                        Add-DhStateIssue -State $state -Phase $planPhase.Name `
                            -Severity $alert.Severity -Message $alert.Message `
                            -FixCommand $alert.FixCommand
                    }
                }

                $phaseStatus = if ($phaseHadFail) { 'fail' } else { 'ok' }
                Set-DhStatePhaseStatus -State $state -PhaseName $planPhase.Name -Status $phaseStatus

                # phase-completed event
                Invoke-DhStreamingRender -Event @{
                    Type       = 'phase-completed'
                    Theme      = $resolvedTheme
                    PhaseName  = $planPhase.Name
                    PhaseType  = 'single'
                    Status     = $phaseStatus
                    OkCount    = if ($result.Success) { 1 } else { 0 }
                    TotalCount = 1
                } -ColorEnabled $colorEnabled
            }
        }

        # Compute final exit code
        $hasFail    = @($state.Issues | Where-Object { $_.Severity -eq 'fail' }).Count -gt 0
        $hasWarning = @($state.Issues | Where-Object { $_.Severity -eq 'warning' }).Count -gt 0
        $state.ExitCode = if ($hasFail) { 2 } elseif ($hasWarning) { 1 } else { 0 }
        $state.CompletedAt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')

        # Emit plan-completed summary
        Invoke-DhStreamingRender -Event @{
            Type     = 'plan-completed'
            Theme    = $resolvedTheme
            State    = $state
            ExitCode = $state.ExitCode
        } -ColorEnabled $colorEnabled

        return $state.ExitCode
    }

    # ── Default TUI path — Phase F stub ──────────────────────────────────────
    throw "Invoke-DhPlan (TUI): Phase F (TUI renderer) not yet implemented."
}

function Test-DhEnvironment { throw [System.NotImplementedException]::new("Test-DhEnvironment: implemented in Phase F") }
