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
source "$SCRIPT_DIR/lib/command-policy.sh"
TASKS_FILE="docs/tasks.md"
LOG_FILE=".ai-session/auto-continue.log"
PID_FILE=".ai-session/auto-continue.pid"
# Default of 10 is deliberately generous enough to clear a typical small
# sprint backlog (e.g. 5 simple tasks) in a single run without needing to be
# manually re-triggered, while still bounded (not unlimited) as a safety
# rail. The no-progress check below provides a second, earlier safety net:
# a stuck loop stops and notifies well before exhausting this cap. Override
# with the AUTO_CONTINUE_MAX_ITERATIONS env var for direct/manual runs.
MAX_ITERATIONS="${AUTO_CONTINUE_MAX_ITERATIONS:-10}"
AUTO_CONTINUE_FLAG=".github/auto-continue-enabled"

log() { echo "$(date -u +%FT%TZ) $*" >>"$LOG_FILE"; }

if ! mkdir -p .ai-session; then
  echo "Cannot create .ai-session runtime directory." >&2
  exit 1
fi
if ! touch "$LOG_FILE"; then
  echo "Cannot write runtime log $LOG_FILE." >&2
  exit 1
fi
echo "Auto-continue log: $LOG_FILE"

# Concurrent-loop guard: if a previous auto-continue.sh is still running (its
# PID file points at a live process), don't start a second one — two loops
# racing on the same docs/tasks.md could both grab the same "next" task and
# step on each other's edits. A leftover PID file from a crashed/killed
# previous run (process no longer alive) is safe to clear and proceed past.
if [[ -f "$PID_FILE" ]]; then
  existing_pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  if [[ -n "$existing_pid" ]] && kill -0 "$existing_pid" 2>/dev/null; then
    log "auto-continue: stopping — another instance is already running (pid $existing_pid)"
    exit 0
  fi
  rm -f "$PID_FILE"
fi

echo "$$" >"$PID_FILE"
CLI_OUTPUT=""
cleanup() {
  rm -f "$PID_FILE"
  if [[ -n "$CLI_OUTPUT" ]]; then
    rm -f "$CLI_OUTPUT"
  fi
}
trap cleanup EXIT

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

if [[ "$CLI" == "cline" ]]; then
  if ! CLI_OUTPUT="$(mktemp "${TMPDIR:-/tmp}/ai-session-kit-cline.XXXXXX")"; then
    log "auto-continue: stopping — could not create a temporary Cline output file"
    exit 1
  fi
fi

PROMPT="Read AGENTS.md, docs/functional-spec.md, docs/technical-spec.md, docs/tasks.md, and docs/handoff.md. Work exactly the next Todo or In Progress task in docs/tasks.md following the TDD/sprint methodology in AGENTS.md — if it's already In Progress, verify real state (git status/diff, test run) before resuming rather than assuming the prior session left it in a working state. Use file-editing tools to create or edit source and tests, not shell heredocs: the command guard scans the entire shell payload, including file content. Do not bypass a denied command. Write a failing test first, then the minimal implementation, then set its status to Done in docs/tasks.md. Update docs/handoff.md before finishing. If you cannot complete the task, set its status to Blocked with a reason in docs/tasks.md instead of guessing."
PROMPT+=" The git push, rm -rf, and sudo deny-list applies to direct commands too, including temporary cleanup and test setup, unless the operator grants the corresponding named exception in command-exceptions/command-exceptions.conf. Never create, edit, or redirect that operator policy or its enforcement files. Using an operator-granted exception is permitted. An unapproved match anywhere in a batch rejects the entire tool call and may end the Cline task. Prefer established test fixtures; plan cleanup of session-created artifacts using explicitly identified individual files and then empty directories. Never retry or disguise a denied operation with alternate spellings, interpreters, or wrappers. When resuming after a denial, check .ai-session/auto-continue.log (or hook stderr if logging was unavailable) and verify real state; do not assume any rejected batch ran. After the operator changes permission, reassess only the affected blocker and rerun necessary validation. Cancellation is not completion; report a necessary operation with no permitted workflow as a blocker."

