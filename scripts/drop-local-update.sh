#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCK_DIR="/tmp/codessa-local-update-drop.lock"
DERIVED_DATA="${DERIVED_DATA:-$ROOT/.build-agent-local-update}"
PROJECT="$ROOT/Codessa.xcodeproj"
SCHEME="Codessa"
CONFIGURATION="${CONFIGURATION:-Debug}"
APP_NAME="Codessa.app"
SOURCE_APP="$DERIVED_DATA/Build/Products/$CONFIGURATION/$APP_NAME"
PENDING_DIR="$HOME/Library/Application Support/Codessa/PendingUpdate"
DEST_APP="$PENDING_DIR/$APP_NAME"
INCOMING="$PENDING_DIR/.Codessa.app.incoming.$$"

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  echo "Another Codessa local-update drop is already running: $LOCK_DIR" >&2
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

mkdir -p "$PENDING_DIR"
rm -rf "$INCOMING"

echo "Dropping local update at $DEST_APP"
/usr/bin/ditto "$SOURCE_APP" "$INCOMING"
/usr/bin/xattr -dr com.apple.quarantine "$INCOMING" 2>/dev/null || true
rm -rf "$DEST_APP"
mv "$INCOMING" "$DEST_APP"
/usr/bin/touch "$DEST_APP"

echo "Local Codessa update is ready. The running /Applications/Codessa.app will prompt from the bottom right."
