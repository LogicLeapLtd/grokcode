#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCK_DIR="/tmp/codessa-canonical-install.lock"
DERIVED_DATA="${DERIVED_DATA:-$ROOT/.build-final}"
PROJECT="$ROOT/Codessa.xcodeproj"
SCHEME="Codessa"
CONFIGURATION="${CONFIGURATION:-Debug}"
APP_NAME="Codessa.app"
SOURCE_APP="$DERIVED_DATA/Build/Products/$CONFIGURATION/$APP_NAME"
DEST_APP="/Applications/$APP_NAME"
INCOMING="/Applications/.Codessa.app.incoming.$$"
BACKUP="/Applications/.Codessa.app.previous.$(date +%Y%m%d%H%M%S)"
LAUNCH=0
PIN_DOCK=0

for arg in "$@"; do
  case "$arg" in
    --launch) LAUNCH=1 ;;
    --dock) PIN_DOCK=1 ;;
    *)
      echo "Unknown argument: $arg" >&2
      echo "Usage: $0 [--launch] [--dock]" >&2
      exit 2
      ;;
  esac
done

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  echo "Another canonical Codessa install is already running: $LOCK_DIR" >&2
  exit 1
fi
trap 'rm -rf "$LOCK_DIR" "$INCOMING"' EXIT

cd "$ROOT"

echo "Building $SCHEME ($CONFIGURATION) into $DERIVED_DATA"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA" \
  build

if [[ ! -d "$SOURCE_APP" ]]; then
  echo "Built app not found at $SOURCE_APP" >&2
  exit 1
fi

echo "Copying built app to staging bundle"
rm -rf "$INCOMING"
/usr/bin/ditto "$SOURCE_APP" "$INCOMING"
/usr/bin/xattr -dr com.apple.quarantine "$INCOMING" 2>/dev/null || true

if pgrep -x Codessa >/dev/null 2>&1; then
  echo "Quitting running Codessa before replacing /Applications bundle"
  /usr/bin/osascript -e 'tell application "Codessa" to quit' >/dev/null 2>&1 || true
  sleep 2
  pgrep -x Codessa >/dev/null 2>&1 && /usr/bin/pkill -x Codessa || true
fi

echo "Installing to $DEST_APP"
if [[ -d "$DEST_APP" ]]; then
  rm -rf "$BACKUP"
  mv "$DEST_APP" "$BACKUP"
fi

if mv "$INCOMING" "$DEST_APP"; then
  rm -rf "$BACKUP"
else
  if [[ -d "$BACKUP" ]]; then
    mv "$BACKUP" "$DEST_APP"
  fi
  echo "Install failed; restored previous Codessa bundle if one existed." >&2
  exit 1
fi

if [[ "$PIN_DOCK" -eq 1 ]]; then
  if command -v dockutil >/dev/null 2>&1; then
    dockutil --remove Codessa --no-restart >/dev/null 2>&1 || true
    dockutil --add "$DEST_APP" --no-restart
    killall Dock >/dev/null 2>&1 || true
  else
    if ! defaults read com.apple.dock persistent-apps 2>/dev/null | grep -q "file:///Applications/Codessa.app/"; then
      defaults write com.apple.dock persistent-apps -array-add \
        '<dict>
          <key>tile-data</key>
          <dict>
            <key>file-data</key>
            <dict>
              <key>_CFURLString</key>
              <string>file:///Applications/Codessa.app/</string>
              <key>_CFURLStringType</key>
              <integer>15</integer>
            </dict>
            <key>file-label</key>
            <string>Codessa</string>
          </dict>
          <key>tile-type</key>
          <string>file-tile</string>
        </dict>'
      killall Dock >/dev/null 2>&1 || true
    fi
  fi
fi

if [[ "$LAUNCH" -eq 1 ]]; then
  echo "Launching $DEST_APP"
  open -n "$DEST_APP"
fi

echo "Canonical Codessa installed at $DEST_APP"
