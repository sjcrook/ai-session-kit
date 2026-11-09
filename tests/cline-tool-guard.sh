#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/ai-session-kit-guard-test.XXXXXX")"
cleanup() {
  chmod u+r "$TEST_ROOT/command-exceptions/command-exceptions.conf" 2>/dev/null || true
  rm -f "$TEST_ROOT/.cline/.active-role" "$TEST_ROOT/.ai-session/auto-continue.log" "$TEST_ROOT/guard.stderr" \
    "$TEST_ROOT/command-exceptions/command-exceptions.conf"
  rmdir "$TEST_ROOT/command-exceptions"
  rmdir "$TEST_ROOT/.cline" "$TEST_ROOT/.ai-session" "$TEST_ROOT"
}
trap cleanup EXIT
mkdir -p "$TEST_ROOT/.cline" "$TEST_ROOT/command-exceptions"
cd "$TEST_ROOT"
printf implementer >.cline/.active-role

# These are inputs to the guard only; none of the payload commands are executed.
heredoc_payload='{"toolName":"run_commands","toolInput":{"command":"cat > tests/unit/output.bats <<EOF\nteardown() { rm -rf \"$TMP\"; }\nEOF","secret":"must-not-be-logged"}}'
result="$(printf '%s' "$heredoc_payload" | bash "$SCRIPT_DIR/cline-tool-guard.sh")"
[[ "$result" == *'"cancel": true'* ]]
grep -F 'cline-tool-guard: denied tool=run_commands role=implementer' .ai-session/auto-continue.log >/dev/null
grep -F 'Command matches a denied pattern: rm -rf.' .ai-session/auto-continue.log >/dev/null
[[ "$result" == *'Use file-editing tools for source/test content'* ]]
[[ "$result" == *'See .ai-session/auto-continue.log'* ]]
[[ "$result" != *must-not-be-logged* ]]
! grep -F 'must-not-be-logged' .ai-session/auto-continue.log >/dev/null
echo 'PASS: heredoc denied and reason logged without payload'

editor_payload='{"toolName":"editor","toolInput":{"path":"tests/unit/output.bats","new_text":"teardown() { rm -rf \"$TMP\"; }"}}'
result="$(printf '%s' "$editor_payload" | bash "$SCRIPT_DIR/cline-tool-guard.sh")"
[[ "$result" == '{"cancel": false}' ]]
echo 'PASS: editor can write test content'

for command in 'rm -rf /example' 'git push origin main' 'sudo example'; do
  result="$(printf '{"toolName":"execute_command","command":"%s"}' "$command" | bash "$SCRIPT_DIR/cline-tool-guard.sh")"
  [[ "$result" == *'"cancel": true'* ]]
  case "$command" in
    'rm -rf '*) rule='rm -rf' ;;
    'git push '*) rule='git push' ;;
    'sudo '*) rule='sudo' ;;
  esac
  [[ "$result" == *"Command matches a denied pattern: $rule."* ]]
  [[ "$result" == *'The entire tool call was rejected'* ]]
  [[ "$result" == *'Do not retry or disguise the denied operation'* ]]
done
echo 'PASS: command deny-list preserved'

cleanup_payload='{"toolName":"run_commands","toolInput":{"commands":["bats tests/unit/","T=$(mktemp -d); rm -rf \"$T\""],"secret":"must-not-be-logged"}}'
result="$(printf '%s' "$cleanup_payload" | bash "$SCRIPT_DIR/cline-tool-guard.sh")"
[[ "$result" == *'"cancel": true'* ]]
[[ "$result" == *'Command matches a denied pattern: rm -rf.'* ]]
[[ "$result" == *'including all commands in a batch'* ]]
! grep -F 'must-not-be-logged' .ai-session/auto-continue.log >/dev/null
! grep -F 'mktemp' .ai-session/auto-continue.log >/dev/null
echo 'PASS: temporary cleanup rejects the whole batch without logging payloads'

result="$(printf '%s' '{"toolName":"run_commands","command":"GIT   PUSH origin main"}' | bash "$SCRIPT_DIR/cline-tool-guard.sh")"
[[ "$result" == *'Command matches a denied pattern: git push.'* ]]
echo 'PASS: case-insensitive whitespace matching preserved'

result="$(printf '%s' '{"toolName":"run_commands","command":"bats tests/unit/output.bats"}' | bash "$SCRIPT_DIR/cline-tool-guard.sh")"
[[ "$result" == '{"cancel": false}' ]]
echo 'PASS: normal test commands allowed'

