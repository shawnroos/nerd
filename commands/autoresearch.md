---
name: autoresearch
description: "Run autonomous codebase research. Analyzes the codebase for tunable parameters, generates experiment plans, executes them in worktrees, and compiles findings. Use with no args for full autonomous pipeline, or pass a topic to focus research (e.g., /autoresearch search relevance)."
argument-hint: "[topic]"
allowed-tools: "Read,Write,Edit,Bash,Glob,Grep,Agent,AskUserQuestion"
---

# Autoresearch — Autonomous Codebase Research Pipeline

Discover optimization opportunities in a codebase and run experiments to find empirically optimal parameter values.

## Input

<user_topic>$ARGUMENTS</user_topic>

## Pre-flight

**Check schedule mode:** If `AUTORESEARCH_SCHEDULED=1` is set, operate fully autonomously — skip all AskUserQuestion calls, execute all backlog experiments, make decisions without user input.

**Check setup:**
```bash
cat ~/.claude/plugins/autoresearch/hardware-profile.yaml 2>/dev/null
```
If no hardware profile: "Run /autoresearch-setup first." Stop.

**Detect project:**
```bash
ls Cargo.toml package.json pyproject.toml go.mod 2>/dev/null
cat CLAUDE.md .claude/CLAUDE.md 2>/dev/null | head -50
git branch --show-current
```

Store: language, test command, current branch.

## Phase 1: Load Backlog

```bash
cat .claude/autoresearch.local.md 2>/dev/null
```

If backlog has `proposed` entries and no topic: skip to Phase 3.
If backlog empty or topic specified: continue to Phase 2.

## Phase 2: Codebase Analysis

Launch the parameter-scanner agent:

```
Agent(subagent_type="autoresearch:parameter-scanner", prompt="Scan {cwd} for tunable parameters. Topic: {user_topic or 'all'}. Return structured JSON list.", run_in_background=false)
```

Present findings. Use AskUserQuestion: "Which experiments to plan?" Add selections to backlog.

## Phase 3: Experiment Planning

For each `proposed` entry, launch plan-reviewer agents **in parallel**:

```
Agent(subagent_type="autoresearch:plan-reviewer", prompt="Create experiment plan for {entry.title}. Parameter: {entry.parameter} at {entry.file}:{entry.line}. Write to docs/research/plans/{entry.id}-plan.md.", run_in_background=true)
```

Update status: `proposed` → `planned`. Wait for all plan agents.

## Phase 4: Review Gate

Present plans. Use AskUserQuestion: "Execute all, review first, or select subset?"

## Phase 5: Execute in Worktrees

### 5.1: Create Shared Eval Scaffold

Before launching experiments, set up consolidated infrastructure on current branch:
```bash
mkdir -p docs/research/plans docs/research/results
```

If no eval module exists, create a scaffold appropriate to the project language (e.g., `src/eval/mod.rs` for Rust, `src/eval/index.ts` for TS). Add a single `Eval` CLI subcommand. Each experiment extends this — never creates its own.

### 5.2: Launch Experiment Agents

For each `planned` experiment:

```bash
git worktree add worktrees/research-{entry.id} --detach HEAD
cd worktrees/research-{entry.id} && git checkout -b research/{entry.id}
```

```
Agent(subagent_type="autoresearch:experiment-executor", prompt="
Execute plan at docs/research/plans/{entry.id}-plan.md.
Worktree: {path}. Language: {lang}. Tests: {test_cmd}.
Put code in src/eval/{entry.id}.rs (or equivalent).
Add to existing EvalAction enum. Commit conventionally.
Write results to docs/research/results/{entry.id}-results.json.
", run_in_background=true)
```

Cap parallel agents at `max_parallel_experiments` from config.

### 5.3: Merge Completed Experiments

As each agent completes, merge immediately:

```bash
git merge research/{entry.id} --no-edit
{test_command}  # verify tests pass
```

If tests fail: `git reset --hard HEAD~1`, mark `failed`, keep worktree.
If merge succeeds: `git worktree remove worktrees/research-{entry.id}`.

Merge conflicts in eval module files (mod.rs, EvalAction enum) are additive — combine both sides.

## Phase 6: Monitor

Use `/loop 5m` to check on background agents. Merge experiments as they complete. When all are done or failed, proceed.

## Phase 7: Compile Reports

```
Agent(subagent_type="autoresearch:report-compiler", prompt="Compile findings from docs/research/results/ into docs/research/findings.md and per-experiment reports.", run_in_background=false)
```

Present summary. Clean up remaining worktrees:
```bash
git worktree prune
```

## Error Handling

- Agent fails → mark `failed`, keep worktree, continue others
- Worktree branch exists → add timestamp suffix
- No git repo → run directly, warn about no isolation
- No parameters found → suggest manual topics
- Build fails after merge → auto-revert, mark `failed`
