You are building **GrokCodeGUI**, a native macOS SwiftUI app that is a faithful clone of the **ChatGPT Codex desktop app** but wired to the local **`grok` CLI** instead of OpenAI. Your job: make every page, control, dropdown, setting, and interaction match Codex's look and behaviour, fix the broken core chat loop, implement the stub pages, and **prove it works by checking yourself against the real Codex app at every step.** ultracode — author and run multi-agent workflows for each phase; token cost is not a constraint; verify findings adversarially.

## 0. Ground truth & environment

- **Repo:** `/Users/joshmatthews/Development/GrokCodeGUI/GrokCode` (this is the git root; `.git` lives here).
- **Xcode project:** `GrokCode.xcodeproj` · **scheme:** `GrokCode` · source under `GrokCode/GrokCode/`.
- **Reference app (source of truth):** `/Applications/Codex.app` — the real ChatGPT Codex. OPEN IT, USE IT, SCREENSHOT IT. Do not guess what Codex looks like; observe it.
- **The CLI you are driving:** `grok` at `~/.grok/bin/grok`. Inspect it: `grok --help`, `grok models`, `grok sessions list`. It supports `-p <prompt> -m <model> --cwd <path> --output-format streaming-json --permission-mode <mode> --effort <level>` and resume via `-r <sessionId>`.
  - `--permission-mode` valid values: `default, acceptEdits, auto, dontAsk, bypassPermissions, plan`.
  - `--effort` valid values: `low, medium, high, xhigh, max`. There is ALSO a separate `--reasoning-effort` flag described as "for reasoning models" — only `grok-4` is a reasoning model.
  - Models: `grok-build`, `grok-composer-2.5-fast` (default), `grok-4`.
- **Build (must pass with no new errors):**
  ```
  cd /Users/joshmatthews/Development/GrokCodeGUI/GrokCode
  xcodebuild -project GrokCode.xcodeproj -scheme GrokCode -configuration Debug -derivedDataPath build 2>&1 | tail -5
  ```
  Expect `** BUILD SUCCEEDED **`.
