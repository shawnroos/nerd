#!/usr/bin/env bash
# nerd SessionStart status hook (type:command).
#
# Emits a single SessionStart additionalContext line ONLY when there is something
# actionable in the research backlog or intern state; otherwise prints nothing and
# exits 0. Replaces a type:prompt hook (removed 2026-06-28) that injected prose into
# every session start.
#
# Safety (KTD-4): under `set -euo pipefail` a zero-match `grep -c` exits non-zero;
# every fallible command is neutralized with `|| true` and the script always ends at
# `exit 0`, so the no-backlog / nothing-actionable path can never abort or break the
# session — the exact failure class this conversion removes.
set -euo pipefail

BACKLOG=".claude/nerd.local.md"
GLOBAL_STATE="$HOME/.claude/plugins/nerd/intern/state.json"
PROJECT_STATE=".nerd/intern/state.json"

messages=()

# --- Research backlog (only if the file exists) ---
if [ -f "$BACKLOG" ]; then
  proposed=$(grep -c '^[[:space:]]*status: proposed' "$BACKLOG" 2>/dev/null || true)
  proposed=${proposed:-0}
  if [ "$proposed" -gt 0 ] 2>/dev/null; then
    messages+=("Nerd: ${proposed} proposal(s) in backlog. Run /nerd to start.")
  fi

  # Stale 'running' experiments whose worktree is missing (possible crashed session).
  running=$(grep -c '^[[:space:]]*status: running' "$BACKLOG" 2>/dev/null || true)
  running=${running:-0}
  if [ "$running" -gt 0 ] 2>/dev/null; then
    worktrees=$(git worktree list 2>/dev/null | grep -c 'nerd-' || true)
    worktrees=${worktrees:-0}
    if [ "$running" -gt "$worktrees" ] 2>/dev/null; then
      messages+=("Nerd: ${running} experiment(s) marked running but worktrees missing (possible crashed session). Run /nerd to recover.")
    fi
  fi
fi

# --- Intern state: recent promotion (global state preferred, else project) ---
STATE=""
if [ -f "$GLOBAL_STATE" ]; then
  STATE="$GLOBAL_STATE"
elif [ -f "$PROJECT_STATE" ]; then
  STATE="$PROJECT_STATE"
fi
if [ -n "$STATE" ]; then
  intern_msg=$(python3 - "$STATE" <<'PY' 2>/dev/null || true
import json, sys, time, datetime
try:
    with open(sys.argv[1]) as f:
        data = json.load(f)
except Exception:
    sys.exit(0)
if not isinstance(data, dict):
    sys.exit(0)
now = time.time()
week = 7 * 24 * 3600
out = []
for name, t in (data.get("tasks", {}) or {}).items():
    if not isinstance(t, dict):
        continue
    pa = t.get("promoted_at")
    if not pa:
        continue
    ts = None
    if isinstance(pa, (int, float)):
        ts = float(pa)
    else:
        try:
            ts = datetime.datetime.fromisoformat(str(pa).replace("Z", "+00:00")).timestamp()
        except Exception:
            ts = None
    if ts is not None and 0 <= (now - ts) <= week:
        out.append("Intern: {} promoted to {}!".format(name, t.get("mode", "live")))
print(" ".join(out))
PY
)
  intern_msg=${intern_msg:-}
  if [ -n "$intern_msg" ]; then
    messages+=("$intern_msg")
  fi
fi

# --- Intern endpoint reachability (bounded, local; only if configured + enabled) ---
if [ -f "$BACKLOG" ] && grep -q '^[[:space:]]*enabled: true' "$BACKLOG" 2>/dev/null; then
  endpoint=$(awk '/^intern:/{f=1;next} f&&/^[^[:space:]]/{f=0} f&&/[[:space:]]endpoint:/{print $2; exit}' "$BACKLOG" 2>/dev/null || true)
  endpoint=${endpoint:-}
  if [ -n "$endpoint" ]; then
    # Bounded local check: -m 1 keeps SessionStart fast even if the endpoint hangs.
    if ! curl -s -m 1 -o /dev/null "$endpoint" 2>/dev/null; then
      messages+=("Intern: endpoint unreachable.")
    fi
  fi
fi

# --- Emit (silent + exit 0 if nothing actionable) ---
if [ "${#messages[@]}" -eq 0 ]; then
  exit 0
fi

context=$(printf '%s ' "${messages[@]}")
context=${context% }
python3 - "$context" <<'PY' 2>/dev/null || true
import json, sys
print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": sys.argv[1],
    }
}))
PY
exit 0
