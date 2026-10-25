#!/usr/bin/env bash
# Shared blocker-detection / notify / auto-continue-launch logic.
# Sourced by scripts/check-handoff.sh (Copilot Stop hook) and
# scripts/check-handoff-cline.sh (Cline TaskComplete/TaskCancel/SessionShutdown
# hooks) so both backends make exactly the same decision from exactly the same
# docs/tasks.md state, instead of maintaining two copies that can drift.
# Vendored, read-only — assumes invocation cwd is the project root.

# Runs the check and sets HANDOFF_MESSAGE to a human-readable summary.
# $1: absolute path to the scripts/ directory (so auto-continue.sh can be
#     located regardless of which hook script sourced this file).
handoff_core_run() {
  local script_dir="$1"
  local tasks_file="docs/tasks.md"
  local handoff_file="docs/handoff.md"
  local notify_script="./notify.sh"
  local log_file="docs/.handoff-notifications.log"
  local auto_continue_flag=".github/auto-continue-enabled"

  local blocked_lines=""
  if [[ -f "$tasks_file" ]]; then
    # Task rows start "| S<sprint> | T<task> |" — anchored on that prefix so a bare
    # substring match doesn't also hit tasks.md's own legend line, which contains
    # the word "Blocked" too.
    blocked_lines=$(grep -nE '^\| *S[0-9]+ *\| *T[0-9]+ *\|.*Blocked' "$tasks_file" || true)
  fi

  if [[ -n "$blocked_lines" ]]; then
    local message="Session ended with blocked task(s) in $tasks_file:
$blocked_lines

See $handoff_file for full context."

    # NOTE: adjust args below to match send_email_to_mailgun.sh's actual signature.
    if [[ -x "$notify_script" ]]; then
      "$notify_script" "Coding session blocked" "$message" || echo "$(date -u +%FT%TZ) notify script failed" >>"$log_file"
    fi

    {
      echo "$(date -u +%FT%TZ) BLOCKED"
      echo "$message"
      echo "---"
    } >>"$log_file"

    HANDOFF_MESSAGE="Blocker detected in $tasks_file — notification attempted, logged to $log_file"
    return
  fi

  local remaining
  remaining=$(grep -E '^\| *S[0-9]+ *\| *T[0-9]+ *\|' "$tasks_file" 2>/dev/null | grep -vc 'Done' || true)

  if [[ ! -f "$auto_continue_flag" ]]; then
    HANDOFF_MESSAGE="No blockers detected. Auto-continue is off (touch $auto_continue_flag to enable it — auto-detects the Copilot/Cline CLI, or write 'copilot'/'cline' into the file to pin one)."
  elif [[ "${remaining:-0}" -eq 0 ]]; then
    HANDOFF_MESSAGE="No blockers and no unfinished tasks remain in $tasks_file — nothing to auto-continue."
  else
    nohup "$script_dir/auto-continue.sh" >/dev/null 2>&1 &
    disown
    HANDOFF_MESSAGE="No blockers detected — auto-continue started in the background (see docs/.auto-continue.log)."
  fi
}
