#Requires -Version 7.5

[CmdletBinding()]
param(
    [switch]$UpdateGoldens
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$moduleRoot = Split-Path -Parent $PSScriptRoot
. "$moduleRoot/lib/state.ps1"
. "$moduleRoot/lib/plan.ps1"
. "$moduleRoot/lib/headless.ps1"   # will fail until D1-3

$failures = 0
$snapshotDir = "$PSScriptRoot/snapshots"

function Assert-Equal {
    param([string]$Name, $Expected, $Actual)
    if ($Expected -eq $Actual) {
        Write-Host "PASS: $Name" -ForegroundColor Green
    } else {
        Write-Host "FAIL: $Name" -ForegroundColor Red
        Write-Host "  Expected: $Expected" -ForegroundColor Yellow
        Write-Host "  Actual:   $Actual" -ForegroundColor Yellow
        $script:failures++
    }
}

function Assert-True {
    param([string]$Name, [bool]$Value)
    if ($Value) {
        Write-Host "PASS: $Name" -ForegroundColor Green
    } else {
        Write-Host "FAIL: $Name" -ForegroundColor Red
        $script:failures++
    }
}

# ── D1: ConvertTo-DhStateJson field correctness ──────────────────────────────

$fixedTs    = "2026-04-26T12:00:00Z"
$fixedTsEnd = "2026-04-26T12:00:05Z"

# Build state the correct way: New-DhState -Title -Subtitle, then Add-DhStatePhase
$state = New-DhState -Title "Test Plan" -Subtitle "12:00:00"
Add-DhStatePhase -State $state -Name "Phase One" -Type "loop"
Add-DhStatePhase -State $state -Name "Phase Two" -Type "single"

# Manually set timestamps (simulate completed run)
$state.StartedAt   = $fixedTs
$state.CompletedAt = $fixedTsEnd
$state.ExitCode    = 0

# Populate phases with synthetic completed data
$state.Phases[0].Status = "ok"
$null = $state.Phases[0].Items.Add(@{ Name = "a"; Status = "ok"; Message = "done" })
$null = $state.Phases[0].Items.Add(@{ Name = "b"; Status = "ok"; Message = "done" })
$state.Phases[1].Status = "ok"

$json   = ConvertTo-DhStateJson -State $state -OverrideStartedAt $fixedTs -OverrideCompletedAt $fixedTsEnd
# Use -AsHashtable to prevent ConvertFrom-Json auto-parsing ISO dates into [datetime]
$parsed = $json | ConvertFrom-Json -AsHashtable

Assert-Equal "D1: version field"             "0.1.0"       $parsed.version
Assert-Equal "D1: title field"               "Test Plan"   $parsed.title
Assert-Equal "D1: subtitle field"            "12:00:00"    $parsed.subtitle
# ConvertFrom-Json parses ISO 8601 strings into [datetime]; format back for comparison
$parsedStartedAt   = if ($parsed.started_at   -is [datetime]) { $parsed.started_at.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') }   else { $parsed.started_at }
$parsedCompletedAt = if ($parsed.completed_at -is [datetime]) { $parsed.completed_at.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') } else { $parsed.completed_at }
Assert-Equal "D1: started_at"                $fixedTs      $parsedStartedAt
Assert-Equal "D1: completed_at"              $fixedTsEnd   $parsedCompletedAt
Assert-Equal "D1: exit_code"                 0             $parsed.exit_code
Assert-Equal "D1: phases count"              2             $parsed.phases.Count
Assert-Equal "D1: phase[0].name"             "Phase One"   $parsed.phases[0].name
Assert-Equal "D1: phase[0].type"             "loop"        $parsed.phases[0].type
Assert-Equal "D1: phase[0].status"           "ok"          $parsed.phases[0].status
Assert-Equal "D1: phase[0].items count"      2             $parsed.phases[0].items.Count
Assert-Equal "D1: phase[1].type"             "single"      $parsed.phases[1].type
Assert-Equal "D1: phase[1].items"            0             $parsed.phases[1].items.Count
Assert-True  "D1: issues is array"           ($parsed.issues -is [array] -or $parsed.issues.Count -eq 0)
Assert-Equal "D1: summary.phases_total"      2             $parsed.summary.phases_total
Assert-Equal "D1: summary.phases_ok"         2             $parsed.summary.phases_ok
Assert-Equal "D1: summary.phases_failed"     0             $parsed.summary.phases_failed
Assert-Equal "D1: summary.issues_total"      0             $parsed.summary.issues_total
Assert-Equal "D1: summary.warnings"          0             $parsed.summary.warnings
Assert-Equal "D1: summary.failures"          0             $parsed.summary.failures

# D1: issues serialization with null fields
$state2 = New-DhState -Title "Issue Plan"
Add-DhStatePhase -State $state2 -Name "Ph" -Type "single"
$state2.StartedAt   = $fixedTs
$state2.CompletedAt = $fixedTsEnd
$state2.ExitCode    = 1
$null = $state2.Issues.Add(@{
    Phase      = "Ph"
    Severity   = "warning"
    Message    = "wrangler not found"
    FixCommand = "npm install -g wrangler"
    Animal     = "owl"
    LogTail    = $null
})
$state2.Phases[0].Status = "warning"

$json2   = ConvertTo-DhStateJson -State $state2 -OverrideStartedAt $fixedTs -OverrideCompletedAt $fixedTsEnd
$parsed2 = $json2 | ConvertFrom-Json -AsHashtable

Assert-Equal "D1: issue[0].phase"       "Ph"                      $parsed2.issues[0].phase
Assert-Equal "D1: issue[0].severity"    "warning"                 $parsed2.issues[0].severity
Assert-Equal "D1: issue[0].message"     "wrangler not found"      $parsed2.issues[0].message
Assert-Equal "D1: issue[0].fix_command" "npm install -g wrangler" $parsed2.issues[0].fix_command
Assert-Equal "D1: issue[0].animal"      "owl"                     $parsed2.issues[0].animal
Assert-True  "D1: issue[0].log_tail is null" ($null -eq $parsed2.issues[0].log_tail)

# D1: No ANSI codes in output
Assert-True  "D1: no ANSI codes in json"  (-not ($json  -match '\x1b\['))
Assert-True  "D1: no ANSI codes in json2" (-not ($json2 -match '\x1b\['))

# D1: Valid JSON (parse roundtrip)
try {
    $null = $json | ConvertFrom-Json
    Write-Host "PASS: D1: json is valid JSON" -ForegroundColor Green
} catch {
    Write-Host "FAIL: D1: json is not valid JSON -- $_" -ForegroundColor Red
    $script:failures++
}

Write-Host ""

# ── D2: Invoke-DhPlan -Headless subprocess integration ───────────────────────
# Use a helper plan script to avoid needing a real module import in the test.
# The helper script dot-sources the lib files directly.

# Embed the absolute module path so the helper works from $env:TEMP
$_derekhModulePath = (Resolve-Path "$moduleRoot/derekh.psm1").Path -replace '\\', '/'

$helperScript = @"
param([switch]`$Headless, [switch]`$NoTui)
Set-StrictMode -Version Latest
`$ErrorActionPreference = 'Stop'

# Use Import-Module with an absolute path so this works from any temp directory.
Import-Module '$_derekhModulePath' -Force -DisableNameChecking

`$plan = @{
    Title    = 'D2 Test Plan'
    Subtitle = '00:00:00'
    Phases   = @(
        @{
            Name   = 'Clone repos'
            Type   = 'loop'
            Items  = @('api', 'web')
            Action = {
                param(`$item)
                return @{ Success = `$true; Message = "`$item ok" }
            }
        }
    )
}

Invoke-DhPlan -Plan `$plan -Headless -FixedTimeForTests '2026-01-01T00:00:00Z'
"@

$helperPath = Join-Path $env:TEMP "dh-d2-helper-$(Get-Random).ps1"
Set-Content -Path $helperPath -Value $helperScript -Encoding UTF8

try {
    $output   = pwsh -NoProfile -File $helperPath -Headless 2>&1
    $exitCode = $LASTEXITCODE

    Assert-Equal "D2: process exits 0"          0              $exitCode
    Assert-True  "D2: stdout is non-empty"       ($output.Length -gt 0)

    $parsed3 = $output | ConvertFrom-Json -AsHashtable
    Assert-True  "D2: parsed is object"          ($null -ne $parsed3)
    Assert-Equal "D2: title field"               "D2 Test Plan"  $parsed3.title
    Assert-Equal "D2: phases count"              1               $parsed3.phases.Count
    Assert-Equal "D2: phase[0].name"             "Clone repos"   $parsed3.phases[0].name
    Assert-Equal "D2: phase[0].items count"      2               $parsed3.phases[0].items.Count
    Assert-Equal "D2: phase[0].items[0].status"  "ok"            $parsed3.phases[0].items[0].status
    Assert-Equal "D2: exit_code field"           0               $parsed3.exit_code
    Assert-True  "D2: no ANSI in stdout"         (-not ($output -match '\x1b\['))
} finally {
    Remove-Item -Path $helperPath -ErrorAction SilentlyContinue
}

# ── Final result (updated after each task appends) ───────────────────────────
if ($failures -gt 0) {
    Write-Host "`n$failures test(s) failed." -ForegroundColor Red
    exit 1
} else {
    Write-Host "`nAll headless tests passed." -ForegroundColor Green
    exit 0
}
