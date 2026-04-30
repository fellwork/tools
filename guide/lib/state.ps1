# guide/lib/state.ps1
# Owns: $GuideState hashtable — phases, items, issues, active label, exit code.
# Does NOT know about: drawing, input, themes.

function New-GuideState {
    param(
        [string]$Title    = "",
        [string]$Subtitle = ""
    )
    return @{
        Title          = $Title
        Subtitle       = $Subtitle
        StartedAt      = $null
        CompletedAt    = $null
        ExitCode       = 0
        Phases         = [System.Collections.ArrayList]@()
        Issues         = [System.Collections.ArrayList]@()
        ActiveLabel    = ""
        # Phase G: resize tracking
        TerminalWidth  = 0
        TerminalHeight = 0
        Paused         = $false
        # Phase G: footer flash state
        FooterFlash    = $null   # [PSCustomObject]@{ Message; RevertTo; SW; DurationMs } | $null
        # Phase G: cached layout for Set-GuideFooter
        CurrentLayout  = $null
    }
}

function Add-GuideStatePhase {
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

function Set-GuideStatePhaseStatus {
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

function Add-GuideStatePhaseItem {
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

function Add-GuideStateIssue {
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

function Set-GuideStateActive {
    param(
        [hashtable]$State,
        [string]$Label
    )
    $State.ActiveLabel = $Label
}

function Get-GuideStateSummary {
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
