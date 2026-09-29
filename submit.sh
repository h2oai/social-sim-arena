#!/usr/bin/env sh
#
# Sign and POST forecast answers to the Social Simulation Arena
# (https://social-simulation-arena.com/docs.html#signed-forecast-submission).
#
# Usage: ./submit.sh answer.json [answer.json ...]
# See SUBMIT.md.
#
# Each answer is one forecast document: {"round_id", "entrant", and a topline,
# profile or ranking}. It is checked locally before anything is signed.
#
# Every answer gets its own signed request file, keyed by round, entrant and
# answer content: re-running with the same answer replays the exact signed bytes
# and returns the original receipt; a changed answer is signed afresh.
#
# Environment:
#   SSA_KEY             private key            (default: ~/.ssh/bench-ssa-key)
#   SSA_KEY_ID          registered key id      (default: bench-ssa-key)
#   SSA_ENTRANT         must match "entrant" in each answer (default: taken from it)
#   SSA_REQUEST_DIR     signed request store   (default: .submissions, kept out of Git)
#   SSA_KEY_PASSPHRASE  for a passphrase-protected key
#   SSA_DRY_RUN=1       validate and print the command, send nothing

set -eu

KEY="${SSA_KEY:-$HOME/.ssh/bench-ssa-key}"
KEY_ID="${SSA_KEY_ID:-bench-ssa-key}"
REQUEST_DIR="${SSA_REQUEST_DIR:-.submissions}"
DRY_RUN="${SSA_DRY_RUN:-}"

# ── Pretty output (only when attached to a terminal) ─────────────────────────
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  BOLD=$(printf '\033[1m'); RESET=$(printf '\033[0m')
  RED=$(printf '\033[31m'); GREEN=$(printf '\033[32m'); YELLOW=$(printf '\033[33m'); BLUE=$(printf '\033[34m')
else
  BOLD=""; RESET=""; RED=""; GREEN=""; YELLOW=""; BLUE=""
fi

step() { printf '%s==>%s %s%s%s\n' "$BLUE" "$RESET" "$BOLD" "$*" "$RESET"; }
ok()   { printf '%s ✔%s  %s\n' "$GREEN" "$RESET" "$*"; }
warn() { printf '%s !%s  %s\n' "$YELLOW" "$RESET" "$*"; }
fail() { printf '%s ✘%s  %s\n' "$RED" "$RESET" "$*" >&2; }
die()  { fail "$*"; exit 1; }

[ $# -gt 0 ] || { echo "Usage: $0 answer.json [answer.json ...]" >&2; exit 2; }

# Resolve answer paths before moving to the repo root, where the tool lives.
ANSWERS=""
for f in "$@"; do
  [ -f "$f" ] || die "Answer file not found: $f"
  ANSWERS="$ANSWERS$(cd "$(dirname "$f")" && pwd)/$(basename "$f")
"
done
cd "$(dirname "$0")"

# ── Preflight ────────────────────────────────────────────────────────────────
command -v uv >/dev/null 2>&1 || die "uv is required (the tool needs requests + cryptography): brew install uv"
[ -f "$KEY" ] || die "Private key not found: $KEY (set SSA_KEY)"
case "$(ls -l "$KEY")" in
  -rw-------*|-r--------*) ;;
  *) die "Private key $KEY is readable by others; run: chmod 600 $KEY" ;;
esac

mkdir -p "$REQUEST_DIR" 2>/dev/null && chmod 700 "$REQUEST_DIR"
if git rev-parse --git-dir >/dev/null 2>&1 && ! git check-ignore -q "$REQUEST_DIR/x"; then
  case "$REQUEST_DIR" in
    /*) ;;  # outside the repo
    *) echo "/$REQUEST_DIR/" >> "$(git rev-parse --git-dir)/info/exclude"
       warn "Added /$REQUEST_DIR/ to .git/info/exclude (signed requests hold plaintext answers)." ;;
  esac
fi

# Prints "<round_id> <entrant> <sha256[:16]>" for a valid answer, or the reason
# it would be rejected. Parsing reuses the Arena's own intake rules.
check_answer() {
  uv run --quiet python - "$1" "${SSA_ENTRANT:-}" <<'PY'
import hashlib, math, re, sys
from pathlib import Path
from ssa.signed_forecasts import IntakeError, parse_body

path, expected = sys.argv[1], sys.argv[2]
raw = Path(path).read_bytes()
try:
    body = parse_body(raw)
except IntakeError as e:
    sys.exit(f"{e.code}: duplicate keys, NaN or not a JSON object")
ident = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}")
for field in ("round_id", "entrant"):
    if not isinstance(body.get(field), str) or not ident.fullmatch(body[field]):
        sys.exit(f"{field} is missing or not a plain id")
if expected and body["entrant"] != expected:
    sys.exit(f"entrant {body['entrant']!r} does not match SSA_ENTRANT={expected}")
kinds = [k for k in ("topline", "profile", "ranking") if k in body]
if len(kinds) != 1:
    sys.exit("expected exactly one of topline, profile, ranking")
top = body.get("topline")
if top is not None:
    num = lambda v: isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(v)
    if isinstance(top, dict) and "quantiles" in top:
        if not isinstance(top["quantiles"], dict) or "0.5" not in top["quantiles"]:
            sys.exit('topline quantiles must include "0.5"')
    elif not (isinstance(top, dict) and num(top.get("mean")) and num(top.get("sd")) and top["sd"] > 0):
        sys.exit("topline must be {mean, sd} with sd > 0 (a point estimate is rejected)")
print(body["round_id"], body["entrant"], hashlib.sha256(raw).hexdigest()[:16])
PY
}

# ── Submit ───────────────────────────────────────────────────────────────────
failed=0
while IFS= read -r answer; do
  [ -n "$answer" ] || continue
  step "$answer"
  info=$(check_answer "$answer" 2>&1) || { fail "$info"; failed=$((failed + 1)); continue; }
  set -- $info
  round="$1"; entrant="$2"; digest="$3"
  request="$REQUEST_DIR/$round/$entrant-$digest.json"
  mkdir -p "$REQUEST_DIR/$round"

  [ -f "$request" ] && warn "Replaying saved request for this exact answer (returns the original receipt)."
  set -- uv run --quiet python tools/submit_signed_forecast.py \
    --entrant "$entrant" --key-id "$KEY_ID" --key "$KEY" \
    --answer "$answer" --request-file "$request"

  if [ -n "$DRY_RUN" ]; then
    echo "$*"
  elif "$@"; then
    ok "$round accepted for $entrant"
  else
    fail "$round rejected (request kept at $request)"; failed=$((failed + 1))
  fi
done <<EOF
$ANSWERS
EOF

[ "$failed" -eq 0 ] || die "$failed submission(s) failed."
