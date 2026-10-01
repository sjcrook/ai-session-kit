#!/usr/bin/env bash
# Headless continuation loop, launched by check-handoff.sh when no blocker is found.
# Requires .github/auto-continue-enabled to exist (opt-in) and either the `copilot`
# or `cline` CLI on PATH. Backend is chosen in priority order: the AUTO_CONTINUE_CLI
# env var (only reaches this script on manual/direct runs, not the hook-triggered path),
# then the contents of .github/auto-continue-enabled (write "copilot" or "cline" into
# that file; leave it empty to auto-detect), then auto-detect (copilot preferred).
# Vendored, read-only — assumes invocation cwd is the project root.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TASKS_FILE="docs/tasks.md"
LOG_FILE="docs/.auto-continue.log"
PID_FILE="docs/.auto-continue.pid"
MAX_ITERATIONS="${AUTO_CONTINUE_MAX_ITERATIONS:-3}"
AUTO_CONTINUE_FLAG=".github/auto-continue-enabled"

log() { echo "$(date -u +%FT%TZ) $*" >>"$LOG_FILE"; }

echo "$$" >"$PID_FILE"
trap 'rm -f "$PID_FILE"' EXIT

CLI="${AUTO_CONTINUE_CLI:-}"
if [[ -z "$CLI" && -f "$AUTO_CONTINUE_FLAG" ]]; then
  CLI="$(tr -d '[:space:]' <"$AUTO_CONTINUE_FLAG")"
fi
if [[ -z "$CLI" ]]; then
  if command -v copilot >/dev/null 2>&1; then
    CLI="copilot"
  elif command -v cline >/dev/null 2>&1; then
    CLI="cline"
  fi
fi
if [[ "$CLI" != "copilot" && "$CLI" != "cline" ]] || ! command -v "$CLI" >/dev/null 2>&1; then
  log "auto-continue: stopping — no supported CLI found (looked for 'copilot' and 'cline'; resolved CLI='$CLI')"
  exit 0
fi

PROMPT="Read AGENTS.md, docs/functional-spec.md, docs/technical-spec.md, docs/tasks.md, and docs/handoff.md. Work exactly the next unchecked, non-BLOCKED task in docs/tasks.md following the TDD/sprint methodology in AGENTS.md. Write a failing test first, then the minimal implementation, then check the task off. Update docs/handoff.md before finishing. If you cannot complete the task, mark it BLOCKED: <reason> in docs/tasks.md instead of guessing."

# Runs one iteration with the selected CLI; leaves its exit code in $ret.
run_agent_cli() {
  case "$CLI" in
  copilot)
    copilot -p "$PROMPT" \
      --allow-all-tools \
      --deny-tool='shell(git push*)' \
      --deny-tool='shell(rm -rf*)' \
      -s >>"$LOG_FILE" 2>&1
    ;;
  cline)
    # Headless mode triggers automatically because stdout is redirected below.
    CLINE_COMMAND_PERMISSIONS='{"deny": ["git push*", "rm -rf*", "sudo *"]}' \
      cline --auto-approve true "$PROMPT" >>"$LOG_FILE" 2>&1
    ;;
  esac
  ret=$?
}

log "auto-continue: started (max $MAX_ITERATIONS iterations, cli=$CLI)"

for ((i = 1; i <= MAX_ITERATIONS; i++)); do
  if grep -q '^- \[ \].*BLOCKED' "$TASKS_FILE"; then
    log "auto-continue: stopping — BLOCKED task found after iteration $((i - 1))"
    "$SCRIPT_DIR/check-handoff.sh" >>"$LOG_FILE" 2>&1
    exit 0
  fi
  if ! grep -q '^- \[ \]' "$TASKS_FILE"; then
    log "auto-continue: stopping — no unchecked tasks remain"
    exit 0
  fi

  log "auto-continue: iteration $i — invoking $CLI CLI"
  run_agent_cli
  log "auto-continue: iteration $i finished with exit code $ret"

  if [[ $ret -ne 0 ]]; then
    log "auto-continue: stopping — $CLI CLI returned non-zero"
    # A CLI crash doesn't necessarily leave a BLOCKED task for check-handoff.sh to find, so notify directly.
    if [[ -x ./notify.sh ]]; then
      ./notify.sh "Auto-continue CLI failed" "The $CLI CLI exited $ret during auto-continue iteration $i. See docs/.auto-continue.log." || true
    fi
    exit 0
  fi
done

log "auto-continue: stopping — reached MAX_ITERATIONS ($MAX_ITERATIONS)"
