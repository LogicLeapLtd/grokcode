#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT/Codessa.xcodeproj"
SCHEME="Codessa"
PUBLISH_REPO="${PUBLISH_REPO:-LogicLeapLtd/grokcode}"
DERIVED_DATA="${DERIVED_DATA:-$ROOT/.build-agent-finalize}"
PRODUCTION_BRANCH="${PRODUCTION_BRANCH:-production}"
RECOVERY_AUDIT_SINCE="${RECOVERY_AUDIT_SINCE:-24 hours ago}"
MODE=""
DRY_RUN=0
NOTES_FILE=""

usage() {
  cat <<'USAGE'
Usage: scripts/finalize-codex-session.sh (--handoff | --publish) [--notes-file FILE] [--dry-run]

Mandatory Codessa session closure gate:
  --handoff   capture dirty git state if needed, build, then drop a Release app for the running app's "New build ready" prompt
  --publish   capture dirty git state if needed, build/package DMG, push release source branch, create GitHub release

Environment:
  PUBLISH_REPO   GitHub repo for releases (default: LogicLeapLtd/grokcode)
  DERIVED_DATA   private derived data path for the validation build
  PRODUCTION_BRANCH  moving remote branch that must point at the published commit (default: production)
  RECOVERY_AUDIT_SINCE  lookback for dangling WIP commit warnings (default: 24 hours ago)
USAGE
}

remote_url() {
  printf 'https://github.com/%s.git' "$PUBLISH_REPO"
}

remote_ref_sha() {
  local ref="$1"
  git ls-remote "$(remote_url)" "$ref" | awk '{print $1}'
}

verify_remote_ref() {
  local label="$1"
  local ref="$2"
  local expected="$3"
  local actual
  actual="$(remote_ref_sha "$ref")"
  if [[ "$actual" != "$expected" ]]; then
    echo "ERROR: $label is not published at $expected (actual: ${actual:-missing})." >&2
    exit 1
  fi
  echo "==> Verified $label -> $expected"
}

verify_dmg_version() {
  local dmg="$1"
  local expected_version="$2"
  local expected_build="$3"
  local mount
  mount="$(mktemp -d "${TMPDIR:-/tmp}/codessa-dmg-mount.XXXXXX")"

  hdiutil attach "$dmg" -mountpoint "$mount" -nobrowse -readonly -quiet
  trap 'hdiutil detach "$mount" -quiet >/dev/null 2>&1 || true; rm -rf "$mount"; [[ -n "${TMP_NOTES:-}" ]] && rm -f "$TMP_NOTES"' EXIT

  local app="$mount/Codessa.app"
  if [[ ! -d "$app" ]]; then
    echo "ERROR: mounted DMG does not contain Codessa.app" >&2
    exit 1
  fi

  local actual_version actual_build
  actual_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
  actual_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")"

  hdiutil detach "$mount" -quiet
  rm -rf "$mount"
  trap '[[ -n "${TMP_NOTES:-}" ]] && rm -f "$TMP_NOTES"' EXIT

  if [[ "$actual_version" != "$expected_version" || "$actual_build" != "$expected_build" ]]; then
    echo "ERROR: DMG app version mismatch. Expected ${expected_version} (${expected_build}), got ${actual_version} (${actual_build})." >&2
    exit 1
  fi
  echo "==> Verified DMG contains Codessa ${actual_version} (${actual_build})"
}

print_recent_unreachable_commits() {
  local rows
  rows="$(
    git fsck --no-reflogs --unreachable 2>/dev/null \
      | awk '/unreachable commit/ {print $3}' \
      | while read -r commit; do
          git log --no-walk --since="$RECOVERY_AUDIT_SINCE" --format='%H %ci %s' "$commit" 2>/dev/null || true
        done \
      | sed '/^$/d' \
      | sort
  )"

  if [[ -n "$rows" ]]; then
    echo "==> Recent dangling WIP commits found since '$RECOVERY_AUDIT_SINCE' (audit before deleting build artifacts):"
    echo "$rows"
  else
    echo "==> No recent dangling WIP commits found since '$RECOVERY_AUDIT_SINCE'"
  fi
}

