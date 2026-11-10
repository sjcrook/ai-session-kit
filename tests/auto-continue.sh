#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/ai-session-kit-test.XXXXXX")"
cleanup() {
  rm -f "$TEST_ROOT/bin/cline" "$TEST_ROOT/bin/copilot" \
    "$TEST_ROOT/docs/tasks.md" "$TEST_ROOT/.ai-session/auto-continue.log" \
    "$TEST_ROOT/.ai-session/auto-continue.pid" "$TEST_ROOT/.github/auto-continue-enabled" \
    "$TEST_ROOT/.cline/.active-role" "$TEST_ROOT/notify.sh" \
    "$TEST_ROOT/.ai-session/workflow-events.jsonl" "$TEST_ROOT/.ai-session/continuation-paused" \
    "$TEST_ROOT/.ai-session/cline-owner" "$TEST_ROOT/.ai-session/cline-completed" \
    "$TEST_ROOT/.ai-session/last-observed-role" \
    "$TEST_ROOT/calls" "$TEST_ROOT/notifications" "$TEST_ROOT/args" \
    "$TEST_ROOT/release" \
    "$TEST_ROOT/command-exceptions/command-exceptions.conf" \
    "$TEST_ROOT/docs/functional-spec.md" "$TEST_ROOT/docs/technical-spec.md" \
    "$TEST_ROOT/docs/planning/functional-spec.md" "$TEST_ROOT/docs/planning/technical-spec.md" \
    "$TEST_ROOT/docs/planning/tasks.md" "$TEST_ROOT/docs/planning/review.md"
  if [[ -d "$TEST_ROOT/.ai-session/auto-continue.lock" ]]; then
    rmdir "$TEST_ROOT/.ai-session/auto-continue.lock"
  fi
  rmdir "$TEST_ROOT/docs/planning"
  rmdir "$TEST_ROOT/bin" "$TEST_ROOT/docs" "$TEST_ROOT/.ai-session" "$TEST_ROOT/.github" "$TEST_ROOT/.cline" "$TEST_ROOT/tmp" "$TEST_ROOT/command-exceptions" "$TEST_ROOT"
}
trap cleanup EXIT
mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/docs/planning" "$TEST_ROOT/.ai-session" "$TEST_ROOT/.github" "$TEST_ROOT/.cline" "$TEST_ROOT/tmp" "$TEST_ROOT/command-exceptions"
printf 'Calculator requirements\n' >"$TEST_ROOT/docs/functional-spec.md"
printf 'Calculator design\n' >"$TEST_ROOT/docs/technical-spec.md"
cp "$TEST_ROOT/docs/functional-spec.md" "$TEST_ROOT/docs/planning/functional-spec.md"
cp "$TEST_ROOT/docs/technical-spec.md" "$TEST_ROOT/docs/planning/technical-spec.md"

cat >"$TEST_ROOT/bin/cline" <<'MOCK'
#!/usr/bin/env bash
for guidance in 'including temporary cleanup and test setup' \
  'Never retry or disguise a denied operation' 'Cancellation is not completion' \
  'check-planning.sh' 'Never select Superseded work' \
  'never shell writes (including printf/echo redirection, heredocs, or interpreter-based writes)' \
  'If file-editing tools are unavailable' \
  'For regression-only tasks covering existing behavior, a correct test may pass immediately' \
  'Never manufacture a failure by using incorrect expectations or temporarily breaking working code' \
  'For new or changed behavior, confirm it fails because the required behavior is missing'; do
  if [[ "$*" != *"$guidance"* ]]; then
    echo "Missing continuation prompt guidance: $guidance" >&2
    exit 99
  fi
