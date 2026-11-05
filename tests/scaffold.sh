#!/usr/bin/env bash
set -euo pipefail

KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/ai-session-kit-scaffold-test.XXXXXX")"
trap 'find "$TEST_ROOT" -depth -delete' EXIT
mkdir "$TEST_ROOT/project"
project="$TEST_ROOT/project"
policy="$project/command-exceptions/command-exceptions.conf"

bash "$KIT_ROOT/template/create-scaffold-kit.sh" "$project" </dev/null >"$TEST_ROOT/output"
cmp "$policy" "$KIT_ROOT/template/project/command-exceptions/command-exceptions.conf"
grep -Fx '/command-exceptions/' "$project/.gitignore" >/dev/null
grep -Fx '/.ai-session/' "$project/.gitignore" >/dev/null
(
  cd "$project"
  source "$KIT_ROOT/scripts/lib/command-policy.sh"
  command_policy_load
  for rule in 'git push' 'rm -rf' sudo; do
    ! command_policy_allows "$rule"
  done
)
echo 'PASS: fresh scaffold creates a policy with no grants and ignores operator state'

manifest="$project/.ai-session-kit-manifest"
if [[ -f "$manifest" ]]; then
  kit_head="$(git -C "$KIT_ROOT" rev-parse HEAD 2>/dev/null || true)"
  [[ -z "$kit_head" || "$(cat "$manifest")" == "$kit_head" ]]
  ! grep -qF '.ai-session-kit-manifest' "$project/.gitignore"
fi
echo 'PASS: a fresh scaffold records the current kit commit without gitignoring it'

for path in AGENTS.md docs/tasks.md .github/prompts/tasks.prompt.md \
  .github/agents/planner.agent.md .cline/skills/tasks/SKILL.md \
  .cline/skills/planner/SKILL.md; do
  cmp "$project/$path" "$KIT_ROOT/template/project/$path"
done
grep -F 'session limits below apply only to implementation sessions.' "$project/AGENTS.md" >/dev/null
grep -F 'Never treat Done or In Progress rows, or rows with other blockers, as placeholders.' "$project/docs/tasks.md" >/dev/null
for path in .github/prompts/tasks.prompt.md .github/agents/planner.agent.md \
  .cline/skills/tasks/SKILL.md .cline/skills/planner/SKILL.md; do
  for constraint in 'three template rows are not a task limit.' \
    '🔲 Todo' 'as-is' 'every requirement in both specifications'; do
    grep -F "$constraint" "$project/$path" >/dev/null
  done
done
grep -Fx 'agent: planner' "$project/.github/prompts/tasks.prompt.md" >/dev/null
grep -Fx 'tools: [read, search, edit]' "$project/.github/agents/planner.agent.md" >/dev/null
echo 'PASS: planning workflows install full-backlog and protected-placeholder instructions'

for path in .github/prompts/tasks.prompt.md .github/agents/planner.agent.md \
  .cline/skills/tasks/SKILL.md .cline/skills/planner/SKILL.md; do
  for constraint in '## Requirement reconciliation' \
    'A Done status is historical evidence, not proof of coverage for a changed requirement.' \
    'append new Todo follow-up tasks with fresh sequential IDs' \
    'including removal or replacement of obsolete tests' \
    'Requirement | Existing task IDs | Coverage or mismatch | New task IDs or blocker' \
    'Do not claim "no changes needed" without this reconciliation.'; do
    grep -F "$constraint" "$project/$path" >/dev/null
  done
done
echo 'PASS: planning workflows require changed-requirement reconciliation and follow-up tasks'

for constraint in 'General conversation is the default.' \
  'Do not automatically read project documents, select tasks, change task statuses, or write a handoff for a general question.' \
  'A previous workflow command does not make later unrelated questions workflow requests.' \
  'Auto-continue requests explicitly activate the implementation workflow.' \
  '## Always-On Safety and Tool Use' \
  '## Implementation Session Start' \
  '## Ending a Workflow Session'; do
  grep -F "$constraint" "$project/AGENTS.md" >/dev/null
