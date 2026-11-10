#!/usr/bin/env bash
# Cline terminal hooks pass their event name explicitly in both hook layouts.
# Payload identity is not assumed: only worker-inherited ownership is verified.
set -uo pipefail
cat >/dev/null
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/workflow-runtime.sh"
source "$SCRIPT_DIR/lib/handoff-core.sh"
event="${1:-unknown}"

finish() {
  printf 'cline-workflow: %s\n' "$1" >&2
  printf '{"cancel": false}\n'
  exit "${2:-0}"
}

workflow_event lifecycle_received "event=$event" || finish "Cannot record lifecycle event; continuation was not checked." 1
if ! workflow_owner_matches; then
  workflow_event lifecycle_ignored "event=$event ownership=$WORKFLOW_OWNERSHIP; marker unchanged, no continuation" ||
    finish "Cannot record lifecycle ownership mismatch." 1
  finish "Lifecycle ownership mismatch or unreadable ownership: marker unchanged; no continuation. Use workflow-status.sh."
fi
workflow_event lifecycle_ownership "event=$event ownership=$WORKFLOW_OWNERSHIP; interactive session identity is unavailable; one active Cline workflow per workspace is required" ||
  finish "Cannot record lifecycle ownership; no continuation." 1

# A CLI may emit shutdown after completion. For verified worker iterations,
# ignore that duplicate rather than pausing the next successful iteration.
if [[ "$WORKFLOW_OWNERSHIP" == worker && -f .ai-session/cline-completed ]] &&
  [[ "$(cat .ai-session/cline-completed)" == "$AI_SESSION_RUN_ID:$AI_SESSION_ITERATION" ]]; then
  workflow_event lifecycle_ignored "event=$event; worker iteration already completed" ||
    finish "Cannot record duplicate lifecycle event." 1
  finish "Worker iteration already completed; duplicate lifecycle event ignored."
fi

if [[ "$event" != TaskComplete ]]; then
  workflow_pause "Cline lifecycle event: $event. Cancellation/shutdown is not successful completion." ||
    finish "Cannot persist cancellation pause; stop any worker and inspect hook stderr." 1
fi

if ! workflow_read_role; then
  finish "Cannot reset .cline/.active-role; continuation was not checked. Correct the role marker with file tools." 1
fi
if [[ "$WORKFLOW_ROLE" != missing ]]; then
  if ! printf '%s' none >.cline/.active-role; then
    finish "Cannot reset .cline/.active-role; continuation was not checked." 1
  fi
  workflow_event role_released "previous=$WORKFLOW_ROLE current=none source=$event ownership=$WORKFLOW_OWNERSHIP" ||
    finish "Role released, but cleanup diagnostic failed; no continuation." 1
fi

if [[ "$event" == TaskComplete && "$WORKFLOW_OWNERSHIP" == worker ]]; then
  if ! printf '%s\n' "$AI_SESSION_RUN_ID:$AI_SESSION_ITERATION" >.ai-session/cline-completed; then
    finish "Cannot record worker completion; continuation was not checked." 1
  fi
fi
if [[ "$event" != TaskComplete ]]; then
  finish "Workflow interrupted ($event). Continuation paused; inspect affected files and use workflow-status.sh before an explicit auto-continue.sh --resume."
fi
handoff_core_run "$SCRIPT_DIR" || finish "$HANDOFF_MESSAGE" 1
finish "$HANDOFF_MESSAGE"
