# derekh/lib/plan.ps1
# Owns: plan validation, loop/single dispatch, action invocation, result normalization.
# Does NOT know: how state is rendered.

# ── Private helpers ──────────────────────────────────────────────────────────

function _Get-DhDefaultAnimal {
    param([string]$Severity)
    switch ($Severity) {
        "fail"    { return "raccoon" }
        "warning" { return "owl"     }
        "info"    { return "turtle"  }
        default   { return "raccoon" }
    }
}

function _Normalize-DhResult {
    param([hashtable]$Result, [bool]$WasThrow = $false)

    # Ensure Success field
    if (-not $Result.ContainsKey('Success')) { $Result.Success = $false }

    # Default Severity from Success
    if (-not $Result.ContainsKey('Severity') -or [string]::IsNullOrEmpty($Result.Severity)) {
        $Result.Severity = if ($Result.Success) { "info" } else { "fail" }
    }

    # Default Animal from Severity (treat empty string same as absent/null)
    if (-not $Result.ContainsKey('Animal') -or $null -eq $Result.Animal -or [string]::IsNullOrEmpty($Result.Animal)) {
        $Result.Animal = _Get-DhDefaultAnimal -Severity $Result.Severity
    }

    # Ensure optional fields exist
    if (-not $Result.ContainsKey('Message'))    { $Result.Message    = "" }
    if (-not $Result.ContainsKey('FixCommand')) { $Result.FixCommand = $null }
    if (-not $Result.ContainsKey('LogTail'))    { $Result.LogTail    = $null }
    if (-not $Result.ContainsKey('RetryHint'))  { $Result.RetryHint  = $null }
    if (-not $Result.ContainsKey('Alerts'))     { $Result.Alerts     = @() }

    return $Result
}

# ── Public API ───────────────────────────────────────────────────────────────

function New-DhPlan {
    param(
        [Parameter(Mandatory)]
        [string]$Title,
        [string]$Subtitle = "",
        [string]$Theme    = "twilight"
    )
    return @{
        Title    = $Title
        Subtitle = $Subtitle
        Theme    = $Theme
        Phases   = [System.Collections.ArrayList]@()
    }
}

function Add-DhLoopPhase {
    param(
        [Parameter(Mandatory)]
        [hashtable]$Plan,
        [Parameter(Mandatory)]
        [string]$Name,
        [Parameter(Mandatory)]
        [array]$Items,
        [Parameter(Mandatory)]
        [scriptblock]$Action
    )
    $null = $Plan.Phases.Add(@{
        Name   = $Name
        Type   = "loop"
        Items  = $Items
        Action = $Action
    })
    return $Plan
}

function Add-DhSinglePhase {
    param(
        [Parameter(Mandatory)]
        [hashtable]$Plan,
        [Parameter(Mandatory)]
        [string]$Name,
        [Parameter(Mandatory)]
        [scriptblock]$Action
    )
    $null = $Plan.Phases.Add(@{
        Name   = $Name
        Type   = "single"
        Action = $Action
    })
    return $Plan
}

function New-DhResult {
    param(
        [Parameter(Mandatory)]
        [bool]$Success,
        [string]$Message      = "",
        [string]$Severity     = "",
        $FixCommand           = $null,
        $Animal               = $null,
        [array]$LogTail       = $null,
        $RetryHint            = $null,
        [array]$Alerts        = @()
    )
    $r = @{
        Success    = $Success
        Message    = $Message
        FixCommand = $FixCommand
        Animal     = $Animal
        LogTail    = $LogTail
        RetryHint  = $RetryHint
        Alerts     = $Alerts
    }
    # Apply default Severity
    if ([string]::IsNullOrEmpty($Severity)) {
        $r.Severity = if ($Success) { "info" } else { "fail" }
    } else {
        $r.Severity = $Severity
    }
    return $r
}

function New-DhAlert {
    param(
        [Parameter(Mandatory)]
        [ValidateSet("info","warning","fail")]
        [string]$Severity,
        [Parameter(Mandatory)]
        [string]$Message,
        $FixCommand = $null
    )
    return @{
        Severity   = $Severity
        Message    = $Message
        FixCommand = $FixCommand
    }
}

