# derekh/lib/headless.ps1
# Headless JSON serializer for Derekh state.
# Knows about: $DerekhState shape.
# Does NOT know about: drawing, ANSI, input, themes.
#
# Public:
#   ConvertTo-DhStateJson -State <hashtable> [-OverrideStartedAt <string>] [-OverrideCompletedAt <string>]
#     -> [string] JSON

Set-StrictMode -Version Latest

function ConvertTo-DhStateJson {
    <#
    .SYNOPSIS
        Serializes a $DerekhState hashtable to the v1 headless JSON contract.

    .PARAMETER State
        The $DerekhState hashtable produced by New-DhState and populated by
        Invoke-DhPlanPhases.

    .PARAMETER OverrideStartedAt
        ISO 8601 UTC string (e.g. "2026-04-26T12:00:00Z"). When supplied,
        overrides state.StartedAt. Used by tests for deterministic output.

    .PARAMETER OverrideCompletedAt
        ISO 8601 UTC string. When supplied, overrides state.CompletedAt.
        Used by tests for deterministic output.

    .OUTPUTS
        [string] Pretty-printed JSON with snake_case keys, no ANSI codes.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$State,

        [Parameter()]
        [string]$OverrideStartedAt = '',

        [Parameter()]
        [string]$OverrideCompletedAt = ''
    )

    # Resolve timestamps
    $startedAt   = if ($OverrideStartedAt)   { $OverrideStartedAt }   else { $State.StartedAt }
    $completedAt = if ($OverrideCompletedAt) { $OverrideCompletedAt } else { $State.CompletedAt }

    # Ensure UTC-Z format if the values are [datetime] objects
    if ($startedAt -is [datetime]) {
        $startedAt = $startedAt.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    }
    if ($completedAt -is [datetime]) {
        $completedAt = $completedAt.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    }

    # Resolve module version from .psd1 (best-effort; fallback to "0.1.0")
    $version = '0.1.0'
    try {
        $psd1 = Join-Path (Split-Path -Parent $PSScriptRoot) 'derekh.psd1'
        if (Test-Path $psd1) {
            $manifest = Import-PowerShellDataFile $psd1
            if ($manifest.ModuleVersion) { $version = $manifest.ModuleVersion.ToString() }
        }
    } catch { <# non-fatal; keep default #> }

    # Helper: strip ANSI escape codes from a string
    function Remove-Ansi([string]$s) {
        if ([string]::IsNullOrEmpty($s)) { return $s }
        return $s -replace '\x1b\[[0-9;]*[mGKHF]', ''
    }

    # Build phases array
    $phases = @(
        foreach ($ph in $State.Phases) {
            # Items: empty array for single phases (or phases with no items yet)
            $items = @(
                foreach ($item in $ph.Items) {
                    [ordered]@{
                        name    = Remove-Ansi ($item.Name    ?? '')
                        status  = ($item.Status ?? 'pending').ToLower()
                        message = Remove-Ansi ($item.Message ?? '')
                    }
                }
            )

            [ordered]@{
                name   = Remove-Ansi ($ph.Name   ?? '')
                type   = ($ph.Type   ?? 'loop').ToLower()
                status = ($ph.Status ?? 'pending').ToLower()
                items  = $items
            }
        }
    )

    # Build issues array
    $issues = @(
        foreach ($issue in $State.Issues) {
            # log_tail: must be explicit null, not omitted
            $logTail = $null
            if ($issue.ContainsKey('LogTail') -and $null -ne $issue.LogTail) {
                $logTail = @($issue.LogTail | ForEach-Object { Remove-Ansi $_ })
            }

            # fix_command: explicit null when absent
            $fixCommand = $null
            if ($issue.ContainsKey('FixCommand') -and $null -ne $issue.FixCommand) {
                $fixCommand = Remove-Ansi $issue.FixCommand
            }

            [ordered]@{
                phase       = Remove-Ansi ($issue.Phase   ?? '')
                severity    = ($issue.Severity ?? 'info').ToLower()
                message     = Remove-Ansi ($issue.Message ?? '')
                fix_command = $fixCommand
                animal      = ($issue.Animal ?? 'owl').ToLower()
                log_tail    = $logTail
            }
        }
    )

    # Compute summary counts
    $phasesOk     = @($State.Phases | Where-Object { $_.Status -eq 'ok' }).Count
    $phasesFailed = @($State.Phases | Where-Object { $_.Status -in @('fail', 'failed') }).Count
    $warnings     = @($State.Issues | Where-Object { ($_.Severity ?? '') -eq 'warning' }).Count
    $failures     = @($State.Issues | Where-Object { ($_.Severity ?? '') -eq 'fail' }).Count

    $document = [ordered]@{
        version      = $version
        title        = Remove-Ansi ($State.Title    ?? '')
        subtitle     = Remove-Ansi ($State.Subtitle ?? '')
        started_at   = $startedAt
        completed_at = $completedAt
        exit_code    = [int]($State.ExitCode ?? 0)
        phases       = $phases
        issues       = $issues
        summary      = [ordered]@{
            phases_total  = $State.Phases.Count
            phases_ok     = $phasesOk
            phases_failed = $phasesFailed
            issues_total  = $State.Issues.Count
            warnings      = $warnings
            failures      = $failures
        }
    }

    return $document | ConvertTo-Json -Depth 10
}
