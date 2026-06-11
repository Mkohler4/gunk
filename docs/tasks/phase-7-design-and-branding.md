# Phase 7 — Design and branding (Liquid Glass rebrand)

This phase turns `gunk.app` from a functional-but-plain SwiftUI app into a
polished, branded, professional macOS application using a **Liquid Glass**
aesthetic. It is a UI/asset layer only: no store, MCP, schema, or engine changes,
so the Phase 5 eval floor and schema-parity checks must stay untouched.

## How to read this document

This file is written to be executed by an AI agent (Codex) **with a human ("me")
in the loop at every step**. Each task is structured the same way:

- **Task execution (Codex prompt):** the literal instruction block Codex should
  follow. Treat the indented prompt as the task brief.
- **Refining loop:** the iterate-until-good cycle. Design is never one-shot;
  Codex produces a variant, captures a screenshot, and refines.
- **Human-in-the-loop (me):** what the human must review, decide, or provide
  before the task is considered done. **Codex must stop and wait at every
  `[HOLD FOR ME]` gate.**
- **Acceptance:** the objective done criteria.

### Working agreement for Codex 

1. Do exactly one task at a time, in order, unless I say otherwise.
2. After any visible change, build the app and capture a screenshot of the
   affected surface. Paste it inline in your summary so I can react.
3. Never proceed past a `[HOLD FOR ME]` gate without my explicit "approved" /
   "go".
4. Never invent brand values (hex codes, fonts, logo art). Where I have not
   provided them yet, scaffold a clearly-marked placeholder (e.g.
   `// BRAND-PLACEHOLDER: replace with approved value`) and surface it at the
   next human gate.
5. Keep each task PR-sized and reversible. One task = one focused change set.
6. Do not touch `Store/`, `Schema.swift`, `engine/`, or `mcp/`. If a task seems
   to require it, stop and ask.

## Decisions locked in

- Visual direction: iOS/macOS **Liquid Glass** — translucency, depth, blur,
  layered surfaces, soft shadows.
- Platform: **raise minimum to macOS 26** to use real `glassEffect` / material
  APIs.
- Brand assets: I have a **logo** and a **color palette**. I will describe
  **typography and layout verbally** as we go. Codex scaffolds placeholders I
  replace.

## Constraints (carried from Phase 6)

- `gunk.app` is a regular Dock/window app first; the menubar item is secondary.
- The Dock recycling-bin drop target remains a core gesture and must keep
  working visually and functionally.
- No filesystem watching, no Full Disk Access.

## Risks and prerequisites

- **Runtime visibility:** real Liquid Glass renders on macOS 26 only. Building
  against the macOS 26 SDK requires the Xcode 26 toolchain. On macOS 15, the
  adaptive fallback (`.ultraThinMaterial` / `NSVisualEffectView`) must still look
  intentional so development is not blocked.
- **No regressions:** existing XCTest suite must stay green; schema-parity script
  must still pass.

---

## Checkpoint map (where the human is required)

| Gate | What I review | Blocks |
| --- | --- | --- |
| CP1 | Brand tokens: palette hex values, typography scale, spacing/radius, brand mark, motion | T-7.2 |
| CP2 | Component gallery: every primitive on one screen | T-7.5+ |
| CP2.5 | UX architecture: what shows up where (landing, navigation, status, placement rules) | all CP3 re-skin tasks |
| CP3 | Per-surface re-skin (structure + skin per the approved UX architecture), screenshot-by-screenshot | each re-skin task |
| CP4 | Packaged `.app`: icon, window chrome, first-run feel | T-7.9 |

---

## T-7.1 — Platform bump to macOS 26

**Status:** Done — built with Xcode 26.5 (macOS 26.5 SDK, Swift 6.3.2).
`swift-tools-version` is 6.2 with `swiftLanguageModes: [.v5]` so the platform
bump does not also force the Swift 6 strict-concurrency migration. The real
`glassEffect` path in `GlassMaterial` (T-7.2) now compiles; note that
offscreen `ImageRenderer` cannot composite Liquid Glass, so its visual check
happens in a real window at the CP2 component gallery.
**Owner:** Codex
**Checkpoint:** none (mechanical)

### Goal
Make the project build against the macOS 26 SDK so real Liquid Glass APIs are
available.

