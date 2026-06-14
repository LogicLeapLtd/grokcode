# scripts/

Release engineering helpers for GrokCode.

## `build-dmg.sh`

Builds the app in **Release** configuration and packages it into a compressed
`.dmg`. Dependency-free — uses only `xcodebuild` and `hdiutil` (both ship with
Xcode / macOS); no Homebrew or `create-dmg` required.

### Usage

```bash
# From anywhere — the script resolves the repo root itself.
./scripts/build-dmg.sh
```

What it does:

1. `xcodebuild ... -configuration Release -derivedDataPath build clean build`
2. Reads `MARKETING_VERSION` from the build settings (falls back to `1.0`).
3. Locates the built `GrokCode.app` and stages it (with an `/Applications`
   drag-target symlink).
4. Writes `dist/GrokCode-<version>.dmg` via `hdiutil` (UDZO, compressed).

Output: `dist/GrokCode-<version>.dmg`.

> A nicer styled DMG (custom window, icon positions, background) can be produced
> with Homebrew's `create-dmg` — see the commented block inside `build-dmg.sh`.

## Code signing & notarization (manual)

These steps are intentionally **not** automated because they require your Apple
Developer account. An unsigned build runs locally but triggers Gatekeeper
warnings ("cannot be opened because the developer cannot be verified") on other
Macs. To distribute publicly:

1. **Sign** the `.app` with your Developer ID (hardened runtime), then
   re-package the DMG:

   ```bash
   codesign --deep --force --options runtime --timestamp \
     --sign "Developer ID Application: Your Name (TEAMID)" \
     build/Build/Products/Release/GrokCode.app

   codesign --verify --deep --strict --verbose=2 \
     build/Build/Products/Release/GrokCode.app
   ```

2. **Store** notarytool credentials once (keychain profile):

   ```bash
   xcrun notarytool store-credentials "GrokCodeNotary" \
     --apple-id "you@example.com" \
     --team-id "TEAMID" \
     --password "app-specific-password"
   ```

3. **Notarize** the DMG and wait:

   ```bash
   xcrun notarytool submit dist/GrokCode-<version>.dmg \
     --keychain-profile "GrokCodeNotary" --wait
   ```

4. **Staple** the ticket so it validates offline:

   ```bash
   xcrun stapler staple dist/GrokCode-<version>.dmg
   xcrun stapler validate dist/GrokCode-<version>.dmg
   ```

The exact commands also live as inline notes at the bottom of `build-dmg.sh`.

## CI

`.github/workflows/release.yml` runs this script on `macos-14` when a `v*` tag
is pushed, then attaches the resulting DMG to a GitHub Release. The CI build is
**unsigned** by default; wiring up signing / notarization there needs repo
secrets (the certificate and Apple credentials).
