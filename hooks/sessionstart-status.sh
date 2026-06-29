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
  # Match each running entry's id (id: precedes status: within an entry) against its
  # SPECIFIC experiment worktree (worktrees/nerd-{id}). A count/substring comparison
  # would over-match unrelated worktrees — e.g. the repo's own worktrees/nerd-fixes —
  # and silently drop the warning.
  running_ids=$(awk '/^[[:space:]]*-?[[:space:]]*id:/{id=$NF} /^[[:space:]]*status: running/{print id}' "$BACKLOG" 2>/dev/null || true)
  if [ -n "$running_ids" ]; then
    wt_list=$(git worktree list 2>/dev/null || true)
    missing=0
    while IFS= read -r rid; do
      [ -z "$rid" ] && continue
      if ! printf '%s\n' "$wt_list" | grep -q "worktrees/nerd-${rid}[[:space:]]"; then
        missing=$((missing + 1))
      fi
    done <<< "$running_ids"
    if [ "$missing" -gt 0 ] 2>/dev/null; then
      messages+=("Nerd: ${missing} experiment(s) marked running but worktree missing (possible crashed session). Run /nerd to recover.")
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
# Parse `enabled` and `endpoint` from WITHIN the intern: block — a sibling section's
# `enabled: true` must not trigger the probe. Only probe when curl exists (a missing
# curl is "can't tell", not "unreachable") and the endpoint is an http(s) URL — the
# scheme check also rejects a leading '-' that curl would otherwise read as an option.
if [ -f "$BACKLOG" ] && command -v curl >/dev/null 2>&1; then
  intern_block=$(awk '/^intern:/{f=1;next} f&&/^[^[:space:]]/{f=0} f' "$BACKLOG" 2>/dev/null || true)
  if printf '%s\n' "$intern_block" | grep -q '[[:space:]]enabled: true'; then
    endpoint=$(printf '%s\n' "$intern_block" | awk '/[[:space:]]endpoint:/{print $2; exit}' 2>/dev/null || true)
    endpoint=${endpoint:-}
    case "$endpoint" in
      http://*|https://*)
        # Bounded check: -m 1 keeps SessionStart fast even if the endpoint hangs.
        if ! curl -s -m 1 -o /dev/null -- "$endpoint" 2>/dev/null; then
          messages+=("Intern: endpoint unreachable.")
        fi
        ;;
    esac
  fi
fi

# --- Emit (silent + exit 0 if nothing actionable) ---
if [ "${#messages[@]}" -eq 0 ]; then
  exit 0
fi

context=$(printf '%s ' "${messages[@]}")
context=${context% }
# Emit additionalContext as JSON WITHOUT a python3 dependency, so a backlog nudge still
# fires on a python3-less machine (python3 above is optional, for intern state only).
# Escape backslash first, then double-quote; messages are single-line (joined with
# spaces, no embedded newlines), so these two escapes are sufficient for valid JSON.
context=${context//\\/\\\\}
context=${context//\"/\\\"}
printf '{"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": "%s"}}\n' "$context"
exit 0
