# Skeleton test — verifies the module loads, the manifest is correct, and the
# only Phase A function (Get-DhVersion) returns the right value. Replaced /
# extended by real per-feature tests as Phases B–H land.

$failures = 0
function Assert-Equal($expected, $actual, $message) {
    if ($expected -ne $actual) {
        Write-Host "FAIL: $message — expected '$expected' got '$actual'" -ForegroundColor Red
        $script:failures++
    } else {
        Write-Host "PASS: $message" -ForegroundColor Green
    }
}
function Assert-True($cond, $message) {
    if ($cond) { Write-Host "PASS: $message" -ForegroundColor Green }
    else       { Write-Host "FAIL: $message" -ForegroundColor Red; $script:failures++ }
}

$moduleDir = Resolve-Path "$PSScriptRoot/.."
$manifestPath = Join-Path $moduleDir 'derekh.psd1'

# Manifest exists
Assert-True (Test-Path $manifestPath) "manifest exists at $manifestPath"

# Module loads
Import-Module $manifestPath -Force -ErrorAction Stop
$mod = Get-Module derekh
Assert-True ($null -ne $mod) "module loads"
Assert-Equal 'derekh' $mod.Name "module name is derekh"

# All 9 declared exports are visible
$expected = @(
    'Invoke-DhPlan'
    'New-DhPlan'
    'Add-DhLoopPhase'
    'Add-DhSinglePhase'
    'New-DhResult'
    'New-DhAlert'
    'Get-DhTheme'
    'Get-DhVersion'
    'Test-DhEnvironment'
)
foreach ($fn in $expected) {
    $cmd = Get-Command -Module derekh -Name $fn -ErrorAction SilentlyContinue
    Assert-True ($null -ne $cmd) "exported function: $fn"
}

# Get-DhVersion returns a real semver-shaped string
$ver = Get-DhVersion
Assert-True ($ver -match '^\d+\.\d+\.\d+$') "Get-DhVersion returns semver: $ver"
Assert-Equal '0.1.0' $ver "Get-DhVersion returns 0.1.0"

if ($failures -eq 0) {
    Write-Host "`nAll skeleton tests passed." -ForegroundColor Green
    exit 0
} else {
    Write-Host "`n$failures skeleton test(s) failed." -ForegroundColor Red
    exit 1
}
