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

## Multi-agent & build discipline — READ THIS FIRST (learned the hard way)

**This working tree is edited by more than one agent at the same time** (Claude Code *and*
Codex, plus Josh). Assume you are **not** alone. The failure mode that has already bitten us:
several agents each run their own `xcodebuild`, then each install/launch a *different* in-flight
build, so the running Codessa keeps flipping versions and work *appears* to vanish — it isn't
(it's in git or still uncommitted; the running app was just a stale build). Rules, non-negotiable:

1. **Never launch or install the app.** Do NOT run the dev-build promote, do NOT
   `cp`/`ditto` a build into `/Applications/Codessa.app`, do NOT `open` the app.
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
6. **The in-app updater is for shipping, not dev iteration.** It installs to the stable
   `/Applications/Codessa.app`; agents promoting dev builds there is exactly what makes the
   running app thrash. Leave `/Applications` alone — publish real releases only via the runbook
   below, and only when Josh asks.

When in doubt: make the edit, do a path-scoped commit, and let Josh build and run.

---

## In-app updates (the update facility)

Implemented in `Codessa/Services/UpdateService.swift` + `Codessa/Views/Shell/UpdateDialog.swift`,
wired in `ContentView` (owns `UpdateService` as a `@StateObject`, injects via `.environmentObject`),
surfaced from the sidebar account menu (`SidebarView`) and **Settings › About** (`SettingsView`).

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
  the account menu; it never pops the dialog uninvited.
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

5. **Package the DMG.** Either run `scripts/build-dmg.sh` (rebuilds + packages), or stage the signed
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
