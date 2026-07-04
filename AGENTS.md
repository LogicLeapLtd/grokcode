# Codessa — Agent Guide

> Kept in sync with `CLAUDE.md` (same content). Update both when this changes.

Native macOS SwiftUI app — a front-end for the Grok CLI.

- **Xcode project:** `Codessa.xcodeproj` · **scheme:** `Codessa` · **bundle id:** `co.codessa.Codessa`
- **Source:** everything under `Codessa/` is a *filesystem-synchronized group* — new `.swift`
  files added to that folder auto-join the build target. **Do not hand-edit `project.pbxproj`
  to add files.**
- **Git:** this folder (`GrokCode/`) is the repo root. It has **no git remote**. Releases are
  published to the GitHub repo **`LogicLeapLtd/grokcode`** with the `gh` CLI (authed as the
  `LogicLeapLtd` org, ADMIN on that repo).
- **Validate** compilation with
  `xcodebuild -project Codessa.xcodeproj -scheme Codessa -configuration Debug -derivedDataPath .build-agent build`
  — note the **private** `.build-agent` derived-data path (git-ignored), NOT the shared `build/`,
  so concurrent agents don't corrupt each other's build. Build only to verify it compiles; never to launch.

---

## ⛔️ NON-NEGOTIABLE #0 — EVERY code change ALWAYS cuts a new versioned build

**This overrides everything else. Josh should never have to ask for a build.**

If your session changed ANY code, config, asset, or project file, you MUST — before
you end the response — do BOTH of these, every single time:

1. **Bump the version.** In `Codessa.xcodeproj/project.pbxproj`, bump
   `CURRENT_PROJECT_VERSION` (build number) in **both** the Debug and Release config
   blocks. Bump `MARKETING_VERSION` too for anything user-visible; a bare build-number
   bump is the minimum for internal/cosmetic changes. Add a one-line `CHANGELOG.md` entry.
2. **Cut the build the running app can pick up.** Run
   `scripts/finalize-codex-session.sh --handoff` (or `scripts/drop-local-update.sh`),
   which builds and drops `Codessa.app` into the PendingUpdate folder so the running
   Dock app shows **"New build ready → Update & Relaunch"**.

**This is required whether or not the change was QA'd, whether or not it "looks trivial",
whether or not you think it's done, and whether or not Josh asked for a build.** "It's only
a one-line/cosmetic change", "I didn't get to test it", "I'll build next turn", and
"waiting for confirmation" are all NOT acceptable reasons to skip the versioned build.
QA status is reported separately in the status table — it is NEVER a gate on cutting the build.

The ONLY exceptions: (a) you changed no code/assets at all (pure diagnosis/answer), or
(b) a hard tool failure (build refuses, hook blocks) that needs Josh to unblock — in which
case state the specific blocker instead of silently skipping. Ending a code-changing response
without a bumped version + handoff build is a hard failure.

**This is enforced automatically** by a Claude Code `Stop` hook that runs
`scripts/auto-handoff-on-change.sh` after every turn. When `HEAD` has moved and the tree is
clean, the script bumps `CURRENT_PROJECT_VERSION` in both config blocks, commits the bump
path-scoped, and cuts + drops a versioned build — so a new versioned build is produced on
every change without anyone asking. It defers (does not skip) only while the tree is dirty,
so commit your work and it fires. Do NOT rely on this as a reason to hand-wave the rule:
if the hook isn't active (e.g. it loads next session), do the bump + `scripts/drop-local-update.sh`
yourself this turn.

---

## Multi-agent & build discipline — READ THIS FIRST (learned the hard way)

