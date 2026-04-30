# CLAUDE.md — tools/guide

Guidance for AI agents working in this directory.

## Design System

Always read [`DESIGN.md`](./DESIGN.md) before making any visual or UI decisions
in this project. All font choices, colors, spacing, border radii, motion
timing, and aesthetic direction are defined there. Do not deviate without
explicit user approval.

In QA / review mode, flag any code that doesn't match `DESIGN.md`:
- font-family / font-size / font-weight / letter-spacing in CSS that doesn't
  match the documented scale
- hex color literals in CSS or JS that aren't the documented CSS variables
- border-radius values outside `--radius-sm/md/lg`
- any of the AI-slop anti-patterns (purple gradients, pill CTAs, icon-in-circle
  feature grids, etc.)

## Architecture

This project is mid-pivot from a PowerShell TUI to a Bun + xterm.js web
dashboard. Authoritative references:

- Spec: [`bootstrap/docs/superpowers/specs/2026-04-29-guide-web-shell-design.md`](../../bootstrap/docs/superpowers/specs/2026-04-29-guide-web-shell-design.md)
- Plan: [`bootstrap/docs/superpowers/plans/2026-04-29-guide-web-shell.md`](../../bootstrap/docs/superpowers/plans/2026-04-29-guide-web-shell.md)

Until the plan completes, both surfaces coexist:
- `tools/guide/ps/` — PowerShell event emitter (post-cutover responsibilities only)
- `tools/guide/server.ts`, `tools/guide/lib/`, `tools/guide/public/` — new web
  dashboard (built phase by phase per the plan)

Do not introduce a third rendering path.

## Conventions

- TypeScript strict mode (`noUncheckedIndexedAccess: true`)
- No bundler. `public/` is served as static assets directly by `Bun.serve`.
- DOM mutations use `document.createElement` + `textContent`. Never set
  `innerHTML` with user-derived strings; never set `innerHTML` even with
  literals where `createElement` works (XSS-safety by construction).
- Prefer `bun:sqlite` over external SQLite drivers.
- Tests use `bun test` (server / browser / e2e) and `pwsh tests/ps/run-all.ps1`
  (PS unit). Each task in the plan is TDD: failing test first, then minimal
  implementation, then commit.

## Localhost-only

The Bun server binds to `127.0.0.1`. Never introduce a flag or code path that
binds to `0.0.0.0` or any external interface. Multi-user access is out of
scope; same-user trust is the security boundary.
