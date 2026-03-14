---
name: autoresearch-schedule
description: "Schedule autoresearch experiments to run at specific times (e.g., overnight). Uses macOS LaunchAgent for scheduling."
argument-hint: "[tonight|weeknights|HH:MM-HH:MM|cancel]"
allowed-tools: "Read,Write,Bash,AskUserQuestion"
---

# Autoresearch Schedule

Schedule when experiments run. Supports overnight windows and recurring schedules.

## Input

<time_spec>$ARGUMENTS</time_spec>

## Parse Time Spec

- `tonight` / `overnight` → 22:00 to 06:00 today
- `weeknights` → Recurring M-F 22:00-06:00
- `HH:MM-HH:MM` → Custom window (e.g., `23:00-05:00`)
- `cancel` / `stop` → Remove scheduled runs
- Empty → Show current schedule and ask

## Check Prerequisites

```bash
cat ~/.claude/plugins/autoresearch/hardware-profile.yaml 2>/dev/null | grep experiments_per_hour
```

If no hardware profile: "Run /autoresearch-setup first."

## Calculate Capacity

```
experiments_per_hour = {from hardware profile}
window_hours = (stop - start)
capacity = experiments_per_hour * window_hours
```

## Create Runner Script

```bash
mkdir -p ~/.claude/plugins/autoresearch/scripts ~/.claude/plugins/autoresearch/logs

cat > ~/.claude/plugins/autoresearch/scripts/scheduled-run.sh << 'RUNNER'
#!/bin/bash
# Autoresearch scheduled runner — resilient to transient failures

LOG="$HOME/.claude/plugins/autoresearch/logs/$(date +%Y-%m-%d).log"
mkdir -p "$(dirname "$LOG")"

log() { echo "$(date): $1" >> "$LOG"; }

log "Autoresearch starting (project: $PROJECT_DIR)"

if [ -z "${PROJECT_DIR:-}" ]; then
    log "ERROR: PROJECT_DIR not set. Exiting."
    exit 1
fi

cd "$PROJECT_DIR" || { log "ERROR: Cannot cd to $PROJECT_DIR"; exit 1; }

# Run with retry on transient failures (max 3 attempts)
attempt=0
max_attempts=3
while [ "$attempt" -lt "$max_attempts" ]; do
    attempt=$((attempt + 1))
    log "Attempt $attempt/$max_attempts"

    AUTORESEARCH_SCHEDULED=1 claude --print --dangerously-skip-permissions -p "
Run /autoresearch. Execute all backlog experiments autonomously.
Use /loop 5m to monitor agents. Merge completed experiments.
When all done, compile reports and exit.
Never ask questions — make all decisions autonomously.
" >> "$LOG" 2>&1

    exit_code=$?
    if [ "$exit_code" -eq 0 ]; then
        log "Autoresearch completed successfully"
        break
    else
        log "WARNING: claude exited with code $exit_code"
        if [ "$attempt" -lt "$max_attempts" ]; then
            log "Retrying in 30 seconds..."
            sleep 30
        else
            log "ERROR: All $max_attempts attempts failed"
        fi
    fi
done

log "Autoresearch session ended"
RUNNER

chmod +x ~/.claude/plugins/autoresearch/scripts/scheduled-run.sh
```

## Register LaunchAgent

```bash
PLIST="$HOME/Library/LaunchAgents/com.autoresearch.scheduled.plist"

cat > "$PLIST" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.autoresearch.scheduled</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>${HOME}/.claude/plugins/autoresearch/scripts/scheduled-run.sh</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>AUTORESEARCH_SCHEDULED</key>
        <string>1</string>
        <key>PROJECT_DIR</key>
        <string>{cwd}</string>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
    </dict>
    <key>StartCalendarInterval</key>
    {calendar_interval_entries}
    <key>StandardOutPath</key>
    <string>${HOME}/.claude/plugins/autoresearch/logs/launchd.log</string>
    <key>StandardErrorPath</key>
    <string>${HOME}/.claude/plugins/autoresearch/logs/launchd-err.log</string>
    <key>Nice</key>
    <integer>10</integer>
    <key>ProcessType</key>
    <string>Background</string>
</dict>
</plist>
PLIST

launchctl load "$PLIST"
```

**Calendar interval entries by schedule type:**
- `tonight`: Single `<dict>` with today's weekday + start hour
- `weeknights`: Five `<dict>` entries for Mon(1)-Fri(5) at start hour
- Custom: Single daily entry at start hour

## Confirm

```
Autoresearch Scheduled
  Window: {start} - {stop}
  Capacity: ~{capacity} experiments per window
  Project: {cwd}
  Logs: ~/.claude/plugins/autoresearch/logs/

  /autoresearch-status to check progress
  /autoresearch-schedule cancel to remove
```

## Cancel

```bash
launchctl unload ~/Library/LaunchAgents/com.autoresearch.scheduled.plist 2>/dev/null
rm ~/Library/LaunchAgents/com.autoresearch.scheduled.plist 2>/dev/null
echo "Schedule cancelled."
```