done
! grep -F 'before doing anything else' "$project/AGENTS.md" >/dev/null
grep -F 'For specification, planning, handoff, recovery, and resume-preparation requests, read only the context required by the invoked prompt or skill.' "$project/AGENTS.md" >/dev/null
grep -F 'Read AGENTS.md, docs/functional-spec.md, docs/technical-spec.md, docs/tasks.md, and docs/handoff.md.' "$KIT_ROOT/scripts/auto-continue.sh" >/dev/null
echo 'PASS: general conversation defaults to no workflow bookkeeping while preserving safety and auto-continue context'

recovery_prompt=".github/prompts/recover-handoff.prompt.md"
recovery_skill=".cline/skills/recover-handoff/SKILL.md"
for path in "$recovery_prompt" "$recovery_skill"; do
  cmp "$project/$path" "$KIT_ROOT/template/project/$path"
  grep -F 'Do not run shell commands or tests.' "$project/$path" >/dev/null
  grep -F '.ai-session/auto-continue.log' "$project/$path" >/dev/null
  grep -F '.github/auto-continue-enabled' "$project/$path" >/dev/null
  grep -F 'If evidence is missing or inaccessible, state that explicitly.' "$project/$path" >/dev/null
done
grep -Fx 'agent: handoff-writer' "$project/$recovery_prompt" >/dev/null
grep -Fx 'name: recover-handoff' "$project/$recovery_skill" >/dev/null
grep -F '`.cline/.active-role`' "$project/$recovery_skill" >/dev/null
echo 'PASS: recovery prompt and skill are installed with evidence and no-shell constraints'

resume_prompt=".github/prompts/prepare-resume.prompt.md"
resume_skill=".cline/skills/prepare-resume/SKILL.md"
for path in "$resume_prompt" "$resume_skill"; do
  cmp "$project/$path" "$KIT_ROOT/template/project/$path"
  for constraint in 'Require exactly one task ID' \
    'command-exceptions/command-exceptions.conf' \
    '.github/auto-continue-enabled' \
    "Require the user's confirmation" \
    'Every restricted class in the rejected batch needs' \
    'Do not clear the entire handoff' \
    'Ready to resume <task_id>' \
    'Not ready to resume <task_id>' \
    'do not mark Done'; do
    grep -F "$constraint" "$project/$path" >/dev/null
  done
done
grep -Fx 'agent: handoff-writer' "$project/$resume_prompt" >/dev/null
grep -Fx 'name: prepare-resume' "$project/$resume_skill" >/dev/null
grep -F '`.cline/.active-role`' "$project/$resume_skill" >/dev/null
echo 'PASS: prepare-resume workflows are installed with targeted readiness safeguards'

printf '# Operator approval\nallow-recursive-delete\n' >"$policy"
cp "$policy" "$TEST_ROOT/approved-policy"
bash "$KIT_ROOT/template/create-scaffold-kit.sh" "$project" </dev/null >"$TEST_ROOT/output"
cmp "$policy" "$TEST_ROOT/approved-policy"
grep -F 'Operator policy preserved: 1' "$TEST_ROOT/output" >/dev/null
[[ "$(grep -Fxc '/command-exceptions/' "$project/.gitignore")" == 1 ]]
[[ -z "$(find "$project/command-exceptions" -name '*.bak.*' -print)" ]]
echo 'PASS: rerunning scaffold preserves approvals without prompting or backups'

rm "$policy"
bash "$KIT_ROOT/template/create-scaffold-kit.sh" "$project" </dev/null >"$TEST_ROOT/output"
cmp "$policy" "$KIT_ROOT/template/project/command-exceptions/command-exceptions.conf"
echo 'PASS: missing policy is recreated with default restrictions'