done
printf '%s\n' "$@" >>args
echo call >>calls
case "$MOCK_MODE" in
  hold)
    for ((i = 0; i < 200; i++)); do
      [[ ! -e release ]] || break
      sleep 0.05
    done
    [[ -e release ]] || exit 98
    printf '| S01 | T001 | Example | Done |\n' >docs/tasks.md
    ;;
  abort) printf '\033[2m[abort] aborted by another client\033[0m\n'; exit 0 ;;
  plain-abort) echo '[abort] aborted' >&2; exit 0 ;;
  timeout) echo '[abort] aborted after timeout'; exit 1 ;;
  policy-rejected)
    printf planner >.cline/.active-role
    printf '{"toolName":"run_commands","command":"git status"}' | bash "$KIT_TEST_SCRIPTS/cline-tool-guard.sh"
    printf '{}' | bash "$KIT_TEST_SCRIPTS/check-handoff-cline.sh" TaskCancel
    echo 'Rejected but CLI exits zero'
    exit 0 ;;
  lifecycle-cancel)
    printf '{}' | bash "$KIT_TEST_SCRIPTS/check-handoff-cline.sh" TaskCancel
    exit 0 ;;
  failure) echo 'provider failed' >&2; exit 7 ;;
  stale) echo 'No changes'; exit 0 ;;
  spec-drift)
    printf 'Changed requirements\n' >>docs/functional-spec.md
    echo 'Specifications changed during the iteration'
    ;;
  task-drift)
    printf '| S01 | T001 | Unapproved replacement | Todo |\n' >docs/tasks.md
    echo 'Task scope changed during the iteration'
    ;;
  progress)
    if [[ "$(wc -l <calls | tr -d ' ')" == 1 ]]; then
      echo 'Task one complete'
      printf '| S01 | T001 | First | Done |\n| S01 | T002 | Second | Todo |\n' >docs/tasks.md
    else
      echo 'Task two complete'
      printf '| S01 | T001 | First | Done |\n| S01 | T002 | Second | Done |\n' >docs/tasks.md
    fi
    ;;
  success)
    echo 'Task complete'
    printf '| S01 | T001 | Example | Done |\n' >docs/tasks.md
    ;;
  policy-change)
    if [[ "$(wc -l <calls | tr -d ' ')" == 1 ]]; then
      printf 'allow-recursive-delete\n' >command-exceptions/command-exceptions.conf
      printf '| S01 | T001 | First | Done |\n| S01 | T002 | Second | Todo |\n' >docs/tasks.md
    else
      printf '| S01 | T001 | First | Done |\n| S01 | T002 | Second | Done |\n' >docs/tasks.md
    fi
    ;;
esac
MOCK
cp "$TEST_ROOT/bin/cline" "$TEST_ROOT/bin/copilot"
cat >"$TEST_ROOT/notify.sh" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "$*" >>notifications
MOCK
chmod +x "$TEST_ROOT/bin/cline" "$TEST_ROOT/bin/copilot" "$TEST_ROOT/notify.sh"