### Files
- `app/Package.swift`
- `app/Makefile`

### Task execution (Codex prompt)

> Raise the deployment target of the Swift package to macOS 26.
> 1. In `app/Package.swift`, change `.macOS(.v14)` to `.macOS(.v26)` and bump
>    `swift-tools-version` to the value required by the Xcode 26 toolchain.
> 2. In `app/Makefile`, change the `LSMinimumSystemVersion` value from `14.0` to
>    `26.0`.
> 3. Run `swift build` and confirm a clean build. If the toolchain is missing,
>    stop and report exactly what is missing.
> 4. Run `swift test` and confirm the suite still passes.

### Refining loop
- If the build fails only due to the platform bump (not design code), fix
  forward minimally; do not start design work in this task.

### Human-in-the-loop (me)
- `[HOLD FOR ME]` Confirm I have Xcode 26 installed before this task starts.
- I confirm the build/test output looks clean.

### Acceptance
- `swift build` and `swift test` pass with `.macOS(.v26)`.
- `LSMinimumSystemVersion` is `26.0`.

---

## T-7.2 — Brand and design-system foundation (CP1)

**Status:** In review — implemented from the approved Ooze concept boards
(palette, type faces, mark geometry, and motion spec); awaiting CP1 sign-off.
**Owner:** Codex
**Checkpoint:** CP1

### Goal
Create the single source of truth for the brand: colors, typography, spacing,
radii, the adaptive glass material, the brand mark, and motion. Nothing else
should hardcode design values after this.

### Files
- `app/Sources/GunkApp/Design/BrandColors.swift` (new)
- `app/Sources/GunkApp/Design/BrandTypography.swift` (new)
- `app/Sources/GunkApp/Design/BrandMetrics.swift` (new)
- `app/Sources/GunkApp/Design/GlassMaterial.swift` (new)
- `app/Sources/GunkApp/Design/BrandMotion.swift` (new)
- `app/Sources/GunkApp/Design/BrandMark.swift` (new)
- `app/Sources/GunkApp/Resources/Assets.xcassets/` (new color sets + brand mark asset)

### Task execution (Codex prompt)

> Create a `Design/` foundation module. Do not change any existing view yet.
> 1. `BrandColors`: semantic tokens only (not raw colors), e.g.
>    `backgroundPrimary`, `backgroundElevated`, `surfaceGlass`, `accent`,
>    `accentSecondary`, `textPrimary`, `textSecondary`, `textTertiary`,
>    `success`, `warning`, `danger`, `separator`. Back each with a named color
>    set in `Assets.xcassets` that has both Light and Dark appearances. Until I
>    approve hex values, use `// BRAND-PLACEHOLDER` neutral values and list every
>    placeholder in your summary.
> 2. `BrandTypography`: a named scale (`display`, `title`, `headline`, `body`,
>    `callout`, `caption`, `mono`) returning `Font` values. Map to a brand font
>    with a system fallback; placeholder = system font until I name the font.
> 3. `BrandMetrics`: spacing scale (`xs`, `sm`, `md`, `lg`, `xl`), corner radii
>    (`small`, `medium`, `large`, `pill`), and glass constants (tint opacity,
>    blur thickness, shadow).
> 4. `GlassMaterial`: an adaptive `ViewModifier`/helper that applies real
>    `glassEffect` on macOS 26 and falls back to `.ultraThinMaterial` /
>    `NSVisualEffectView` on older systems via `if #available(macOS 26, *)`.
> 5. `BrandMotion`: named animation tokens (durations, easing/spring curves,
>    delays) so motion is centralized like color and type. Nothing downstream
>    should hardcode `Animation`/`withAnimation` values after this.
> 6. `BrandMark`: the reusable brand glyph/mark as a SwiftUI view, backed by the
>    brand mark asset in `Assets.xcassets`, sized from `BrandMetrics` and driven
>    by `BrandMotion` for its idle/loading animation. This is the shared source
>    the app icon (T-7.5), wordmark, launch view, and loading/empty states all
>    build on. Until I deliver the real mark, use a `// BRAND-PLACEHOLDER`.
> 7. Add `#Preview`s showing the palette swatches, type scale, the brand mark
>    (static + animated), and the motion tokens.

