# fellwork/tools

Shared CLI tooling for Fellwork. Each subdirectory is a self-contained PowerShell module
that other Fellwork repos can `Import-Module` from.

## Tools

- **[guide/](guide/)** — TUI framework for Fellwork CLI tools. Provides a Stardew-themed
  dashboard, headless JSON mode for agents/CI, and a streaming fallback for non-TTY
  environments. First consumer: `fellwork/bootstrap`.

## Usage from a sibling Fellwork repo

This repo is intended to clone as a sibling under your Fellwork workspace:

```
some-dir/
├── api/
├── web/
├── ops/
├── tools/        ← this repo
└── bootstrap/    ← consumer
```

Consumer scripts import via the relative sibling path:

```powershell
Import-Module "$PSScriptRoot/../tools/guide/guide.psd1"
```

## Adding a new tool

Each tool is a folder containing a PowerShell module (`.psd1` + `.psm1`) plus its own
`tests/`. See `guide/` for the canonical layout.

## Tests

Each tool has its own `tests/run-all.ps1`. To run all tools' tests at once:

```powershell
Get-ChildItem -Directory | ForEach-Object {
    $runner = "$($_.FullName)/tests/run-all.ps1"
    if (Test-Path $runner) { pwsh -NoProfile -File $runner }
}
```
