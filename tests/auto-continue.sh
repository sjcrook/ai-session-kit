#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/ai-session-kit-test.XXXXXX")"
cleanup() {
  rm -f "$TEST_ROOT/bin/cline" "$TEST_ROOT/bin/copilot" \
    "$TEST_ROOT/docs/tasks.md" "$TEST_ROOT/.ai-session/auto-continue.log" \
    "$TEST_ROOT/.ai-session/auto-continue.pid" "$TEST_ROOT/.github/auto-continue-enabled" \
    "$TEST_ROOT/.cline/.active-role" "$TEST_ROOT/notify.sh" \
    "$TEST_ROOT/calls" "$TEST_ROOT/notifications" "$TEST_ROOT/args" \
    "$TEST_ROOT/command-exceptions/command-exceptions.conf"
  rmdir "$TEST_ROOT/bin" "$TEST_ROOT/docs" "$TEST_ROOT/.ai-session" "$TEST_ROOT/.github" "$TEST_ROOT/.cline" "$TEST_ROOT/tmp" "$TEST_ROOT/command-exceptions" "$TEST_ROOT"
}
trap cleanup EXIT
mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/docs" "$TEST_ROOT/.ai-session" "$TEST_ROOT/.github" "$TEST_ROOT/.cline" "$TEST_ROOT/tmp" "$TEST_ROOT/command-exceptions"

cat >"$TEST_ROOT/bin/cline" <<'MOCK'
#!/usr/bin/env bash
for guidance in 'including temporary cleanup and test setup' \
  'Never retry or disguise a denied operation' 'Cancellation is not completion'; do
  if [[ "$*" != *"$guidance"* ]]; then
    echo "Missing continuation prompt guidance: $guidance" >&2
    exit 99
  fi
done
printf '%s\n' "$@" >>args
echo call >>calls
case "$MOCK_MODE" in
  abort) printf '\033[2m[abort] aborted by another client\033[0m\n'; exit 0 ;;
  plain-abort) echo '[abort] aborted' >&2; exit 0 ;;
  timeout) echo '[abort] aborted after timeout'; exit 1 ;;
  failure) echo 'provider failed' >&2; exit 7 ;;
  stale) echo 'No changes'; exit 0 ;;
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
  printf '| S01 | T001 | Example | Todo |\n' >"$TEST_ROOT/docs/tasks.md"
  : >"$TEST_ROOT/.ai-session/auto-continue.log"
  if [[ "$mode" == success ]]; then
    printf '\033[2m[abort] aborted by another client\033[0m\n' >>"$TEST_ROOT/.ai-session/auto-continue.log"
  fi
  : >"$TEST_ROOT/calls"
  : >"$TEST_ROOT/notifications"
  : >"$TEST_ROOT/args"
  local status=0
  (
    cd "$TEST_ROOT"
    PATH="$TEST_ROOT/bin:$PATH" TMPDIR="$TEST_ROOT/tmp" AUTO_CONTINUE_CLI="$cli" \
      AUTO_CONTINUE_MAX_ITERATIONS=4 MOCK_MODE="$mode" bash "$SCRIPT_DIR/auto-continue.sh"
  ) || status=$?
  [[ "$status" == "$expected_status" ]]
  [[ "$(wc -l <"$TEST_ROOT/calls" | tr -d ' ')" == "$expected_calls" ]]
  grep -F "$expected_log" "$TEST_ROOT/.ai-session/auto-continue.log" >/dev/null
  [[ ! -f "$TEST_ROOT/.ai-session/auto-continue.pid" ]]
  if [[ "$mode" == abort || "$mode" == plain-abort || "$mode" == timeout ]]; then
    grep -F 'Auto-continue CLI aborted' "$TEST_ROOT/notifications" >/dev/null
    ! grep -F 'Auto-continue made no progress' "$TEST_ROOT/notifications" >/dev/null
  fi
  echo "PASS: $cli $mode"
}

run_case cline abort 1 1 'CLI reported an abort'
run_case cline plain-abort 1 1 'CLI reported an abort'
run_case cline timeout 1 1 'CLI reported an abort'
run_case cline failure 0 1 'CLI returned non-zero'
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