- **Run:** `open build/Build/Products/Debug/GrokCode.app`. Relaunch pattern: `pkill -x GrokCode; sleep 1; open …`.
- **Screenshot for self-review:** `screencapture -x -o /tmp/grok_<surface>.png`, then crop with Python/PIL (`Image.open(...).crop((l,t,r,w)).resize(...)`) — the full-screen PNG is 3600×2338 (Retina 2×), so multiply logical coords by ~2. Read the cropped PNG back to actually LOOK at the pixels.
- **Note:** `MACOSX_DEPLOYMENT_TARGET` is currently `27.0` (above the installed SDK's 26.5). It currently builds with only a *warning*, but lower it to `15.0` early to be safe (the app uses `@Observable`/`Observation`, needs macOS 14+).

## 1. Current architecture (already built — read before changing)

Read these files first; reuse their patterns, don't reinvent:

| Layer | File | Role |
|---|---|---|
| Entry | `GrokCodeApp.swift` | WindowGroup, 1200×800 default, Cmd-N → New Chat |
| Root | `ContentView.swift` | `HStack`: Sidebar │ 1px divider │ MainContentView; overlays Settings + Hooks `AnimatedModal`s |
| Router | `Views/Shell/MainContentView.swift` | switches `model.activePage` → Home / Chat / Search / Plugins* / Automations* |
| Composer | `Views/PromptComposer.swift` | shared "Do anything" input + toolbar (attach, permission menu, model+effort menu, send/stop) + project picker |
| Chat | `Views/ChatView.swift` | message list + divider + composer; `MessageBlock` renders You/Grok + "Thinking…" |
| Home | `Views/HomeView.swift` | centered hero composer; HooksBanner, GrokMissingBanner |
| Sidebar | `Views/SidebarView.swift`, `Views/Sidebar/SidebarControlsBar.swift` | nav, projects (grouped/flat), pin/archive, view-settings menu, settings button |
| Search | `Views/Search/SearchPageView.swift` | project + session search |
| Modals | `Views/SettingsView.swift`, `Views/HooksReviewView.swift`, `Views/Shell/AnimatedModal.swift` | project roots + CLI status; pending-hook trust |
| Stubs | `Views/Shell/FeaturePlaceholderView.swift` | Plugins & Automations — icon+title only, NOT implemented |
| State | `ViewModels/AppViewModel.swift` | `@Observable @MainActor`; `sendPrompt()`, `handleStreamEvent()`, sidebar/session/hook logic |
| CLI | `Services/GrokCLIService.swift` | spawns `grok`, streams/parses `streaming-json`, parses models/sessions |
| Models | `Models/Project.swift` | `Project, GrokSession, PermissionMode, EffortLevel, GrokModelOption, ChatMessage, MainPage` |
| Other services | `Services/{SessionIndexService,HooksService,ProjectDiscovery}.swift` | session index from `~/.grok/sessions/**/summary.json`; hooks from `~/.grok/hooks/*.json`; project discovery |
| Design | `Design/CodexTheme.swift`, `Design/CodexMotion.swift` | hardcoded light-mode tokens + named springs (`pageSpring`, `panelSpring`, `modalSpring`, `quickSpring`) |

Data flow when sending: `sendPrompt()` (AppViewModel:146) → appends user msg + empty streaming assistant msg → `GrokCLIService.streamPrompt()` (builds args, spawns Process, line-by-line decodes `GrokStreamEvent`) → `handleStreamEvent()` (AppViewModel:359) mutates the assistant message.

## 2. Confirmed bugs to FIX (verified in code)

**BLOCKER — chat hangs on "Thinking…":** `handleStreamEvent` (AppViewModel.swift:362-374) only handles `"text"` and `"end"`. The grok CLI emits a stream of `"thought"` events (reasoning tokens) BEFORE the final `"text"` + `"end"`. They hit `default: break` and are silently dropped, so the assistant message stays empty for the whole reasoning phase and the UI looks dead. **Fix:** handle `"thought"` (stream it into a separate reasoning field rendered as a collapsible "Thinking" / reasoning block, Codex-style), keep streaming `"text"` into the answer body, finalize on `"end"`. Verify live by running the CLI: `grok -p "say hi" -m grok-composer-2.5-fast --cwd . --output-format streaming-json --permission-mode bypassPermissions --effort medium` and observe the `{"type":"thought",...}` … `{"type":"text",...}` … `{"type":"end",...}` sequence.

**MAJOR — `GrokStreamEvent` has no `CodingKeys`** (GrokCLIService.swift:20-25): relies on exact camelCase key matching; if the CLI emits `session_id`/`stop_reason` they decode to `nil`. Add explicit `CodingKeys` or `.convertFromSnakeCase`. Inspect the real JSON keys from the live command above and match them exactly.

**MAJOR — partial-line JSON drops events** (GrokCLIService.swift:161-177): the readability handler splits each `availableData` chunk on newlines and `try?`-decodes per line with no carry-over buffer; a JSON object split across two reads is silently lost (could be the `text` or `end` event). Add a buffer that accumulates across reads and only decodes complete lines.

**MAJOR — no timeout / watchdog** (GrokCLIService.swift:132-208): a hung CLI process (auth stall, never emits `end`) leaves `sendPrompt` awaiting forever and `isRunning` stuck true. Add a timeout that terminates the process and throws a surfaced error.

**MAJOR — input dead while running; no queue/steering** (PromptComposer.swift:71 `.disabled(model.isRunning)`, and the return-key handler bails on `isRunning`; AppViewModel `sendPrompt` has no `isRunning` guard and overwrites `runningProcess` GrokCLIService.swift:155). Codex lets you keep typing and **queue a follow-up while a run is in flight**, and shows queued messages. Implement: keep the field editable during a run; pressing return while running **enqueues** the message (show queued bubbles) and it auto-sends when the current run ends; guard `sendPrompt` so a second concurrent spawn can't orphan the first process. Match Codex's exact queue/steer behaviour — observe it in Codex.app first.

**MAJOR — `errorMessage` set but never shown** (AppViewModel.swift:71,188): on failure the pending assistant bubble is removed with no visible explanation. Surface failures (inline error bubble or banner).

**MAJOR — divider line above the composer** (ChatView.swift:31-33): explicit `Rectangle().fill(CodexTheme.divider).frame(height:1)` sits directly above `PromptComposer`. Codex has no hard rule there. **Remove it** (the composer already has its own rounded border). Confirm against Codex.app.

**MAJOR — empty "Do anything" box too tall** (PromptComposer.swift:68-69): `axis:.vertical` + `.lineLimit(1...6)` + `.frame(minHeight:24, maxHeight:120, alignment:.topLeading)` lets the empty field expand toward `maxHeight`. Make it hug content when empty (single line ~24pt) and grow only as the user types, capping at ~6 lines — match Codex's compact input. Use `fixedSize(horizontal:false, vertical:true)` / an ideal height and verify the empty state is one line tall.

**MINOR/POLISH (fix while in the area):** role label is binary `You`/`Grok` (system/tool roles mislabel); "Thinking…" has no animation; assistant vs user messages have no visual distinction; Plugins/Automations are non-functional stubs; `parseModels`/`parseSessions` are fragile text-scraping (prefer a JSON `grok` output if one exists); `runCapture` can return error text as success (GrokCLIService.swift:115-121); **no dark mode** (theme is hardcoded light — Codex ships a real dark theme; add full dark-mode parity); no spacing/shadow/radius token scale; no `accessibilityReduceMotion` handling.

## 3. Scope — every surface must be real, not stubbed

Build/finish all of these to Codex parity (observe each in Codex.app, then replicate):
1. **Home / empty state** — hero, greeting, composer, suggestion chips/quick actions if Codex has them.
2. **Chat** — streaming answer + reasoning ("Thinking") block, tool/command call rendering, queued/steering messages, stop, copy, error states, auto-scroll, message actions.
3. **Composer** — attach, permission-mode menu, combined model+effort control, send/stop, project picker, the hooks-needing-review banner, keyboard shortcuts.
4. **Sidebar** — nav, project list (grouped + flat), threads, pin/archive, view-settings menu, search/filter, new chat.
5. **Search page**.
6. **Settings** — match Codex's settings surface (project roots, CLI status, model defaults, appearance/theme, anything Codex exposes).
7. **Hooks review**.
8. **Plugins** and **Automations** — implement real functionality matching Codex's equivalents (or, if Codex has no equivalent, design them coherently and flag the decision).
9. **Theming** — light AND dark, matching Codex tokens; reduced-motion.

## 4. Method — Codex is the spec

For EVERY surface, follow this loop:
1. **Observe Codex:** open `/Applications/Codex.app`, navigate to the surface, open every dropdown/menu/setting, and screenshot each state (`screencapture`). Catalog: layout, spacing, type scale, colors, control styles, copy/labels, empty/loading/error states, hover/active states, animations, keyboard shortcuts.
2. **Implement** the GrokCode equivalent reusing `CodexTheme`/`CodexMotion` tokens (extend them — add spacing/shadow/radius scales and dark-mode variants rather than scattering magic numbers).
3. **Self-check** (Section 5) until it matches.
4. **Commit** that surface (see Section 6).

When Codex and Grok genuinely differ (model names, effort vs reasoning, grok-specific hooks/permissions), adapt sensibly and note the deviation in the commit body — don't invent Grok features Codex lacks, and don't drop Codex affordances without reason.

## 5. Self-QA protocol — MANDATORY, do not declare anything "done" without it

You must pass ALL gates per surface. Never claim "done/working/matches Codex" from code inspection alone — you must build, run, and look at pixels.

**Gate A — Build:** `xcodebuild … build` returns `** BUILD SUCCEEDED **` with no new warnings/errors. A broken build is the same severity as no work.

**Gate B — Runtime / behaviour (functional truth):** launch the app and actually exercise the feature. For the chat loop specifically, this is non-negotiable end-to-end proof:
- Send a real prompt to `grok-composer-2.5-fast` at `medium`. Confirm the reasoning ("Thinking") streams visibly, then the answer streams, then it finalizes — **it must NOT sit blank on "Thinking…"**.
- Repeat with `grok-4` at `high`/`max` (long reasoning) — confirm progress is visible the whole time.
- While a run is in flight: type and press return → confirm the message **queues** and auto-sends after; confirm Stop cancels and the process actually dies (`pgrep -fl grok` shows no orphan).
- Force an error (e.g. invalid model) → confirm the failure is **surfaced**, not a silently vanishing bubble.
- Confirm the timeout fires on a hung run.
- Read console/stderr if anything misbehaves.

**Gate C — Visual self-review (adversarial):** invoke the **`visual-quality:visual-self-review`** skill on the actual screenshot. First TRANSCRIBE every visible string and account for every region (flag blank/dead space, unlabelled controls, truncation, misalignment, inconsistent spacing, leftover placeholders, low contrast, double chevrons, oversized inputs). Then sweep for defects. End only with `VISUAL-SELF-REVIEW: PASS` when the Definition of Done is genuinely met. Run a second adversarial pass via the **`visual-quality:visual-reviewer`** agent (give it the screenshot path + the original Codex reference shot) for an independent verdict.

**Gate D — Side-by-side parity diff:** capture Codex.app and GrokCode at the SAME window size for the same surface/state. Place them side by side (or read both crops) and enumerate EVERY delta: spacing, font weight/size, color, radius, control placement, label text, icon, animation. Iterate until the list is empty or every remaining delta is a deliberate, justified Grok adaptation. Record the comparison shots under `/tmp/parity/<surface>_codex.png` vs `<surface>_grok.png`.

**Gate E — Regression sweep:** after each surface, re-run the chat send test + screenshot Home/Chat/Sidebar to confirm you didn't break a previously-passing surface (e.g. the earlier double-chevron fix, the consolidated sidebar view-settings menu, friendly model display names).

**Per-surface QA record:** keep a running checklist (a `QA.md` in the repo or a TodoWrite list) with a row per surface × gate (A–E) marked pass/fail with the screenshot path and the parity-delta notes. A surface is DONE only when A–E all pass. Report this matrix at the end.

## 6. Working discipline

- **ultracode:** for each phase (audit → fix core loop → per-surface parity → dark mode → final QA) run a Workflow: fan out observation/implementation, and **adversarially verify** every "it matches" claim with an independent reviewer agent before trusting it. Don't solo anything substantive.
- **Commit after every surface/fix** (the repo auto-expects commits): `git status -s`, stage only the exact paths you touched (never `git add -A`), commit with a clear message, end commit messages with `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`. Multiple agents may share the tree — stay in your lane, never bulk-add others' changes.
- Don't rewrite history, don't `git worktree`/`stash`/force-push without explicit OK.
- If a gate fails, fix the root cause and re-run the gate — no speculative patches, no claiming done with a red gate.

## 7. Definition of Done (the whole task)

- Build succeeds; deployment target sane.
- Chat send works end-to-end with visible reasoning + answer streaming, queue/steer, stop, timeout, and surfaced errors — proven by a live run, not inspection.
- Every surface in Section 3 implemented and passing Gates A–E, including light + dark themes and reduced-motion.
- No stubs left (Plugins/Automations real or explicitly descoped with rationale).
- A final QA matrix (surface × A–E) reported with screenshot paths and parity notes, plus the side-by-side comparison shots.
- All work committed.

Start by: (1) building once to confirm the baseline, (2) opening Codex.app and the app side by side, (3) running the live `grok … streaming-json` command to see the real event schema, then (4) fixing the BLOCKER chat-streaming bug first and proving it with Gate B before moving on.
