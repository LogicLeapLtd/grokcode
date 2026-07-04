#!/usr/bin/env bash
# Enforced local-update handoff: after any change lands in the Codessa repo,
# rebuild and drop a PendingUpdate so the running /Applications/Codessa.app
# offers "New build ready". Wired to the Claude Code Stop hook so it fires
# after every turn — but it only rebuilds when HEAD actually moved, so plain
# conversation turns are a cheap no-op.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAMP="$ROOT/.build-agent-local-update/.last-handoff-sha"

cd "$ROOT"

# No commits yet / not a repo → nothing to hand off.
HEAD_SHA="$(git rev-parse HEAD 2>/dev/null || true)"
[[ -z "$HEAD_SHA" ]] && exit 0

# Skip if the working tree is dirty — wait until the change is committed so we
# never hand off a half-finished edit.
if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
  exit 0
fi

# Already dropped a build for this exact commit → nothing to do.
if [[ -f "$STAMP" && "$(cat "$STAMP" 2>/dev/null)" == "$HEAD_SHA" ]]; then
  exit 0
fi

echo "[auto-handoff] HEAD $HEAD_SHA changed since last drop — rebuilding local update…" >&2
if "$ROOT/scripts/drop-local-update.sh" >&2; then
  mkdir -p "$(dirname "$STAMP")"
  printf '%s' "$HEAD_SHA" > "$STAMP"
  echo "[auto-handoff] Local update dropped for $HEAD_SHA." >&2
else
  echo "[auto-handoff] drop-local-update.sh failed for $HEAD_SHA." >&2
  exit 1
fi
