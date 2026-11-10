#!/usr/bin/env bash
# Read-only status, run from the consuming project root. No state is repaired.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/planning-core.sh"
source "$SCRIPT_DIR/lib/workflow-readiness.sh"
source "$SCRIPT_DIR/lib/workflow-runtime.sh"

workflow_readiness
printf 'Readiness: %s\nReason: %s\nNext: %s\n' "$WORKFLOW_STATE" "$WORKFLOW_REASON" "$WORKFLOW_NEXT"
if workflow_read_role; then
  printf 'Role marker: %s (not proof that a workflow is active or inactive)\n' "$WORKFLOW_ROLE"
else
  printf 'Role marker: unreadable or invalid; developer attention required\n'
fi
if [[ -f .ai-session/auto-continue.pid ]]; then
  pid="$(cat .ai-session/auto-continue.pid)"
  if [[ "$pid" =~ ^[1-9][0-9]*$ ]] && kill -0 "$pid" 2>/dev/null; then
    printf 'Worker: live recorded PID %s (verify process identity before acting)\n' "$pid"
  else
    printf 'Worker: stale or invalid PID record; no state changed\n'
  fi
else
  printf 'Worker: no recorded PID (interactive Cline activity is not detected)\n'
fi
if [[ -d .ai-session/auto-continue.lock ]]; then
  printf 'Worker lock: present; do not remove until no worker is running\n'
fi
if [[ -f .ai-session/cline-owner ]]; then
  printf 'Cline worker ownership record: '
  cat .ai-session/cline-owner
fi
printf 'Interactive Cline ownership: unverified; use only one active workflow per workspace\n'
if [[ -e .ai-session/continuation-paused ]]; then
  printf 'Continuation: paused\n'
  if [[ ! -f .ai-session/continuation-paused || ! -r .ai-session/continuation-paused ]]; then
    printf 'Cannot read .ai-session/continuation-paused.\n' >&2
    exit 1
  fi
  cat .ai-session/continuation-paused
  printf 'Recovery: inspect interrupted edits/tests, resolve the cause, then explicitly run auto-continue.sh --resume.\n'
fi
if [[ -f .ai-session/workflow-events.jsonl ]]; then
  printf 'Latest recorded event (not an inferred cause):\n'
  tail -n 1 .ai-session/workflow-events.jsonl
else
  printf 'Latest recorded event: unavailable\n'
fi
