# Phase 8 test plan — Shell & IA restructure, in depth

Covers everything Phase 8 shipped (T-8.2 → T-8.11, PRs #150–#162): the
three-section IA, the toolbox-v2 Library, sources and approval folded in,
the whole-window drop target, the run inspector, the decomposed status
elements, the model switcher, and the multi-client MCP setup flow.

How to use this document: run the suites in order — each one stages state
the next can reuse. Every case has a checkbox; a case fails if **any**
expectation in it fails. File failures against the task that owns the
surface (noted per suite). The visual-law and geometry suites (10–11) are
cross-cutting: run them last, after you have seen every surface once.

---

## 0. Environment and staging harness

### Two builds, two purposes

- **Packaged app** (`make app` from `app/` → `app/build/gunk.app`): use for
  the end-to-end suites that need the real Keychain, the real engine, and
  Apple-events folder intake (Dock drops). This binary is signed, so
  Keychain probes do not raise consent dialogs.
- **Debug binary** (`swift build` → `app/.build/debug/GunkApp`): use for
  staged-state suites via the dev hooks below. **Always set
  `GUNK_DEBUG_NO_KEYCHAIN=1`** — an unsigned debug binary changes identity
  every rebuild and otherwise blocks its first window behind a Keychain
  consent dialog.

### Isolation — never test against your real data

| Variable | Effect |
| --- | --- |
| `GUNK_DB_PATH=<path>` | App opens a scratch SQLite store instead of `~/.gunk/store.db`. Copy your real store (`store.db`, `-wal`, `-shm`) to a temp dir for a populated Library. |
| `GUNK_MCP_CONFIG=<path>` | Overrides the Cursor MCP config path the status check reads — stage "Agent connected" (valid config with a `gunk` entry whose command contains `gunk-mcp`) vs "MCP not set up" (missing file). |
| `GUNK_DEBUG_MCP_HOME=<dir>` | Points the **entire** multi-client configurator (all five clients) at a fake home so wire/unwire tests never touch real configs. |
| `GUNK_ENGINE_BIN=<script>` | Replaces the engine with anything executable that emits the NDJSON event contract — use the fake engine below for deterministic processing states. |
| `GUNK_MCP_BIN=<path>` | Explicit `gunk-mcp` binary for the configurator (skips the install-path resolution). |

### Dev hooks (staged states without real interaction)

| Hook | Stages |
| --- | --- |
| `GUNK_DEBUG_SECTION=<library\|marketplace\|addModule\|settings>` | Land on a given section. |
| `GUNK_DEBUG_DROP_OVERLAY=<over\|ready\|error>` | The three drop-overlay states without a live drag. |
| `GUNK_DEBUG_RUN_INSPECTOR=<all\|failure\|source:<id>>` | Run inspector open at launch with that context. |
| `GUNK_DEBUG_TOAST=<success\|failure>` | The run-end toast without a run (no auto-dismiss timer, so captures don't race). |
| `GUNK_DEBUG_MODEL_MENU=1` | Model switcher menu open at launch. |
| `GUNK_DEBUG_KEYED_PROVIDERS=anthropic,openai` | Stages saved-key state for those providers (debug only). |
| `GUNK_DEBUG_NO_KEYCHAIN=1` | Forces the no-key state and skips the Keychain probe. |
| `GUNK_DEBUG_MCP_SETUP=1` | MCP setup sheet open at launch (pair with `GUNK_DEBUG_MCP_HOME`). |

### Fake engine for deterministic runs

Save as `/tmp/gunk-test/fake-engine.sh`, `chmod +x`:

```bash
#!/bin/bash
emit() { echo "{\"type\":\"progress\",\"stage\":\"refine\",\"fraction\":$1,\"modulesFound\":$2}"; }
emit 0.05 0; sleep 1
emit 0.20 2; sleep 1
emit 0.47 6
sleep 90   # hold here so the live-processing state can be inspected
echo '{"type":"result","runId":"fake-run","gunkIds":[],"accepted":0,"needsApproval":0,"rejected":0}'
```

For a **failed** run, swap the result line for:
`echo '{"type":"error","message":"staged failure for testing","stage":"refine"}'`
(and drop the `sleep 90` if you want the failure quickly).

Folder intake without drag-and-drop: the packaged app accepts folders via
the Dock icon or `open -a app/build/gunk.app <folder>`; both routes go
through the same handler as drops.

---

## 1. Automated baseline (run first, and again after any fix)

- [ ] **1.1** `cd app && swift build` — completes with no errors.
- [ ] **1.2** `swift test` — all tests green, zero failures. Suites that
      must be present (each guards a Phase 8 behavior):
      `RunCompletionSummaryTests`, `ShellRunToastTests`, `ModelCatalogTests`,
      `RunInspectorTests`, `MCPClientConfiguratorTests`, `MCPSetupModelTests`,
      `BrowseModelTests`.
- [ ] **1.3** `make app` from `app/` — bundle builds, `verify-app` passes
      (binary, engine, icon, plist lint, codesign all green).

---

## 2. Shell & IA (T-8.2)

- [ ] **2.1 Sections.** Sidebar shows exactly: Library, Marketplace,
      Add module, Settings. No Sources, Approval, or Runs tab anywhere.
- [ ] **2.2 Landing.** Cold launch lands on Library — both with an empty
      scratch store and a populated one.
- [ ] **2.3 Marketplace placeholder.** Branded empty state: "Marketplace —
      coming soon" + "Use other people's modules, and publish yours."
      Nothing else.
- [ ] **2.4 Add module.** Intentionally blank screen (design pending).
      Selecting it doesn't crash or render stray chrome.
- [ ] **2.5 Section title.** The toolbar shows the selected section's name;
      the window title stays "gunk" (sidebar wordmark reads gunk — no
      double-branding).
- [ ] **2.6 Library badge logic.** While a run is active, the Library row
      shows the pulsing processing dot; idle with a non-empty approval
      queue it shows the green count badge; idle with an empty queue it
      shows nothing. The dot **wins** over the count during a run.

## 3. Library grid & toolbox-v2 restyle (T-8.3b)

Stage: populated scratch store, default window size, dark appearance.

- [ ] **3.1 Appbar (one row).** `Library` title + plain muted count,
      `Project | Model` segmented, one search field (hairline border,
      capped width), trailing `provider · model ⌄` switcher. No filter UI,
      no Add button in the appbar.
- [ ] **3.2 Grouping.** `Project` buckets by source; `Model` re-buckets by
      extracting `provider · model` with gunks lacking a trace in an
      "Unknown model" bucket. Group headers: name left, `N capabilities`
      right.
- [ ] **3.3 Hero cell.** Each group promotes one module to a 2-column,
      taller hero (agent-ready first, then confidence desc, then name).
      A one-module group renders just the hero; no group ever crashes
      empty.
- [ ] **3.4 Cell anatomy.** One verdict per cell (`Agent-ready` green /
      `Needs approval` amber / `Not in toolbox` dimmed at ~50% opacity,
      restored on hover); provider-colored corner badge (coral Anthropic /
      teal OpenAI / indigo Google / neutral unknown); `via <model>`
      provenance; tag pills in system font. **No** confidence/containment
      readout on cells, **no** usage numbers anywhere.
- [ ] **3.5 Search.** Matches name + purpose + tags + project/folder name,
      case-insensitive; typing a folder name scopes the grid to that
      project; clearing restores the full grid. Focus survives the grid
      refreshing under it — a full word can be typed without the field
      dropping first responder after the first letter.
- [ ] **3.6 Selection vocabulary.** Selecting a cell draws the 2px green
      ring. The amber needs-approval top edge never competes with it —
      ring wins while present.

## 4. Sources folded into Library (T-8.3)

- [ ] **4.1 Sources panel.** Open via the folder glyph in the appbar's
      actions cluster. Rows show per-source status: processing progress,
      "N modules" (clicking closes the panel and applies that source
      filter), failed-with-error, and delete.
- [ ] **4.2 Delete confirmation.** Source delete asks first; copy reads
      "Removes the source from gunk. Its modules remain until you delete
      them." — and that is what actually happens (modules survive,
      verify in the grid).
- [ ] **4.3 Arrival highlight.** After a run completes, the newly created
      module cells carry the ~2s green highlight in the grid (same green
      ring vocabulary as selection), then decay.
- [ ] **4.4 View runs.** Each source row's "View runs" opens the run
      inspector pre-selected to that source's most recent run.

## 5. Approval folded into Library (T-8.4)

Stage: a store with at least one needs-approval module (run a low-confidence
extraction, or use a store snapshot that has one).

- [ ] **5.1 Cell treatment.** Needs-approval cells show the amber headline
      **plus** the 3px amber top edge, rounded with the card's top radius.
      Coral provider badges are unaffected (provenance ≠ approval).
- [ ] **5.2 Badge tap-through.** Clicking the sidebar Library count badge
      navigates to Library and applies the needs-approval scope; the amber
      "Needs approval (N) ×" chip appears in the appbar gap. Clicking ×
      clears the scope and the chip.
- [ ] **5.3 Review block.** Detail for a needs-approval module shows
      confidence with threshold context ("NN% — below the 70% auto-accept
      threshold") above the actions row, with Approve (primary) and
      Reject (destructive).
- [ ] **5.4 Approve feedback.** Approving animates the verdict to
      Agent-ready in place; selection stays on the module even if the
      active scope no longer matches it.
- [ ] **5.5 Reject confirms.** Reject opens a confirmation stating it
      permanently deletes the module ("This cannot be undone."); cancel
      leaves everything untouched; confirm removes the module.
- [ ] **5.6 Cleared queue.** Approving/rejecting the last queued module
      under the scope lands on "All caught up" (not the generic empty
      state) and the scope chip goes with it.
- [ ] **5.7 No one-click deletes.** Walk every surface: no destructive
      action anywhere fires without a confirmation.

## 6. Whole-window drop target (T-8.5)

- [ ] **6.1 Section-agnostic.** From **each** of the four sections, drag a
      folder from Finder over the window: the full-window overlay raises
      (dimmed scrim + centered glass card, "Drop folders to add them to
      your library"), and the drop is accepted.
- [ ] **6.2 Two drag states.** Drag-over shows the dashed border;
      drop-ready goes solid green with the "— let go" affordance.
- [ ] **6.3 Zero layout shift.** While the overlay is up, nothing beneath
      reflows, resizes, or scrolls — compare screenshots during/after.
- [ ] **6.4 Invalid drop.** Dropping a file (not a folder) shows "Only
      folders can be added." **inside** the overlay, which then dismisses
      on its own. No injected layout, no orphaned overlay.
- [ ] **6.5 Post-drop navigation.** A successful drop from any section
      lands you in Library (same as Dock drops).
- [ ] **6.6 No flicker.** Drag in and out of the window edge repeatedly —
      the overlay must not strobe (exit is debounced).
- [ ] **6.7 Add affordances without drag.** Empty Library: the content
      area is a click-or-drag zone with an Add folder button. Populated
      Library: intake still reachable without a drag gesture (empty-state
      button / Add module path). Both route through the same handler as
      drops.

## 7. Run inspector (T-8.6)

- [ ] **7.1 Entry points.** All three open the inspector: a sources-panel
      row's "View runs" (pre-filtered to that source), the module detail's
      "Last run" line, and the failure toast's Inspect (at the most recent
      failed run).
- [ ] **7.2 Opens on something.** Every context selects a run immediately —
      never an empty detail pane. With no matching run it falls back to
      the most recent.
- [ ] **7.3 Live refresh.** Open the inspector during a fake-engine run:
      traces refresh (~2.5s cadence) without reopening.
- [ ] **7.4 Human formatting.** Durations read as seconds ("83.2s", never
      "83214 ms"); timestamps carry a date only when the run wasn't today.
- [ ] **7.5 Failure diagnosable.** From a staged failed run: failure
      signal → Inspect → the failing stage's error text, in one path with
      no dead ends.

## 8. Status elements (T-8.7)

- [ ] **8.1 MCP chip — connected.** With a valid `GUNK_MCP_CONFIG`: green
      "Agent connected" pinned at the sidebar bottom. **Clicking it does
      nothing** — it is not a button. Hovering shows the config path as
      help text.
- [ ] **8.2 MCP chip — not set up.** With the config missing: amber "MCP
      not set up / Connect". Clicking opens the MCP setup sheet (T-8.10).
- [ ] **8.3 Processing element.** During a fake-engine run, a chip appears
      **above** the MCP chip: source name, linear progress bar, "NN% ·
      M found". Clicking lands in Library. The MCP chip stays visible
      beneath it — two independent elements.
- [ ] **8.4 Transient, not a toast.** When the run ends, the processing
      element disappears from the sidebar; it never lingers or converts.
- [ ] **8.5 Success toast.** On a successful run end that added ≥1 module, a
      glass toast floats bottom-center of the detail area: "N modules added ·
      M need review", a View button, and ×. The count is the **store diff**
      (the #154 regression sentinel: engine telemetry must never become the
      completion claim — a run whose live element showed "6 found" but
      persisted those modules reads its true added count).
- [ ] **8.5b No-modules toast.** A clean run that persisted **nothing** reads
      "Run finished — no new modules" with a neutral check icon and **no
      View button** (there is nothing new to view) — never "0 modules added"
      with a dead View action.
- [ ] **8.6 View action scope rule.** With M > 0, View lands in Library
      with the needs-approval scope applied (chip and all — same wiring as
      the badge). With M = 0 and a single project, View clears the scope and
      searches that project name so the run's additions are revealed. With
      M = 0 across multiple projects, View just lands in Library unscoped.
- [ ] **8.7 Failure toast.** On a failed run: "Run failed" with Inspect →
      run inspector at the most recent failure. No success numbers ever
      appear on a failure toast.
- [ ] **8.8 Toast lifecycle.** Auto-dismisses after ~8s; × dismisses
      immediately; a new run starting dismisses any visible toast. The
      entrance has the deliberate settle/spring feel — completion should
      read as feedback, not a vanishing chip (Mark's gut check).
- [ ] **8.9 Toast never shifts layout.** With a module selected (detail
      pane open) at the 960pt minimum window: the toast floats
      bottom-center and overlaps nothing in the detail's action row;
      content beneath never moves when it appears/disappears.

## 9. Model switcher (T-8.8)

- [ ] **9.1 Label.** Trailing appbar slot reads `provider · model ⌄`;
      switching models does **not** change the label's footprint or move
      the search field (middle-truncation, capped width).
- [ ] **9.2 Menu.** Only providers with a saved API key appear, as
      uppercase sections with two-line model rows and the accent check on
      the selected model. Ollama is absent by design. "Model settings…"
      routes to Settings.
- [ ] **9.3 No keys.** With no saved keys: the menu shows the
      add-a-key-in-Settings message plus "Model settings…" — no selectable
      models.
- [ ] **9.4 Custom model.** With Settings holding an off-catalog model id,
      the menu shows it as an extra "Custom · from Settings" row, selected.
- [ ] **9.5 Missing-key dot.** With the selected provider's key absent
      (and provider ≠ Ollama), the amber dot shows on the label and the
      help text points to Settings.
- [ ] **9.6 Storage contract.** Switch in the menu → Settings reflects it
      instantly; change in Settings → label reflects it. Same two keys,
      no drift.
- [ ] **9.7 Engine pickup (packaged app, real key).** Switch provider via
      the menu, run a folder: the run's trace records the newly selected
      provider/model.

## 10. MCP config writers + setup UI (T-8.9 / T-8.10)

Unit tests own idempotency/preservation per client (suite 1.2). Manual pass
covers integration. Stage with `GUNK_DEBUG_MCP_HOME=<fake home>` +
`GUNK_DEBUG_MCP_SETUP=1` first; finish with the real-Cursor case.

- [ ] **10.1 Setup sheet.** Lists detected clients (Cursor, Claude Code,
      Claude Desktop, Codex, OpenCode) with status — Connected / Not set
      up / Not detected — and the one-line payoff copy.
- [ ] **10.2 Connect.** Per-row Connect wires that client; status flips to
      Connected inline; errors render inline on the row, verbatim.
- [ ] **10.3 Connect all.** Appears only when 2+ detected clients are
      unwired; wires exactly those.
- [ ] **10.4 Routing.** The warning MCP chip opens this sheet (not
      Settings); the module detail's "MCP not set up" line routes here too.
- [ ] **10.5 Settings toggles.** Settings shows the per-client list with
      wire/unwire toggles; after any change, chip + sheet + Settings all
      agree without relaunching.
- [ ] **10.6 Preservation (fake home).** Pre-seed a config with an
      unrelated MCP server; wire, then unwire gunk: the unrelated entry
      survives byte-for-byte; double-wire produces identical bytes.
- [ ] **10.7 Malformed config.** Seed invalid JSON; Connect must abort
      with a clear error — never overwrite.
- [ ] **10.8 Real Cursor end-to-end (CP-C).** **Back up
      `~/.cursor/mcp.json` first.** One-click Connect in the packaged app,
      restart Cursor, ask the agent "What gunks do I have?" — it calls
      `list_gunks` against your library. Then unwire and confirm only the
      gunk entry was removed.

## 11. Visual law audit (toolbox-v2 — cross-cutting)

Walk every surface seen above and check:

- [ ] **11.1 Glass placement.** Glass only on the floating controls layer:
      sidebar, appbar, overlays, toast, sheets' chrome. Cards, rows, and
      content all solid. The sidebar chips (MCP, processing) are solid —
      they sit on the sidebar surface.
- [ ] **11.2 Green on meaning only.** Accent green appears only on:
      Agent-ready, success toast, connected chip, selection/arrival ring,
      approve-primary, the count badge, processing accents. Never on
      grouping toggles or neutral chrome.
- [ ] **11.3 Amber/red discipline.** Amber strictly needs-attention (chip
      warning, needs-approval, missing-key dot, scope chip); red strictly
      failure. Card top edges exist only in amber/red.
- [ ] **11.4 Type.** Mono only for paths/code; everything else system/brand
      sans with real hierarchy.
- [ ] **11.5 Surfaces.** Neutral graphite everywhere — no green-tinted
      backgrounds, borders, or pills anywhere in the shell.
- [ ] **11.6 No fabricated data.** No usage counts anywhere ("uses this
      week" stays a `// FUTURE` seam).

## 12. Geometry, appearance, accessibility

- [ ] **12.1 960×600 minimum.** Resize to minimum: appbar falls back to its
      two-row stack, hero reflows (never clips), sidebar never collapses,
      detail pane fits, toast clears the action row, no clipped controls
      on any section.
- [ ] **12.2 Default size.** Same walk at default size — no stretched or
      orphaned layouts.
- [ ] **12.3 Light appearance.** Flip to light mode and walk all sections:
      legible text ramp, visible separators, sensible accents. (Dark is
      primary; light must not be broken.)
- [ ] **12.4 Reduce Motion.** Enable system Reduce Motion: pulsing dot,
      toast spring, approve transition, and arrival highlight all render
      final frames without animating loops.
- [ ] **12.5 VoiceOver spot-check.** The MCP chip announces its state and
      config path; the toast announces its message; the processing element
      announces subject/percent/found; the count badge announces the
      review action; cells announce name + verdict.

## 13. Sign-off

- [ ] Suites 1–12 pass, or every failure is filed with its owning task.
- [ ] Mark's gut checks (the phase's human gates): drops feel section-less,
      review feels like a state not a room, the completion moment feels
      like feedback, one-click MCP setup works against real Cursor.

Found a failure? Note the suite/case id, the build (commit hash), whether
it was packaged or debug+hooks, and the staging env vars in effect —
hook-staged states and real states can differ, and the repro matters.
