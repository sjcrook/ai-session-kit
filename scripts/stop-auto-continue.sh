#!/usr/bin/env bash
# Stops a running auto-continue loop and its current CLI child.
# Vendored, read-only — assumes invocation cwd is the project root.
set -uo pipefail

PID_FILE="docs/.auto-continue.pid"

if [[ ! -f "$PID_FILE" ]]; then
  echo "No auto-continue PID file found; no loop is recorded as running."
  exit 0
fi

pid="$(cat "$PID_FILE")"
if [[ ! "$pid" =~ ^[1-9][0-9]*$ ]]; then
  echo "Invalid PID in $PID_FILE: '$pid'." >&2
  exit 1
fi

if ! kill -0 "$pid" 2>/dev/null; then
  rm -f "$PID_FILE"
  echo "The recorded auto-continue process is no longer running; removed stale $PID_FILE."
  exit 0
fi

process_command="$(ps -p "$pid" -o command= 2>/dev/null || true)"
if [[ "$process_command" != *"auto-continue.sh"* ]]; then
  echo "PID $pid is running, but does not appear to be auto-continue.sh; refusing to signal it." >&2
  exit 1
fi

if ! command -v pkill >/dev/null 2>&1; then
  echo "pkill is required to stop the active CLI child." >&2
  exit 1
fi

child_status=0
pkill -TERM -P "$pid" || child_status=$?
if [[ "$child_status" -gt 1 ]]; then
  echo "Failed to signal the active CLI child of auto-continue process $pid (pkill exit $child_status)." >&2
  exit 1
fi

if ! kill -TERM "$pid"; then
  if kill -0 "$pid" 2>/dev/null; then
    echo "Failed to signal auto-continue process $pid." >&2
    exit 1
  fi
  echo "Auto-continue process $pid exited before it could be signaled."
  exit 0
fi

if [[ "$child_status" -eq 0 ]]; then
  echo "Sent TERM to auto-continue process $pid and its current CLI child."
else
  echo "Sent TERM to auto-continue process $pid; it had no current CLI child."
fi
