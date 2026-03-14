# autoresearch

Autonomous codebase research plugin for Claude Code. Scans for tunable parameters, plans experiments, runs them in parallel worktrees, and compiles findings.

## Getting Started

```
/autoresearch-setup            # First-time: calibrate hardware, install deps
/autoresearch                  # Full pipeline: scan → plan → execute → report
/autoresearch <topic>          # Focused research on a specific area
/autoresearch-schedule tonight # Schedule overnight runs
/autoresearch-status           # Check queue and progress
```

## How It Works

1. **Scan** — finds hardcoded thresholds, magic numbers, and tunable parameters
2. **Plan** — generates experiment plans with acceptance criteria and sweep harnesses
3. **Execute** — runs experiments in parallel git worktrees, merges as they complete
4. **Report** — writes findings to `docs/research/` with KEEP/CHANGE/INVESTIGATE recommendations

## Requirements

- Git with worktree support
- Claude Code with agent capabilities
- Python 3.10+ and `uv` (for LLM training experiments)
