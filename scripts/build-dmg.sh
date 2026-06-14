#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# build-dmg.sh — Build GrokCode (Release) and package it into a .dmg
# ---------------------------------------------------------------------------
# Dependency-free: uses only xcodebuild + hdiutil (both ship with Xcode/macOS).
# No Homebrew, no create-dmg required. See the NEXT STEPS notes at the bottom
# for code-signing + notarization (manual, needs your Apple Developer creds).
# ---------------------------------------------------------------------------
set -euo pipefail

# Resolve repo root (this script lives in <repo>/scripts) so the script can be
# invoked from anywhere.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

PROJECT="GrokCode.xcodeproj"
SCHEME="GrokCode"
CONFIGURATION="Release"
DERIVED_DATA="build"
APP_NAME="GrokCode.app"
DIST_DIR="dist"
VOLNAME="GrokCode"

echo "==> Building ${SCHEME} (${CONFIGURATION})"

# ---------------------------------------------------------------------------
# 1) Clean + build the Release configuration into ./build
# ---------------------------------------------------------------------------
xcodebuild \
  -project "${PROJECT}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -derivedDataPath "${DERIVED_DATA}" \
  clean build

# ---------------------------------------------------------------------------
# 2) Determine the marketing version (falls back to 1.0)
# ---------------------------------------------------------------------------
VERSION="$(
  xcodebuild -project "${PROJECT}" -scheme "${SCHEME}" -showBuildSettings 2>/dev/null \
    | awk -F' = ' '/ MARKETING_VERSION = /{print $2; exit}'
)"
VERSION="${VERSION:-1.0}"
echo "==> Marketing version: ${VERSION}"

# ---------------------------------------------------------------------------
# 3) Locate the built .app
# ---------------------------------------------------------------------------
# Preferred location for -derivedDataPath build:
APP_PATH="${DERIVED_DATA}/Build/Products/${CONFIGURATION}/${APP_NAME}"

if [[ ! -d "${APP_PATH}" ]]; then
  echo "==> ${APP_PATH} not found; searching derived data for ${APP_NAME}..."
  APP_PATH="$(
    find "${DERIVED_DATA}" -type d -name "${APP_NAME}" -path "*/${CONFIGURATION}/*" 2>/dev/null \
      | head -n 1
  )"
fi

if [[ -z "${APP_PATH:-}" || ! -d "${APP_PATH}" ]]; then
  echo "ERROR: could not locate ${APP_NAME} under ${DERIVED_DATA}/" >&2
  exit 1
fi
echo "==> Found app: ${APP_PATH}"

# ---------------------------------------------------------------------------
# 4) Stage the .app into a clean directory for packaging
# ---------------------------------------------------------------------------
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/grokcode-dmg.XXXXXX")"
trap 'rm -rf "${STAGING_DIR}"' EXIT

echo "==> Staging app into ${STAGING_DIR}"
cp -R "${APP_PATH}" "${STAGING_DIR}/"

# Convenience: drop an /Applications symlink so the DMG offers a drag target.
ln -s /Applications "${STAGING_DIR}/Applications" || true

# ---------------------------------------------------------------------------
# 5) Build the DMG with hdiutil (dependency-free, compressed UDZO)
# ---------------------------------------------------------------------------
mkdir -p "${DIST_DIR}"
DMG_PATH="${DIST_DIR}/GrokCode-${VERSION}.dmg"

echo "==> Creating ${DMG_PATH}"
hdiutil create \
  -volname "${VOLNAME}" \
  -srcfolder "${STAGING_DIR}" \
  -ov \
  -format UDZO \
  "${DMG_PATH}"

echo ""
echo "==> Done: ${DMG_PATH}"
echo ""

# ---------------------------------------------------------------------------
# Nicer alternative (optional) — `create-dmg` (Homebrew) for a styled DMG
# window with custom background, icon positions, etc:
#
#   brew install create-dmg
#   create-dmg \
#     --volname "GrokCode" \
#     --window-pos 200 120 --window-size 600 400 \
#     --icon-size 100 \
#     --icon "GrokCode.app" 150 190 \
#     --hide-extension "GrokCode.app" \
#     --app-drop-link 450 190 \
#     "dist/GrokCode-${VERSION}.dmg" \
#     "${STAGING_DIR}/"
# ---------------------------------------------------------------------------

# ===========================================================================
# NEXT STEPS — CODE SIGNING & NOTARIZATION  (manual; needs Apple Developer creds)
# ===========================================================================
# These are intentionally NOT automated here because they require your Apple
# Developer account: a "Developer ID Application" certificate in your keychain
# and notarytool credentials. Unsigned builds will trigger Gatekeeper warnings
# ("cannot be opened because the developer cannot be verified") on other Macs.
#
# 1) Code-sign the .app with your Developer ID (hardened runtime enabled):
#
#      codesign --deep --force --options runtime --timestamp \
#        --sign "Developer ID Application: Your Name (TEAMID)" \
#        "${APP_PATH}"
#
#    Verify:
#      codesign --verify --deep --strict --verbose=2 "${APP_PATH}"
#      spctl -a -vvv --type execute "${APP_PATH}"
#
#    (Re-run steps 4–5 above to repackage the SIGNED .app into the DMG.)
#
# 2) Store notarytool credentials once (keychain profile):
#
#      xcrun notarytool store-credentials "GrokCodeNotary" \
#        --apple-id "you@example.com" \
#        --team-id "TEAMID" \
#        --password "app-specific-password"
#
# 3) Notarize the DMG and wait for the result:
#
#      xcrun notarytool submit "${DMG_PATH}" \
#        --keychain-profile "GrokCodeNotary" \
#        --wait
#
# 4) Staple the notarization ticket to the DMG (and/or the .app):
#
#      xcrun stapler staple "${DMG_PATH}"
#      xcrun stapler validate "${DMG_PATH}"
#
# After stapling, the DMG opens cleanly on any Mac without Gatekeeper prompts.
# ===========================================================================
