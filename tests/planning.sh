#!/usr/bin/env bash
set -euo pipefail

KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/ai-session-kit-planning-test.XXXXXX")"
trap 'find "$TEST_ROOT" -depth -delete' EXIT
cd "$TEST_ROOT"
source "$KIT_ROOT/scripts/lib/planning-core.sh"
source "$KIT_ROOT/scripts/lib/handoff-core.sh"

expect_rejected() {
  if bash "$KIT_ROOT/scripts/check-planning.sh" >output 2>&1; then
    echo "Unapproved planning state unexpectedly accepted: $1" >&2
    exit 1
  fi
  grep -F "$1" output >/dev/null
}

expect_rejected 'missing or pending'
mkdir -p docs/planning .github
printf 'Operators: + - * /\n' >docs/functional-spec.md
printf 'Parser and evaluator\n' >docs/technical-spec.md
printf '| S01 | T001 | Reject exponentiation; acceptance: error for 2 ^ 3 | Done |\n' >docs/tasks.md
printf 'Status: Pending\n' >docs/planning/review.md
expect_rejected 'missing or pending'
printf 'Status: Approved\n' >docs/planning/review.md
expect_rejected 'missing, empty, or unreadable'
for name in functional-spec technical-spec tasks; do
  cp "docs/$name.md" "docs/planning/$name.md"
done
bash "$KIT_ROOT/scripts/check-planning.sh" >output
grep -Fx 'Planning approval is current.' output >/dev/null
echo 'PASS: initial planning needs explicit approval and complete snapshots'

printf 'Operators: + - * / ^; 2 ^ 3 = 8\n' >docs/functional-spec.md
expect_rejected 'Specifications differ'
touch .github/auto-continue-enabled
handoff_core_run "$KIT_ROOT/scripts"
[[ "$HANDOFF_MESSAGE" == *'Auto-continue was not started'* ]]
[[ "$HANDOFF_MESSAGE" == *'Specifications differ'* ]]
echo 'PASS: changed specs invalidate approval and prevent hook continuation'

cp docs/functional-spec.md docs/planning/functional-spec.md
printf 'Right-associative exponentiation parser\n' >docs/technical-spec.md
expect_rejected 'Specifications differ'
cp docs/technical-spec.md docs/planning/technical-spec.md
printf '| S01 | T002 | Support exponentiation; acceptance: 2 ^ 3 = 8 | Todo |\n' >>docs/tasks.md
expect_rejected 'Task scope'
cp docs/tasks.md docs/planning/tasks.md
planning_check
printf 'Status: Pending\n' >docs/planning/review.md
expect_rejected 'missing or pending'
printf 'Status: Approved\nStatus: Pending\n' >docs/planning/review.md
expect_rejected 'missing or pending'
printf 'Status: Approved\n' >docs/planning/review.md
echo 'PASS: technical changes, unapproved follow-ups, pending review, and ambiguous approval are rejected'

printf '| S01 | T001 | Reject exponentiation; acceptance: error for 2 ^ 3 | Done |\n| S01 | T002 | Support exponentiation; acceptance: 2 ^ 3 = 8 | In Progress |\n' >docs/tasks.md
planning_check
printf '| S01 | T001 | Reject exponentiation; acceptance: error for 2 ^ 3 | Done |\n| S01 | T002 | Support exponentiation; acceptance: 2 ^ 3 = 8 | Done |\n' >docs/tasks.md
planning_check
handoff_core_run "$KIT_ROOT/scripts"
[[ "$HANDOFF_MESSAGE" == *'nothing to auto-continue'* ]]
echo 'PASS: status-only implementation progress preserves planning approval'

printf '| S01 | T001 | Reject exponentiation; acceptance: error for 2 ^ 3 | ✅ Done · 2026-11-05 |\n| S01 | T002 | Support exponentiation; acceptance: 2 ^ 3 = 8 | 🔄 In Progress · 2026-11-05 (replace Superseded tests) |\n' >docs/tasks.md
planning_check
rm .github/auto-continue-enabled
handoff_core_run "$KIT_ROOT/scripts"
[[ "$HANDOFF_MESSAGE" == *'Auto-continue is off'* ]]
touch .github/auto-continue-enabled
echo 'PASS: emoji/date statuses and status notes preserve scope without implying supersession'

printf '| S01 | T001 | Old behavior | Superseded · replaced by T002 |\n| S01 | T002 | New behavior | Done |\n' >docs/tasks.md
cp docs/tasks.md docs/planning/tasks.md
planning_check
handoff_core_run "$KIT_ROOT/scripts"
[[ "$HANDOFF_MESSAGE" == *'nothing to auto-continue'* ]]
printf '| S01 | T001 | Old behavior | Todo |\n| S01 | T002 | New behavior | Done |\n' >docs/tasks.md
expect_rejected 'Task scope'
echo 'PASS: approved supersessions are terminal and cannot be silently reactivated'

printf '| S01 | T001 | Blocked input now valid | Superseded · scope removed |\n| S01 | T002 | New behavior | Done |\n' >docs/tasks.md
cp docs/tasks.md docs/planning/tasks.md
handoff_core_run "$KIT_ROOT/scripts"
[[ "$HANDOFF_MESSAGE" == *'nothing to auto-continue'* ]]
echo 'PASS: words in descriptions do not create false blockers or unfinished work'

for row in '| S01 | T001 | | Todo |' \
  '| S01 | T001 | Invalid | Unknown |' \
  '| S01 | T001 | Invalid | NotDone |' \
  '| S01 | Tbad | Invalid | Todo |' \
  '| S01 | T001 | Literal | pipe | Todo |'; do
  printf '%s\n' "$row" >docs/tasks.md
  expect_rejected 'blank, duplicate, or malformed'
done
printf '| S01 | T001 | First | Todo |\n| S01 | T001 | Duplicate | Todo |\n' >docs/tasks.md
expect_rejected 'blank, duplicate, or malformed'
cp docs/planning/tasks.md docs/tasks.md
printf '| S01 | T002 | New behavior | Done |\n| S01 | T001 | Blocked input now valid | Superseded · scope removed |\n' >docs/tasks.md
expect_rejected 'Task scope'
echo 'PASS: placeholders, invalid IDs/statuses/cells, duplicate IDs, and reordered tasks are rejected'
