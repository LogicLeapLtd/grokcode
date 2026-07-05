#!/usr/bin/env bash
# Enforced updater-visible publish (see CLAUDE.md / AGENTS.md NON-NEGOTIABLE #0):
# after any change lands in the Codessa repo, ALWAYS capture the current tree,
# bump to a NEW version, and publish a GitHub release so /Applications/Codessa.app
# can see it through Check for Updates. Wired to the Claude Code Stop hook so it
# fires after every turn, but only acts when HEAD moved. QA status and dirty-tree
# state are irrelevant here: every change gets a release.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAMP="$ROOT/.build-agent-local-update/.last-publish-sha"
PBXPROJ="$ROOT/Codessa.xcodeproj/project.pbxproj"
CHANGELOG="$ROOT/CHANGELOG.md"

bump_patch_version() {
  local version="$1"
  local major minor patch
  IFS='.' read -r major minor patch <<<"$version"
  if [[ "$major" =~ ^[0-9]+$ && "$minor" =~ ^[0-9]+$ && "$patch" =~ ^[0-9]+$ ]]; then
    printf '%s.%s.%s' "$major" "$minor" "$((patch + 1))"
  else
    printf '%s' "$version"
  fi
}

insert_release_note() {
  local version="$1"
  local date_stamp="$2"
  if [[ ! -f "$CHANGELOG" ]] || grep -q "^## \\[$version\\]" "$CHANGELOG"; then
    return 0
  fi

  local tmp
  tmp="$(mktemp "${TMPDIR:-/tmp}/codessa-changelog.XXXXXX")"
  {
    IFS= read -r first_line || true
    printf '%s\n\n' "$first_line"
    printf '## [%s] - %s\n\n' "$version" "$date_stamp"
    printf -- '- Automatic updater-visible release for the latest Codessa code changes.\n\n'
    cat
  } < "$CHANGELOG" > "$tmp"
  mv "$tmp" "$CHANGELOG"
}

cd "$ROOT"

# No commits yet / not a repo -> nothing to publish.
HEAD_SHA="$(git rev-parse HEAD 2>/dev/null || true)"
[[ -z "$HEAD_SHA" ]] && exit 0

# Dirty trees are not a blocker. Capture the exact current tree first so the
# published release always corresponds to a recoverable commit.
if [[ -n "$(git status --porcelain --untracked-files=all 2>/dev/null)" ]]; then
  echo "[auto-handoff] working tree dirty - capturing before updater publish." >&2
  git status --short --branch --untracked-files=all >&2
  git add -A
  if ! git diff --cached --quiet; then
    STAMPED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    git commit -q -m "chore: capture dirty tree before updater publish [auto]

Automatically captured by auto-handoff-on-change.sh at ${STAMPED_AT} so every Codessa change gets an updater-visible release even when concurrent work left the tree dirty.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
    HEAD_SHA="$(git rev-parse HEAD)"
  fi
fi

# Already published for this exact commit -> nothing to do.
if [[ -f "$STAMP" && "$(cat "$STAMP" 2>/dev/null)" == "$HEAD_SHA" ]]; then
  exit 0
fi

CUR="$(grep -Eo 'CURRENT_PROJECT_VERSION = [0-9]+;' "$PBXPROJ" | grep -Eo '[0-9]+' | sort -n | tail -1)"
if [[ -z "$CUR" ]]; then
  echo "[auto-handoff] could not read CURRENT_PROJECT_VERSION - aborting." >&2
  exit 1
fi

MARKETING="$(grep -m1 -Eo 'MARKETING_VERSION = [^;]+;' "$PBXPROJ" | sed -E 's/MARKETING_VERSION = ([^;]+);/\1/')"
if [[ -z "$MARKETING" ]]; then
  echo "[auto-handoff] could not read MARKETING_VERSION - aborting." >&2
  exit 1
fi

NEXT=$((CUR + 1))
NEXT_MARKETING="$(bump_patch_version "$MARKETING")"
TODAY="$(date '+%Y-%m-%d')"

/usr/bin/sed -i '' -E "s/CURRENT_PROJECT_VERSION = [0-9]+;/CURRENT_PROJECT_VERSION = ${NEXT};/g" "$PBXPROJ"
/usr/bin/sed -i '' -E "s/MARKETING_VERSION = [^;]+;/MARKETING_VERSION = ${NEXT_MARKETING};/g" "$PBXPROJ"
insert_release_note "$NEXT_MARKETING" "$TODAY"

git add "$PBXPROJ" "$CHANGELOG"
git commit -q -m "chore: bump Codessa to ${NEXT_MARKETING} (${NEXT}) for updater publish [auto]

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"

echo "[auto-handoff] publishing Codessa ${NEXT_MARKETING} (${NEXT})..." >&2
if "$ROOT/scripts/finalize-codex-session.sh" --publish >&2; then
  NEW_HEAD="$(git rev-parse HEAD)"
  mkdir -p "$(dirname "$STAMP")"
  printf '%s' "$NEW_HEAD" > "$STAMP"
  echo "[auto-handoff] Codessa ${NEXT_MARKETING} (${NEXT}) published for $NEW_HEAD." >&2
else
  echo "[auto-handoff] publish failed for Codessa ${NEXT_MARKETING} (${NEXT})." >&2
  exit 1
fi
