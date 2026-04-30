#Requires -Version 7
# test-streaming-snapshot.ps1 -- Streaming renderer golden-file snapshot tests.
#
# Runs fixed plans through Invoke-GuidePlan -NoTui -NoColor, captures Write-Host
# output via stream-6 redirection, normalizes whitespace, and compares to
# golden files in tests/snapshots/.
#
# Three cases: all-success, all-fail, mixed-alerts.
#
# Golden files are created automatically on first run (GOLDEN: prefix).
# On subsequent runs, mismatches are reported as FAIL:.

$ErrorActionPreference = 'Stop'

$passCount = 0
$failCount = 0
$snapshotDir = Join-Path $PSScriptRoot 'snapshots'
if (-not (Test-Path $snapshotDir)) {
    New-Item -ItemType Directory -Path $snapshotDir | Out-Null
}

# -- Helpers ------------------------------------------------------------------

function Normalize-Snapshot([string]$text) {
    $text  = $text -replace "`r`n", "`n"
    $lines = $text -split "`n" | ForEach-Object { $_.TrimEnd() }
    return ($lines -join "`n").TrimEnd() + "`n"
}

function Compare-Snapshot {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Actual
    )
    $goldenPath = Join-Path $snapshotDir "$Name.txt"
    $normalized = Normalize-Snapshot $Actual

    if (-not (Test-Path $goldenPath)) {
        Set-Content -Path $goldenPath -Value $normalized -Encoding UTF8 -NoNewline
        Write-Host "GOLDEN: $Name -- created at $goldenPath"
        $script:passCount++
        return
    }

    $expected = Normalize-Snapshot (Get-Content -Path $goldenPath -Raw -Encoding UTF8)
    if ($expected -eq $normalized) {
        Write-Host "PASS: $Name"
        $script:passCount++
    } else {
        Write-Host "FAIL: $Name -- snapshot mismatch" -ForegroundColor Red
        Write-Host "--- Expected ---" -ForegroundColor Cyan
        Write-Host $expected
        Write-Host "--- Actual ---" -ForegroundColor Cyan
        Write-Host $normalized
        $script:failCount++
    }
}

# -- Module setup -------------------------------------------------------------

$manifestPath = Join-Path $PSScriptRoot '../guide.psd1'
Import-Module ([System.IO.Path]::GetFullPath($manifestPath)) -Force

# Stub animal phrases for determinism.
# streaming.ps1 checks via Get-Command; defining it here in the session scope
# makes it visible to the module's internal call.
function Get-GuideAnimalPhrase {
    param([string]$Animal, [string]$Situation)
    return "[$Animal/$Situation]"
}

# -- Helper: capture streaming Write-Host output ------------------------------

function Invoke-CaptureStreaming {
    param([hashtable]$Plan)
    # Write-Host goes to the Information stream (stream 6).
    # Redirect stream 6 to stdout, then filter to only InformationRecord objects
    # to discard the integer return value from Invoke-GuidePlan.
    $records = & {
        Invoke-GuidePlan -Plan $Plan -NoTui -NoColor
    } 6>&1 | Where-Object { $_ -is [System.Management.Automation.InformationRecord] }

    # Each InformationRecord's MessageData is the string passed to Write-Host
    $lines = $records | ForEach-Object { $_.MessageData.ToString() }
    return $lines -join "`n"
}

# -- Case 1: all-success ------------------------------------------------------

$planSuccess = New-GuidePlan -Title 'Test Plan' -Subtitle '00:00:00' -Theme 'twilight'
$planSuccess = Add-GuideLoopPhase -Plan $planSuccess -Name 'Clone repos' -Items @('api','web','ops') -Action {
    param($item)
    return New-GuideResult -Success $true -Message "$item cloned"
}
$planSuccess = Add-GuideLoopPhase -Plan $planSuccess -Name 'Proto install' -Items @('api','web','ops') -Action {
    param($item)
    return New-GuideResult -Success $true -Message "$item tools installed"
}

$out1 = Invoke-CaptureStreaming -Plan $planSuccess
Compare-Snapshot -Name 'streaming-all-success' -Actual $out1

# -- Case 2: all-fail ---------------------------------------------------------

$planFail = New-GuidePlan -Title 'Test Plan' -Subtitle '00:00:00' -Theme 'twilight'
$planFail = Add-GuideLoopPhase -Plan $planFail -Name 'Clone repos' -Items @('api','web') -Action {
    param($item)
    return New-GuideResult -Success $false -Message "clone failed (exit 128)" `
        -FixCommand "git clone https://github.com/fellwork/$item.git" `
        -Animal 'octopus'
}

$out2 = Invoke-CaptureStreaming -Plan $planFail
Compare-Snapshot -Name 'streaming-all-fail' -Actual $out2

# -- Case 3: mixed with alerts ------------------------------------------------

$planMixed = New-GuidePlan -Title 'Test Plan' -Subtitle '00:00:00' -Theme 'twilight'
$planMixed = Add-GuideLoopPhase -Plan $planMixed -Name 'Clone repos' -Items @('api','web','ops') -Action {
    param($item)
    if ($item -eq 'ops') {
        return New-GuideResult -Success $false -Message "clone failed" `
            -FixCommand "git clone https://github.com/fellwork/ops.git" `
            -Animal 'raccoon'
    }
    return New-GuideResult -Success $true -Message "$item cloned"
}
$planMixed = Add-GuideSinglePhase -Plan $planMixed -Name 'Other prereqs' -Action {
    $alerts = @(
        (New-GuideAlert -Severity 'warning' -Message 'wrangler is not installed' `
            -FixCommand 'npm install -g wrangler')
    )
    return New-GuideResult -Success $true -Alerts $alerts
}

$out3 = Invoke-CaptureStreaming -Plan $planMixed
Compare-Snapshot -Name 'streaming-mixed-alerts' -Actual $out3

# -- Summary ------------------------------------------------------------------

Write-Host ''
Write-Host "Streaming snapshots: $passCount pass, $failCount fail"

if ($failCount -gt 0) { exit 1 } else { exit 0 }