### Refining loop
1. Build, screenshot the palette + type-scale previews.
2. I react to the placeholders; you encode my real values.
3. Repeat until I approve the token values.

### Human-in-the-loop (me)
- `[HOLD FOR ME] CP1` — I provide:
  - The palette hex values (light + dark) for each semantic token.
  - The typography choices (font family, weights, sizes per scale step).
  - Spacing/radius preferences (or accept your defaults).
  - The brand mark source files and the animation spec (timing, easing, what
    moves).
- I approve the rendered swatches, type scale, brand mark, and motion before any
  surface uses them.

### Acceptance
- All design values live in `Design/`; no view hardcodes colors/fonts/spacing/
  animation.
- Color sets have Light + Dark variants.
- Previews render swatches, the full type scale, the brand mark, and motion.
- `BrandMark` and `BrandMotion` exist and are the shared source for downstream
  icon/wordmark/launch/loading surfaces.
- I have signed off on CP1.

---

## T-7.3 — Liquid Glass component library

**Status:** In review — all seven components built on the T-7.2 `Design/`
tokens (plus new `BrandMetrics.Control` tokens for hover/press/tinted-fill
states), each with light + dark previews; no existing view touched. Offscreen
`ImageRenderer` cannot composite the real `glassEffect`, so the glass look of
`GlassCard`/`GlassSidebar` is verified live at CP2.
**Owner:** Codex
**Checkpoint:** none yet (reviewed in CP2)

### Goal
Build the reusable components every screen will use, replacing today's inline,
duplicated capsule/pill code.

### Files
- `app/Sources/GunkApp/Design/Components/GlassCard.swift` (new)
- `app/Sources/GunkApp/Design/Components/GlassSidebar.swift` (new)
- `app/Sources/GunkApp/Design/Components/BrandButton.swift` (new)
- `app/Sources/GunkApp/Design/Components/TagChip.swift` (new)
- `app/Sources/GunkApp/Design/Components/StatusBadge.swift` (new)
- `app/Sources/GunkApp/Design/Components/SectionHeader.swift` (new)
- `app/Sources/GunkApp/Design/Components/EmptyStateView.swift` (new)

### Task execution (Codex prompt)

> Build reusable SwiftUI components on top of the `Design/` tokens. Each must use
> only `BrandColors`/`BrandTypography`/`BrandMetrics`/`GlassMaterial` — no
> hardcoded values.
> 1. `GlassCard`: a glass container with configurable padding/elevation.
> 2. `GlassSidebar`: the navigation container shell (used later by the app
>    shell).
> 3. `BrandButton`: primary / secondary / destructive / icon styles.
> 4. `TagChip`: replaces the inline capsule in `BrowseView.swift`'s `tagRow`.
> 5. `StatusBadge`: replaces the inline status capsule in `BrowseView.swift`'s
>    `statusRow`/`pill` (success/warn/danger/neutral variants).
> 6. `SectionHeader`: replaces `DetailSectionHeader`.
> 7. `EmptyStateView`: a branded replacement for `ContentUnavailableView`.
> 8. Add a `#Preview` for every component in light and dark.

### Refining loop
1. Build, screenshot each component preview.
2. I react; you adjust radii, glass tint, shadow, padding, weights.
3. Repeat per component until each feels "professional."

### Human-in-the-loop (me)
- I review component previews as you produce them and request specific tweaks.

### Acceptance
- All listed components exist and compile with previews (light + dark).
- No component hardcodes design values.

---

## T-7.4 — Component gallery (CP2)

**Status:** Done — CP2 signed off. `ComponentGalleryView` renders every token
and component on one scrollable glass screen, gated behind
`GUNK_DESIGN_GALLERY=1` (env-flag Debug menu + auto-open; an `#if DEBUG`
gate would still ship because `make app` builds the debug configuration).
Full-window screenshots captured live in light + dark (real `glassEffect`
composites verified). The design system is frozen; changes now go through
the gallery refining loop.
**Owner:** Codex
**Checkpoint:** CP2

### Goal
Give me one screen to review the entire system at a glance before any real
screen is touched.

### Files
- `app/Sources/GunkApp/Design/ComponentGalleryView.swift` (new)
- a temporary dev entry point to open it (gated, not shipped)

