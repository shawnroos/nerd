# autoresearch

Autonomous codebase research plugin for Claude Code. Discovers tunable parameters in your code, plans experiments to find optimal values, runs them overnight in parallel git worktrees, and delivers findings with actionable recommendations.

Built from a real session where 15 experiments were designed, implemented, and run across two codebases (Arras and OpenPencil) in a single sitting. This plugin packages that workflow so you can repeat it on any project.

## Quick Start

```bash
# First time — calibrate your hardware
/autoresearch-setup

# Run research on the current project
/autoresearch

# Focus on a specific area
/autoresearch search relevance
/autoresearch agent prompts
/autoresearch sync pipeline

# Schedule overnight runs
/autoresearch-schedule tonight
/autoresearch-schedule weeknights

# Check progress
/autoresearch-status
```

## What It Does

**The problem:** Codebases accumulate hardcoded thresholds, magic numbers, and heuristic weights that were chosen by intuition, not measurement. A fuzzy match threshold of 0.85, an RRF k of 60, a token budget of 10,000 — are these optimal? Nobody knows, because nobody has tested.

**The solution:** Autoresearch applies the scientific method to your codebase parameters:

1. **Scan** — The `parameter-scanner` agent greps for constants, thresholds, weights, prompts, and pipeline budgets. Categorizes by impact (search quality, AI efficiency, data pipeline) and feasibility (can we define a metric? is there ground truth?).

2. **Plan** — For each finding, the `plan-reviewer` agent (Opus) generates an experiment plan with hypothesis, metric, sweep ranges, ground truth strategy, and acceptance criteria. Plans go through SpecFlow analysis to catch gaps before execution.

3. **Execute** — The `experiment-executor` agent builds evaluation harnesses in isolated git worktrees. Each experiment gets its own branch and worktree. Multiple experiments run in parallel, capped by your hardware profile.

4. **Report** — The `report-compiler` agent writes findings to `docs/research/` with three possible recommendations:
   - **KEEP** — current value is empirically validated
   - **CHANGE** — a better value was found (includes exact code diff)
   - **INVESTIGATE** — insufficient data or inconclusive results

## Overnight Runs

The plugin is designed for unattended operation. Schedule experiments to run while you sleep:

```bash
/autoresearch-schedule tonight        # Run 22:00 - 06:00
/autoresearch-schedule weeknights     # Recurring M-F 22:00-06:00
/autoresearch-schedule 23:00-05:00    # Custom window
/autoresearch-schedule cancel         # Stop scheduled runs
```

Scheduled runs use macOS LaunchAgents with:
- **Retry on failure** — transient errors don't kill the window (3 attempts, 30s backoff)
- **Low priority** — Nice 10, background process type, minimal fan noise
- **Crash recovery** — SessionStart hook detects orphaned experiments on next session
- **`/loop` monitoring** — checks agent progress every 5 minutes, handles stalls

## Passive Discovery

A `PostToolUse` hook watches as you write code. When you create or edit files containing hardcoded thresholds, it silently appends proposals to the project backlog (`.claude/autoresearch.local.md`). By the time you run `/autoresearch`, there's already a queue of findings waiting.

## Multi-Project Scheduling

If you have experiments queued across multiple projects (e.g., Arras and Jeans), the global queue at `~/.claude/plugins/autoresearch/global-queue.yaml` coordinates:
- Round-robin across projects for fairness
- Max 4 parallel codebase experiments total
- Max 2 per project to prevent hogging

## Pipeline

```
/autoresearch
    |
    +-- parameter-scanner (cyan)
    |     Finds: thresholds, weights, prompts, budgets, timing
    |
    +-- User selects experiments
    |
    +-- plan-reviewer (yellow, opus)
    |     Plans: hypothesis, metric, sweep, ground truth, phases
    |     Reviews: SpecFlow gap analysis, self-improvement loop
    |
    +-- experiment-executor (green) x N parallel
    |     Builds: eval harness in worktree branch
    |     Runs: parameter sweep, captures results
    |     Merges: auto-merge on success, auto-revert on test failure
    |
    +-- /loop 5m monitors until queue complete
    |
    +-- report-compiler (blue)
          Writes: docs/research/findings.md + per-experiment reports
```

## Project Structure

After running autoresearch, your project gains:

```
docs/research/
  findings.md              # Executive summary with recommendations
  plans/
    E001-plan.md           # Experiment plans with acceptance criteria
    E002-plan.md
  results/
    E001-results.json      # Raw sweep data
    E002-results.json
  E001-report.md           # Detailed finding with KEEP/CHANGE/INVESTIGATE
  E002-report.md
```

## Configuration

### Hardware Profile (global)

Created by `/autoresearch-setup` at `~/.claude/plugins/autoresearch/hardware-profile.yaml`:

```yaml
hardware:
  chip: "Apple M1 Pro"
  memory_gb: 16
codebase:
  build_time_seconds: 6.5
  test_time_seconds: 12.3
  language: rust
```

### Project Config

Per-project settings at `.claude/autoresearch.local.md`:

```yaml
---
max_parallel_experiments: 4
merge_strategy: auto           # auto | pr | branches
auto_cleanup_worktrees: true
backlog:
  - id: E001
    title: "JW Threshold Tuning"
    status: proposed
    parameter: jw_threshold
    file: src/entities/resolution.rs
    line: 92
    current_value: "0.85"
---
```

### Merge Strategies

| Strategy | Behavior | Best For |
|----------|----------|---------|
| `auto` | Merges immediately, auto-reverts if tests fail | Solo dev, overnight runs |
| `pr` | Creates a PR per experiment for review | Team repos |
| `branches` | Stays on worktree branches, you cherry-pick | Exploratory research |

## Components

| Type | Name | Model | Purpose |
|------|------|-------|---------|
| Command | `/autoresearch` | — | Main pipeline orchestrator |
| Command | `/autoresearch-setup` | — | Hardware calibration + dependency install |
| Command | `/autoresearch-schedule` | — | Overnight scheduling via LaunchAgent |
| Command | `/autoresearch-status` | — | Queue and progress monitor |
| Agent | `parameter-scanner` | Sonnet | Finds tunable parameters |
| Agent | `plan-reviewer` | Opus | Reviews and improves experiment plans |
| Agent | `experiment-executor` | Sonnet | Builds and runs experiments in worktrees |
| Agent | `report-compiler` | Sonnet | Writes structured research reports |
| Skill | `codebase-analysis` | — | Scan patterns and parameter categories |
| Skill | `experiment-planning` | — | Sweep design and ground truth strategies |
| Skill | `research-reporting` | — | Report format and recommendation logic |
| Hook | `SessionStart` | — | Checks backlog, detects crashed sessions |
| Hook | `PostToolUse:Write` | — | Passively discovers tunable parameters |

## Requirements

- Git with worktree support
- Claude Code with agent capabilities
- macOS (for LaunchAgent scheduling; codebase experiments work on any platform)

## Origin

This plugin was born from running Karpathy's [autoresearch](https://github.com/karpathy/autoresearch) concept — autonomous ML experiment loops — and realizing the same pattern applies to any codebase with tunable parameters. The first run produced 15 experiments across search relevance, entity resolution, temporal decay, prompt compression, sync pipeline efficiency, and agent orchestration. Key findings:

- Entity resolution thresholds were already optimal (validated, not just assumed)
- System prompt compression saves 99% tokens for query expansion calls
- Orchestrator layout weights were dead code in the primary path
- Pre-validation heuristics catch 30-40% of design issues at zero API cost
- Temporal decay data was bursty, not exponential — the model was wrong, not the parameters
