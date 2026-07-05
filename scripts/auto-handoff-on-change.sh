#!/usr/bin/env bash
# Enforced versioned publish (see CLAUDE.md / AGENTS.md NON-NEGOTIABLE #0):
# after any change lands in the Codessa repo, ALWAYS capture the current tree,
# bump to a NEW version, and publish a GitHub release so /Applications/Codessa.app
# can install it through Check for Updates. Wired to the Claude Code Stop hook so
# it fires after every turn — but it only acts when HEAD actually moved, so plain
# conversation turns are a cheap no-op. QA status and dirty-tree state are
# irrelevant here: every change gets a published update.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAMP="$ROOT/.build-agent-local-update/.last-published-sha"
PBXPROJ="$ROOT/Codessa.xcodeproj/project.pbxproj"

cd "$ROOT"

# No commits yet / not a repo → nothing to publish.
HEAD_SHA="$(git rev-parse HEAD 2>/dev/null || true)"
[[ -z "$HEAD_SHA" ]] && exit 0

# Dirty trees are not a blocker. Capture the exact current tree first so the
# versioned build always corresponds to a recoverable commit instead of silently
# deferring and leaving Josh with no installable update.
if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
  echo "[auto-handoff] working tree dirty — capturing before versioned build." >&2
  git status --short --branch --untracked-files=all >&2
  git add -A
  if ! git diff --cached --quiet; then
    STAMPED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    git commit -q -m "chore: capture dirty tree before versioned handoff [auto]

Automatically captured by auto-handoff-on-change.sh at ${STAMPED_AT} so every Codessa change gets an installable update even when concurrent work left the tree dirty.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
    HEAD_SHA="$(git rev-parse HEAD)"
  fi
fi

# Already built for this exact commit → nothing to do.
if [[ -f "$STAMP" && "$(cat "$STAMP" 2>/dev/null)" == "$HEAD_SHA" ]]; then
  exit 0
fi

# 1. Bump the marketing version and build number in every config block so the
#    GitHub updater sees a genuinely NEW release. Commit the bump path-scoped
#    so it's recoverable.
CUR="$(grep -Eo 'CURRENT_PROJECT_VERSION = [0-9]+;' "$PBXPROJ" | grep -Eo '[0-9]+' | sort -n | tail -1)"
if [[ -z "$CUR" ]]; then
  echo "[auto-handoff] could not read CURRENT_PROJECT_VERSION — aborting." >&2
  exit 1
fi
NEXT=$(( CUR + 1 ))
MARKETING="$(grep -m1 -Eo 'MARKETING_VERSION = [^;]+;' "$PBXPROJ" | sed -E 's/MARKETING_VERSION = ([^;]+);/\1/')"
IFS='.' read -r MAJOR MINOR PATCH_EXTRA <<< "$MARKETING"
PATCH="${PATCH_EXTRA%%[^0-9]*}"
if [[ -z "${MAJOR:-}" || -z "${MINOR:-}" || -z "${PATCH:-}" ]]; then
  echo "[auto-handoff] could not parse MARKETING_VERSION '$MARKETING' — aborting." >&2
  exit 1
fi
NEXT_MARKETING="${MAJOR}.${MINOR}.$(( PATCH + 1 ))"
/usr/bin/sed -i '' -E "s/CURRENT_PROJECT_VERSION = [0-9]+;/CURRENT_PROJECT_VERSION = ${NEXT};/g" "$PBXPROJ"
/usr/bin/sed -i '' -E "s/MARKETING_VERSION = [^;]+;/MARKETING_VERSION = ${NEXT_MARKETING};/g" "$PBXPROJ"

git add "$PBXPROJ"
git commit -q -m "chore: bump version to ${NEXT_MARKETING} (${NEXT}) for updater publish [auto]

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
NEW_HEAD="$(git rev-parse HEAD)"

echo "[auto-handoff] publishing versioned update ${NEXT_MARKETING} (${NEXT})…" >&2
if DERIVED_DATA="$ROOT/.build-agent-auto-publish" "$ROOT/scripts/finalize-codex-session.sh" --publish >&2; then
  mkdir -p "$(dirname "$STAMP")"
  printf '%s' "$NEW_HEAD" > "$STAMP"
  echo "[auto-handoff] versioned update ${NEXT_MARKETING} (${NEXT}) published for $NEW_HEAD." >&2
else
  echo "[auto-handoff] publish failed for ${NEXT_MARKETING} (${NEXT})." >&2
  exit 1
fi
