# 06 — Settings page

Source file: `Views/SettingsView.swift` (plus `Models/MCPStatusProvider.swift`)

> Mostly **not re-skinned**: a standard grouped `Form` fixed at **520 pt
> wide**, left-aligned in the detail pane (not centered), with system
> fonts. Functionally it is the most complete page in the app — it is the
> only place the full pipeline health is visible.

## Purpose

Configure the LLM provider used for decomposition, and verify the whole
pipeline (provider → key → store → engine → MCP) is healthy.

## Layout

A grouped form with two sections:

```
+--------------------- 520 pt form ----------------------+
| PROVIDER                                                |
|   Provider        [ OpenAI / Anthropic / Ollama ▾ ]     |
|   Model           [ text field                    ]     |
|   API key         [ secure field  ]  (hidden for Ollama)|
|   [––––––●––––––]  ← UNLABELED slider                   |
|   0.70             ← bare number caption                |
|   [Save] [Test connection]                              |
|   (status message caption)                              |
|                                                         |
| STATUS                                                  |
|   ✓ Provider / model   ...        Ready                 |
|   ✓ API key            ...        Ready                 |
|   ✓ Local store        ...        Ready                 |
|   ✓ Engine binary      ...        Ready                 |
|   ⚠ MCP config         ...        Needs setup           |
|   [Refresh status]                                      |
+---------------------------------------------------------+
```

## Feature inventory

### Provider section

- **Provider picker:** OpenAI / Anthropic / Ollama. Changing provider
  resets the model field to that provider's default model and loads that
  provider's saved API key from Keychain.
- **Model text field:** free-text model name. Persisted via `@AppStorage`
  (`llm.model`); changing it re-runs the status checks live.
- **API key secure field:** hidden entirely when Ollama is selected (local,
  no key needed). Saved to the **macOS Keychain** (never SQLite) per
  provider.
- **The slider (unlabeled):** range 0–1, step 0.05, with only a bare number
  caption under it (e.g. "0.70"). It is actually the **auto-accept
  confidence threshold** — modules at/above it are auto-accepted and
  extracted; below it they go to the Approval queue. **Nothing on screen
  says any of that.** Persisted as `llm.confidenceThreshold`.
- **Save button:** writes the API key to Keychain, shows "Saved" (or the
  error) as a caption, refreshes status.
- **Test connection button:** saves first, then performs a real one-shot
  structured-output request against the selected provider ("Return
  {\"ok\": true}", max 64 tokens). Button label flips to "Testing…" and
  disables while in flight. Result: "Connection ok" or the error message,
  inline caption.

### Status section (pipeline health)

Five status rows, each with a state icon/color (green check = Ready, orange
triangle = Needs setup, red x = Unavailable), a title, a monospaced value
(selectable, middle-truncated), and a guidance message:

| Row | Ready when | Guidance examples |
| --- | --- | --- |
| **Provider / model** | a model name is set | "Choose a model before dropping a source." |
| **API key** | key in Keychain (or Ollama) | "Save a {provider} API key before processing sources…" / "Stored locally in Keychain, not in SQLite." |
| **Local store** | on-disk SQLite path exists | shows the DB path; "The app, engine, and MCP server share this SQLite database." |
| **Engine binary** | engine binary (or dev runner) resolves | shows the resolved path; "Build the app with `make app`, or set GUNK_ENGINE_BIN…" |
| **MCP config** | gunk-mcp is present in the MCP config file | This row is the **only full MCP setup guidance in the app**; the shell's status strip and the Modules "MCP not set up" affordances all route here. |

- **Refresh status button** re-runs all five checks. Checks also re-run on
  appear, on save/test, and on model/provider changes.

## States

- No empty state (the form always renders). Errors surface inline as the
  status message caption and as red/orange status rows.

## Known problems & quirks

1. **The unlabeled slider is the page's headline confusion.** The single
   number that decides what lands in Approval has no label, no helper text,
   and no link to the Approval concept. (The ux-architecture doc flagged
   this as D14 and it was *not* fixed in phase 7.)
2. **Known bug B1 (open, verified in code):** the engine honors this
   slider when processing, but the in-app Approval queue and its sidebar
   badge are computed against a hard-coded 0.7 — move the slider and the
   UI's idea of "needs review" diverges from the engine's.
3. **Save vs. Test semantics overlap:** Test silently saves first; "Saved"
   and "Connection ok" share the same anonymous caption slot.
4. **Fixed 520 pt form floats left** in the wide detail pane rather than
   centering; lots of dead space to the right.
5. **The Status section is excellent content with debug-grade presentation**
   — raw paths, dense captions — yet it's the destination for every health
   affordance in the app ("Connect Cursor → Settings"). Users sent here for
   MCP setup land on the whole form, with no scrolling/highlighting to the
   MCP row.
6. **Provider switching silently overwrites the model field** with the new
   provider's default — any custom model name typed for the previous
   provider appears lost.
