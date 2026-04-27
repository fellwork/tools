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

    # ── Default TUI path — Phase F ────────────────────────────────────────────

    # TUI teardown safety net: any unhandled exception exits the alt buffer.
    trap {
        Stop-DhTui
        Write-Error $_ -ErrorAction Continue
        exit 2
    }

    # Environment check: fall through to streaming if terminal is incapable.
    $envInfo = Test-DhEnvironment
    $useTui  = $envInfo.IsTty -and $envInfo.Fits -and $envInfo.HasColor

    if (-not $useTui) {
        # Streaming fallback (same as -NoTui path above).
        $colorEnabled = (-not $NoColor.IsPresent) -and [string]::IsNullOrEmpty($env:NO_COLOR)
        $themeName2    = Resolve-DhTheme -CliFlag $Theme -PlanField ($Plan.Theme) -Default 'twilight'
        $resolvedTheme2 = Get-DhTheme -Name $themeName2

        Invoke-DhStreamingRender -Event @{
            Type     = 'plan-started'
            Theme    = $resolvedTheme2
            Title    = $Plan.Title
            Subtitle = if ($Plan.Subtitle) { $Plan.Subtitle } else { (Get-Date -Format 'HH:mm:ss') }
        } -ColorEnabled $colorEnabled

        $phaseIndex2 = 0
        $phaseTotal2 = $Plan.Phases.Count

        foreach ($planPhase2 in $Plan.Phases) {
            $phaseIndex2++
            $phaseType2 = if ($planPhase2.ContainsKey('Type')) { $planPhase2.Type } else { 'loop' }

            Invoke-DhStreamingRender -Event @{
                Type       = 'phase-started'
                Theme      = $resolvedTheme2
                PhaseName  = $planPhase2.Name
                PhaseType  = $phaseType2
                PhaseIndex = $phaseIndex2
                PhaseTotal = $phaseTotal2
            } -ColorEnabled $colorEnabled

            Set-DhStatePhaseStatus -State $state -PhaseName $planPhase2.Name -Status 'running'
            $phaseHadFail2 = $false

            if ($phaseType2 -eq 'loop') {
                $items2     = $planPhase2.Items
                $itemCount2 = $items2.Count
                $itemIdx2   = 0

                foreach ($item2 in $items2) {
                    $itemIdx2++
                    Set-DhStateActive -State $state -Label $item2.ToString()

                    $result2 = $null
                    try {
                        $result2 = & $planPhase2.Action $item2
                        if ($null -eq $result2 -or $result2 -isnot [hashtable]) {
                            $result2 = @{ Success = $true; Message = $item2.ToString() }
                        }
                        $result2 = _Normalize-DhResult -Result $result2
                    } catch {
                        $result2 = _Normalize-DhResult -Result @{
                            Success  = $false
                            Message  = $_.Exception.Message
                            Severity = 'fail'
                            Animal   = 'raccoon'
                            LogTail  = @($_.ScriptStackTrace)
                        }
                    }

                    $itemStatus2 = if ($result2.Success) { 'ok' } else {
                        if ($result2.Severity -eq 'warning') { 'warn' } else { 'fail' }
                    }
                    Add-DhStatePhaseItem -State $state -PhaseName $planPhase2.Name `
                        -ItemName $item2.ToString() -Status $itemStatus2 -Message $result2.Message

                    if (-not $result2.Success) {
                        $phaseHadFail2 = $true
                        Add-DhStateIssue -State $state -Phase $planPhase2.Name `
                            -Severity $result2.Severity -Message $result2.Message `
                            -FixCommand $result2.FixCommand -Animal $result2.Animal `
                            -LogTail $result2.LogTail
                    }

                    if ($result2.Alerts -and $result2.Alerts.Count -gt 0) {
                        foreach ($alert2 in $result2.Alerts) {
                            Add-DhStateIssue -State $state -Phase $planPhase2.Name `
                                -Severity $alert2.Severity -Message $alert2.Message `
                                -FixCommand $alert2.FixCommand
                        }
                    }

                    $sev2   = if ($result2.Success) { 'ok' } elseif ($result2.Severity -eq 'warning') { 'warning' } else { 'fail' }
                    $isLast2 = ($itemIdx2 -eq $itemCount2)
                    Invoke-DhStreamingRender -Event @{
                        Type      = 'phase-progress'
                        Theme     = $resolvedTheme2
                        PhaseName = $planPhase2.Name
                        ItemName  = $item2.ToString()
                        Message   = $result2.Message
                        Success   = $result2.Success
                        Severity  = $sev2
                        IsLast    = $isLast2
                    } -ColorEnabled $colorEnabled
                }

                Set-DhStateActive -State $state -Label ''
                $statePhase2 = $state.Phases | Where-Object { $_.Name -eq $planPhase2.Name } | Select-Object -First 1
                $okCount2    = @($statePhase2.Items | Where-Object { $_.Status -eq 'ok' }).Count
                $phaseStatus2 = if ($phaseHadFail2) {
                    if ($okCount2 -gt 0) { 'warn' } else { 'fail' }
                } else { 'ok' }
                Set-DhStatePhaseStatus -State $state -PhaseName $planPhase2.Name -Status $phaseStatus2

                Invoke-DhStreamingRender -Event @{
                    Type       = 'phase-completed'
                    Theme      = $resolvedTheme2
                    PhaseName  = $planPhase2.Name
                    PhaseType  = 'loop'
                    Status     = $phaseStatus2
                    OkCount    = $okCount2
                    TotalCount = $itemCount2
                } -ColorEnabled $colorEnabled

            } elseif ($phaseType2 -eq 'single') {
                Set-DhStateActive -State $state -Label $planPhase2.Name

                $result2 = $null
                try {
                    $result2 = & $planPhase2.Action
                    if ($null -eq $result2 -or $result2 -isnot [hashtable]) {
                        $result2 = @{ Success = $true; Message = $planPhase2.Name }
                    }
                    $result2 = _Normalize-DhResult -Result $result2
                } catch {
                    $result2 = _Normalize-DhResult -Result @{
                        Success  = $false
                        Message  = $_.Exception.Message
                        Severity = 'fail'
                        Animal   = 'raccoon'
                        LogTail  = @($_.ScriptStackTrace)
                    }
                }

                Set-DhStateActive -State $state -Label ''

                if (-not $result2.Success) {
                    $phaseHadFail2 = $true
                    Add-DhStateIssue -State $state -Phase $planPhase2.Name `
                        -Severity $result2.Severity -Message $result2.Message `
                        -FixCommand $result2.FixCommand -Animal $result2.Animal `
                        -LogTail $result2.LogTail
                }

                if ($result2.Alerts -and $result2.Alerts.Count -gt 0) {
                    foreach ($alert2 in $result2.Alerts) {
                        Add-DhStateIssue -State $state -Phase $planPhase2.Name `
                            -Severity $alert2.Severity -Message $alert2.Message `
                            -FixCommand $alert2.FixCommand
                    }
                }

                $phaseStatus2 = if ($phaseHadFail2) { 'fail' } else { 'ok' }
                Set-DhStatePhaseStatus -State $state -PhaseName $planPhase2.Name -Status $phaseStatus2

                Invoke-DhStreamingRender -Event @{
                    Type       = 'phase-completed'
                    Theme      = $resolvedTheme2
                    PhaseName  = $planPhase2.Name
                    PhaseType  = 'single'
                    Status     = $phaseStatus2
                    OkCount    = if ($result2.Success) { 1 } else { 0 }
                    TotalCount = 1
                } -ColorEnabled $colorEnabled
            }
        }

        $hasFail2    = @($state.Issues | Where-Object { $_.Severity -eq 'fail' }).Count -gt 0
        $hasWarning2 = @($state.Issues | Where-Object { $_.Severity -eq 'warning' }).Count -gt 0
        $state.ExitCode = if ($hasFail2) { 2 } elseif ($hasWarning2) { 1 } else { 0 }
        $state.CompletedAt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')

        Invoke-DhStreamingRender -Event @{
            Type     = 'plan-completed'
            Theme    = $resolvedTheme2
            State    = $state
            ExitCode = $state.ExitCode
        } -ColorEnabled $colorEnabled

        return $state.ExitCode
    }

    # ── Full TUI path ─────────────────────────────────────────────────────────

    # Resolve theme for TUI.
    $tuiThemeName   = Resolve-DhTheme -CliFlag $Theme -PlanField ($Plan.Theme) -Default 'twilight'
    $tuiTheme       = Get-DhTheme -Name $tuiThemeName

    # Ctrl+C handler: restore terminal and exit 130 (SIGINT convention).
    $cancelHandler = {
        param($sender, $e)
        $e.Cancel = $true
        Stop-DhTui
        [Environment]::Exit(130)
    }
    $cancelEvent = Register-ObjectEvent -InputObject ([Console]) -EventName CancelKeyPress -Action $cancelHandler

    try {
        Initialize-DhTui

        # Compute layout.
        $layout = Get-DhLayout -Width $envInfo.Width -Height $envInfo.Height `
                               -Theme $tuiTheme

        # Initial full-frame render.
        Render-DhHeader      -State $state -Theme $tuiTheme -Layout $layout
        Render-DhPhasesPane  -State $state -Theme $tuiTheme -Layout $layout
        Render-DhActivePane  -State $state -Theme $tuiTheme -Layout $layout
        Render-DhIssuesPane  -State $state -Theme $tuiTheme -Layout $layout
        Render-DhFooter      -State $state -Theme $tuiTheme -Layout $layout

        # Key handlers — Phase F: quit only.
        $shouldQuit = $false
        Clear-DhKeyHandlers
        Register-DhKeyHandler -Key 'Q'      -Action { $script:shouldQuit = $true }
        Register-DhKeyHandler -Key 'Escape' -Action { $script:shouldQuit = $true }
        Register-DhKeyHandler -Key 'Enter'  -Action { $script:shouldQuit = $true }

        # Run phases with TUI redraws on state change.
        foreach ($tuiPhase in $Plan.Phases) {
            $tuiPhaseType = if ($tuiPhase.ContainsKey('Type')) { $tuiPhase.Type } else { 'loop' }
            Set-DhStatePhaseStatus -State $state -PhaseName $tuiPhase.Name -Status 'running'
            Render-DhPhasesPane -State $state -Theme $tuiTheme -Layout $layout

            $tuiPhaseHadFail = $false

            if ($tuiPhaseType -eq 'loop') {
                foreach ($tuiItem in $tuiPhase.Items) {
                    Set-DhStateActive -State $state -Label $tuiItem.ToString()
                    Render-DhActivePane -State $state -Theme $tuiTheme -Layout $layout

                    $tuiResult = $null
                    try {
                        $tuiResult = & $tuiPhase.Action $tuiItem
                        if ($null -eq $tuiResult -or $tuiResult -isnot [hashtable]) {
                            $tuiResult = @{ Success = $true; Message = $tuiItem.ToString() }
                        }
                        $tuiResult = _Normalize-DhResult -Result $tuiResult
                    } catch {
                        $tuiResult = _Normalize-DhResult -Result @{
                            Success  = $false
                            Message  = $_.Exception.Message
                            Severity = 'fail'
                            Animal   = 'raccoon'
                            LogTail  = @($_.ScriptStackTrace)
                        }
                    }

                    $tuiItemStatus = if ($tuiResult.Success) { 'ok' } else {
                        if ($tuiResult.Severity -eq 'warning') { 'warn' } else { 'fail' }
                    }
                    Add-DhStatePhaseItem -State $state -PhaseName $tuiPhase.Name `
                        -ItemName $tuiItem.ToString() -Status $tuiItemStatus -Message $tuiResult.Message

                    if (-not $tuiResult.Success) {
                        $tuiPhaseHadFail = $true
                        Add-DhStateIssue -State $state -Phase $tuiPhase.Name `
                            -Severity $tuiResult.Severity -Message $tuiResult.Message `
                            -FixCommand $tuiResult.FixCommand -Animal $tuiResult.Animal `
                            -LogTail $tuiResult.LogTail
                        Render-DhIssuesPane -State $state -Theme $tuiTheme -Layout $layout
                    }

                    if ($tuiResult.Alerts -and $tuiResult.Alerts.Count -gt 0) {
                        foreach ($tuiAlert in $tuiResult.Alerts) {
                            Add-DhStateIssue -State $state -Phase $tuiPhase.Name `
                                -Severity $tuiAlert.Severity -Message $tuiAlert.Message `
                                -FixCommand $tuiAlert.FixCommand
                        }
                        Render-DhIssuesPane -State $state -Theme $tuiTheme -Layout $layout
                    }

                    # Poll for quit key between items.
                    if (Test-DhKeyAvailable) {
                        $tuiKey = Read-DhKey
                        Invoke-DhKeyDispatch -KeyInfo $tuiKey
                    }
                    if ($shouldQuit) { break }
                }

                Set-DhStateActive -State $state -Label ''
                $tuiStatePhase = $state.Phases | Where-Object { $_.Name -eq $tuiPhase.Name } | Select-Object -First 1
                $tuiOkCount    = @($tuiStatePhase.Items | Where-Object { $_.Status -eq 'ok' }).Count
                $tuiPhaseStatus = if ($tuiPhaseHadFail) {
                    if ($tuiOkCount -gt 0) { 'warn' } else { 'fail' }
                } else { 'ok' }
                Set-DhStatePhaseStatus -State $state -PhaseName $tuiPhase.Name -Status $tuiPhaseStatus
                Render-DhPhasesPane -State $state -Theme $tuiTheme -Layout $layout
                Render-DhActivePane -State $state -Theme $tuiTheme -Layout $layout

            } elseif ($tuiPhaseType -eq 'single') {
                Set-DhStateActive -State $state -Label $tuiPhase.Name
                Render-DhActivePane -State $state -Theme $tuiTheme -Layout $layout

                $tuiResult = $null
                try {
                    $tuiResult = & $tuiPhase.Action
                    if ($null -eq $tuiResult -or $tuiResult -isnot [hashtable]) {
                        $tuiResult = @{ Success = $true; Message = $tuiPhase.Name }
                    }
                    $tuiResult = _Normalize-DhResult -Result $tuiResult
                } catch {
                    $tuiResult = _Normalize-DhResult -Result @{
                        Success  = $false
                        Message  = $_.Exception.Message
                        Severity = 'fail'
                        Animal   = 'raccoon'
                        LogTail  = @($_.ScriptStackTrace)
                    }
                }

                Set-DhStateActive -State $state -Label ''

                if (-not $tuiResult.Success) {
                    $tuiPhaseHadFail = $true
                    Add-DhStateIssue -State $state -Phase $tuiPhase.Name `
                        -Severity $tuiResult.Severity -Message $tuiResult.Message `
                        -FixCommand $tuiResult.FixCommand -Animal $tuiResult.Animal `
                        -LogTail $tuiResult.LogTail
                    Render-DhIssuesPane -State $state -Theme $tuiTheme -Layout $layout
                }

                if ($tuiResult.Alerts -and $tuiResult.Alerts.Count -gt 0) {
                    foreach ($tuiAlert in $tuiResult.Alerts) {
                        Add-DhStateIssue -State $state -Phase $tuiPhase.Name `
                            -Severity $tuiAlert.Severity -Message $tuiAlert.Message `
                            -FixCommand $tuiAlert.FixCommand
                    }
                    Render-DhIssuesPane -State $state -Theme $tuiTheme -Layout $layout
                }

                $tuiPhaseStatus = if ($tuiPhaseHadFail) { 'fail' } else { 'ok' }
                Set-DhStatePhaseStatus -State $state -PhaseName $tuiPhase.Name -Status $tuiPhaseStatus
                Render-DhPhasesPane -State $state -Theme $tuiTheme -Layout $layout
                Render-DhActivePane -State $state -Theme $tuiTheme -Layout $layout

                # Poll for quit key.
                if (Test-DhKeyAvailable) {
                    $tuiKey = Read-DhKey
                    Invoke-DhKeyDispatch -KeyInfo $tuiKey
                }
            }

            if ($shouldQuit) { break }
        }

        # Compute final exit code.
        $tuiHasFail    = @($state.Issues | Where-Object { $_.Severity -eq 'fail' }).Count -gt 0
        $tuiHasWarning = @($state.Issues | Where-Object { $_.Severity -eq 'warning' }).Count -gt 0
        $state.ExitCode    = if ($tuiHasFail) { 2 } elseif ($tuiHasWarning) { 1 } else { 0 }
        $state.CompletedAt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')

        # Re-render footer with quit prompt (plan complete).
        Render-DhFooter -State $state -Theme $tuiTheme -Layout $layout

        # Wait loop: poll keys at 50ms intervals until quit.
        while (-not $shouldQuit) {
            if (Test-DhKeyAvailable) {
                $waitKey = Read-DhKey
                Invoke-DhKeyDispatch -KeyInfo $waitKey
            }
            Start-Sleep -Milliseconds 50
        }

    } finally {
        Stop-DhTui
        Unregister-Event -SourceIdentifier $cancelEvent.Name -ErrorAction SilentlyContinue
        Remove-Job -Id $cancelEvent.Id -Force -ErrorAction SilentlyContinue
    }

    exit $state.ExitCode
}
