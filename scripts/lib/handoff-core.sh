#!/usr/bin/env bash
# Shared blocker-detection / notify / auto-continue-launch logic.
# Sourced by scripts/check-handoff.sh (Copilot Stop hook) and
# scripts/check-handoff-cline.sh (normal Cline completion only) so both
# completion paths make the same decision from the same
# docs/tasks.md state, instead of maintaining two copies that can drift.
# Vendored, read-only — assumes invocation cwd is the project root.

# Runs the check and sets HANDOFF_MESSAGE to a human-readable summary.
# $1: absolute path to the scripts/ directory (so auto-continue.sh can be
#     located regardless of which hook script sourced this file).
handoff_core_run() {
  local script_dir="$1"
  source "$script_dir/lib/planning-core.sh"
  source "$script_dir/lib/workflow-readiness.sh"
  source "$script_dir/lib/workflow-runtime.sh"
  HANDOFF_MESSAGE=""
  if [[ -e .ai-session/continuation-paused ]]; then
    HANDOFF_MESSAGE="Continuation is paused after an interruption. No worker was started. Inspect workflow-status.sh and affected files; resolve the cause, then explicitly run auto-continue.sh --resume."
    workflow_event continuation_skipped "$HANDOFF_MESSAGE" || return 1
    return
  fi
  local tasks_file="docs/tasks.md"
  local handoff_file="docs/handoff.md"
  local notify_script="./notify.sh"
  local log_file=".ai-session/handoff-notifications.log"
  local auto_continue_flag=".github/auto-continue-enabled"

  local blocked_lines=""
  if [[ -f "$tasks_file" ]]; then
    # Task rows start "| S<sprint> | T<task> |" — anchored on that prefix so a bare
    # substring match doesn't also hit tasks.md's own legend line, which contains
    # the word "Blocked" too.
    blocked_lines=$(awk -F '|' '/^\| *S[0-9]+ *\| *T[0-9]+ *\|/ { status=$5; sub(/^[^[:alnum:]]*/, "", status); if (status ~ /^Blocked([[:space:]]|$)/) print NR ":" $0 }' "$tasks_file")
  fi

  if [[ -n "$blocked_lines" ]]; then
    if ! mkdir -p .ai-session; then
      HANDOFF_MESSAGE="Cannot create .ai-session runtime directory for blocker notifications."
      printf '%s\n' "$HANDOFF_MESSAGE" >&2
      return 1
    fi
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
    } >>"$log_file" || {
      HANDOFF_MESSAGE="Blocker detected, but could not write $log_file."
      printf '%s\n' "$HANDOFF_MESSAGE" >&2
      return 1
    }

    HANDOFF_MESSAGE="Blocker detected in $tasks_file — notification attempted, logged to $log_file"
    workflow_event continuation_skipped "$HANDOFF_MESSAGE" || return 1
    return
  fi

  workflow_readiness || { HANDOFF_MESSAGE="Cannot inspect workflow readiness; no worker was started."; return 1; }
  if [[ "$WORKFLOW_STATE" == planning-required ]]; then
    HANDOFF_MESSAGE="$WORKFLOW_REASON No implementation started by this check; this check changed no documents or approval. $WORKFLOW_NEXT"
    workflow_event continuation_skipped "$HANDOFF_MESSAGE" || return 1
    return
  fi

  if [[ ! -f "$auto_continue_flag" ]]; then
    HANDOFF_MESSAGE="No blockers detected. Auto-continue is off (touch $auto_continue_flag to enable it — auto-detects the Copilot/Cline CLI, or write 'copilot'/'cline' into the file to pin one)."
  elif [[ "$WORKFLOW_STATE" == complete ]]; then
    HANDOFF_MESSAGE="No blockers and no unfinished tasks remain in $tasks_file — nothing to auto-continue."
  else
    local worker_pid=""
    if [[ -f .ai-session/auto-continue.pid ]]; then
      worker_pid="$(cat .ai-session/auto-continue.pid)" || return 1
    fi
    if [[ "$worker_pid" =~ ^[1-9][0-9]*$ ]] && kill -0 "$worker_pid" 2>/dev/null; then
      HANDOFF_MESSAGE="Continuation already has a live recorded worker (pid $worker_pid); no additional worker started."
      workflow_event continuation_skipped "$HANDOFF_MESSAGE" || return 1
      return
    fi
    nohup "$script_dir/auto-continue.sh" --from-hook >/dev/null 2>&1 &
    disown
    HANDOFF_MESSAGE="No blockers detected — background auto-continue launch requested, not yet verified (see .ai-session/auto-continue.log and workflow-status.sh)."
  fi
  workflow_event continuation_decision "$HANDOFF_MESSAGE"
}
