# Changelog

All notable changes to GrokCode are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-06-14

First public release of GrokCode — a native SwiftUI macOS client for the
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

[Unreleased]: https://github.com/joshmatthews/GrokCode/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/joshmatthews/GrokCode/releases/tag/v1.0.0