function Test-DhPlan {
    param(
        [Parameter(Mandatory)]
        [hashtable]$Plan
    )
    $errors = [System.Collections.ArrayList]@()

    if (-not $Plan.ContainsKey('Title') -or [string]::IsNullOrEmpty($Plan.Title)) {
        $null = $errors.Add("Plan.Title is required")
    }
    if (-not $Plan.ContainsKey('Phases')) {
        $null = $errors.Add("Plan.Phases is required")
    } else {
        $i = 0
        foreach ($phase in $Plan.Phases) {
            if (-not $phase.ContainsKey('Name') -or [string]::IsNullOrEmpty($phase.Name)) {
                $null = $errors.Add("Phase[$i] missing Name")
            }
            if (-not $phase.ContainsKey('Type') -or $phase.Type -notin @("loop","single")) {
                $null = $errors.Add("Phase[$i] Type must be loop or single")
            }
            if (-not $phase.ContainsKey('Action') -or $phase.Action -isnot [scriptblock]) {
                $null = $errors.Add("Phase[$i] Action must be a scriptblock")
            }
            if ($phase.Type -eq "loop" -and (-not $phase.ContainsKey('Items') -or $null -eq $phase.Items)) {
                $null = $errors.Add("Phase[$i] loop phase requires Items")
            }
            $i++
        }
    }

    return @{
        Valid  = ($errors.Count -eq 0)
        Errors = @($errors)
    }
}

function Invoke-DhPlanPhases {
    param(
        [Parameter(Mandatory)]
        [hashtable]$Plan,
        [Parameter(Mandatory)]
        [hashtable]$State
    )

    foreach ($planPhase in $Plan.Phases) {
        # Find corresponding state phase by name
        $statePhase = $State.Phases | Where-Object { $_.Name -eq $planPhase.Name } | Select-Object -First 1
        Set-DhStatePhaseStatus -State $State -PhaseName $planPhase.Name -Status "running"

        $phaseHadFail = $false

        if ($planPhase.Type -eq "loop") {
            foreach ($item in $planPhase.Items) {
                Set-DhStateActive -State $State -Label $item.ToString()

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
                        Severity = "fail"
                        Animal   = "raccoon"
                        LogTail  = @($_.ScriptStackTrace)
                    }
                }

                $itemStatus = if ($result.Success) { "ok" } else {
                    if ($result.Severity -eq "warning") { "warn" } else { "fail" }
                }
                Add-DhStatePhaseItem -State $State -PhaseName $planPhase.Name -ItemName $item.ToString() -Status $itemStatus -Message $result.Message

                if (-not $result.Success) {
                    $phaseHadFail = $true
                    Add-DhStateIssue -State $State -Phase $planPhase.Name -Severity $result.Severity `
                        -Message $result.Message -FixCommand $result.FixCommand `
                        -Animal $result.Animal -LogTail $result.LogTail
                }

                # Surface any alerts from loop items
                if ($result.Alerts -and $result.Alerts.Count -gt 0) {
                    foreach ($alert in $result.Alerts) {
                        Add-DhStateIssue -State $State -Phase $planPhase.Name -Severity $alert.Severity `
                            -Message $alert.Message -FixCommand $alert.FixCommand
                    }
                }
            }

            Set-DhStateActive -State $State -Label ""
            $phaseStatus = if ($phaseHadFail) {
                # Check if ALL items failed or just some
                $okCount = ($statePhase.Items | Where-Object { $_.Status -eq "ok" }).Count
                if ($okCount -gt 0) { "warn" } else { "fail" }
            } else { "ok" }
            Set-DhStatePhaseStatus -State $State -PhaseName $planPhase.Name -Status $phaseStatus

        } elseif ($planPhase.Type -eq "single") {
            Set-DhStateActive -State $State -Label $planPhase.Name

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
                    Severity = "fail"
                    Animal   = "raccoon"
                    LogTail  = @($_.ScriptStackTrace)
                }
            }

            Set-DhStateActive -State $State -Label ""

            if (-not $result.Success) {
                $phaseHadFail = $true
                Add-DhStateIssue -State $State -Phase $planPhase.Name -Severity $result.Severity `
                    -Message $result.Message -FixCommand $result.FixCommand `
                    -Animal $result.Animal -LogTail $result.LogTail
            }

            # Surface alerts even on success
            if ($result.Alerts -and $result.Alerts.Count -gt 0) {
                foreach ($alert in $result.Alerts) {
                    Add-DhStateIssue -State $State -Phase $planPhase.Name -Severity $alert.Severity `
                        -Message $alert.Message -FixCommand $alert.FixCommand
                }
            }

            $phaseStatus = if ($phaseHadFail) { "fail" } else { "ok" }
            Set-DhStatePhaseStatus -State $State -PhaseName $planPhase.Name -Status $phaseStatus
        }
    }

    # Compute exit code from issues
    $hasFail    = ($State.Issues | Where-Object { $_.Severity -eq "fail" }).Count -gt 0
    $hasWarning = ($State.Issues | Where-Object { $_.Severity -eq "warning" }).Count -gt 0

    $exitCode = if ($hasFail) { 1 } elseif ($hasWarning) { 2 } else { 0 }
    $State.ExitCode = $exitCode
    return $exitCode
}