capture_dirty_tree() {
  if [[ -z "$(git status --porcelain --untracked-files=all)" ]]; then
    return 0
  fi

  echo "==> Working tree is dirty; capturing it before finalizing"
  git status --short --branch --untracked-files=all
  git add -A

  if git diff --cached --quiet; then
    echo "==> Dirty-tree capture produced no staged changes"
    return 0
  fi

  local stamp
  stamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  git commit -m "chore: capture dirty tree before Codessa finalization

Automatically captured by finalize-codex-session.sh at ${stamp} so every Codessa code-changing session can produce a versioned handoff or published update even when concurrent work left the tree dirty."
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

capture_dirty_tree

git diff --check
print_recent_unreachable_commits

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
BUILD_DMG_DERIVED_DATA="${BUILD_DMG_DERIVED_DATA:-${DERIVED_DATA}-release}" "$ROOT/scripts/build-dmg.sh"

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
verify_dmg_version "$DMG" "$VERSION" "$BUILD"

HEAD_SHA="$(git rev-parse HEAD)"
if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "DRY RUN: would push $HEAD_SHA to $SOURCE_BRANCH + $PRODUCTION_BRANCH and create $TAG on $PUBLISH_REPO with $DMG"
  [[ -n "$TMP_NOTES" ]] && rm -f "$TMP_NOTES"
  exit 0
fi

echo "==> Pushing release source branch $SOURCE_BRANCH"
git push "$(remote_url)" HEAD:"refs/heads/${SOURCE_BRANCH}"

echo "==> Pushing moving production branch $PRODUCTION_BRANCH"
git push "$(remote_url)" HEAD:"refs/heads/${PRODUCTION_BRANCH}"

echo "==> Creating GitHub release $TAG"
gh release create "$TAG" \
  --repo "$PUBLISH_REPO" \
  --target "$SOURCE_BRANCH" \
  --title "Codessa ${VERSION}" \
  --notes-file "$RELEASE_NOTES" \
  "$DMG"

echo "==> Verifying latest release"
gh release view "$TAG" --repo "$PUBLISH_REPO" --json tagName,publishedAt,url,assets

verify_remote_ref "release source branch $SOURCE_BRANCH" "refs/heads/${SOURCE_BRANCH}" "$HEAD_SHA"
verify_remote_ref "production branch $PRODUCTION_BRANCH" "refs/heads/${PRODUCTION_BRANCH}" "$HEAD_SHA"
verify_remote_ref "release tag $TAG" "refs/tags/${TAG}" "$HEAD_SHA"

LATEST_TAG="$(gh release view --repo "$PUBLISH_REPO" --json tagName --jq '.tagName')"
if [[ "$LATEST_TAG" != "$TAG" ]]; then
  echo "ERROR: latest GitHub release is $LATEST_TAG, expected $TAG." >&2
  exit 1
fi

LOCAL_SHA="$(shasum -a 256 "$DMG" | awk '{print $1}')"
REMOTE_DIGEST="$(gh release view "$TAG" --repo "$PUBLISH_REPO" --json assets --jq ".assets[] | select(.name == \"Codessa-${VERSION}.dmg\") | .digest")"
if [[ "$REMOTE_DIGEST" != "sha256:$LOCAL_SHA" ]]; then
  echo "ERROR: release asset digest mismatch. Expected sha256:$LOCAL_SHA, got ${REMOTE_DIGEST:-missing}." >&2
  exit 1
fi
echo "==> Verified release asset digest sha256:$LOCAL_SHA"

INSTALLED_VERSION=""
if [[ -f "/Applications/Codessa.app/Contents/Info.plist" ]]; then
  INSTALLED_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' /Applications/Codessa.app/Contents/Info.plist 2>/dev/null || true)"
fi
if [[ -n "$INSTALLED_VERSION" && "$INSTALLED_VERSION" != "$VERSION" ]]; then
  echo "==> Update-ready: installed Codessa is $INSTALLED_VERSION; published Codessa is $VERSION"
elif [[ -n "$INSTALLED_VERSION" ]]; then
  echo "==> Installed Codessa already matches published version $VERSION"
else
  echo "==> No installed /Applications/Codessa.app detected; release is published for fresh install"
fi

[[ -n "$TMP_NOTES" ]] && rm -f "$TMP_NOTES"
echo "==> Published Codessa ${VERSION}"
