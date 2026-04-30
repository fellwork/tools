@{
    RootModule        = 'guide.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = '6f4e8d52-2a1b-4c3d-9e7f-1a2b3c4d5e6f'
    Author            = 'Fellwork'
    Description       = 'Reusable TUI framework for Fellwork CLI tools — guides users through phased work.'
    PowerShellVersion = '7.0'
    FunctionsToExport = @(
        # Primary entry point
        'Invoke-GuidePlan'
        # Plan builders
        'New-GuidePlan'
        'Add-GuideLoopPhase'
        'Add-GuideSinglePhase'
        # Result/alert builders
        'New-GuideResult'
        'New-GuideAlert'
        # Diagnostics
        'Get-GuideTheme'
        'Get-GuideVersion'
        'Test-GuideEnvironment'
        # Theme helpers (Phase C)
        'Resolve-GuideTheme'
        'Get-GuideAvailableThemes'
        'Get-GuideThemeColor'
        'Get-GuideThemeGlyph'
        'Test-GuideTheme'
        # Render primitives (Phase F1)
        'Initialize-GuideTui'
        'Stop-GuideTui'
        'Set-GuideCursor'
        'Clear-GuideRegion'
        'Write-GuideAt'
        # Region drawers (Phase F2)
        'Show-GuideHeader'
        'Show-GuidePhasesPane'
        'Show-GuideActivePane'
        'Show-GuideIssuesPane'
        'Show-GuideFooter'
        # Input handling (Phase F3)
        'Test-GuideKeyAvailable'
        'Read-GuideKey'
        'Register-GuideKeyHandler'
        'Unregister-GuideKeyHandler'
        'Get-GuideKeyHandlers'
        'Clear-GuideKeyHandlers'
        'Invoke-GuideKeyDispatch'
        # Clipboard (Phase F4)
        'Test-GuideClipboardAvailable'
        'Set-GuideClipboard'
        # Resize handling (Phase G1)
        'Write-GuideCentered'
        'Start-GuideResizeWatcher'
        'Stop-GuideResizeWatcher'
        'Invoke-GuideResize'
        'Resize-GuideWindow'
        # Footer management (Phase G2)
        'Set-GuideFooter'
        'Invoke-GuideFooterFlash'
        # Post-completion interactive mode (Phase G2)
        'Enter-GuideInteractiveMode'
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
