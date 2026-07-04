#!/usr/bin/env bash
# Enforced versioned handoff (see CLAUDE.md / AGENTS.md NON-NEGOTIABLE #0):
# after any change lands in the Codessa repo, ALWAYS cut a NEW versioned build
# and drop it as a PendingUpdate so the running /Applications/Codessa.app offers
# "New build ready". Wired to the Claude Code Stop hook so it fires after every
# turn — but it only acts when HEAD actually moved, so plain conversation turns
# are a cheap no-op. QA status is irrelevant here: every change gets a build.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAMP="$ROOT/.build-agent-local-update/.last-handoff-sha"
PBXPROJ="$ROOT/Codessa.xcodeproj/project.pbxproj"

cd "$ROOT"

# No commits yet / not a repo → nothing to hand off.
HEAD_SHA="$(git rev-parse HEAD 2>/dev/null || true)"
[[ -z "$HEAD_SHA" ]] && exit 0

# Skip while the working tree is dirty — never hand off (or version-bump on top
# of) a half-finished edit, and never touch another agent's uncommitted work.
if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
  echo "[auto-handoff] working tree dirty — deferring versioned build until it's committed." >&2
  exit 0
fi

# Already built for this exact commit → nothing to do.
if [[ -f "$STAMP" && "$(cat "$STAMP" 2>/dev/null)" == "$HEAD_SHA" ]]; then
  exit 0
fi

# 1. Bump the build number (CURRENT_PROJECT_VERSION) in every config block so the
#    dropped build is a genuinely NEW version the updater/About screen can tell
#    apart. Commit the bump path-scoped (never `git add -A`) so it's recoverable.
CUR="$(grep -Eo 'CURRENT_PROJECT_VERSION = [0-9]+;' "$PBXPROJ" | grep -Eo '[0-9]+' | sort -n | tail -1)"
if [[ -z "$CUR" ]]; then
  echo "[auto-handoff] could not read CURRENT_PROJECT_VERSION — aborting." >&2
  exit 1
fi
NEXT=$(( CUR + 1 ))
/usr/bin/sed -i '' -E "s/CURRENT_PROJECT_VERSION = [0-9]+;/CURRENT_PROJECT_VERSION = ${NEXT};/g" "$PBXPROJ"
MARKETING="$(grep -m1 -Eo 'MARKETING_VERSION = [^;]+;' "$PBXPROJ" | sed -E 's/MARKETING_VERSION = ([^;]+);/\1/')"

git add "$PBXPROJ"
git commit -q -m "chore: bump build to ${MARKETING} (${NEXT}) for versioned handoff [auto]

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
NEW_HEAD="$(git rev-parse HEAD)"

echo "[auto-handoff] cutting versioned build ${MARKETING} (${NEXT})…" >&2
if "$ROOT/scripts/drop-local-update.sh" >&2; then
  mkdir -p "$(dirname "$STAMP")"
  printf '%s' "$NEW_HEAD" > "$STAMP"
  echo "[auto-handoff] versioned build ${MARKETING} (${NEXT}) dropped for $NEW_HEAD." >&2
else
  echo "[auto-handoff] drop-local-update.sh failed for build ${NEXT}." >&2
  exit 1
fi