for role in planner handoff-writer; do
  printf '%s' "$role" >.cline/.active-role
  for tool in run_commands execute_command; do
    result="$(printf '{"toolName":"%s","command":"echo example"}' "$tool" | bash "$SCRIPT_DIR/cline-tool-guard.sh")"
    [[ "$result" == *'"cancel": true'* ]]
    grep -F "denied tool=$tool role=$role" .ai-session/auto-continue.log >/dev/null
  done
  result="$(printf '%s' "$editor_payload" | bash "$SCRIPT_DIR/cline-tool-guard.sh")"
  [[ "$result" == '{"cancel": false}' ]]
done
echo 'PASS: role restrictions preserved'

for state in missing empty none; do
  case "$state" in
    missing) rm .cline/.active-role ;;
    empty) : >.cline/.active-role ;;
    none) printf none >.cline/.active-role ;;
  esac
  for tool in run_commands execute_command; do
    result="$(printf '{"toolName":"%s","command":"git status"}' "$tool" | bash "$SCRIPT_DIR/cline-tool-guard.sh")"
    [[ "$result" == '{"cancel": false}' ]]
    for command in 'rm -rf /example' 'git push origin main' 'sudo example'; do
      result="$(printf '{"toolName":"%s","command":"%s"}' "$tool" "$command" | bash "$SCRIPT_DIR/cline-tool-guard.sh")"
      [[ "$result" == *'"cancel": true'* ]]
      [[ "$result" == *'Command matches a denied pattern:'* ]]
    done
  done
done
echo 'PASS: missing, empty, and neutral roles allow orientation without bypassing command policy'

printf implementer >.cline/.active-role
rm -f .ai-session/auto-continue.log
rmdir .ai-session
touch .ai-session
result="$(printf '%s' "$cleanup_payload" | bash "$SCRIPT_DIR/cline-tool-guard.sh" 2>guard.stderr)"
[[ "$result" == *'"cancel": true'* ]]
[[ "$result" == *'See hook stderr for the diagnostic'* ]]
grep -F 'denied tool=run_commands role=implementer' guard.stderr >/dev/null
! grep -F 'must-not-be-logged' guard.stderr >/dev/null
rm .ai-session
mkdir .ai-session

mkdir .ai-session/auto-continue.log
result="$(printf '%s' "$cleanup_payload" | bash "$SCRIPT_DIR/cline-tool-guard.sh" 2>guard.stderr)"
[[ "$result" == *'"cancel": true'* ]]
[[ "$result" == *'See hook stderr for the diagnostic'* ]]
grep -F 'could not write .ai-session/auto-continue.log' guard.stderr >/dev/null
grep -F 'Command matches a denied pattern: rm -rf.' guard.stderr >/dev/null
! grep -F 'must-not-be-logged' guard.stderr >/dev/null
rmdir .ai-session/auto-continue.log
echo 'PASS: absent or unwritable log falls back explicitly to stderr'

policy="command-exceptions/command-exceptions.conf"
printf '# No grants\n\n' >"$policy"
result="$(printf '%s' "$cleanup_payload" | bash "$SCRIPT_DIR/cline-tool-guard.sh")"
[[ "$result" == *'"cancel": true'* ]]
echo 'PASS: empty and missing policies retain default restrictions'

for exception in allow-recursive-delete allow-git-push allow-sudo; do
  printf '%s\n' "$exception" >"$policy"
  for command in 'rm -rf /example' 'git push origin main' 'sudo example'; do
    result="$(printf '{"toolName":"execute_command","command":"%s"}' "$command" | bash "$SCRIPT_DIR/cline-tool-guard.sh")"
    case "$exception:$command" in
      'allow-recursive-delete:rm -rf '*|'allow-git-push:git push '*|'allow-sudo:sudo '*)
        [[ "$result" == '{"cancel": false}' ]] ;;
      *) [[ "$result" == *'"cancel": true'* ]] ;;
    esac
  done
done
echo 'PASS: each named exception grants only its own command class'