### Task execution (Codex prompt)

> Create `ComponentGalleryView` that renders every token and component on a
> single scrollable, glass-backed screen: palette swatches, type scale, all
> button styles, chips, badges, cards, empty states, and a sample glass sidebar.
> Wire a dev-only way to open it (e.g. a hidden menu item or debug flag) so it is
> not part of the shipping UI. Build and capture full-window screenshots in light
> and dark mode.

### Refining loop
1. Screenshot the gallery (light + dark).
2. I do a holistic pass: "this badge is too heavy", "tighten card padding",
   "accent is too saturated", etc.
3. You apply changes to the tokens/components (not the gallery) and re-screenshot.
4. Repeat until I approve the system as a whole.

### Human-in-the-loop (me)
- `[HOLD FOR ME] CP2` — I must approve the full gallery before any surface
  re-skin (T-7.5 onward) begins. This is the design-system freeze gate.

### Acceptance
- Gallery shows every token + component, light and dark.
- I have signed off on CP2.

---

## T-7.4b — Product UX pass: information architecture and placement (CP2.5)

**Status:** Not started
**Owner:** Codex (decisions: me)
**Checkpoint:** CP2.5 — blocks all CP3 re-skin tasks

### Goal
Decide what shows up where — landing logic, navigation hierarchy, status and
feedback placement, primary actions, and state patterns — before any surface
is re-skinned, so CP3 tasks implement structure and skin together. Basic UX
only: no onboarding flow, no engine/store/MCP behavior changes.

### Files
- `docs/design/ux-architecture.md` (new — wireframe-level, no code)

### Task execution (Codex prompt)

> 1. Audit the running app: inventory every surface, every piece of
>    information and action on it, and where it currently lives. Include the
>    menubar item, Dock bin, and window chrome.
> 2. Walk the core journey end-to-end (drop folder → processing → browse →
>    approve → consume via MCP) and list every dead-end, invisible state, and
>    "why am I here" moment.
> 3. Propose, per surface: purpose, primary action, content hierarchy,
>    empty/loading/error state placement, and what navigates here when.
> 4. Propose cross-cutting rules: default/landing section (first-run vs
>    returning), sidebar order/grouping/badges (approval count, processing
>    indicator), global status placement (processing, cost), drop-gesture
>    feedback (what the window does when the Dock bin is fed), window sizing.
> 5. Write it all into `docs/design/ux-architecture.md` with text/ASCII
>    wireframes. No code changes in this task.

### Refining loop
1. I react to the audit + proposals surface-by-surface.
2. You revise the doc until placements feel right.

### Human-in-the-loop (me)
- `[HOLD FOR ME] CP2.5` — I approve the UX architecture doc. It becomes the
  contract every CP3 re-skin task implements alongside the visual system.

### Acceptance
- `ux-architecture.md` covers every surface + cross-cutting rules.
- T-7.6–T-7.9 are amended to reference it (structure + skin, not visual-only).
- I have signed off on CP2.5.

---

## T-7.5 — App icon and brand identity

**Status:** Not started
**Owner:** Codex
**Checkpoint:** CP1 values, CP4 final

### Goal
Apply the logo to the app icon, sidebar header, and launch screen.

### Files
- `app/Sources/GunkApp/Resources/Assets.xcassets/AppIcon.appiconset/` (new)
- `app/AppIcon.icns`
- `app/Sources/GunkApp/Design/Components/BrandWordmark.swift` (new)

### Task execution (Codex prompt)

> 1. Add a complete `AppIcon` set to `Assets.xcassets` and regenerate
>    `app/AppIcon.icns`, rendered from the `BrandMark` defined in T-7.2 (do not
>    invent a new mark here). The icon is the static, export-sized form of that
>    mark.
> 2. Create `BrandWordmark` (`BrandMark` + "gunk" lockup) for the sidebar header
>    and launch view, sized from `BrandMetrics`. Use `BrandMotion` where the
>    wordmark/mark animates (e.g. launch reveal).
> 3. Build the app and screenshot the Dock icon and the wordmark in context.

### Refining loop
1. I drop the real logo files into the repo; you wire them into the icon set and
   wordmark.