# Runs one iteration; preserves the CLI exit code and detects Cline aborts,
# which can be reported in output even when the process exits successfully.
run_agent_cli() {
  cli_aborted=false
  if ! command_policy_load; then
    log "auto-continue: stopping — command policy error: $COMMAND_POLICY_ERROR"
    if [[ -x ./notify.sh ]]; then
      ./notify.sh "Auto-continue command policy error" "$COMMAND_POLICY_ERROR No agent was launched. Correct command-exceptions/command-exceptions.conf from the host before restarting." || log "auto-continue: policy error notification failed"
    fi
    exit 1
  fi
  case "$CLI" in
  copilot)
    # --agent implementer: explicitly identifies this invocation as the
    # implementer persona (.github/agents/implementer.agent.md, always
    # present from the scaffold) rather than running unscoped — mirrors the
    # explicit role=implementer reset the cline branch below performs.
    #
    # NOTE on --deny-tool syntax: confirmed empirically that a trailing `*`
    # glob (e.g. 'shell(rm -rf*)', what this repo used previously) only
    # matches that exact literal string — a real `rm -rf <anything>` call
    # was NOT blocked by it. The working wildcard syntax is a `:*` suffix
    # (e.g. 'shell(rm -rf:*)'), confirmed empirically to actually block the
    # command. This was a pre-existing, silent no-op bug, not specific to
    # auto-continue's use of it.
    local copilot_args=(-p "$PROMPT" --agent implementer --allow-all-tools -s)
    local rule
    for rule in 'git push' 'rm -rf' 'sudo'; do
      if command_policy_allows "$rule"; then
        log "auto-continue: copilot operator exception enabled: $rule (command-exceptions/command-exceptions.conf)"
      else
        copilot_args+=("--deny-tool=shell($rule:*)")
      fi
    done
    copilot "${copilot_args[@]}" >>"$LOG_FILE" 2>&1
    ret=$?
    ;;
  cline)
    # This invocation always needs real shell access to implement tasks, so
    # clear any role restriction a previous interactive session left behind
    # in .cline/.active-role (see scripts/cline-tool-guard.sh) before running —
    # otherwise a session that last used the planner or handoff-writer role
    # would leave the continuation loop wrongly blocked from running shell
    # commands at all.
    mkdir -p .cline
    printf 'implementer' >.cline/.active-role

    # Headless mode triggers automatically because stdout is redirected below.
    # NOTE: deny-listing dangerous commands here via an env var doesn't work —
    # confirmed empirically that CLINE_COMMAND_PERMISSIONS has no effect; the
    # Cline CLI has no built-in command allow/deny list. The equivalent of
    # Copilot's --deny-tool above is the scaffolded PreToolUse hook
    # (.cline/hooks/PreToolUse.sh / .clinerules/hooks/PreToolUse, both backed
    # by scripts/cline-tool-guard.sh), which actually cancels matching tool
    # calls and applies to every Cline session in the project, not just this
    # one invocation.
    cline --auto-approve true "$PROMPT" 2>&1 | tee "$CLI_OUTPUT" >>"$LOG_FILE"
    local pipeline_status=("${PIPESTATUS[@]}")
    ret="${pipeline_status[0]}"
    if [[ "${pipeline_status[1]}" -ne 0 ]]; then
      log "auto-continue: stopping — could not capture Cline output"
      exit 1
    fi
    # Strip terminal colors and inspect only this invocation, not aborts from
    # earlier sessions in the append-only log. Do not short-circuit grep: under
    # pipefail that could make sed's SIGPIPE hide a matching abort.
    if sed $'s/\033\\[[0-9;]*m//g' "$CLI_OUTPUT" | grep -E '^[[:space:]]*\[abort\]' >/dev/null; then
      cli_aborted=true
    fi
    ;;
  esac
}

log "auto-continue: started (max $MAX_ITERATIONS iterations, cli=$CLI)"

prev_tasks_content=""
stale_count=0