run_case() {
  local cli="$1" mode="$2" expected_status="$3" expected_calls="$4" expected_log="$5"
  printf 'Calculator requirements\n' >"$TEST_ROOT/docs/functional-spec.md"
  printf 'Calculator design\n' >"$TEST_ROOT/docs/technical-spec.md"
  cp "$TEST_ROOT/docs/functional-spec.md" "$TEST_ROOT/docs/planning/functional-spec.md"
  cp "$TEST_ROOT/docs/technical-spec.md" "$TEST_ROOT/docs/planning/technical-spec.md"
  printf '| S01 | T001 | Example | Todo |\n' >"$TEST_ROOT/docs/tasks.md"
  if [[ "$mode" == progress || "$mode" == policy-change ]]; then
    printf '| S01 | T001 | First | Todo |\n| S01 | T002 | Second | Todo |\n' >"$TEST_ROOT/docs/tasks.md"
  fi
  if [[ "$mode" == superseded ]]; then
    printf '| S01 | T001 | Example | Superseded · scope removed |\n' >"$TEST_ROOT/docs/tasks.md"
  fi
  cp "$TEST_ROOT/docs/tasks.md" "$TEST_ROOT/docs/planning/tasks.md"
  printf 'Status: Approved\n' >"$TEST_ROOT/docs/planning/review.md"
  : >"$TEST_ROOT/.ai-session/auto-continue.log"
  if [[ "$mode" == success ]]; then
    printf '\033[2m[abort] aborted by another client\033[0m\n' >>"$TEST_ROOT/.ai-session/auto-continue.log"
  fi
  : >"$TEST_ROOT/calls"
  : >"$TEST_ROOT/notifications"
  : >"$TEST_ROOT/args"
  rm -f "$TEST_ROOT/.ai-session/continuation-paused"
  local status=0 limit=4
  if [[ "$mode" == policy-rejected || "$mode" == lifecycle-cancel ]]; then limit=1; fi
  (
    cd "$TEST_ROOT"
    PATH="$TEST_ROOT/bin:$PATH" TMPDIR="$TEST_ROOT/tmp" AUTO_CONTINUE_CLI="$cli" KIT_TEST_SCRIPTS="$SCRIPT_DIR" \
      AUTO_CONTINUE_MAX_ITERATIONS="$limit" MOCK_MODE="$mode" bash "$SCRIPT_DIR/auto-continue.sh"
  ) || status=$?
  [[ "$status" == "$expected_status" ]]
  [[ "$(wc -l <"$TEST_ROOT/calls" | tr -d ' ')" == "$expected_calls" ]]
  grep -F "$expected_log" "$TEST_ROOT/.ai-session/auto-continue.log" >/dev/null
  [[ ! -f "$TEST_ROOT/.ai-session/auto-continue.pid" ]]
  [[ ! -d "$TEST_ROOT/.ai-session/auto-continue.lock" ]]
  if [[ "$mode" == abort || "$mode" == plain-abort || "$mode" == timeout ]]; then
    grep -F 'Auto-continue CLI aborted' "$TEST_ROOT/notifications" >/dev/null
    ! grep -F 'Auto-continue made no progress' "$TEST_ROOT/notifications" >/dev/null
  fi
  if [[ "$mode" == policy-rejected ]]; then
    grep -F 'Policy rejection: tool=run_commands role=planner' "$TEST_ROOT/.ai-session/continuation-paused" >/dev/null
    grep -F '"event":"tool_rejected"' "$TEST_ROOT/.ai-session/workflow-events.jsonl" >/dev/null
    grep -F '"event":"role_released"' "$TEST_ROOT/.ai-session/workflow-events.jsonl" >/dev/null
    [[ "$(cat "$TEST_ROOT/.cline/.active-role")" == none ]]
  fi
  echo "PASS: $cli $mode"
}

run_case cline abort 1 1 'CLI reported an abort'
run_case cline plain-abort 1 1 'CLI reported an abort'
run_case cline timeout 1 1 'CLI reported an abort'
run_case cline failure 1 1 'CLI returned non-zero'
run_case cline policy-rejected 1 1 'continuation paused by'
run_case cline lifecycle-cancel 1 1 'continuation paused by'
run_case cline stale 0 2 'no real progress'
run_case cline progress 0 2 'no unfinished tasks remain'
run_case cline success 0 1 'no unfinished tasks remain'
run_case copilot success 0 1 'no unfinished tasks remain'
for rule in 'git push' 'rm -rf' sudo; do
  grep -Fx -- "--deny-tool=shell($rule:*)" "$TEST_ROOT/args" >/dev/null
done
echo 'PASS: Copilot missing-policy defaults retain all native deny arguments'

for exception in allow-recursive-delete allow-git-push allow-sudo; do
  printf '%s\n' "$exception" >"$TEST_ROOT/command-exceptions/command-exceptions.conf"
  run_case copilot success 0 1 'no unfinished tasks remain'
  for rule in 'git push' 'rm -rf' sudo; do
    case "$exception:$rule" in
      'allow-recursive-delete:rm -rf'|'allow-git-push:git push'|'allow-sudo:sudo')
        ! grep -Fx -- "--deny-tool=shell($rule:*)" "$TEST_ROOT/args" >/dev/null
        grep -F "operator exception enabled: $rule" "$TEST_ROOT/.ai-session/auto-continue.log" >/dev/null ;;
      *) grep -Fx -- "--deny-tool=shell($rule:*)" "$TEST_ROOT/args" >/dev/null ;;
    esac
  done
done
printf 'allow-recursive-delete\nallow-git-push\nallow-sudo\n' >"$TEST_ROOT/command-exceptions/command-exceptions.conf"
run_case copilot success 0 1 'no unfinished tasks remain'
! grep -F -- '--deny-tool=' "$TEST_ROOT/args" >/dev/null
echo 'PASS: Copilot removes only approved deny arguments, including an empty deny array'

for cli in cline copilot; do
  printf 'allow-recursive-delete\ninvalid-secret-entry\n' >"$TEST_ROOT/command-exceptions/command-exceptions.conf"
  run_case "$cli" success 1 0 'command policy error'
  grep -F 'Auto-continue command policy error' "$TEST_ROOT/notifications" >/dev/null
  ! grep -F 'invalid-secret-entry' "$TEST_ROOT/.ai-session/auto-continue.log" >/dev/null