2. Screenshot Dock icon at multiple sizes + sidebar header; refine padding/scale.
3. Repeat until the mark reads cleanly at 16px and 1024px.

### Human-in-the-loop (me)
- `[HOLD FOR ME]` I deliver the logo source files (and tell you the lockup
  rules: spacing, min size, mono vs. color).
- I approve the icon and wordmark rendering.

### Acceptance
- App icon renders at all required sizes; `AppIcon.icns` rebuilt.
- `BrandWordmark` used by the shell and launch view.

---

## T-7.6 — Re-skin: app shell, sidebar, toolbar (CP3)

**Status:** Not started
**Owner:** Codex
**Checkpoint:** CP3

### Goal
Make the primary window frame feel like a designed Liquid Glass app.

### Files
- `app/Sources/GunkApp/Views/AppShellView.swift`
- `app/Sources/GunkApp/MainWindowController.swift`

### Task execution (Codex prompt)

> Re-skin `AppShellView` using the approved components, implementing the
> approved `docs/design/ux-architecture.md` decisions for the shell (landing
> section, sidebar order/grouping/badges, global status placement).
> 1. Replace the default sidebar `List` with the glass sidebar treatment
>    (`GlassSidebar` + branded row styling) and put `BrandWordmark` in the
>    sidebar header.
> 2. Apply a unified, glass toolbar; align with macOS 26 conventions.
> 3. Apply `backgroundPrimary` and glass layering to the detail container.
> 4. Structural changes only where `ux-architecture.md` calls for them; no
>    engine/store behavior changes.
> 5. Build and capture full-window screenshots, each section selected, light +
>    dark.

### Refining loop
1. Screenshot shell with each section selected.
2. I react to sidebar width, row spacing, selection highlight, toolbar density,
   window min-size.
3. Repeat until approved.

### Human-in-the-loop (me)
- `[HOLD FOR ME] CP3` per surface — I approve the shell before moving on.

### Acceptance
- Shell uses brand components throughout; navigation unchanged.
- Light + dark both approved.

---

## T-7.7 — Re-skin: Sources and drop zone (CP3)

**Status:** Not started
**Owner:** Codex
**Checkpoint:** CP3

### Goal
Make adding sources feel like the signature gesture of a premium app.

### Files
- `app/Sources/GunkApp/Views/DropZoneView.swift`
- `app/Sources/GunkApp/Views/GunkListView.swift`
- the `SourcesSectionView` in `app/Sources/GunkApp/Views/AppShellView.swift`

### Task execution (Codex prompt)

> Implement the approved `docs/design/ux-architecture.md` decisions for this
> surface (incl. the drop-gesture feedback loop) alongside the re-skin.
> 1. Rebuild the drop zone as a `BrandDropZone` (glass surface, branded
>    targeted/idle states, animated highlight) — keep the existing `onDrop`
>    handler and `DropZoneHandler` logic untouched.
> 2. Re-skin the source list rows using `GlassCard`/`TagChip`/`StatusBadge`,
>    showing per-source processing state cleanly.
> 3. Re-skin the processing/error status area.
> 4. Build and screenshot idle, drag-targeted, processing, and error states.

### Refining loop
1. Screenshot each of the four states.
2. I react to the drag affordance, animation, empty state copy/visuals.
3. Repeat until approved.

### Human-in-the-loop (me)
- `[HOLD FOR ME] CP3` — approve Sources before moving on. Confirm the drop
  gesture still works end-to-end with a real folder.

### Acceptance
- Drop zone + source list re-skinned; drop behavior verified working.
- All four states approved, light + dark.

---

## T-7.8 — Re-skin: Modules browser and detail (CP3)

**Status:** Not started
**Owner:** Codex
**Checkpoint:** CP3

### Goal
Make the modules browser — the product's core object view — look first-class.

### Files
- `app/Sources/GunkApp/Views/BrowseView.swift`

### Task execution (Codex prompt)

