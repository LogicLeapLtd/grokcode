# design-sync notes — @grokcode/design-system

## What this package is
A **hand-authored React mirror** of the GrokCodeGUI native macOS (SwiftUI) app's
"Codex" visual language. The app itself has no web/React UI, so a faithful 1:1
`dist/` import is impossible; this package recreates the look as real React
components so claude.ai/design can build on-brand.

**Source of truth** (Swift, in the sibling app): `GrokCode/GrokCode/Design/`
— `CodexTheme.swift` (all colour tokens + metrics), `CodexMotion.swift` (springs),
`PageScaffold.swift` (page container). Layout constants (radii 7/9/12/16,
spacing 2/4/6/8/10/12/18/24, type 11/12/13/14/15/17/28) were extracted from the
`Views/` tree.

## Build
- `npm run build` → `build.mjs` (esbuild bundles `src/index.tsx` → `dist/index.es.js`,
  copies `src/styles.css` → `dist/styles.css`) then `tsc --emitDeclarationOnly`
  (emits `dist/index.d.ts` + `dist/components/*.d.ts`).
- React/react-dom/react/jsx-runtime are external in the bundle (the converter /
  host provides React).
- esbuild also emits `dist/index.es.css` (from the `import "./styles.css"` in the
  barrel) — ignore it; the authoritative stylesheet is `dist/styles.css` (cfg.cssEntry).

## Converter invocation (run from `design-system/`)
```
node .ds-sync/package-build.mjs --config .design-sync/config.json \
  --node-modules ./node_modules --entry ./dist/index.es.js --out ./ds-bundle
node .ds-sync/package-validate.mjs ./ds-bundle
```

## Styling idiom
- Plain CSS classes, BEM-ish, all prefixed `gc-`. One stylesheet (`styles.css`).
- Theming: light tokens on `:root`/`.gc-root`; dark overrides on `.gc-theme-dark`.
  Wrap a subtree in `<div class="gc-root gc-theme-dark">` for dark mode.
- All colours are `var(--gc-*)` tokens — no hard-coded hex in components.
- System fonts only (`-apple-system`/`SF Mono`) — no `@font-face`, so no
  `[FONT_MISSING]` is expected.

## Re-sync risks (read before re-syncing)
- **Decoupled from the Swift app**: this React port does NOT auto-track
  `CodexTheme.swift`. If the app's tokens/metrics change, update `src/styles.css`
  (and components) by hand, then rebuild + re-sync.
- Component set is a curated subset of the app's surfaces, not exhaustive.

## Re-sync — 2026-07-04
- Re-synced with skill build **2.1.201** (newer converter than the 2026-06-18
  first sync). No DS source change; `sourceKeys`/`renderHashes` all matched the
  anchor, so **zero re-grading** — grades carried forward, driver spot-checked 5
  (SidebarItem, Toggle, Button, MenuSeparator, EmptyState) as pipeline-churn
  canaries; all confirmed good. Render check 24/24 clean, `bad`/`thin`/
  `variantsIdentical` all 0.
- **All 24 uploaded anyway** (`upload.any: true`, `bundle`/`styling: true`): the
  newer converter emits different `.jsx`/`.d.ts`/`.prompt.md`/bundle/CSS bytes,
  so every `sourceHash` differed from the anchor even though nothing rendered
  differently. `deletePaths: []` (no renames/removals). This is expected on a
  skill-version bump — not a source change.
- `conventions.md` re-validated against the fresh build: every token, class,
  component, and prop-value enumeration still resolves. No drift, left unchanged.
- Only real friction was the playwright/chromium version pin (see Toolchain notes).

## First sync — state as of 2026-06-18
- Synced to Claude Design project **GrokCode Design System**
  (`projectId: a1299383-f8d9-4f29-b11e-aaf4fb0c0163`, recorded in config.json).
- **All 24 components have authored previews** in `.design-sync/previews/` (6 were
  pre-existing: Badge, Button, IconButton, Pill, SendButton, Toggle; the other 18
  authored this run). Every cell graded `good`; render check 24/24 clean.
- `conventions.md` authored and wired via `cfg.readmeHeader` — it names real
  tokens/classes/components, validated against the built artifacts. Keep it true
  on re-sync (don't rewrite; re-validate names against the fresh build).

## Known render gotchas (read before re-syncing)
- **Banner `⚠` icon vs the harness error-fallback marker.** The render harness
  marks a *crashed* cell by writing `⚠ <message>` as the cell text. An error-tone
  `Banner` rendered as the FIRST/only thing in a cell starts with the default `⚠`
  icon and gets misread as that crash fallback → false `[RENDER_ERRORS]` / `bad`.
  Fix used: `Banner.tsx` `InlineError` passes a non-`⚠` icon (`icon="⊘"`). The
  default `⚠` error icon is still demonstrated inside the `Tones` cell (where an
  info banner leads, so the cell doesn't start with `⚠`). If you add a standalone
  error-banner cell, don't let `⚠` be the first glyph in the cell.

## Toolchain notes
- Playwright/Chromium for the render check installed under
  `~/Library/Caches/ms-playwright/` (macOS path — the SKILL's `~/.cache/...` check
  is Linux-only; on macOS verify via `ls ~/Library/Caches/ms-playwright`).
- **Playwright npm version MUST match the cached chromium build, or the render
  check fails `[RENDER_SKIPPED]` ("Executable doesn't exist").** The `.ds-sync`
  lock pins `playwright@1.49.1` (= chromium-1148), but this machine's cache holds
  **chromium-1228**, which is pinned by **`playwright@1.61.0`**. On re-sync, check
  `ls ~/Library/Caches/ms-playwright` and install the matching playwright into
  `.ds-sync`: `npm i playwright@<v> playwright-core@<v>`. Map (chromium rev → pw):
  1148→1.49, 1200→1.57, 1208→1.58, 1217→1.59, 1223→1.60, **1228→1.61**. Verify with
  `node -e "console.log(require('./node_modules/playwright-core/browsers.json').browsers.find(b=>b.name==='chromium').revision)"`.
  Alternatively `npx playwright install chromium` downloads the lock's 1148 (~180MB).
- Converter deps live in `.ds-sync/node_modules` (esbuild, ts-morph, @types/react,
  playwright). Re-copy `.ds-sync/` scripts from the skill before re-syncing.
- No `[FONT_MISSING]`: system fonts only; tokens are inlined in `styles.css`, so
  `tokens/`, `fonts/`, `guidelines/` come out empty — expected, not a miss.
