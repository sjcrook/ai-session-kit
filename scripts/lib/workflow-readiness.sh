#!/usr/bin/env bash
# Shared implementation readiness; callers source planning-core.sh first.
workflow_readiness() {
  WORKFLOW_STATE=planning-required
  WORKFLOW_NEXT_TASK=""
  WORKFLOW_BLOCKED_TASK=""
  if ! planning_check; then
    WORKFLOW_REASON="$PLANNING_ERROR"
    WORKFLOW_NEXT="Ask whether to start /tasks reconciliation; obtain explicit approval before implementation."
    return
  fi
  local tasks
  if ! tasks="$(awk -F '|' '
    /^\| *S[0-9]+ *\| *T[0-9]+ *\|/ {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", $3)
      status=$5; sub(/^[^[:alnum:]]*/, "", status)
      if (status ~ /^Blocked([[:space:]]|$)/ && !blocked) blocked=$3
      if (status ~ /^(Todo|In Progress)([[:space:]]|$)/ && !next_task) next_task=$3
    }
    END { print blocked "|" next_task }
  ' docs/tasks.md)"; then
    printf 'Cannot inspect docs/tasks.md for readiness.\n' >&2
    return 1
  fi
  WORKFLOW_BLOCKED_TASK="${tasks%%|*}"
  WORKFLOW_NEXT_TASK="${tasks#*|}"
  if [[ -n "$WORKFLOW_BLOCKED_TASK" ]]; then
    WORKFLOW_STATE=blocked
    WORKFLOW_REASON="Blocked task $WORKFLOW_BLOCKED_TASK prevents unattended continuation."
    WORKFLOW_NEXT="Review the blocker and ask for the required decision; do not clear unrelated blockers."
  elif [[ -n "$WORKFLOW_NEXT_TASK" ]]; then
    WORKFLOW_STATE=ready
    WORKFLOW_REASON="Planning approval is current. Next eligible task: $WORKFLOW_NEXT_TASK."
    WORKFLOW_NEXT="Use the implementer workflow; verify real state before resuming In Progress work."
  else
    WORKFLOW_STATE=complete
    WORKFLOW_REASON="No unfinished tasks remain."
    WORKFLOW_NEXT="No implementation is scheduled. Ask about new scope before starting another workflow."
  fi
}
