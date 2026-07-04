#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT/Codessa.xcodeproj"
SCHEME="Codessa"
PUBLISH_REPO="${PUBLISH_REPO:-LogicLeapLtd/grokcode}"
DERIVED_DATA="${DERIVED_DATA:-$ROOT/.build-agent-finalize}"
MODE=""
DRY_RUN=0
NOTES_FILE=""

usage() {
  cat <<'USAGE'
Usage: scripts/finalize-codex-session.sh (--handoff | --publish) [--notes-file FILE] [--dry-run]

Mandatory Codessa session closure gate:
  --handoff   require clean git state, build, then drop a Release app for the running app's "New build ready" prompt
  --publish   require clean git state, build/package DMG, push release source branch, create GitHub release

Environment:
  PUBLISH_REPO   GitHub repo for releases (default: LogicLeapLtd/grokcode)
  DERIVED_DATA   private derived data path for the validation build
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --handoff|--local-update)
      MODE="handoff"
      ;;
    --publish)
      MODE="publish"
      ;;
    --notes-file)
      NOTES_FILE="${2:-}"
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if [[ -z "$MODE" ]]; then
  echo "ERROR: choose --handoff or --publish. A Codessa coding session cannot end with only local source changes." >&2
  usage >&2
  exit 2
fi

cd "$ROOT"

if [[ -n "$(git status --porcelain --untracked-files=all)" ]]; then
  echo "ERROR: working tree is not clean. Commit or intentionally remove every change before finalizing." >&2
  git status --short --branch --untracked-files=all >&2
  exit 1
fi

git diff --check

VERSION="$(
  xcodebuild -project "$PROJECT" -scheme "$SCHEME" -showBuildSettings 2>/dev/null \
    | awk -F' = ' '/ MARKETING_VERSION = /{print $2; exit}'
)"
BUILD="$(
  xcodebuild -project "$PROJECT" -scheme "$SCHEME" -showBuildSettings 2>/dev/null \
    | awk -F' = ' '/ CURRENT_PROJECT_VERSION = /{print $2; exit}'
)"

if [[ -z "${VERSION:-}" ]]; then
  echo "ERROR: could not read MARKETING_VERSION from $PROJECT" >&2
  exit 1
fi

echo "==> Finalizing Codessa ${VERSION} (${BUILD:-unknown}) via $MODE"
echo "==> Validation build"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" \
  build

if [[ "$MODE" == "handoff" ]]; then
  echo "==> Dropping Release local update handoff"
  CONFIGURATION=Release "$ROOT/scripts/drop-local-update.sh"
  echo "==> Handoff complete. The running /Applications/Codessa.app should prompt with New build ready."
  exit 0
fi

command -v gh >/dev/null 2>&1 || {
  echo "ERROR: gh CLI is required to publish a release." >&2
  exit 1
}

TAG="v${VERSION}"
SOURCE_BRANCH="release/${TAG}"
DMG="$ROOT/dist/Codessa-${VERSION}.dmg"

if gh release view "$TAG" --repo "$PUBLISH_REPO" >/dev/null 2>&1; then
  echo "ERROR: release $TAG already exists on $PUBLISH_REPO. Bump MARKETING_VERSION before publishing." >&2
  exit 1
fi

echo "==> Building DMG"
"$ROOT/scripts/build-dmg.sh"

if [[ ! -f "$DMG" ]]; then
  echo "ERROR: expected DMG not found at $DMG" >&2
  exit 1
fi

TMP_NOTES=""
if [[ -n "$NOTES_FILE" ]]; then
  RELEASE_NOTES="$NOTES_FILE"
else
  TMP_NOTES="$(mktemp "${TMPDIR:-/tmp}/codessa-release-notes.XXXXXX.md")"
  RELEASE_NOTES="$TMP_NOTES"
  awk -v version="$VERSION" '
    BEGIN { capture = 0 }
    $0 ~ "^## \\[" version "(\\.0)?\\]" { capture = 1; next }
    capture && $0 ~ "^## \\[" { exit }
    capture { print }
  ' CHANGELOG.md > "$RELEASE_NOTES"
  if [[ ! -s "$RELEASE_NOTES" ]]; then
    printf 'Codessa %s production release.\n' "$VERSION" > "$RELEASE_NOTES"
  fi
fi

echo "==> DMG checksum"
shasum -a 256 "$DMG"

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "DRY RUN: would push HEAD to $SOURCE_BRANCH and create $TAG on $PUBLISH_REPO with $DMG"
  [[ -n "$TMP_NOTES" ]] && rm -f "$TMP_NOTES"
  exit 0
fi

echo "==> Pushing release source branch $SOURCE_BRANCH"
git push "https://github.com/${PUBLISH_REPO}.git" HEAD:"refs/heads/${SOURCE_BRANCH}"

echo "==> Creating GitHub release $TAG"
gh release create "$TAG" \
  --repo "$PUBLISH_REPO" \
  --target "$SOURCE_BRANCH" \
  --title "Codessa ${VERSION}" \
  --notes-file "$RELEASE_NOTES" \
  "$DMG"

echo "==> Verifying latest release"
gh release view "$TAG" --repo "$PUBLISH_REPO" --json tagName,publishedAt,url,assets

[[ -n "$TMP_NOTES" ]] && rm -f "$TMP_NOTES"
echo "==> Published Codessa ${VERSION}"
