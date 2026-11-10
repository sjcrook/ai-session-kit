#!/usr/bin/env bash
# Stops a running auto-continue loop and its CLI process tree.
# Vendored, read-only — assumes invocation cwd is the project root.
set -uo pipefail

PID_FILE=".ai-session/auto-continue.pid"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/workflow-runtime.sh"

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

# Freeze the loop so it cannot start another iteration while children stop.
workflow_pause "Developer stopped the auto-continue worker; inspect interrupted work before explicitly restarting." || exit 1
if ! kill -STOP "$pid"; then
  echo "Failed to pause auto-continue process $pid." >&2
  exit 1
fi
trap 'kill -CONT "$pid" 2>/dev/null || true' EXIT

if ! process_tree="$(ps -e -o pid= -o ppid=)"; then
  echo "Failed to inspect descendants of auto-continue process $pid." >&2
  exit 1
fi
descendants="$(printf '%s\n' "$process_tree" | awk -v root="$pid" '
  { children[$2] = children[$2] " " $1 }
  function visit(parent, ids, count, i) {
    count = split(children[parent], ids, " ")
    for (i = 1; i <= count; i++) {
      if (ids[i] != "") {
        visit(ids[i])
        print ids[i], parent
      }
    }
  }
  END { visit(root) }
')"

while read -r child parent; do
  [[ -n "$child" ]] || continue
  # Recheck ancestry before signaling a PID from the snapshot.
  actual_parent="$(ps -p "$child" -o ppid= 2>/dev/null || true)"
  actual_parent="${actual_parent//[[:space:]]/}"
  [[ "$actual_parent" == "$parent" ]] || continue
  if ! kill -TERM "$child" 2>/dev/null && kill -0 "$child" 2>/dev/null; then
    echo "Failed to signal CLI descendant $child of auto-continue process $pid." >&2
    exit 1
  fi
done <<<"$descendants"

if ! kill -TERM "$pid"; then
  if kill -0 "$pid" 2>/dev/null; then
    echo "Failed to signal auto-continue process $pid." >&2
    exit 1
  fi
  echo "Auto-continue process $pid exited before it could be signaled."
  exit 0
fi

if [[ -n "$descendants" ]]; then
  echo "Sent TERM to auto-continue process $pid and its CLI descendants."
else
  echo "Sent TERM to auto-continue process $pid; it had no current CLI child."
fi
