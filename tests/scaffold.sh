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

for path in AGENTS.md .github/copilot-instructions.md docs/tasks.md docs/planning/review.md \
  .github/instructions/planning.instructions.md .github/prompts/tasks.prompt.md \
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

for path in .cline/skills/tasks/SKILL.md .cline/skills/planner/SKILL.md; do
  for constraint in 'Use a native file-editing tool for this role marker' \
    'Use only native file-reading, searching, and editing tools throughout planning' \
    'Do not invoke `run_commands` or `execute_command`' \
    'snapshots, re-read them with file tools' \
    'Do not run `check-planning.sh`' \
    'report the limitation and stop'; do
    grep -F "$constraint" "$project/$path" >/dev/null
  done
done
echo 'PASS: Cline planning skills install native-file-tool guidance for setup, inspection, and snapshots'

for skill in planner tasks handoff handoff-writer recover-handoff prepare-resume implementer; do
  path=".cline/skills/$skill/SKILL.md"
  cmp "$project/$path" "$KIT_ROOT/template/project/$path"
  grep -F '## Role cleanup' "$project/$path" >/dev/null
  grep -F 'write the exact text `none`' "$project/$path" >/dev/null
  grep -F 'Do not run shell commands after cleanup' "$project/$path" >/dev/null
done
grep -F 'before any shell command, including orientation' "$project/AGENTS.md" >/dev/null
grep -F 'Do not clear the role merely because a task is resumed' "$project/AGENTS.md" >/dev/null
for event in TaskComplete TaskCancel SessionShutdown; do
  for path in ".cline/hooks/$event.sh" ".clinerules/hooks/$event"; do
    cmp "$project/$path" "$KIT_ROOT/template/project/$path"
    grep -F 'scripts/check-handoff-cline.sh' "$project/$path" >/dev/null
  done
done
echo 'PASS: role cleanup, startup recovery, and both lifecycle hook layouts are installed'
for event in TaskComplete TaskCancel SessionShutdown; do
  for path in ".cline/hooks/$event.sh" ".clinerules/hooks/$event"; do
    grep -F "check-handoff-cline.sh\" $event" "$project/$path" >/dev/null
  done
done
for skill in planner tasks handoff handoff-writer recover-handoff prepare-resume implementer functional-spec technical-spec; do
  grep -F 'Readiness and Steering' "$project/.cline/skills/$skill/SKILL.md" >/dev/null
done
for constraint in '## Readiness and Steering' \
  'Do not start a different workflow without asking' \
  'Never batch role selection, workflow edits, and dependent verification together' \
  'Do not infer the cancellation cause from the current role marker' \
  'Never clear the pause or invoke `--resume` autonomously'; do
  grep -F "$constraint" "$project/AGENTS.md" >/dev/null
done
grep -F 'workflow-status.sh' "$TEST_ROOT/output" >/dev/null
echo 'PASS: readiness steering, sequential phases, and explicit lifecycle events are installed'

for path in .github/prompts/tasks.prompt.md .github/agents/planner.agent.md \
  .cline/skills/tasks/SKILL.md .cline/skills/planner/SKILL.md; do
  for constraint in 'planning.instructions.md' 'explicit developer approval' \
    'docs/planning/' 'Approved last'; do
    grep -F "$constraint" "$project/$path" >/dev/null
  done
done
for constraint in 'Initial planning:' 'Change planning:' 'Missing/incomplete baseline:' \
  'A Done status is historical evidence, not proof of coverage for a changed requirement.' \
  'append new Todo follow-up tasks with fresh sequential IDs' \
  'including removal or replacement of obsolete tests' \
  'Requirement | Existing task IDs | Coverage or mismatch | New task IDs or blocker' \
  'Do not claim "no changes needed" without this reconciliation.' \
  'Preserve unrelated requirements' 'do not ask the developer to enumerate changed requirements' \
  'Never infer approval' 'Superseded' 'Status: Approved'; do
  grep -F "$constraint" "$project/.github/instructions/planning.instructions.md" >/dev/null
done
grep -Fx 'Status: Pending' "$project/docs/planning/review.md" >/dev/null
[[ ! -e "$project/docs/planning/functional-spec.md" ]]
for path in .github/prompts/functional-spec.prompt.md .github/prompts/technical-spec.prompt.md \
  .github/prompts/handoff.prompt.md .github/agents/handoff-writer.agent.md \
  .cline/skills/functional-spec/SKILL.md .cline/skills/technical-spec/SKILL.md \
  .cline/skills/handoff/SKILL.md .cline/skills/handoff-writer/SKILL.md; do
  grep -F 'planning.instructions.md' "$project/$path" >/dev/null
done
for path in AGENTS.md .github/prompts/implement.prompt.md \
  .github/agents/implementer.agent.md .cline/skills/implementer/SKILL.md; do
  grep -F 'check-planning.sh' "$project/$path" >/dev/null
  grep -F 'Superseded' "$project/$path" >/dev/null
done
echo 'PASS: both integrations install shared spec preservation, change planning, explicit approval, and implementation checks'

