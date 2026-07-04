# Changelog

All notable changes to Codessa are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/LogicLeapLtd/grokcode/compare/v1.2...HEAD
[1.2.0]: https://github.com/LogicLeapLtd/grokcode/releases/tag/v1.2
[1.1.0]: https://github.com/LogicLeapLtd/grokcode/releases/tag/v1.1
[1.0.0]: https://github.com/LogicLeapLtd/grokcode/releases/tag/v1.0