done
echo 'PASS: invalid policy prevents either CLI from launching'

: >"$TEST_ROOT/command-exceptions/command-exceptions.conf"
run_case copilot policy-change 0 2 'no unfinished tasks remain'
[[ "$(grep -Fxc -- '--deny-tool=shell(rm -rf:*)' "$TEST_ROOT/args")" == 1 ]]
[[ "$(grep -Fxc -- '--deny-tool=shell(git push:*)' "$TEST_ROOT/args")" == 2 ]]
echo 'PASS: policy is reloaded between Copilot invocations'

: >"$TEST_ROOT/command-exceptions/command-exceptions.conf"
for cli in cline copilot; do
  run_case "$cli" spec-drift 1 1 'Specifications differ'
  run_case "$cli" task-drift 1 1 'Task scope'
  run_case "$cli" superseded 0 0 'no unfinished tasks remain'
done
echo 'PASS: approval is rechecked between iterations and superseded work never launches an agent'

for cli in cline copilot; do
  printf 'Status: Pending\n' >"$TEST_ROOT/docs/planning/review.md"
  : >"$TEST_ROOT/calls"
  : >"$TEST_ROOT/notifications"
  status=0
  (
    cd "$TEST_ROOT"
    PATH="$TEST_ROOT/bin:$PATH" AUTO_CONTINUE_CLI="$cli" \
      MOCK_MODE=success bash "$SCRIPT_DIR/auto-continue.sh"
  ) || status=$?
  [[ "$status" == 1 ]]
  [[ ! -s "$TEST_ROOT/calls" ]]
  grep -F 'Planning approval required' "$TEST_ROOT/notifications" >/dev/null
done
echo 'PASS: pending planning review prevents either CLI from launching'

printf '| S01 | T001 | Example | Todo |\n' >"$TEST_ROOT/docs/tasks.md"
cp "$TEST_ROOT/docs/tasks.md" "$TEST_ROOT/docs/planning/tasks.md"
printf 'Status: Approved\n' >"$TEST_ROOT/docs/planning/review.md"
: >"$TEST_ROOT/calls"
: >"$TEST_ROOT/.ai-session/auto-continue.log"
workers=()
for ((i = 0; i < 12; i++)); do
  (
    cd "$TEST_ROOT"
    PATH="$TEST_ROOT/bin:$PATH" TMPDIR="$TEST_ROOT/tmp" AUTO_CONTINUE_CLI=cline \
      MOCK_MODE=hold bash "$SCRIPT_DIR/auto-continue.sh"
  ) &
  workers+=("$!")
done
for ((i = 0; i < 100; i++)); do
  [[ ! -s "$TEST_ROOT/calls" ]] || break
  sleep 0.05
done
sleep 0.5
concurrent_calls="$(wc -l <"$TEST_ROOT/calls" | tr -d ' ')"
lock_held=false
[[ ! -d "$TEST_ROOT/.ai-session/auto-continue.lock" ]] || lock_held=true
touch "$TEST_ROOT/release"
for worker in "${workers[@]}"; do
  wait "$worker" || [[ "$?" == 1 ]]
done
[[ "$lock_held" == true ]]
[[ "$concurrent_calls" == 1 ]]
[[ "$(wc -l <"$TEST_ROOT/calls" | tr -d ' ')" == 1 ]]
[[ ! -e "$TEST_ROOT/.ai-session/auto-continue.pid" ]]
[[ ! -e "$TEST_ROOT/.ai-session/auto-continue.lock" ]]
echo 'PASS: twelve simultaneous starts launch exactly one CLI and release runtime ownership'

mkdir "$TEST_ROOT/.ai-session/auto-continue.lock"
: >"$TEST_ROOT/calls"
status=0
(
  cd "$TEST_ROOT"
  PATH="$TEST_ROOT/bin:$PATH" AUTO_CONTINUE_CLI=cline \
    MOCK_MODE=success bash "$SCRIPT_DIR/auto-continue.sh"
) || status=$?
[[ "$status" == 1 ]]
[[ ! -s "$TEST_ROOT/calls" ]]
grep -F 'lock exists without a live recorded worker' "$TEST_ROOT/.ai-session/auto-continue.log" >/dev/null
rmdir "$TEST_ROOT/.ai-session/auto-continue.lock"
run_case cline success 0 1 'no unfinished tasks remain'
echo 'PASS: an abandoned lock fails explicitly and a recovered worker can restart'