for path in AGENTS.md .github/prompts/implement.prompt.md \
  .github/agents/implementer.agent.md .cline/skills/implementer/SKILL.md; do
  cmp "$project/$path" "$KIT_ROOT/template/project/$path"
  for constraint in \
    'For regression-only tasks covering existing behavior, a correct test may pass immediately' \
    'Never manufacture a failure by using incorrect expectations or temporarily breaking working code' \
    'never shell writes (including printf/echo redirection, heredocs, or interpreter-based writes)' \
    'required behavior is missing'; do
    grep -F "$constraint" "$project/$path" >/dev/null
  done
done
echo 'PASS: implementation workflows preserve honest regression evidence and require file-editing tools'

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

grep -F '## Literal Slash Commands' "$project/AGENTS.md" >/dev/null
grep -F 'Read the mapped prompt and role instructions from disk on each invocation' "$project/AGENTS.md" >/dev/null
grep -F 'even when every existing task is Done' "$project/AGENTS.md" >/dev/null
grep -F 'A count of completed tasks is not a planning result' "$project/AGENTS.md" >/dev/null
grep -F 'reading a role file does not enforce tool permissions' "$project/AGENTS.md" >/dev/null
grep -F 'Do not execute both the prompt and skill workflows' "$project/AGENTS.md" >/dev/null
for command in functional-spec technical-spec tasks handoff implement recover-handoff prepare-resume; do
  grep -F "| \`/$command\` | \`.github/prompts/$command.prompt.md\` |" "$project/AGENTS.md" >/dev/null
  [[ -f "$project/.github/prompts/$command.prompt.md" ]]
  skill="$command"
  [[ "$command" != implement ]] || skill=implementer
  [[ -f "$project/.cline/skills/$skill/SKILL.md" ]]
done
for role in planner handoff-writer implementer; do
  [[ -f "$project/.github/agents/$role.agent.md" ]]
done
grep -F 'best-effort guidance, not a command dispatcher' "$project/AGENTS.md" >/dev/null
grep -F 'explicitly select `planner`' "$project/AGENTS.md" >/dev/null
echo 'PASS: installed command mapping documents explicit agent selection and best-effort limitations'
grep -F '[AGENTS.md](../AGENTS.md)' "$project/.github/copilot-instructions.md" >/dev/null
grep -F 'Read it from disk before' "$project/.github/copilot-instructions.md" >/dev/null
grep -F 'file in `.github/`, not relative to the working directory.' "$project/.github/copilot-instructions.md" >/dev/null
grep -F '`<repository-root>/AGENTS.md`; do not use `<repository-root>/../AGENTS.md`.' "$project/.github/copilot-instructions.md" >/dev/null
grep -F 'ask the developer rather than probing parent folders.' "$project/.github/copilot-instructions.md" >/dev/null
grep -F 'status summary' "$project/.github/copilot-instructions.md" >/dev/null
grep -F "include those links in the approval question's message" "$project/.github/instructions/planning.instructions.md" >/dev/null
for path in .github/agents/planner.agent.md .cline/skills/planner/SKILL.md; do
  grep -F 'clickable Markdown links' "$project/$path" >/dev/null
done
echo 'PASS: Copilot entry point and planner outputs include loading guidance and review-link requirements'

cmp "$project/docs/handoff.md" "$KIT_ROOT/template/project/docs/handoff.md"
grep -F 'no handoff has been recorded yet' "$project/docs/handoff.md" >/dev/null
! grep -F 'no session has run yet' "$project/docs/handoff.md" >/dev/null
grep -F 'treat `docs/tasks.md`'"'"'s actual statuses as authoritative' "$project/AGENTS.md" >/dev/null
grep -F 'no handoff has been recorded yet' "$project/AGENTS.md" >/dev/null
! grep -F 'this is the first session' "$project/AGENTS.md" >/dev/null
grep -F "doesn't write a handoff" "$KIT_ROOT/README.md" >/dev/null
grep -F 'treat `docs/tasks.md` as authoritative over a now-stale "Next" list' "$KIT_ROOT/README.md" >/dev/null
echo 'PASS: handoff docs distinguish "no handoff recorded" from "no session ran" and favor tasks.md over a stale Next list'

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

printf 'Status: Approved\nReviewed project state\n' >"$project/docs/planning/review.md"
printf 'Approved functional snapshot\n' >"$project/docs/planning/functional-spec.md"
cp "$project/docs/planning/review.md" "$TEST_ROOT/approved-review"
bash "$KIT_ROOT/template/create-scaffold-kit.sh" "$project" </dev/null >"$TEST_ROOT/output"
cmp "$project/docs/planning/review.md" "$TEST_ROOT/approved-review"
grep -Fx 'Approved functional snapshot' "$project/docs/planning/functional-spec.md" >/dev/null
grep -F 'Planning review preserved: 1' "$TEST_ROOT/output" >/dev/null
[[ -z "$(find "$project/docs/planning" -name '*.bak.*' -print)" ]]
echo 'PASS: scaffold updates preserve project planning review and approved snapshots'