**This working tree is edited by more than one agent at the same time** (Claude Code *and*
Codex, plus Josh). Assume you are **not** alone. The failure mode that has already bitten us:
several agents each run their own `xcodebuild`, then each install/launch a *different* in-flight
build, so the running Codessa keeps flipping versions and work *appears* to vanish — it isn't
(it's in git or still uncommitted; the running app was just a stale build). Rules, non-negotiable:

1. **Never launch or install the app during ordinary coding.** Do NOT run the
   dev-build promote, do NOT hand-copy/`ditto` a build into `/Applications/Codessa.app`,
   and do NOT `open` the app unless Josh explicitly asks for a final/canonical local build.
   **Deciding which build runs is Josh's job.** Concurrent installs are the #1 cause of
   "different versions launching" and perceived lost work.
2. **Build only to check compilation, only when needed, to a PRIVATE derived-data path**
   (`.build-agent…`, git-ignored) — never the shared `build/`. Don't build "just to be safe";
   it contends with other agents' builds.
3. **Commit small, often, and ONLY your paths.** Never `git add -A` / `git add .`. Stage the
   exact files you touched, by name. A giant shared uncommitted blob is what makes work look
   "lost" — frequent path-scoped commits keep each agent's work isolated and recoverable.
4. **NEVER run destructive/history git ops on this shared tree:** no `git reset --hard`, no
   `git checkout -- <path>` on files you didn't author, no `git stash`, `git clean`,
   `git rebase`, force-push, or `commit --amend`. They silently wipe another agent's
   uncommitted work. If `git status` shows changes you don't recognise, **leave them**.
5. **Stay in your lane** — only touch files your task needs. If two agents need the same file,
   coordinate through Josh instead of racing edits.
6. **Agent-to-app handoff builds use exactly one script.** If Josh wants the running canonical
   Dock app to pick up your finished local changes, run `scripts/drop-local-update.sh`. It builds
   in private `.build-agent-local-update`, drops `Codessa.app` into
   `~/Library/Application Support/Codessa/PendingUpdate/`, and does **not** install or launch.
   The running `/Applications/Codessa.app` shows a bottom-right **New build ready** prompt with
   **Update & Relaunch**. Do not improvise another handoff path.
7. **Canonical local installs use exactly one script.** If Josh explicitly asks to make the
   current tree the final local app, run `scripts/install-canonical-local.sh --dock --launch`.
   That script builds in a private `.build-final` derived-data path, takes a lock, installs
   to `/Applications/Codessa.app`, keeps the Dock pin stable, and avoids the shared `build/`
   race. Do not improvise your own install/copy/open commands.
8. **The in-app updater is for user-visible prompts.** Local handoff builds and published releases
   both install to stable `/Applications/Codessa.app` only after Josh clicks a prompt. Background
   release checks show a bottom-right "Update available" prompt that opens the updater dialog;
   local handoffs show "New build ready" directly. Nothing silently replaces the app.
   Publish real releases only via the runbook below, and only when Josh asks.
9. **Mandatory session closure gate — ALWAYS cut a versioned build (see NON-NEGOTIABLE #0).**
   Any Codex/Claude session that changes code must bump the version (per #0) and end by
   running `scripts/finalize-codex-session.sh --handoff` or, when Josh explicitly approved a
   production publish, `scripts/finalize-codex-session.sh --publish`. Do this on EVERY
   code-changing session regardless of QA status — never leave finished edits without a
   handoff build for the running app. This gate refuses dirty
   trees, validates a private build, and either drops a local update for the running app or creates
   the GitHub release the updater can see. Publish mode must also verify the DMG's embedded
   version/build, the remote `release/v<version>` branch, the moving `production` branch, the
   release tag, and the uploaded asset checksum. Do not tell Josh work is "done" if this gate did
   not run and pass; report the blocker instead.

When in doubt: make the edit, do a path-scoped commit, and run the closure gate so the work is
recoverable and installable.

---

## In-app updates (the update facility)

Implemented in `Codessa/Services/UpdateService.swift`,
`Codessa/Services/LocalBuildUpdateService.swift`, and `Codessa/Views/Shell/UpdateDialog.swift`,
wired in `ContentView` (owns the services as `@StateObject`s; `UpdateService` is injected via
`.environmentObject`), surfaced from the sidebar account menu (`SidebarView`) and
**Settings › About** (`SettingsView`).

How it behaves:

- **Check for updates** queries `https://api.github.com/repos/LogicLeapLtd/grokcode/releases/latest`,
  SemVer-compares the tag to the running build's `CFBundleShortVersionString`, and if newer
  downloads the release's `.dmg` (preferred) or `.zip` asset with progress, extracts the `.app`,
  and installs it.
- **Stable install path.** Updates always land at, and relaunch from, **`/Applications/Codessa.app`**.
  Because that path never changes, a pinned Dock shortcut survives every update. The swap runs from
  a detached shell script that waits for the app to quit, `mv`s the old bundle aside, `ditto`s the
  new one in, clears the `com.apple.quarantine` flag, and relaunches — with rollback if the copy fails.
- **Dev-build promotion.** When Codessa runs from Xcode's DerivedData (or anywhere outside
  `/Applications`), the dialog offers **"Install this build to /Applications & Relaunch"** — this is
  the fix for the drifting Dock shortcut during development (no more manual quit + re-pin).
- **Background check on launch** (toggle in Settings › About) lights an "Update available" badge in
  the account menu and shows a bottom-right "Update available" prompt; it never pops the dialog
  uninvited.
- **Local agent handoff builds.** Future Codex/Claude sessions that should hand off a finished
  build to the running app must run `scripts/drop-local-update.sh`. The running canonical app watches
  `~/Library/Application Support/Codessa/PendingUpdate/Codessa.app` and shows a bottom-right
  "New build ready" prompt with **Update & Relaunch**. This keeps the app stable until Josh accepts
  the update.
- **Canonical local build install.** When Josh asks to promote the current working tree to the Dock
  app, use `scripts/install-canonical-local.sh --dock --launch`. Do not manually copy bundles into
  `/Applications` or launch DerivedData builds.
- The target repo is set by `UpdateService.repoOwner` / `repoName` constants — change there if
  releases move.

---

## Release runbook — how to ship an update the app will detect

Do all of this whenever you cut a new version. The running app only sees a new version once a
**non-draft, non-prerelease** GitHub release exists on `LogicLeapLtd/grokcode` with a DMG asset.

1. **Bump the version.** In `Codessa.xcodeproj/project.pbxproj` there are **two** config blocks
   (Debug + Release) — bump `MARKETING_VERSION` (and `CURRENT_PROJECT_VERSION`) in **both**. Add a
   `CHANGELOG.md` entry.

2. **Build Release:**
   ```sh
   xcodebuild -project Codessa.xcodeproj -scheme Codessa -configuration Release -derivedDataPath build build
   ```

3. **Sign for distribution** (Developer ID + hardened runtime):
   ```sh
   codesign --deep --force --options runtime --timestamp \
     --sign "Developer ID Application: LOGICLEAP LTD (DKP8S5XCXU)" \
     build/Build/Products/Release/Codessa.app
   ```
   > ⚠️ **This needs interactive keychain access.** In a headless / non-interactive shell it fails
   > with `errSecInternalComponent` (codesign can't unlock the private key). Run it from a real
   > Terminal, or first `security unlock-keychain` / grant access with
   > `security set-key-partition-list -S apple-tool:,apple: -s -k <pw> login.keychain-db`.
   >
   > If you genuinely can't Developer-ID-sign, an **Apple-Development-signed** build still updates
   > fine on *your own* Mac (the updater clears quarantine on install), but it is **NOT
   > distributable** to other Macs — never hand such a DMG to a customer.

4. **Notarize + staple** (only needed for *other* people's Macs). No notarytool profile exists yet —
   create one once with `xcrun notarytool store-credentials <profile> --apple-id <id> --team-id
   DKP8S5XCXU --password <app-specific-password>`, then:
   ```sh
   xcrun notarytool submit dist/Codessa-<version>.dmg --keychain-profile <profile> --wait
   xcrun stapler staple dist/Codessa-<version>.dmg
   ```

5. **Package the DMG.** Either run `scripts/finalize-codex-session.sh --publish` for the guarded
   end-to-end path, run `scripts/build-dmg.sh` (rebuilds + packages), or stage the signed
   `Codessa.app` plus an `/Applications` symlink and:
   ```sh
   hdiutil create -volname Codessa -srcfolder <staging-dir> -ov -format UDZO dist/Codessa-<version>.dmg
   ```
   The DMG must contain exactly one `.app` (any name — it installs as `Codessa.app`).

6. **Publish the release** (this is what the updater reads):
   ```sh
   gh release create v<version> --repo LogicLeapLtd/grokcode \
     --title "Codessa <version>" \
     --notes "<markdown release notes>" \
     dist/Codessa-<version>.dmg
   ```
   - Must **not** be a draft or prerelease — the app queries `/releases/latest`, which excludes both.
   - The `--notes` body is shown verbatim in the update dialog ("What's new").

7. **Verify:** `curl -s https://api.github.com/repos/LogicLeapLtd/grokcode/releases/latest` shows the
   new `tag_name` + DMG asset, and an older running build's **Check for updates** now offers it.

### Mandatory end-of-session commands

- For ordinary finished local work: commit the exact touched paths, then run
  `scripts/finalize-codex-session.sh --handoff`.
- For an approved production release: bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`, add a
  `CHANGELOG.md` entry, commit the exact touched paths, then run
  `scripts/finalize-codex-session.sh --publish`.
- The final answer must say which gate mode ran and whether it passed. If it failed, give the
  smallest concrete blocker; do not describe unpublished local source as shipped.
- Publish mode pushes both `release/v<version>` and `production`, then verifies both remote refs,
  the release tag, the DMG app version/build, and the GitHub asset digest.

### Signing identities available on this machine
- **Developer ID Application: LOGICLEAP LTD (DKP8S5XCXU)** — use for distribution.
- Apple Distribution: LOGICLEAP LTD (DKP8S5XCXU).
- Apple Development (personal) — automatic signing default; own-machine only.

---

## Conventions

- **Design system:** use `CodexTheme` tokens, `CodexPressableStyle`, `AnimatedModal`,
  `CodexMenuItem`, etc. — match the existing components, don't reinvent.
- **Services:** `@Observable`/`ObservableObject`, created in `ContentView`, injected via
  `.environment` / `.environmentObject`.
- **Commit after each change**, staging only the exact paths you touched. This is a shared
  multi-agent working tree — leave changes you don't recognise alone; never `git add -A`.
