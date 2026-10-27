#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/ai-session-kit-guard-test.XXXXXX")"
cleanup() {
  rm -f "$TEST_ROOT/.cline/.active-role" "$TEST_ROOT/docs/.auto-continue.log" "$TEST_ROOT/guard.stderr"
  rmdir "$TEST_ROOT/.cline" "$TEST_ROOT/docs" "$TEST_ROOT"
}
trap cleanup EXIT
mkdir -p "$TEST_ROOT/.cline" "$TEST_ROOT/docs"
cd "$TEST_ROOT"
printf implementer >.cline/.active-role

# These are inputs to the guard only; none of the payload commands are executed.
heredoc_payload='{"toolName":"run_commands","toolInput":{"command":"cat > tests/unit/output.bats <<EOF\nteardown() { rm -rf \"$TMP\"; }\nEOF","secret":"must-not-be-logged"}}'
result="$(printf '%s' "$heredoc_payload" | bash "$SCRIPT_DIR/cline-tool-guard.sh")"
[[ "$result" == *'"cancel": true'* ]]
grep -F 'cline-tool-guard: denied tool=run_commands role=implementer' docs/.auto-continue.log >/dev/null
grep -F 'Command matches a denied pattern: rm -rf.' docs/.auto-continue.log >/dev/null
[[ "$result" == *'Use file-editing tools for source/test content'* ]]
[[ "$result" == *'See docs/.auto-continue.log'* ]]
[[ "$result" != *must-not-be-logged* ]]
! grep -F 'must-not-be-logged' docs/.auto-continue.log >/dev/null
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
! grep -F 'must-not-be-logged' docs/.auto-continue.log >/dev/null
! grep -F 'mktemp' docs/.auto-continue.log >/dev/null
echo 'PASS: temporary cleanup rejects the whole batch without logging payloads'

result="$(printf '%s' '{"toolName":"run_commands","command":"GIT   PUSH origin main"}' | bash "$SCRIPT_DIR/cline-tool-guard.sh")"
[[ "$result" == *'Command matches a denied pattern: git push.'* ]]
echo 'PASS: case-insensitive whitespace matching preserved'

result="$(printf '%s' '{"toolName":"run_commands","command":"bats tests/unit/output.bats"}' | bash "$SCRIPT_DIR/cline-tool-guard.sh")"
[[ "$result" == '{"cancel": false}' ]]
echo 'PASS: normal test commands allowed'

for role in planner handoff-writer; do
  printf '%s' "$role" >.cline/.active-role
  result="$(printf '%s' '{"toolName":"run_commands","command":"echo example"}' | bash "$SCRIPT_DIR/cline-tool-guard.sh")"
  [[ "$result" == *'"cancel": true'* ]]
  grep -F "denied tool=run_commands role=$role" docs/.auto-continue.log >/dev/null
  result="$(printf '%s' "$editor_payload" | bash "$SCRIPT_DIR/cline-tool-guard.sh")"
  [[ "$result" == '{"cancel": false}' ]]
done
echo 'PASS: role restrictions preserved'

printf implementer >.cline/.active-role
rm -f docs/.auto-continue.log
rmdir docs
result="$(printf '%s' "$cleanup_payload" | bash "$SCRIPT_DIR/cline-tool-guard.sh" 2>guard.stderr)"
[[ "$result" == *'"cancel": true'* ]]
[[ "$result" == *'See hook stderr for the diagnostic'* ]]
grep -F 'denied tool=run_commands role=implementer' guard.stderr >/dev/null
! grep -F 'must-not-be-logged' guard.stderr >/dev/null
mkdir docs

mkdir docs/.auto-continue.log
result="$(printf '%s' "$cleanup_payload" | bash "$SCRIPT_DIR/cline-tool-guard.sh" 2>guard.stderr)"
[[ "$result" == *'"cancel": true'* ]]
[[ "$result" == *'See hook stderr for the diagnostic'* ]]
grep -F 'could not write docs/.auto-continue.log' guard.stderr >/dev/null
grep -F 'Command matches a denied pattern: rm -rf.' guard.stderr >/dev/null
! grep -F 'must-not-be-logged' guard.stderr >/dev/null
rmdir docs/.auto-continue.log
echo 'PASS: absent or unwritable log falls back explicitly to stderr'
