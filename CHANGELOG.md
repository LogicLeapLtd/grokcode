# Changelog

- Claude/Codex/Gemini one-shot provider replies are now flushed into chat before the UI checks for an empty response, fixing the false "Claude returned an empty response" banner. Claude stream-json parsing is also narrowed to assistant/result records so hook output never pollutes the answer.

- Plan mode now collapses to a single composer dropdown in the macOS 26 Liquid Glass toolbar; the redundant "Plan mode" permission pill is hidden there too.

- Claude runs that fail on a hard API error (rate limit / 429 / auth) no longer show a blank "Claude returned an empty response". Claude's stream-json puts the reason only in the terminal `result` field on those errors while leaving the assistant `content` blocks empty; the extractor now falls back to that `result` text, so you see the actual message (e.g. "You've reached your Fable 5 limit. Run /usage-credits…") instead of an empty bubble.
- Removed the redundant "Plan mode" toggle from the composer "+" menu. Plan was surfacing three times (the + toggle, the mode pill, and the permission menu); the always-visible mode pill and the ⇧⌘M permission menu already cover it.

- Stopped loading the grok CLI session list on launch. The app used to shell out to `grok sessions list` during startup to "restore previous sessions", but that list only feeds the Search page (the sidebar renders from the on-disk session index). It's now loaded lazily the first time you open Search — opening the app no longer spawns a grok process to pull old sessions.

- Stopped prewarming the warm `grok agent stdio` session on launch. Previously the app booted the entire MCP server fleet (dozens of subprocesses) the moment Codessa opened — even while the user was still on the home screen and might never send anything — pinning a large amount of idle memory and spawning a storm of processes on startup. The warm session now boots lazily on the first real send, so MCP starts on demand instead of on every launch.

- Fixed the model pill (e.g. "Opus 4.8") reserving a fixed 150pt of width and pushing the chevron to the far right, leaving a large empty gap — it now hugs the model name like the other composer pills.
- Fixed the top-right window controls (split view + open-in-new-window) getting clipped by the window's rounded corner. They now sit clear of the curve, and the chat header reserves matching space so the "Export" button never tucks underneath them.

- Grok error messages are now specific instead of the generic "hit a temporary failure" banner. The warm agent session used to discard the agent process's stderr and report a bland "the process exited" — it now keeps a rolling tail of stderr and surfaces the actual crash / auth / rate-limit reason (with the exit code) when the process dies. The one-shot streaming path also falls back to whatever Grok wrote to stdout (a plain-text or undecodable error line) when stderr is empty, so the real diagnostic is shown rather than boilerplate.

- Tightened the composer toolbar so long model names (e.g. "Grok Composer 2.5 Fast") no longer overflow the row. The mode dropdown no longer echoes the selected model beside the mode name — it just shows the mode (Execute, Plan, …) — and the model pill now truncates gracefully instead of expanding to the model's full intrinsic width.

- Starting a chat no longer empties the sidebar. Previously the "With chats" filter would collapse the whole project list down to just the active project the instant a chat began (the optimistic "New chat" placeholder made it the only project "with chats"). Pending placeholders are now ignored when deciding which projects to show, so every project stays visible and the sort simply floats the active one to the top. The owning project also auto-expands when a chat starts, so the new chat is immediately visible instead of hidden under a collapsed project row.

- Cleaned up the composer's mode/model labels. Agent modes no longer leak raw model IDs (e.g. `claude-fable-5`) or a redundant "Provider ·" prefix — they now show the friendly product name (Fable 5, Opus 4.8, GPT-5.5, …), consistently with the model picker. The duplicate "Plan mode" permission pill is hidden while Plan mode is active, since the mode already locks permissions to read-only.

- Transient Grok failures (rate limiting or a brief network/backend hiccup — the "Grok hit a temporary failure" case) now retry automatically with backoff before any error is shown, so a momentary blip self-heals instead of interrupting you. If it still fails, the home-screen error banner now offers a one-click **Retry**, and the banner reflows cleanly on every window size (baseline-aligned icon, text that always wraps instead of clipping, and actions that wrap to a new line on narrow viewports).

- Fixed rapid flickering/jitter when dragging to resize the sidebar. The resize handle now measures the drag against a stable window-anchored coordinate space instead of its own (moving) one, so the edge tracks the cursor 1:1 without the feedback loop.

- Errors are now human and actionable instead of cryptic exit codes. "Grok exited with code 75" (a transient rate-limit/network failure) now reads "Grok hit a temporary failure — usually rate limiting or a brief network/backend hiccup. Wait a few seconds and try again."; auth, rate-limit, timeout and other common failures get tailored guidance.
- Errors on the home screen are now shown in the same styled card (icon, container, dismiss/retry) as in-chat errors, instead of as bare red text.
- Composer "+" (add attachment) button is now circular instead of a rounded square.
- Home quick-action cards: removed the redundant "New chat" card (the Home page is already the new-chat surface) and made all remaining labels render at the same font size ("Browse plugins" no longer auto-shrinks to fit).
- Composer toolbar: pills now size to their content (no more truncated mode/permission labels or "Full access" wrapping); model pill drops the "(default)" suffix.

