# Design System — Guide

The visual source of truth for `tools/guide/`. Read this before touching any
CSS, HTML, or color/typography decision in `public/` or generated mockups.
If a code change deviates from this file, flag it.

## Product Context

- **What this is:** a localhost web dashboard plus embedded persistent shell.
  A long-lived Bun server renders plan-execution state in a sidebar and brokers
  `pwsh` and `bash` PTYs into an `xterm.js` pane. SQLite persists command
  history and plan-run snapshots.
- **Who it's for:** developers running `fellwork/bootstrap` and adjacent CLI
  tools that emit plan events. Single-user, single-machine, localhost only.
- **Space:** developer dashboards / build runners / embedded terminals.
  Visual peers: Warp, Hyper, Vercel CLI, Railway, Linear, GitHub Actions.
- **Project type:** developer dashboard with embedded terminal as a primary
  surface. Not a SaaS, not multi-user, not designed for browser tabs.

## Aesthetic Direction

- **Direction:** Refined editorial — *"evening study at a fine library."*
- **Decoration level:** Intentional. Subtle parchment grain on surfaces
  (1–2% SVG noise overlay), hairline rules between sidebar sections, no
  other ornament. Typography carries the rest.
- **Mood:** Ink and lamplight. Serif headings frame the dashboard as an
  instrument, not a console. The product takes itself seriously without
  becoming corporate.
- **Reframe:** the existing "Stardew Valley dusk" framing of the twilight
  palette is retired. Same hex anchors, new posture: classy, dignified,
  editorial. *Seriously* twilight, not whimsically.

## Typography

Three faces, each with one job. No additional fonts without explicit approval.

- **Display / section headers:** **Fraunces** (Google Fonts).
  Variable transitional serif. Use `opsz=14` and `soft=100` for chrome
  (sidebar headers, toast titles); `opsz=72` for any rare hero text.
  Why: warmth + authority, distinct from category-default sans.
- **UI text / sidebar items / prompt input:** **Inter Tight** (Google Fonts).
  Slightly tighter tracking than base Inter; reads sharper at 13px and gives
  a quieter modern foil to the serif.
  Why: legibility at small sizes without competing with Fraunces.
- **Mono / shell / data / code:** **JetBrains Mono** (free, vendored or
  Google Fonts). Tabular-nums on, ligatures on for code, off for shell prompt.
  Optional upgrade: **Berkeley Mono** if license budget allows.
  Why: terminal output expects a fixed-pitch face; JetBrains balances
  classy with accessible.

**Loading:** vendored as static assets in `public/` (offline-first). Google
Fonts CDN is the fallback if vendored files are missing.

**Scale (px):**

| Role | Size | Family | Weight | Tracking |
|---|---|---|---|---|
| Sidebar section header | 11 | Fraunces | 600 | +0.08em, all-caps |
| Sidebar item | 13 | Inter Tight | 450 | normal |
| Sidebar count chip | 10 | Inter Tight | 500 | +0.04em |
| Prompt input | 13 | Inter Tight | 450 | normal |
| Shell output | 13 | JetBrains Mono | 400 | normal, line-height 1.45 |
| Toast | 12 | Inter Tight | 500 | normal |
| Hero (rare) | 22 | Fraunces | 600 | normal |

## Color

Twilight evolved. Same anchors as the original palette; values refined for
dignity over cuteness. Color is sparse — most of the UI is ink + parchment +
lamplight. Saturation kicks in only for state.

```
--bg:        #16142a    /* deep ink, slightly cooler than the original */
--surface:   #251c3a    /* lifted plum — the "page" under the lamp */
--frame:     #9b7fc4    /* muted lavender for hairline rules */
--title:     #f4dca3    /* lantern gold — section headers + chrome */
--accent:    #f0a868    /* warm amber — active state, primary action */
--ok:        #7ed4a3    /* sage — phase ok, exit 0 */
--warn:      #f0a868    /* shares with accent — both warm */
--fail:      #e87878    /* coral — phase fail, exit nonzero */
--running:   #7ec0f0    /* cool blue — in-flight */
--pending:   #6a5878    /* dim plum — not started */
--dim:       #9888a8    /* secondary text, timestamps */
--text:      #ede4f5    /* primary text on --bg/--surface */
--chip-bg:   #382850    /* count chips, hover backgrounds */
```

**Semantic mapping:**
- `success` → `--ok`
- `warning` → `--warn`
- `error`   → `--fail`
- `info`    → `--running`