for ((i = 1; i <= MAX_ITERATIONS; i++)); do
  # Task rows start "| S<sprint> | T<task> |" — anchored so this doesn't also match the legend line.
  if grep -qE '^\| *S[0-9]+ *\| *T[0-9]+ *\|.*Blocked' "$TASKS_FILE"; then
    log "auto-continue: stopping — Blocked task found after iteration $((i - 1))"
    "$SCRIPT_DIR/check-handoff.sh" >>"$LOG_FILE" 2>&1
    exit 0
  fi
  # Single-process check (no pipe): under `set -o pipefail`, a two-stage
  # `grep | grep -q` here would be racy — `grep -q` exits as soon as it finds
  # a match, which can SIGPIPE the upstream grep before it finishes writing,
  # and pipefail then reports that SIGPIPE as the pipeline's failure status
  # even though a real unfinished task was found. That flips this check's
  # sense and makes the loop stop early, claiming "no unfinished tasks
  # remain" while rows further down the file are still Todo.
  if ! awk '/^\| *S[0-9]+ *\| *T[0-9]+ *\|/ && !/Done/ { found=1 } END { exit !found }' "$TASKS_FILE"; then
    log "auto-continue: stopping — no unfinished tasks remain"
    exit 0
  fi

  # No-progress safety net: compare the whole file's content (not just a
  # remaining-count) across iterations, so a task legitimately left
  # "In Progress (depends on T0XX)" — real but incomplete progress — doesn't
  # look identical to a genuinely stuck loop that changed nothing at all. Two
  # consecutive iterations with byte-identical docs/tasks.md, despite the CLI
  # reporting success each time, means something is wrong (confused model,
  # task it can't actually act on, etc.) — stop and notify well before
  # burning the full MAX_ITERATIONS budget on a stuck loop.
  current_tasks_content="$(cat "$TASKS_FILE" 2>/dev/null || true)"
  if [[ "$i" -gt 1 && "$current_tasks_content" == "$prev_tasks_content" ]]; then
    stale_count=$((stale_count + 1))
  else
    stale_count=0
  fi
  if [[ "$stale_count" -ge 2 ]]; then
    log "auto-continue: stopping — $TASKS_FILE unchanged for 2 consecutive iterations (no real progress)"
    if [[ -x ./notify.sh ]]; then
      ./notify.sh "Auto-continue made no progress" "auto-continue stopped after $i iterations: $TASKS_FILE's content didn't change for 2 consecutive iterations even though the $CLI CLI reported success each time. See .ai-session/auto-continue.log." || true
    fi
    exit 0
  fi

  log "auto-continue: iteration $i — invoking $CLI CLI"
  run_agent_cli
  log "auto-continue: iteration $i finished with exit code $ret"

  if [[ "$cli_aborted" == true ]]; then
    log "auto-continue: stopping — $CLI CLI reported an abort (exit code $ret); task completion was interrupted"
    if [[ -x ./notify.sh ]]; then
      ./notify.sh "Auto-continue CLI aborted" "Cline reported an abort during auto-continue iteration $i (exit code $ret). This is not successful task completion. Check .ai-session/auto-continue.log and Cline's session diagnostics for the cancellation source before restarting; do not run competing clients against the same session." || true
    fi
    exit 1
  fi

  if [[ $ret -ne 0 ]]; then
    log "auto-continue: stopping — $CLI CLI returned non-zero"
    # A CLI crash doesn't necessarily leave a BLOCKED task for check-handoff.sh to find, so notify directly.
    if [[ -x ./notify.sh ]]; then
      ./notify.sh "Auto-continue CLI failed" "The $CLI CLI exited $ret during auto-continue iteration $i. See .ai-session/auto-continue.log." || true
    fi
    exit 0
  fi

  prev_tasks_content="$current_tasks_content"
done

log "auto-continue: stopping — reached MAX_ITERATIONS ($MAX_ITERATIONS)"
if [[ -x ./notify.sh ]]; then
  ./notify.sh "Auto-continue reached its iteration cap" "auto-continue stopped after $MAX_ITERATIONS iterations with unfinished tasks still remaining in $TASKS_FILE. Re-trigger it (e.g. end another session with auto-continue still enabled) for another batch, or raise AUTO_CONTINUE_MAX_ITERATIONS. See .ai-session/auto-continue.log." || true
fi