All notable changes to Codessa are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.8.10] - 2026-07-05

### Changed

- Model/provider menus now use bundled real SVG marks for Claude, Cursor, ChatGPT/OpenAI, Gemini, and Grok instead of hand-drawn approximations.
- Plan mode now inherits the selected composer model by default, migrates the old hidden Claude/Fable route, and preserves provider-specific CLI options when launching runs.
- Chat header actions now sit in one labelled toolbar group: Export, Split, and Pop out, so the two window controls are no longer mystery icons floating in the corner.
- Starting a chat now uses a calmer, chat-specific focus transition, and the temporary sidebar "New chat" row uses a small activity sweep instead of pulsing the entire row.
- Sidebar navigation icons now use stronger, clearer symbols with heavier rendering, so New chat, Search, Plugins, and Automations read less like placeholder outline glyphs.
- Finalization now captures dirty work before publishing instead of blocking, and the automatic closure hook publishes an updater-visible release after every code change.

## [1.8.0] - 2026-07-04

### Changed

- **Reasoning level is now its own composer dropdown**, split out of the combined
  model picker so the model menu no longer carries the reasoning pills inline.

### Fixed

- **Dropdown menu cards no longer show sharp corners.** The menu card (and flyout
  submenu) content is now clipped to the same rounded rectangle as its background,
  so the square inner content no longer pokes past the rounded frame at the corners.

## [1.7.0] - 2026-07-04

### Added

- **Sidebar project context menu**: right-click a project row for Pin/Unpin,
  Reveal in Finder, Create permanent worktree, Rename project (label-only,
  never touches the folder on disk), Archive chats, and Remove from sidebar.

### Fixed

- **Duplicate Grok agent spawns**: the warm `grok agent stdio` process is now
  guarded by a start-in-progress lock, so two callers racing to start the
  session can no longer launch two competing agent processes.
- **Titlebar controls misaligned with the traffic lights**: tuned the custom
  sidebar/back/forward control strip's top inset so it sits on the same
  centerline as the native close/minimize/zoom buttons.
- **Selected-project chip stretched into empty grey space** in the composer:
  it's now sized to its content instead of filling the row, with long
  project/branch names truncating instead of stretching the pill.
- **Branch chip showed "none"** on sidebar rows with no active git branch
  instead of just not rendering the chip.
- Removed a stray git hook that reinstalled and relaunched `/Applications/Codessa.app`
  after *every* commit from *any* agent working in this tree — the root cause
  of the app appearing to randomly "flip versions" and lose work during
  concurrent multi-agent sessions. Installs are Josh-initiated only, per the
  documented release/handoff scripts.

## [1.6.0] - 2026-07-04

### Fixed

- **Runaway memory / "Not Responding" during long or fast agent turns.** The
  provider stream delivered one main-actor task per chunk with no backpressure,
  so a fast (or looping) stream flooded the UI thread faster than SwiftUI could
  drain it — the task backlog plus an unbounded, cumulative tool-output string
  pinned the main thread and grew memory without limit (~50 GB observed). Stream
  events are now coalesced into at most one in-flight flush and applied in a
  single batched mutation, and per-tool detail is capped, so memory stays bounded
  no matter how fast the agent streams.

## [1.5.0] - 2026-07-04

### Changed
- **Final provider-label cleanup**: kept model menu labels from repeating the
  provider name while removing the Swift actor-isolation warning introduced by
  the helper extension.

## [1.4.0] - 2026-07-04

### Added
- **Final loose-artifact preservation pass**: copied the design-system sync notes
  and current Automations/Command Palette screenshots into `docs/design-system/`
  so the parent-workspace reference artifacts from July 4 are committed and
  pushed with the app source.

## [1.3.0] - 2026-07-04

### Added
- **Recovery audit** for the July 4 overnight work, including the exact commit
  coverage, dropped WIP snapshot check, parent-workspace artifact handling, and
  live app/release verification evidence.
- **Home alternative design artifacts** under `docs/design/home-alternatives/`,
  preserving the loose parent-workspace HTML/CSS/screenshots inside the pushed
  source tree.
- **Provider logo marks** for model and provider menus, replacing generic CPU
  and brain icons with recognizable provider-specific glyphs.

### Changed
- **Finalization gate is stricter.** Publishing now verifies the DMG's embedded
  app version/build, pushes both a versioned release branch and a moving
  `production` branch, confirms remote branch/tag SHAs, checks the uploaded asset
  digest against the local DMG, and reports whether the installed app is behind
  the newly published version.
- Model names now render as human-readable labels such as `GPT 5.5` and
  `GPT 5.4 Mini`, and the project picker menu is width-clamped so it does not
  stretch the composer.

