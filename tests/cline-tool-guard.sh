#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/ai-session-kit-guard-test.XXXXXX")"
cleanup() {
  rm -f "$TEST_ROOT/.cline/.active-role" "$TEST_ROOT/docs/.auto-continue.log"
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
grep -F 'Command matches a denied pattern' docs/.auto-continue.log >/dev/null
! grep -F 'must-not-be-logged' docs/.auto-continue.log >/dev/null
echo 'PASS: heredoc denied and reason logged without payload'

editor_payload='{"toolName":"editor","toolInput":{"path":"tests/unit/output.bats","new_text":"teardown() { rm -rf \"$TMP\"; }"}}'
result="$(printf '%s' "$editor_payload" | bash "$SCRIPT_DIR/cline-tool-guard.sh")"
[[ "$result" == '{"cancel": false}' ]]
echo 'PASS: editor can write test content'

for command in 'rm -rf /example' 'git push origin main' 'sudo example'; do
  result="$(printf '{"toolName":"execute_command","command":"%s"}' "$command" | bash "$SCRIPT_DIR/cline-tool-guard.sh")"
  [[ "$result" == *'"cancel": true'* ]]
done
echo 'PASS: command deny-list preserved'

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
