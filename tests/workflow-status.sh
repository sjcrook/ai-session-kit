#!/usr/bin/env bash
set -euo pipefail
KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/ai-session-kit-status-test.XXXXXX")"
trap 'find "$TEST_ROOT" -depth -delete' EXIT
cd "$TEST_ROOT"

bash "$KIT_ROOT/scripts/workflow-status.sh" >output
grep -Fx 'Readiness: planning-required' output >/dev/null
grep -F 'Ask whether to start /tasks' output >/dev/null
[[ ! -e .ai-session && ! -e .cline && ! -e docs ]]
echo 'PASS: missing planning state gets a next step without creating runtime files'

mkdir -p docs/planning .cline .github
printf 'Requirements\n' >docs/functional-spec.md
printf 'Design\n' >docs/technical-spec.md
printf '| S01 | T001 | First | Done |\n| S01 | T002 | Second | In Progress |\n| S01 | T003 | Third | Todo |\n' >docs/tasks.md
for name in functional-spec technical-spec tasks; do cp "docs/$name.md" "docs/planning/$name.md"; done
printf 'Status: Approved\n' >docs/planning/review.md
printf none >.cline/.active-role
bash "$KIT_ROOT/scripts/workflow-status.sh" >output
grep -Fx 'Readiness: ready' output >/dev/null
grep -F 'Next eligible task: T002.' output >/dev/null
grep -F 'not proof that a workflow is active or inactive' output >/dev/null
[[ ! -e .ai-session ]]
echo 'PASS: approved readiness selects the first eligible task, not a stale handoff'

printf '| S01 | T001 | First | Done |\n| S01 | T002 | Second | Done |\n| S01 | T003 | Third | Blocked · decision needed |\n' >docs/tasks.md
bash "$KIT_ROOT/scripts/workflow-status.sh" >output
grep -Fx 'Readiness: blocked' output >/dev/null
grep -F 'Blocked task T003' output >/dev/null
printf '| S01 | T001 | First | Done |\n| S01 | T002 | Second | Done |\n| S01 | T003 | Third | Superseded |\n' >docs/tasks.md
cp docs/tasks.md docs/planning/tasks.md
bash "$KIT_ROOT/scripts/workflow-status.sh" >output
grep -Fx 'Readiness: complete' output >/dev/null
echo 'PASS: blockers and approved supersessions have consistent readiness outcomes'

source "$KIT_ROOT/scripts/lib/workflow-runtime.sh"
workflow_pause 'Test interruption: "quoted" \ reason'
before="$(find . -type f -exec cksum {} \; | sort)"
bash "$KIT_ROOT/scripts/workflow-status.sh" >"$TEST_ROOT/status-output"
after="$(find . -type f ! -name status-output -exec cksum {} \; | sort)"
[[ "$before" == "$after" ]]
grep -Fx 'Continuation: paused' status-output >/dev/null
grep -F -- '--resume' status-output >/dev/null
grep -F 'Latest recorded event (not an inferred cause)' status-output >/dev/null
[[ "$(workflow_json_string $'quote" slash\\\nline\ttab\r')" == '"quote\" slash\\\nline\ttab\r"' ]]
echo 'PASS: paused status is read-only and diagnostics escape JSON text'

source "$KIT_ROOT/scripts/lib/handoff-core.sh"
touch .github/auto-continue-enabled
handoff_core_run "$KIT_ROOT/scripts"
[[ "$HANDOFF_MESSAGE" == *'Continuation is paused'* ]]
[[ ! -e .ai-session/auto-continue.pid ]]
echo 'PASS: a completion hook cannot restart paused continuation even when enabled'
