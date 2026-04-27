# derekh/lib/state.ps1
# Owns: $DerekhState hashtable — phases, items, issues, active label, exit code.
# Does NOT know about: drawing, input, themes.

function New-DhState {
    param(
        [string]$Title    = "",
        [string]$Subtitle = ""
    )
    return @{
        Title       = $Title
        Subtitle    = $Subtitle
        StartedAt   = $null
        CompletedAt = $null
        ExitCode    = 0
        Phases      = [System.Collections.ArrayList]@()
        Issues      = [System.Collections.ArrayList]@()
        ActiveLabel = ""
    }
}

function Add-DhStatePhase {
    param(
        [hashtable]$State,
        [string]$Name,
        [ValidateSet("loop","single")]
        [string]$Type
    )
    $null = $State.Phases.Add(@{
        Name   = $Name
        Type   = $Type
        Status = "pending"
        Items  = [System.Collections.ArrayList]@()
    })
}

function Set-DhStatePhaseStatus {
    param(
        [hashtable]$State,
        [string]$PhaseName,
        [ValidateSet("pending","running","ok","fail","warn")]
        [string]$Status
    )
    $phase = $State.Phases | Where-Object { $_.Name -eq $PhaseName } | Select-Object -First 1
    if ($null -ne $phase) {
        $phase.Status = $Status
    }
}

function Add-DhStatePhaseItem {
    param(
        [hashtable]$State,
        [string]$PhaseName,
        [string]$ItemName,
        [ValidateSet("ok","fail","warn")]
        [string]$Status,
        [string]$Message = ""
    )
    $phase = $State.Phases | Where-Object { $_.Name -eq $PhaseName } | Select-Object -First 1
    if ($null -ne $phase) {
        $null = $phase.Items.Add(@{
            Name    = $ItemName
            Status  = $Status
            Message = $Message
        })
    }
}

function Add-DhStateIssue {
    param(
        [hashtable]$State,
        [string]$Phase,
        [ValidateSet("info","warning","fail")]
        [string]$Severity,
        [string]$Message,
        $FixCommand = $null,
        $Animal     = $null,
        $LogTail    = $null
    )
    $null = $State.Issues.Add(@{
        Phase      = $Phase
        Severity   = $Severity
        Message    = $Message
        FixCommand = $FixCommand
        Animal     = $Animal
        LogTail    = $LogTail
    })
}

function Set-DhStateActive {
    param(
        [hashtable]$State,
        [string]$Label
    )
    $State.ActiveLabel = $Label
}

function Get-DhStateSummary {
    param(
        [hashtable]$State
    )
    $phasesOk     = @($State.Phases | Where-Object { $_.Status -eq "ok" }).Count
    $phasesFailed = @($State.Phases | Where-Object { $_.Status -eq "fail" }).Count
    $warnings     = @($State.Issues | Where-Object { $_.Severity -eq "warning" }).Count
    $failures     = @($State.Issues | Where-Object { $_.Severity -eq "fail" }).Count

    return @{
        PhasesTotal  = $State.Phases.Count
        PhasesOk     = $phasesOk
        PhasesFailed = $phasesFailed
        IssuesTotal  = $State.Issues.Count
        Warnings     = $warnings
        Failures     = $failures
    }
}