> Re-skin `BrowseView` and its `ModuleDetailView` using brand components only,
> implementing the approved `docs/design/ux-architecture.md` decisions for the
> browser (hierarchy, primary action, empty/detail placement).
> 1. Replace inline capsules (`tagRow`, `pill`, `statusRow`) with `TagChip` and
>    `StatusBadge`.
> 2. Wrap module rows and detail sections in `GlassCard`; restyle the filter bar
>    (group/source/tag/language/approval pickers) to match.
> 3. Replace `ContentUnavailableView` usages with `EmptyStateView`.
> 4. Restyle the runability section so "self-contained for AI reuse" vs.
>    "standalone runnable" reads clearly with branded status badges.
> 5. Keep all `BrowseModel` bindings intact; structural changes only where
>    `ux-architecture.md` calls for them.
> 6. Build and screenshot: empty, list-with-modules, and detail-selected, light +
>    dark.

### Refining loop
1. Screenshot each state.
2. I react to row density, chip wrapping, detail hierarchy, confidence display.
3. Repeat until approved.

### Human-in-the-loop (me)
- `[HOLD FOR ME] CP3` — approve Modules before moving on.

### Acceptance
- Browser + detail re-skinned, no inline design values remain.
- All states approved, light + dark.

---

## T-7.9 — Re-skin: Approval, Runs, Settings, launch/error (CP3 + CP4)

**Status:** Not started
**Owner:** Codex
**Checkpoint:** CP3 per surface, CP4 final

### Goal
Bring the remaining surfaces up to the same standard and ship a packaged app.

### Files
- `app/Sources/GunkApp/Views/ApprovalQueueView.swift`
- `app/Sources/GunkApp/Views/RunsView.swift`
- `app/Sources/GunkApp/Views/SettingsView.swift`
- the launch/error views in `app/Sources/GunkApp/Views/AppShellView.swift`
  (`AppLaunchView`)

### Task execution (Codex prompt)

> Re-skin each remaining surface with brand components, implementing the
> approved `docs/design/ux-architecture.md` decisions per surface (behavior
> intact; structural changes only where the UX doc calls for them):
> 1. Approval queue: branded cards, `StatusBadge` for confidence, `BrandButton`
>    for approve/reject.
> 2. Runs: branded list/timeline using cards and badges.
> 3. Settings: re-skin the `Form`, provider picker, key field, slider, and
>    status messaging into a branded layout.
> 4. Launch failure + empty states: use `EmptyStateView` / `BrandWordmark`.
> 5. Run `make app`, launch `build/gunk.app`, and capture the Dock icon, launch,
>    and each section.

### Refining loop
1. Screenshot each surface; iterate per my notes.
2. Final holistic pass on the packaged app: window chrome, sizing, traffic-light
   alignment, first-run feel.

### Human-in-the-loop (me)
- `[HOLD FOR ME] CP3` for each of Approval / Runs / Settings.
- `[HOLD FOR ME] CP4` — I review the built `.app` as a whole and sign off on the
  rebrand.

### Acceptance
- All surfaces re-skinned; `make app` produces a runnable, branded `.app`.
- I have signed off on CP4.

---

## T-7.10 — Docs and ADR

**Status:** Not started
**Owner:** Codex
**Checkpoint:** none (review with CP4)

### Goal
Record the design system and the platform decision so they are not lost.

### Files
- `docs/adr/0016-design-system-and-macos-26.md` (new)
- `app/README.md`
- `docs/roadmap.md`

### Task execution (Codex prompt)

> 1. Write ADR-0016 capturing: the macOS 26 bump and why, the Liquid Glass
>    direction, the `Design/` token + component architecture, and the
>    adaptive-fallback decision. Match the existing ADR format.
> 2. Update `app/README.md` with a "Design system" section pointing at `Design/`
>    and the component gallery.
> 3. Update `docs/roadmap.md` to reflect that the design phase exists and its
>    status.

### Refining loop
- I review the ADR wording for accuracy.

### Human-in-the-loop (me)
- I approve the ADR and doc updates.

### Acceptance
- ADR-0016 merged; README + roadmap updated.

---

## Definition of done for Phase 7

1. Code is on `main`, CI green, XCTest suite passing.
2. Schema-parity check still passes (no store/MCP/schema changes).
3. `make app` produces a branded, runnable `.app`.
4. Every surface uses the `Design/` system; no hardcoded design values remain.
5. I have signed off on CP1, CP2, CP2.5, all CP3 surfaces, and CP4.
6. ADR-0016 documents the decisions.
