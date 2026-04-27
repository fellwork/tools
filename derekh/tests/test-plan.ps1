# derekh/tests/test-plan.ps1
. "$PSScriptRoot/../lib/state.ps1"
. "$PSScriptRoot/../lib/plan.ps1"

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

# --- New-DhPlan ---
$plan = New-DhPlan -Title "Test" -Subtitle "now" -Theme "twilight"
Assert-True ($plan -is [hashtable]) "New-DhPlan returns hashtable"
Assert-Equal "Test" $plan.Title "Title set"
Assert-Equal "now" $plan.Subtitle "Subtitle set"
Assert-Equal "twilight" $plan.Theme "Theme set"
Assert-Equal 0 $plan.Phases.Count "Phases starts empty"

# --- Add-DhLoopPhase ---
$items = @("api", "web")
$plan = Add-DhLoopPhase -Plan $plan -Name "Clone repos" -Items $items -Action { param($i) New-DhResult -Success $true -Message "$i ok" }
Assert-Equal 1 $plan.Phases.Count "Add-DhLoopPhase appends phase"
Assert-Equal "loop" $plan.Phases[0].Type "Phase type is loop"
Assert-Equal "Clone repos" $plan.Phases[0].Name "Phase name set"
Assert-Equal 2 $plan.Phases[0].Items.Count "Items array preserved"

# --- Add-DhSinglePhase ---
$plan = Add-DhSinglePhase -Plan $plan -Name "Check prereqs" -Action { New-DhResult -Success $true -Message "all good" }
Assert-Equal 2 $plan.Phases.Count "Add-DhSinglePhase appends second phase"
Assert-Equal "single" $plan.Phases[1].Type "Phase type is single"

# --- New-DhResult ---
$r = New-DhResult -Success $true -Message "done"
Assert-Equal $true $r.Success "Result Success=$true"
Assert-Equal "done" $r.Message "Result Message set"
Assert-Equal "info" $r.Severity "Success=true defaults Severity to info"
Assert-Equal $null $r.FixCommand "FixCommand defaults null"
Assert-Equal $null $r.Animal "Animal defaults null (filled at dispatch)"
Assert-True ($r.Alerts -is [array]) "Alerts is array"
Assert-Equal 0 $r.Alerts.Count "Alerts starts empty"

$rf = New-DhResult -Success $false -Message "boom" -FixCommand "fix it" -Severity "fail"
Assert-Equal $false $rf.Success "Result Success=$false"
Assert-Equal "fail" $rf.Severity "Explicit Severity preserved"
Assert-Equal "fix it" $rf.FixCommand "FixCommand set"

# --- New-DhAlert ---
$a = New-DhAlert -Severity "warning" -Message "watch out" -FixCommand "npm install"
Assert-Equal "warning" $a.Severity "Alert severity"
Assert-Equal "watch out" $a.Message "Alert message"
Assert-Equal "npm install" $a.FixCommand "Alert FixCommand"

$a2 = New-DhAlert -Severity "info" -Message "note"
Assert-Equal $null $a2.FixCommand "Alert FixCommand defaults null"

# --- Test-DhPlan ---
$valid = Test-DhPlan -Plan $plan
Assert-Equal $true $valid.Valid "Valid plan passes Test-DhPlan"
Assert-Equal 0 $valid.Errors.Count "No errors on valid plan"

$bad = @{ Title = "" }  # missing Phases key
$invalid = Test-DhPlan -Plan $bad
Assert-Equal $false $invalid.Valid "Plan missing Phases is invalid"
Assert-True ($invalid.Errors.Count -gt 0) "Invalid plan has Errors"

# --- Invoke-DhPlanPhases: loop phase, all success ---
$loopPlan = New-DhPlan -Title "Loop test"
$loopPlan = Add-DhLoopPhase -Plan $loopPlan -Name "Clone" -Items @("a","b") -Action {
    param($item) New-DhResult -Success $true -Message "$item cloned"
}
$state = New-DhState -Title "Loop test"
Add-DhStatePhase -State $state -Name "Clone" -Type "loop"
$exitCode = Invoke-DhPlanPhases -Plan $loopPlan -State $state
Assert-Equal 0 $exitCode "All-success loop → exit code 0"
Assert-Equal 0 $state.Issues.Count "No issues on all-success loop"
Assert-Equal "ok" $state.Phases[0].Status "Phase status ok after success"
Assert-Equal 2 $state.Phases[0].Items.Count "Two items recorded"

