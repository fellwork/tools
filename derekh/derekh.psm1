# Derekh — TUI framework for Fellwork CLI tools.
# Module entry: dot-sources every file in lib/ and re-exports the public API.

$libDir = Join-Path $PSScriptRoot 'lib'
if (Test-Path $libDir) {
    Get-ChildItem -Path $libDir -Filter '*.ps1' -File | ForEach-Object {
        . $_.FullName
    }
}

# Get-DhVersion is the only Phase A function — gives the test suite a real
# passing assertion before any Phase B logic exists. All other public
# functions are stubbed below until their implementing lib/*.ps1 lands.

function Get-DhVersion {
    $manifestPath = Join-Path $PSScriptRoot 'derekh.psd1'
    if (-not (Test-Path $manifestPath)) {
        throw "Module manifest missing at $manifestPath"
    }
    $data = Import-PowerShellDataFile -Path $manifestPath
    return $data.ModuleVersion
}

function Invoke-DhPlan      { throw [System.NotImplementedException]::new("Invoke-DhPlan: implemented in Phase D (headless) and Phases E/F/G (other modes)") }
function New-DhPlan         { throw [System.NotImplementedException]::new("New-DhPlan: implemented in Phase B") }
function Add-DhLoopPhase    { throw [System.NotImplementedException]::new("Add-DhLoopPhase: implemented in Phase B") }
function Add-DhSinglePhase  { throw [System.NotImplementedException]::new("Add-DhSinglePhase: implemented in Phase B") }
function New-DhResult       { throw [System.NotImplementedException]::new("New-DhResult: implemented in Phase B") }
function New-DhAlert        { throw [System.NotImplementedException]::new("New-DhAlert: implemented in Phase B") }
function Get-DhTheme        { throw [System.NotImplementedException]::new("Get-DhTheme: implemented in Phase B") }
function Test-DhEnvironment { throw [System.NotImplementedException]::new("Test-DhEnvironment: implemented in Phase F") }