mixed_payload='{"toolName":"run_commands","commands":["rm -rf /example","git push origin main"],"secret":"must-not-be-logged"}'
printf 'allow-recursive-delete\n' >"$policy"
: >.ai-session/auto-continue.log
result="$(printf '%s' "$mixed_payload" | bash "$SCRIPT_DIR/cline-tool-guard.sh")"
[[ "$result" == *'"cancel": true'* ]]
[[ "$result" == *'denied pattern: git push.'* ]]
! grep -F 'allowed by operator exception' .ai-session/auto-continue.log >/dev/null
printf 'allow-recursive-delete\nallow-git-push\n' >"$policy"
result="$(printf '%s' "$mixed_payload" | bash "$SCRIPT_DIR/cline-tool-guard.sh")"
[[ "$result" == '{"cancel": false}' ]]
grep -F 'allowed by operator exception tool=run_commands role=implementer: rm -rf' .ai-session/auto-continue.log >/dev/null
grep -F 'allowed by operator exception tool=run_commands role=implementer: git push' .ai-session/auto-continue.log >/dev/null
! grep -F 'must-not-be-logged' .ai-session/auto-continue.log >/dev/null
printf '# Revoked\n' >"$policy"
result="$(printf '%s' "$mixed_payload" | bash "$SCRIPT_DIR/cline-tool-guard.sh")"
[[ "$result" == *'"cancel": true'* ]]
echo 'PASS: all matched rules need approval; subsequent calls observe grants and revocation'

printf 'allow-recursive-delete\nallow-git-push\nallow-sudo\n' >"$policy"
for role in planner handoff-writer; do
  printf '%s' "$role" >.cline/.active-role
  result="$(printf '%s' "$cleanup_payload" | bash "$SCRIPT_DIR/cline-tool-guard.sh")"
  [[ "$result" == *'"cancel": true'* ]]
  [[ "$result" == *"The '$role' role does not run shell commands"* ]]
done
printf implementer >.cline/.active-role
echo 'PASS: operator exceptions do not override role restrictions'

printf '  # Comments and CRLF\r\n\tallow-recursive-delete \r\nallow-recursive-delete\r\n' >"$policy"
result="$(printf '%s' "$cleanup_payload" | bash "$SCRIPT_DIR/cline-tool-guard.sh")"
[[ "$result" == '{"cancel": false}' ]]
echo 'PASS: whitespace, CRLF, and duplicate entries accepted'

for invalid in 'unknown-secret-entry' 'allow-recursive-delete extra' '$(touch policy-executed)'; do
  printf 'allow-recursive-delete\n%s\n' "$invalid" >"$policy"
  result="$(printf '%s' "$cleanup_payload" | bash "$SCRIPT_DIR/cline-tool-guard.sh")"
  [[ "$result" == *'"cancel": true'* ]]
  [[ "$result" == *'Command policy error:'* ]]
  [[ "$result" != *"$invalid"* ]]
  result="$(printf '%s' '{"toolName":"run_commands","command":"echo permitted"}' | bash "$SCRIPT_DIR/cline-tool-guard.sh")"
  [[ "$result" == *'Command policy error:'* ]]
  result="$(printf '%s' "$editor_payload" | bash "$SCRIPT_DIR/cline-tool-guard.sh")"
  [[ "$result" == '{"cancel": false}' ]]
done
[[ ! -e policy-executed ]]
! grep -F 'unknown-secret-entry' .ai-session/auto-continue.log >/dev/null
echo 'PASS: invalid policy blocks shell access, leaks no values, and is never executed'

printf 'allow-recursive-delete\n' >"$policy"
chmod 000 "$policy"
if [[ ! -r "$policy" ]]; then
  result="$(printf '%s' "$cleanup_payload" | bash "$SCRIPT_DIR/cline-tool-guard.sh")"
  [[ "$result" == *'Command policy error:'* ]]
else
  echo 'SKIP: unreadable-file check requires a non-root test user'
fi
chmod 600 "$policy"
rm "$policy"
ln -s missing-policy "$policy"
result="$(printf '%s' "$cleanup_payload" | bash "$SCRIPT_DIR/cline-tool-guard.sh")"
[[ "$result" == *'Command policy error:'* ]]
rm "$policy"
mkdir "$policy"
result="$(printf '%s' "$cleanup_payload" | bash "$SCRIPT_DIR/cline-tool-guard.sh")"
[[ "$result" == *'Command policy error:'* ]]
rmdir "$policy"
rmdir command-exceptions
ln -s docs command-exceptions
result="$(printf '%s' "$cleanup_payload" | bash "$SCRIPT_DIR/cline-tool-guard.sh")"
[[ "$result" == *'Command policy error:'* ]]
rm command-exceptions
mkdir command-exceptions
echo 'PASS: unreadable and non-regular policy files cannot grant exceptions'
