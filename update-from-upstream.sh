#!/usr/bin/env sh
#
# Fast-forward local main to upstream/main. Only main is ever updated.
#
# Usage: ./update-from-upstream.sh
# See UPDATE-FROM-UPSTREAM.md.

set -eu

REMOTE="upstream"
BRANCH="main"
TARGET="$REMOTE/$BRANCH"

# ── Pretty output (only when attached to a terminal) ─────────────────────────
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  BOLD=$(printf '\033[1m'); DIM=$(printf '\033[2m'); RESET=$(printf '\033[0m')
  RED=$(printf '\033[31m'); GREEN=$(printf '\033[32m')
  BLUE=$(printf '\033[34m'); GREY=$(printf '\033[90m')
else
  BOLD=""; DIM=""; RESET=""; RED=""; GREEN=""; BLUE=""; GREY=""
fi

step() { printf '%s==>%s %s%s%s\n' "$BLUE" "$RESET" "$BOLD" "$*" "$RESET"; }
ok()   { printf '%s ✔%s  %s\n' "$GREEN" "$RESET" "$*"; }
die()  { printf '%s ✘%s  %s\n' "$RED" "$RESET" "$*" >&2; exit 1; }

# Run git with its output (stdout + stderr) rendered in grey.
# Git's own colors are disabled so they don't override the grey.
git_grey() {
  rc=0
  printf '%s' "$GREY"
  git -c color.ui=never "$@" || rc=$?
  printf '%s' "$RESET"
  return "$rc"
}

# ── Preflight ────────────────────────────────────────────────────────────────
[ "$#" -eq 0 ] || die "Usage: $0   (takes no arguments; always updates $BRANCH)"
git rev-parse --git-dir >/dev/null 2>&1 || die "Not inside a git repository."
git remote get-url "$REMOTE" >/dev/null 2>&1 \
  || die "Remote '$REMOTE' is not configured. Add it with: git remote add $REMOTE <url>"

CURRENT=$(git symbolic-ref --quiet --short HEAD) || die "Detached HEAD; check out a branch first."
[ "$CURRENT" = "$BRANCH" ] \
  || die "On branch '$CURRENT'; only '$BRANCH' can be updated. Run: git switch $BRANCH"

# ── Fetch ────────────────────────────────────────────────────────────────────
step "Fetching $REMOTE ${DIM}($(git remote get-url "$REMOTE"))${RESET}"
git_grey fetch --prune "$REMOTE"
git rev-parse --verify --quiet "$TARGET" >/dev/null || die "Branch '$TARGET' does not exist."

AHEAD=$(git rev-list --count "$TARGET..HEAD")
BEHIND=$(git rev-list --count "HEAD..$TARGET")

if [ "$BEHIND" -eq 0 ]; then
  ok "Already up to date with $TARGET."
  exit 0
fi

[ "$AHEAD" -eq 0 ] \
  || die "'$CURRENT' has $AHEAD local commit(s) not in $TARGET; fast-forward impossible."

# ── Merge ────────────────────────────────────────────────────────────────────
step "Incoming $BEHIND commit(s) from $TARGET"
git --no-pager log --oneline --no-decorate "HEAD..$TARGET" | sed 's/^/    /'

step "Fast-forwarding $CURRENT"
git_grey merge --ff-only "$TARGET"
ok "$CURRENT is now at $(git rev-parse --short HEAD)."
