# guide

Reusable TUI framework for Fellwork CLI tools. Renders a structured dashboard
(phases on the left, active task and issues stacked on the right) with a Stardew
Valley "twilight" theme. Stays interactive after completion so users can press
`1`-`9` to copy fix commands.

Three execution modes:

- **TUI** (default) — alternate-screen-buffer dashboard with live updates
- **Headless** (`-Headless`) — emits JSON to stdout, no UI; for agents and CI
- **Streaming** (`-NoTui` or auto-detect non-TTY) — sequential `Write-Host` output

## Quick example

```powershell
Import-Module ./guide.psd1

$plan = New-GuidePlan -Title "My Tool" -Subtitle (Get-Date -Format HH:mm:ss)
$plan = Add-GuideLoopPhase -Plan $plan -Name "Cloning" -Items $repos -Action {
    param($r)
    git clone "https://github.com/fellwork/$r.git" 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        return New-GuideResult -Success $false -Message "$r failed" `
            -FixCommand "git clone https://github.com/fellwork/$r.git"
    }
    return New-GuideResult -Success $true -Message "$r cloned"
}

Invoke-GuidePlan -Plan $plan
```

## Design

See [the design spec](https://github.com/fellwork/bootstrap/blob/main/docs/superpowers/specs/2026-04-26-derekh-tui-design.md) in the bootstrap repo.

## Tests

```powershell
pwsh -NoProfile -File tests/run-all.ps1
```