## [1.2.0] - 2026-07-04

### Added
- **Production recovery release** that rolls in the post-1.1 local work: split
  workspace panes, expanded Settings, mode routing, attachment previews,
  provider runtime scaffolding, refreshed launch mascot assets, and the latest
  shell/composer polish.
- **Local build handoff flow** for agent sessions. Finished local builds can be
  dropped into `~/Library/Application Support/Codessa/PendingUpdate/` and the
  running app prompts with "New build ready" instead of requiring manual bundle
  copies.
- **Session finalization gate** via `scripts/finalize-codex-session.sh`, making
  dirty-tree checks, private builds, local update handoff, and approved release
  publishing an explicit end-of-session step.

### Changed
- Codessa is now permanently unlocked as a free build while the old licensing
  machinery remains dormant for any future paid build.
- Release source is pushed to a dedicated `release/v<version>` branch before
  creating the GitHub release, so published DMGs are tied to recoverable source.

## [1.1.0] - 2026-07-04

### Added
- **In-app software updates** — "Check for updates" now checks the GitHub
  releases feed, compares versions, and (when newer) downloads, installs, and
  relaunches the app in place instead of just opening a browser.
- **Stable install location** — updates always land at
  `/Applications/Codessa.app` and relaunch from there, so a pinned Dock
  shortcut never breaks across updates.
- **Development-build promotion** — when Codessa is run from Xcode's
  DerivedData (or anywhere outside `/Applications`), the update dialog offers
  "Install this build to /Applications & Relaunch", ending the manual
  quit-and-re-pin dance during development.
- **Automatic background update checks** on launch (toggleable in Settings ›
  About), surfacing an "Update available" badge in the account menu.

## [1.0.0] - 2026-06-14

First public release of Codessa — a native SwiftUI macOS client for the
`grok` coding agent.

### Added
- **Warm `grok agent stdio` session** — a persistent agent process is kept warm
  so prompts no longer pay the ~30s per-prompt MCP boot cost (no cold starts).
- **Markdown chat rendering** with syntax-highlighted code blocks and one-click
  **copy** on code snippets.
- **Live tool-call streaming** — grok's file edits, shell commands, and file
  reads render inline in the chat as they happen.
- **Sidebar overhaul** — projects and git branches, collapsible sections,
  auto-expand, project picker, real navigation icons, and nested-repo /
  `.git`-pointer branch detection.
- **Plugin marketplace** — a Discover catalogue plus in-app publishing, with
  Import-from-agents and Installed views, backed by a plugin import service.
- **Automations** — an automations page and service for recurring / triggered
  agent tasks.
- **⌘K command palette** for fast navigation and actions.
- **Composer slash-commands and @file-mentions** for quick command entry and
  file targeting.
- **Chat markdown export** to save a conversation as Markdown.
- **First-run onboarding** flow.
- **Per-project AGENTS.md editor** for project-scoped agent instructions.
- **Full Settings page** with custom dropdowns, popout window, and effort
  gating controls.
- **Dark mode** support across the app shell.
- **Keyboard shortcuts** throughout, including menu shortcut hints and
  ⇧⌘M to cycle permission mode.
- App icon (terminal-prompt mark on a dark squircle), README, MIT LICENSE, and
  documentation screenshots for launch.

### Changed
- Merged model + reasoning-effort into a single combined control, with friendly
  model display names.
- Reworked the window chrome and sidebar styling (glassier sidebar, real nav
  icons, folder rows) for visual parity with the reference design.
- Smoother chat experience: settle-in page transition, title header, and
  realtime streaming polish.
- Split the composer "+" / attach affordances and mode menus so the right menu
  opens for each action.
- Persist and restore the last selected project (including "Don't work in a
  project").

### Fixed
- Fixed the core chat streaming loop and the reasoning / queue / error UX.
- Auto-retry as a new session on any session-resume failure (including
  "Session does not exist").
- Start a fresh session automatically when the model changes (no more
  model-switch error).
- Fixed flaky / empty custom dropdowns, hover hit-testing, and sidebar fonts.
- Fixed double chevrons on composer menus and consolidated sidebar filters into
  a single View settings menu.
- Fixed input placeholders, mode-menu shortcuts, and modal dropdowns.
- Fixed no-project privacy prompts and the thinking-dots animation.

[Unreleased]: https://github.com/LogicLeapLtd/grokcode/compare/v1.4...HEAD
[1.4.0]: https://github.com/LogicLeapLtd/grokcode/releases/tag/v1.4
[1.3.0]: https://github.com/LogicLeapLtd/grokcode/releases/tag/v1.3
[1.2.0]: https://github.com/LogicLeapLtd/grokcode/releases/tag/v1.2
[1.1.0]: https://github.com/LogicLeapLtd/grokcode/releases/tag/v1.1
[1.0.0]: https://github.com/LogicLeapLtd/grokcode/releases/tag/v1.0