rm "$TEST_ROOT/release"
printf '| S01 | T001 | Example | Todo |\n' >"$TEST_ROOT/docs/tasks.md"
cp "$TEST_ROOT/docs/tasks.md" "$TEST_ROOT/docs/planning/tasks.md"
: >"$TEST_ROOT/calls"
(
  cd "$TEST_ROOT"
  PATH="$TEST_ROOT/bin:$PATH" TMPDIR="$TEST_ROOT/tmp" AUTO_CONTINUE_CLI=cline \
    MOCK_MODE=hold bash "$SCRIPT_DIR/auto-continue.sh"
) &
worker=$!
for ((i = 0; i < 100; i++)); do
  [[ ! -s "$TEST_ROOT/calls" ]] || break
  sleep 0.05
done
[[ -s "$TEST_ROOT/calls" ]]
(
  cd "$TEST_ROOT"
  bash "$SCRIPT_DIR/stop-auto-continue.sh"
)
wait "$worker" 2>/dev/null || true
[[ ! -e "$TEST_ROOT/.ai-session/auto-continue.pid" ]]
[[ ! -e "$TEST_ROOT/.ai-session/auto-continue.lock" ]]
run_case cline success 0 1 'no unfinished tasks remain'
echo 'PASS: stopping a real runner releases its lock and permits restart'

printf '%s\n' "$$" >"$TEST_ROOT/.ai-session/auto-continue.pid"
: >"$TEST_ROOT/calls"
(
  cd "$TEST_ROOT"
  PATH="$TEST_ROOT/bin:$PATH" AUTO_CONTINUE_CLI=cline \
    MOCK_MODE=success bash "$SCRIPT_DIR/auto-continue.sh"
)
[[ ! -s "$TEST_ROOT/calls" ]]
[[ "$(cat "$TEST_ROOT/.ai-session/auto-continue.pid")" == "$$" ]]
[[ ! -e "$TEST_ROOT/.ai-session/auto-continue.lock" ]]
rm "$TEST_ROOT/.ai-session/auto-continue.pid"
sleep 0.01 &
old_pid=$!
wait "$old_pid"
printf '%s\n' "$old_pid" >"$TEST_ROOT/.ai-session/auto-continue.pid"
run_case cline success 0 1 'no unfinished tasks remain'
echo 'PASS: legacy live PID ownership is preserved and a stale legacy PID is recovered'

printf 'Operator cancellation\n' >"$TEST_ROOT/.ai-session/continuation-paused"
printf '| S01 | T001 | Example | Todo |\n' >"$TEST_ROOT/docs/tasks.md"
cp "$TEST_ROOT/docs/tasks.md" "$TEST_ROOT/docs/planning/tasks.md"
: >"$TEST_ROOT/calls"
for mode in manual --from-hook; do
  status=0
  (cd "$TEST_ROOT"; PATH="$TEST_ROOT/bin:$PATH" AUTO_CONTINUE_CLI=cline \
    MOCK_MODE=success bash "$SCRIPT_DIR/auto-continue.sh" "$mode") || status=$?
  [[ "$status" == 1 && ! -s "$TEST_ROOT/calls" ]]
  [[ -f "$TEST_ROOT/.ai-session/continuation-paused" ]]
done
(cd "$TEST_ROOT"; PATH="$TEST_ROOT/bin:$PATH" AUTO_CONTINUE_CLI=cline \
  MOCK_MODE=success bash "$SCRIPT_DIR/auto-continue.sh" --resume)
[[ "$(wc -l <"$TEST_ROOT/calls" | tr -d ' ')" == 1 ]]
[[ ! -e "$TEST_ROOT/.ai-session/continuation-paused" ]]
grep -F '"event":"continuation_resumed"' "$TEST_ROOT/.ai-session/workflow-events.jsonl" >/dev/null
echo 'PASS: paused continuation rejects ordinary/hook starts and requires explicit --resume'
