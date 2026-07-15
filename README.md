<div align="center">

# Codessa

**A focused, native macOS workspace for ChatGPT Codex.**

[![macOS](https://img.shields.io/badge/macOS-15%2B-000000?style=flat&logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.9-F05138?style=flat&logo=swift&logoColor=white)](https://swift.org)
[![SwiftUI](https://img.shields.io/badge/SwiftUI-native-0A84FF?style=flat&logo=swift&logoColor=white)](https://developer.apple.com/xcode/swiftui/)
[![Build](https://img.shields.io/badge/Build-free-22C55E?style=flat)](LICENSE)
[![Download](https://img.shields.io/badge/Download-latest_release-0A84FF?style=flat)](https://github.com/LogicLeapLtd/grokcode/releases/latest)

![Codessa chat](docs/chat.png)

</div>

---

## Why Codessa

Codessa gives the local Codex CLI a purpose-built desktop workspace: ChatGPT sign-in, project-aware conversations, model and reasoning controls, plugins, scheduled automations, and git-branch organisation in one native macOS app. It drives Codex through the supported non-interactive CLI flow and streams structured events into the conversation UI.

Codex is the first provider shown, the default for new and existing installs that never chose another agent, and the primary setup path throughout onboarding, Home, and Settings. Claude Code, Cursor, Gemini, Grok, Z.AI, and custom local CLIs remain available as optional alternatives.

The interface is fully native SwiftUI: markdown chat with copyable code blocks, a ⌘K command palette, slash commands and `@file` mentions, a plugin marketplace, scheduled automations, and project + git-branch organisation — all keyboard-driven, in full light and dark mode.

---

## Features

- **ChatGPT Codex first** — Codex is the default provider, with first-class model, reasoning, permission, structured-event, and sign-in handling through the local `codex` CLI.
- **Optional local agents** — switch a chat to Claude Code, Gemini, Grok, or another configured CLI without losing the focused Codex workflow.
- **Rich markdown chat** — headings, lists, tables, inline code, and fenced **code blocks with one‑click copy**, plus a live "Thinking…" reasoning trace as the model works.

  ![Home / new chat](docs/home.png)

- **⌘K command palette** — jump to any project, session, page, or action without lifting your hands off the keyboard.

  ![Command palette](docs/command-palette.png)

- **Composer that does anything** — type `/` for **slash‑commands** and `@` to **mention files** in the active project, pick your model, effort, and permission mode inline, then send or stop.
- **Plugin marketplace + in‑app publishing** — Discover community MCP servers, import a custom one, see what's Installed, and **publish your own** in a couple of clicks (more below).
- **Automations** — run a prompt **manually**, on an **interval**, or **daily** on a schedule, scoped to a project.
- **Projects & git‑branch organisation** — group sessions by project, organised by branch, with pin and archive.
- **Resizable, collapsible sidebar** — drag to resize, collapse for focus, grouped or flat project views.
- **Per‑project `AGENTS.md` editor** — edit the agent instructions that ship with each project, right inside the app.
- **First‑run onboarding** — a guided welcome that gets you from install to first prompt with zero guesswork.

  ![Onboarding](docs/onboarding.png)

- **Full light & dark mode** — a complete, hand‑tuned theme on both sides of the system appearance.
- **Keyboard‑driven everywhere** — new chat, search, settings, page switching, mode cycling, and stop are all one shortcut away.

---

## Pricing

Codessa is currently a **free, fully unlocked** macOS app. The old licensing
code remains in the source tree as dormant infrastructure, but this production
build does not start a trial, show a paywall, or call Lemon Squeezy licensing
endpoints on launch.

---

## Install

### Download

Download the latest **`.dmg`** from GitHub Releases, drag Codessa to
**Applications**, and launch.

> **Download:** [latest Codessa release](https://github.com/LogicLeapLtd/grokcode/releases/latest)

---

## Requirements

- **macOS 15 or later** (Apple silicon or Intel).
- The **Codex CLI** installed with `npm install -g @openai/codex`.
- A signed-in Codex CLI — run **`codex login`** and use your ChatGPT account before your first chat.
- Optional providers require their own local CLI and account only when you choose to use them.

Codessa talks to your local agent CLI; provider requests follow that provider's
own account and data policies. The update checker reads GitHub Releases when enabled.

---

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| `⌘N` | New chat |
| `⌘K` | Command palette |
| `⌘F` | Search |
| `⌘,` | Settings |
| `⌘1`–`⌘4` | Switch page (Home / Chat / Plugins / Automations) |
| `⇧⌘M` | Cycle permission / agent mode |
| `Esc` | Stop the current run |

---

## Plugins / Marketplace

Codessa ships a built‑in marketplace for **MCP servers**, organised into three tabs:

- **Discover** — browse community plugins pulled live from the public marketplace manifest.
- **Import** — add a custom MCP server by command, args, URL, and environment.
- **Installed** — manage everything you've added, including enable/disable.

![Marketplace](docs/marketplace.png)

### Publishing a plugin

Built something worth sharing? Use **Publish a plugin** inside the app to generate a ready‑to‑submit manifest entry, then open a pull request against the marketplace repo.

![Publish a plugin](docs/publish.png)

The marketplace is just a single JSON file — anyone can contribute by adding an entry. See **[`logicleaplabs/grokcode-marketplace`](https://github.com/logicleaplabs/grokcode-marketplace)** for the manifest format and the PR workflow.

---

## Architecture

Codessa is a focused, native stack:

- **SwiftUI** for the entire interface — windows, sidebar, chat, modals, and theming.
- **A custom menu / motion engine** (`CodexTheme` + `CodexMotion`) providing the named springs and design tokens that give the app its consistent, Codex‑like feel across light and dark.
- **A first-class Codex runtime adapter** that drives `codex exec --json`, translates structured events into native chat state, and preserves model, reasoning, permission, and working-directory choices.
- **Optional provider adapters**, including the existing ACP JSON-RPC warm-session path for Grok when Grok is explicitly selected.

State lives in a single `@Observable @MainActor` view model; provider runtime adapters spawn and parse the selected local CLI, and small services index sessions, hooks, plugins, and the marketplace.

---

## Disclaimer

**Unofficial.** Codessa is an independent LogicLeap project. It is **not affiliated with, sponsored by, or endorsed by OpenAI.** ChatGPT, Codex, and OpenAI are trademarks of OpenAI. Optional third-party provider names and trademarks belong to their respective owners.

---

## License

Codessa is currently distributed as a free LogicLeap build. See [LICENSE](LICENSE)
for the current terms in this repository.

Made by **LogicLeap Labs**.