# --- Invoke-DhPlanPhases: loop phase, one failure ---
$loopFailPlan = New-DhPlan -Title "Loop fail"
$loopFailPlan = Add-DhLoopPhase -Plan $loopFailPlan -Name "Clone" -Items @("good","bad") -Action {
    param($item)
    if ($item -eq "bad") {
        return New-DhResult -Success $false -Message "$item failed" -FixCommand "retry $item" -Severity "fail"
    }
    return New-DhResult -Success $true -Message "$item ok"
}
$state2 = New-DhState -Title "Loop fail"
Add-DhStatePhase -State $state2 -Name "Clone" -Type "loop"
$exitCode2 = Invoke-DhPlanPhases -Plan $loopFailPlan -State $state2
Assert-Equal 1 $exitCode2 "One failure → exit code 1"
Assert-Equal 1 $state2.Issues.Count "One issue emitted"
Assert-Equal "fail" $state2.Issues[0].Severity "Issue severity is fail"
Assert-Equal "retry bad" $state2.Issues[0].FixCommand "FixCommand preserved on issue"
Assert-Equal "warn" $state2.Phases[0].Status "Phase status warn when partial failure"

# --- Invoke-DhPlanPhases: action throws → raccoon, plan continues ---
$throwPlan = New-DhPlan -Title "Throw test"
$throwPlan = Add-DhLoopPhase -Plan $throwPlan -Name "Risky" -Items @("explode") -Action {
    param($item) throw "something went wrong"
}
$state3 = New-DhState -Title "Throw test"
Add-DhStatePhase -State $state3 -Name "Risky" -Type "loop"
$exitCode3 = Invoke-DhPlanPhases -Plan $throwPlan -State $state3
Assert-Equal 1 $exitCode3 "Throw → exit code 1"
Assert-Equal 1 $state3.Issues.Count "Throw emits one issue"
Assert-Equal "fail" $state3.Issues[0].Severity "Thrown issue severity is fail"
Assert-Equal "raccoon" $state3.Issues[0].Animal "Thrown issue animal is raccoon"
Assert-True ($state3.Issues[0].Message -match "something went wrong") "Exception message captured"

# --- Invoke-DhPlanPhases: single phase with Alerts ---
$singlePlan = New-DhPlan -Title "Single test"
$singlePlan = Add-DhSinglePhase -Plan $singlePlan -Name "Prereqs" -Action {
    return New-DhResult -Success $true -Message "ok" -Alerts @(
        (New-DhAlert -Severity "warning" -Message "wrangler missing" -FixCommand "npm i -g wrangler"),
        (New-DhAlert -Severity "info"    -Message "optional dep absent")
    )
}
$state4 = New-DhState -Title "Single test"
Add-DhStatePhase -State $state4 -Name "Prereqs" -Type "single"
$exitCode4 = Invoke-DhPlanPhases -Plan $singlePlan -State $state4
Assert-Equal 2 $state4.Issues.Count "Two alerts become two issues"
Assert-Equal "warning" $state4.Issues[0].Severity "First alert severity warning"
Assert-Equal "info" $state4.Issues[1].Severity "Second alert severity info"
Assert-Equal "npm i -g wrangler" $state4.Issues[0].FixCommand "Alert FixCommand preserved"
Assert-Equal 2 $exitCode4 "Warning-only → exit code 2"

# --- _Get-DhDefaultAnimal (via side effect on result normalization) ---
# Verify animal defaults are applied when Animal field is null in result
$animalPlan = New-DhPlan -Title "Animal test"
$animalPlan = Add-DhLoopPhase -Plan $animalPlan -Name "Phase" -Items @("x") -Action {
    param($item)
    return New-DhResult -Success $false -Message "fail" -Severity "fail"
    # Animal not set → should become raccoon
}
$state5 = New-DhState -Title "Animal test"
Add-DhStatePhase -State $state5 -Name "Phase" -Type "loop"
Invoke-DhPlanPhases -Plan $animalPlan -State $state5 | Out-Null
Assert-Equal "raccoon" $state5.Issues[0].Animal "fail severity → raccoon default animal"

$warnPlan = New-DhPlan -Title "Warn animal"
$warnPlan = Add-DhLoopPhase -Plan $warnPlan -Name "Phase" -Items @("x") -Action {
    param($item)
    return New-DhResult -Success $false -Message "warn" -Severity "warning"
}
$state6 = New-DhState -Title "Warn animal"
Add-DhStatePhase -State $state6 -Name "Phase" -Type "loop"
Invoke-DhPlanPhases -Plan $warnPlan -State $state6 | Out-Null
Assert-Equal "owl" $state6.Issues[0].Animal "warning severity → owl default animal"

if ($failures -eq 0) {
    Write-Host "`nAll plan tests passed." -ForegroundColor Green
    exit 0
} else {
    Write-Host "`n$failures plan test(s) failed." -ForegroundColor Red
    exit 1
}
