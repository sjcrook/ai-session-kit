#!/usr/bin/env bash
# Stop hook: notify if the session ended with a BLOCKED task in docs/tasks.md.
# Vendored, read-only — assumes invocation cwd is the project root (the Stop hook sets this).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TASKS_FILE="docs/tasks.md"
HANDOFF_FILE="docs/handoff.md"
NOTIFY_SCRIPT="./notify.sh"
LOG_FILE="docs/.handoff-notifications.log"

blocked_lines=""
if [[ -f "$TASKS_FILE" ]]; then
  # Anchored to real checkbox task lines — a bare substring match also hits tasks.md's own
  # legend line ("...replace the line with ... BLOCKED: <reason>..."), causing false positives.
  blocked_lines=$(grep -n '^- \[ \].*BLOCKED' "$TASKS_FILE" || true)
fi

if [[ -n "$blocked_lines" ]]; then
  message="Session ended with blocked task(s) in $TASKS_FILE:
$blocked_lines

See $HANDOFF_FILE for full context."

  # NOTE: adjust args below to match send_email_to_mailgun.sh's actual signature.
  if [[ -x "$NOTIFY_SCRIPT" ]]; then
    "$NOTIFY_SCRIPT" "Coding session blocked" "$message" || echo "$(date -u +%FT%TZ) notify script failed" >> "$LOG_FILE"
  fi

  {
    echo "$(date -u +%FT%TZ) BLOCKED"
    echo "$message"
    echo "---"
  } >> "$LOG_FILE"

  echo "{\"systemMessage\": \"Blocker detected in $TASKS_FILE — notification attempted, logged to $LOG_FILE\"}"
else
  AUTO_CONTINUE_FLAG=".github/auto-continue-enabled"
  remaining=$(grep -c '^- \[ \]' "$TASKS_FILE" 2>/dev/null || true)

  if [[ ! -f "$AUTO_CONTINUE_FLAG" ]]; then
    echo "{\"systemMessage\": \"No blockers detected. Auto-continue is off (touch $AUTO_CONTINUE_FLAG to enable it — auto-detects the Copilot/Cline CLI, or write 'copilot'/'cline' into the file to pin one).\"}"
  elif [[ "${remaining:-0}" -eq 0 ]]; then
    echo "{\"systemMessage\": \"No blockers and no unchecked tasks remain in $TASKS_FILE — nothing to auto-continue.\"}"
  else
    nohup "$SCRIPT_DIR/auto-continue.sh" >/dev/null 2>&1 &
    disown
    echo "{\"systemMessage\": \"No blockers detected — auto-continue started in the background (see docs/.auto-continue.log).\"}"
  fi
fi

exit 0
