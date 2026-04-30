#Requires -Version 7
# Run every test suite in tests/ and print a summary.
# Adapted from bootstrap/tests/run-all.ps1.

[CmdletBinding()]
param(
    [switch]$Bail
)

$ErrorActionPreference = 'Stop'
$testsDir = $PSScriptRoot

$suites = Get-ChildItem -Path $testsDir -Filter 'test-*.ps1' |
    Where-Object { $_.Name -ne 'run-all.ps1' } |
    Sort-Object Name

if ($suites.Count -eq 0) {
    Write-Host "No test-*.ps1 files found in $testsDir" -ForegroundColor Yellow
    exit 1
}

$totalPass = 0
$totalFail = 0
$totalSeconds = 0.0
$suiteFailed = $false

function Write-Header($t) { Write-Host $t -ForegroundColor Cyan }
function Write-Ok($t)     { Write-Host $t -ForegroundColor Green }
function Write-Fail($t)   { Write-Host $t -ForegroundColor Red }
function Write-Dim($t)    { Write-Host $t -ForegroundColor DarkGray }

Write-Header ""
Write-Header "Running $($suites.Count) test suite(s) from $testsDir"
Write-Header ("=" * 60)
Write-Host ""

foreach ($suite in $suites) {
    $name = $suite.BaseName
    Write-Host -NoNewline ("  {0,-22} " -f $name)

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $output = & pwsh -NoProfile -File $suite.FullName 2>&1 | Out-String
    $exit = $LASTEXITCODE
    $sw.Stop()
    $totalSeconds += $sw.Elapsed.TotalSeconds

    $passCount = ([regex]::Matches($output, '^PASS:', 'Multiline')).Count
    $failCount = ([regex]::Matches($output, '^FAIL:', 'Multiline')).Count
    $totalPass += $passCount
    $totalFail += $failCount

    if ($exit -eq 0 -and $failCount -eq 0) {
        Write-Ok ("{0,4} pass  ({1,5:F1}s)" -f $passCount, $sw.Elapsed.TotalSeconds)
    } else {
        Write-Fail ("{0,4} pass  {1} fail  (exit {2}, {3:F1}s)" -f $passCount, $failCount, $exit, $sw.Elapsed.TotalSeconds)
        $suiteFailed = $true
        $failingLines = ($output -split "`n") | Where-Object { $_ -match '^FAIL:' }
        foreach ($line in $failingLines) { Write-Dim ("      $line") }
        if ($Bail) {
            Write-Host ""
            Write-Fail "Bailing on first failed suite (-Bail flag)."
            break
        }
    }
}

Write-Host ""
Write-Header ("=" * 60)
if ($suiteFailed) {
    Write-Fail ("TOTAL: {0} pass, {1} fail  ({2:F1}s)" -f $totalPass, $totalFail, $totalSeconds)
    exit 1
} else {
    Write-Ok ("TOTAL: {0} pass, 0 fail  ({1:F1}s)" -f $totalPass, $totalSeconds)
    exit 0
}