**Dark mode:** the palette above *is* the default dark mode. A light mode is
not v1. If/when added, redesign surfaces from scratch (don't auto-invert);
target a parchment background (#f6efe1), ink text (#1a1830), and reduce
saturation on accent + state colors by ~15%.

**Contrast targets:** AA minimum on body text (--text on --bg = 13.2:1, ok).
Hairline frame on surface is sub-AA by design (it's decoration, not text).

## Decoration

- **Parchment grain:** a tileable SVG noise overlay applied as a CSS
  `background-image` on `body` at 1.5% opacity, multiply blend mode. Source:
  generate via `<feTurbulence baseFrequency="0.9" numOctaves="2" />` in a
  256×256 SVG, vendor as `public/grain.svg`. Performance budget: <3kb.
- **Hairline rules between sidebar sections:** `1px solid var(--frame)`,
  `opacity: 0.3`. No other separators (no card shadows, no inset borders).
- **Blueprint dot grid behind xterm:** 1px dots, 24px spacing, 5% opacity in
  `--frame` color. Implemented as a CSS `radial-gradient` background on
  `#shell-pane`, sits behind the xterm canvas. Subtle enough to be felt,
  not seen.
- **No ornament beyond the above.** No icons in colored circles, no gradient
  buttons, no decorative blobs, no purple-gradient hero. The library
  metaphor is broken by anything cute.

## Spacing

- **Base unit:** 4px (so the 8px / 16px / 24px scale aligns to whole units).
- **Density:** comfortable. Lean toward editorial breathing room over
  dashboard data-density. The shell pane is dense by nature; the chrome
  around it should be quiet.
- **Scale:** `2xs=2  xs=4  sm=8  md=16  lg=24  xl=32  2xl=48  3xl=64`
- **Sidebar:** 240px wide. 8px padding. 16px gap between sections. 4px
  vertical / 8px horizontal padding on rows.
- **Prompt:** 6px vertical / 8px horizontal padding. Auto-grow up to 8 rows
  (capped via `max-height: 168px`), then internal scroll.
- **Toast:** 4px vertical / 12px horizontal, 4px corner radius.

## Layout

- **Approach:** hybrid grid. Strict columns for the dashboard chrome;
  editorial vertical rhythm inside the sidebar.
- **Grid:** CSS Grid. `grid-template-columns: 240px 1fr;
  grid-template-rows: 1fr auto;` — sidebar / main / full-width prompt.
  Defined in `public/style.css`. Do not change without a design review.
- **Max content width:** none. The dashboard fills the viewport; xterm
  expands to consume available width.
- **Border radius:** hierarchical, restrained.
  - `--radius-sm: 2px` — chips, count badges
  - `--radius-md: 4px` — buttons, toasts
  - `--radius-lg: 6px` — modal corners (none in v1)
  - No fully-rounded pills, no large radii. Editorial typography pairs with
    sharp/near-sharp corners; soft pills break the metaphor.

## Motion

- **Approach:** minimal-functional with one signature. The shell is an
  instrument. The chrome shouldn't dance.
- **Easing:** `enter: ease-out` `exit: ease-in` `move: ease-in-out`.
  No bouncy or elastic curves.
- **Duration:**
  - micro (50–100ms): hover state changes, button press feedback
  - short (150–250ms): phase status cross-fade, toast fade-up
  - medium (250–400ms): history row prepend slide+fade
  - long (400–700ms): reserved, none in v1
- **Signature animations:**
  - `phase-status-change`: 150ms ease-out cross-fade between glyph + color
  - `history-row-prepend`: 200ms slide-down (8px) + fade-in
  - `running-indicator`: 1s blink loop (already in the spec; keep)
  - `toast-show`: 150ms fade-up (8px) + opacity 0→1
- **What we explicitly don't do:** scroll-driven animation, parallax, hover
  zooms on cards, page-transition choreography, decorative loading spinners
  outside the shell.

## What this design system is *not*

- Not the Vercel/Geist look. We deliberately do not adopt Geist or any
  monospaced-influenced sans-serif as the UI face. That convergence is the
  thing we're avoiding.
- Not Stardew Valley. The original "twilight = dusk farm at the end of a
  workday" framing is retired. Same colors, dignified posture.
- Not a generic terminal theme. The palette and type are coherent only
  within the dashboard chrome. Don't ship the same hex values as a Warp
  theme or VS Code theme; the system depends on serif headings to land.
- Not data-dense. Comfortable density, editorial breathing room. If you're
  cramming six metric chips into a row, you're in the wrong system.

## AI slop anti-patterns (never include)

- Purple/violet gradients (we use solid plum surfaces; gradients break the
  library metaphor)
- 3-column feature-grid with icons in colored circles
- Centered everything with uniform spacing
- Uniform large border-radius (pill buttons, fully-rounded cards)
- Gradient CTAs as the primary action style
- Stock-photo-style hero sections
- "Built for X / Designed for Y" copy patterns
- Animated emoji or playful glyphs in the chrome (the spinner unicode is fine)

## Decisions Log

| Date | Decision | Rationale |
|---|---|---|
| 2026-04-29 | Initial design system created | Created via /design-consultation. Pivot from PowerShell TUI (twilight.json) to web dashboard; aesthetic reframed from "Stardew Valley dusk" to "evening study at a fine library." Same hex anchors, refined values, serif display added. |
| 2026-04-29 | Fraunces (serif) for section headers | Risk choice. Every dev tool defaults to sans; this product is named *guide* and benefits from an editorial posture. Documented as Risk #1 in the consultation. |
| 2026-04-29 | Twilight palette evolved, not replaced | The existing palette is already a category departure. Doubling down beats starting over. Hex values tightened for dignity (slightly cooler bg, less saturated frame). |
| 2026-04-29 | Parchment grain on surfaces | Risk choice. Adds 1.5% noise overlay to escape "flat dark." ~3kb cost; library metaphor doesn't survive without it. |
| 2026-04-29 | No light mode in v1 | Light mode requires a from-scratch palette redesign (don't auto-invert). Deferred. |
| 2026-04-29 | JetBrains Mono over Berkeley Mono | Free + classy + tabular-nums. Berkeley is the upgrade path if license budget appears. |

## Source spec

This design system materializes the Phase 5–6 sections of
[`bootstrap/docs/superpowers/specs/2026-04-29-guide-web-shell-design.md`](../../bootstrap/docs/superpowers/specs/2026-04-29-guide-web-shell-design.md)
(browser dashboard layout + History sidebar + standalone shell mode).
The implementation tasks live at
[`bootstrap/docs/superpowers/plans/2026-04-29-guide-web-shell.md`](../../bootstrap/docs/superpowers/plans/2026-04-29-guide-web-shell.md).
