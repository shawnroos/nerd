#!/usr/bin/env bash
# Smoke test for hooks/sessionstart-status.sh.
#
# Locks the hook's core contract — it must NEVER break a session: exit 0 on every path,
# stay silent when nothing is actionable, and emit valid JSON additionalContext only when
# there is something to say. This is the exact failure class the type:prompt → type:command
# conversion removes, so it is worth a regression test even though the rest of nerd is
# prose-driven. Run: bash hooks/sessionstart-status.test.sh
set -uo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/sessionstart-status.sh"
PASS=0
FAIL=0

note() { printf '%s\n' "$*"; }
ok()   { PASS=$((PASS + 1)); note "  ok: $1"; }
bad()  { FAIL=$((FAIL + 1)); note "  FAIL: $1"; }

# Run the hook in a throwaway dir; capture stdout + exit code.
run() { # $1 = setup function name
  local dir out rc
  dir=$(mktemp -d)
  ( cd "$dir" && "$1" )
  out=$(cd "$dir" && bash "$SCRIPT" 2>/dev/null); rc=$?
  rm -rf "$dir"
  RUN_OUT="$out"; RUN_RC="$rc"
}

valid_json() { # $1 = string; returns 0 if valid JSON (python3 if available, else heuristic)
  if command -v python3 >/dev/null 2>&1; then
    printf '%s' "$1" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null
  else
    case "$1" in '{'*'}') return 0;; *) return 1;; esac
  fi
}

# --- scenarios ---
s_no_backlog() { git init -q; }
s_empty_backlog() { git init -q; mkdir -p .claude; printf 'backlog: []\n' > .claude/nerd.local.md; }
s_two_proposed() { git init -q; mkdir -p .claude; printf 'backlog:\n- id: E001\n  status: proposed\n- id: E002\n  status: proposed\n' > .claude/nerd.local.md; }
s_non_git() { mkdir -p .claude; printf 'backlog:\n- id: E001\n  status: proposed\n' > .claude/nerd.local.md; }  # no git init
s_running_no_wt() { git init -q; mkdir -p .claude; printf 'backlog:\n- id: E007\n  status: running\n' > .claude/nerd.local.md; }
# Over-match regression: a confounding worktrees/nerd-* worktree exists, but the RUNNING
# experiment's own worktree (nerd-E007) does not. The old count-compare (grep -c 'nerd-')
# counted the confounder and dropped the warning; per-id matching must still warn.
s_running_overmatch() {
  git init -q; git config user.email t@t; git config user.name t
  printf 'x\n' > seed; git add seed; git commit -qm seed
  git worktree add -q worktrees/nerd-fixes -b confounder >/dev/null 2>&1
  mkdir -p .claude; printf 'backlog:\n- id: E007\n  status: running\n' > .claude/nerd.local.md
}

note "== sessionstart-status.sh smoke test =="

run s_no_backlog
[ "$RUN_RC" -eq 0 ] && ok "no backlog → exit 0" || bad "no backlog → exit $RUN_RC"
[ -z "$RUN_OUT" ] && ok "no backlog → silent" || bad "no backlog → emitted: $RUN_OUT"

run s_empty_backlog
[ "$RUN_RC" -eq 0 ] && ok "empty backlog → exit 0" || bad "empty backlog → exit $RUN_RC"
[ -z "$RUN_OUT" ] && ok "empty backlog → silent" || bad "empty backlog → emitted: $RUN_OUT"

run s_two_proposed
[ "$RUN_RC" -eq 0 ] && ok "2 proposed → exit 0" || bad "2 proposed → exit $RUN_RC"
case "$RUN_OUT" in *'2 proposal'*) ok "2 proposed → mentions count";; *) bad "2 proposed → missing count: $RUN_OUT";; esac
valid_json "$RUN_OUT" && ok "2 proposed → valid JSON" || bad "2 proposed → invalid JSON: $RUN_OUT"

run s_non_git
[ "$RUN_RC" -eq 0 ] && ok "non-git cwd → exit 0" || bad "non-git cwd → exit $RUN_RC"

run s_running_no_wt
[ "$RUN_RC" -eq 0 ] && ok "running w/o worktree → exit 0" || bad "running w/o worktree → exit $RUN_RC"
case "$RUN_OUT" in *'worktree missing'*) ok "running w/o worktree → warns";; *) bad "running w/o worktree → no warning: $RUN_OUT";; esac

run s_running_overmatch
[ "$RUN_RC" -eq 0 ] && ok "over-match → exit 0" || bad "over-match → exit $RUN_RC"
case "$RUN_OUT" in *'worktree missing'*) ok "over-match → still warns (per-id, not count-compare)";; *) bad "over-match REGRESSION → warning dropped: $RUN_OUT";; esac

note "== $PASS passed, $FAIL failed =="
[ "$FAIL" -eq 0 ]
