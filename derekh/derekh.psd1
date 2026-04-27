@{
    RootModule        = 'derekh.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = '6f4e8d52-2a1b-4c3d-9e7f-1a2b3c4d5e6f'
    Author            = 'Fellwork'
    Description       = 'Reusable TUI framework for Fellwork CLI tools (the "way" your tools take).'
    PowerShellVersion = '7.0'
    FunctionsToExport = @(
        # Primary entry point
        'Invoke-DhPlan'
        # Plan builders
        'New-DhPlan'
        'Add-DhLoopPhase'
        'Add-DhSinglePhase'
        # Result/alert builders
        'New-DhResult'
        'New-DhAlert'
        # Diagnostics
        'Get-DhTheme'
        'Get-DhVersion'
        'Test-DhEnvironment'
        # Theme helpers (Phase C)
        'Resolve-DhTheme'
        'Get-DhAvailableThemes'
        'Get-DhThemeColor'
        'Get-DhThemeGlyph'
        'Test-DhTheme'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags         = @('TUI', 'CLI', 'Fellwork')
            ProjectUri   = 'https://github.com/fellwork/tools'
            ReleaseNotes = 'v0.1.0 — initial scaffolding'
        }
    }
}
