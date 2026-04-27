# derekh/tests/test-state.ps1
. "$PSScriptRoot/../lib/state.ps1"

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

# --- New-DhState ---
$state = New-DhState -Title "Test Plan" -Subtitle "12:00:00"
Assert-True ($state -is [hashtable]) "New-DhState returns hashtable"
Assert-Equal "Test Plan" $state.Title "Title is set"
Assert-Equal "12:00:00" $state.Subtitle "Subtitle is set"
Assert-Equal 0 $state.Phases.Count "Phases starts empty"
Assert-Equal 0 $state.Issues.Count "Issues starts empty"
Assert-Equal 0 $state.ExitCode "ExitCode starts 0"
Assert-Equal "" $state.ActiveLabel "ActiveLabel starts empty"

# --- Add-DhStatePhase ---
Add-DhStatePhase -State $state -Name "Clone repos" -Type "loop"
Assert-Equal 1 $state.Phases.Count "Add-DhStatePhase appends one phase"
Assert-Equal "Clone repos" $state.Phases[0].Name "Phase name set"
Assert-Equal "loop" $state.Phases[0].Type "Phase type set"
Assert-Equal "pending" $state.Phases[0].Status "Phase status starts pending"
Assert-Equal 0 $state.Phases[0].Items.Count "Phase items starts empty"

Add-DhStatePhase -State $state -Name "Check prereqs" -Type "single"
Assert-Equal 2 $state.Phases.Count "Second Add-DhStatePhase brings count to 2"
Assert-Equal "single" $state.Phases[1].Type "Second phase is single"

# --- Set-DhStatePhaseStatus ---
Set-DhStatePhaseStatus -State $state -PhaseName "Clone repos" -Status "running"
Assert-Equal "running" $state.Phases[0].Status "Set-DhStatePhaseStatus updates to running"

Set-DhStatePhaseStatus -State $state -PhaseName "Clone repos" -Status "ok"
Assert-Equal "ok" $state.Phases[0].Status "Set-DhStatePhaseStatus updates to ok"

Set-DhStatePhaseStatus -State $state -PhaseName "Check prereqs" -Status "fail"
Assert-Equal "fail" $state.Phases[1].Status "Set-DhStatePhaseStatus on second phase"

# --- Add-DhStatePhaseItem ---
Add-DhStatePhaseItem -State $state -PhaseName "Clone repos" -ItemName "api" -Status "ok" -Message "cloned"
Assert-Equal 1 $state.Phases[0].Items.Count "Add-DhStatePhaseItem appends item"
Assert-Equal "api" $state.Phases[0].Items[0].Name "Item name set"
Assert-Equal "ok" $state.Phases[0].Items[0].Status "Item status set"
Assert-Equal "cloned" $state.Phases[0].Items[0].Message "Item message set"

Add-DhStatePhaseItem -State $state -PhaseName "Clone repos" -ItemName "web" -Status "fail" -Message "timeout"
Assert-Equal 2 $state.Phases[0].Items.Count "Second item appended"
Assert-Equal "fail" $state.Phases[0].Items[1].Status "Second item status fail"

# --- Add-DhStateIssue ---
Add-DhStateIssue -State $state -Phase "Clone repos" -Severity "fail" -Message "web clone failed" -FixCommand "git clone web"
Assert-Equal 1 $state.Issues.Count "Add-DhStateIssue appends issue"
Assert-Equal "Clone repos" $state.Issues[0].Phase "Issue phase set"
Assert-Equal "fail" $state.Issues[0].Severity "Issue severity set"
Assert-Equal "web clone failed" $state.Issues[0].Message "Issue message set"
Assert-Equal "git clone web" $state.Issues[0].FixCommand "Issue FixCommand set"

Add-DhStateIssue -State $state -Phase "Check prereqs" -Severity "warning" -Message "wrangler missing"
Assert-Equal 2 $state.Issues.Count "Second issue appended"
Assert-Equal $null $state.Issues[1].FixCommand "FixCommand defaults to null"

# --- Set-DhStateActive ---
Set-DhStateActive -State $state -Label "cloning web..."
Assert-Equal "cloning web..." $state.ActiveLabel "Set-DhStateActive sets label"

Set-DhStateActive -State $state -Label ""
Assert-Equal "" $state.ActiveLabel "Set-DhStateActive can clear label"

# --- Get-DhStateSummary ---
$summary = Get-DhStateSummary -State $state
Assert-True ($summary -is [hashtable]) "Get-DhStateSummary returns hashtable"
Assert-Equal 2 $summary.PhasesTotal "PhasesTotal = 2"
Assert-Equal 1 $summary.PhasesOk "PhasesOk = 1 (Clone repos)"
Assert-Equal 1 $summary.PhasesFailed "PhasesFailed = 1 (Check prereqs)"
Assert-Equal 2 $summary.IssuesTotal "IssuesTotal = 2"
Assert-Equal 1 $summary.Warnings "Warnings = 1"
Assert-Equal 1 $summary.Failures "Failures = 1"

# ExitCode is updated by plan.ps1, not state.ps1; default is 0
Assert-Equal 0 $state.ExitCode "ExitCode still 0 (plan.ps1 owns this)"

if ($failures -eq 0) {
    Write-Host "`nAll state tests passed." -ForegroundColor Green
    exit 0
} else {
    Write-Host "`n$failures state test(s) failed." -ForegroundColor Red
    exit 1
}
