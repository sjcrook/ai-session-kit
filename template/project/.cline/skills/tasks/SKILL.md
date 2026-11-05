---
name: tasks
description: Break down docs/functional-spec.md and docs/technical-spec.md into sprint tasks and update docs/tasks.md. Use when the user says "/tasks" or asks to plan or re-plan sprint tasks. Does not write implementation code or run shell commands.
---

Before anything else, write the exact text `planner` (no trailing newline) to
`.cline/.active-role`, creating the `.cline` directory if needed, so the
project's `PreToolUse` hook enforces the planner role's restrictions for the
rest of this task (no shell commands). This also clears any role a previous
task may have left behind.

Read `docs/functional-spec.md`, `docs/technical-spec.md`, and the current
`docs/tasks.md`. Plan the full backlog, not just the handoff's "Next" tasks;
implementation session limits do not apply. Add or revise tasks so each one
has a concrete description and testable acceptance criteria and is small and
independently testable (TDD-sized) following an Agile, sprint-based methodology,
as rows in the task table with sequential `S<2-digit>`/`T<3-digit>` IDs — each task
should have exactly one test that can pass on its own, without needing a
later task's code to exist. If a forward dependency is genuinely unavoidable,
say so explicitly in the earlier task's description (e.g. "depends on T0XX
for its test to pass") rather than leaving it implicit.

Fill blank template placeholders in place using the definition in
`docs/tasks.md`, retaining their IDs, then append as many sequential tasks and
sprints as needed. The three template rows are not a task limit. Reset only
a placeholder blocked solely for missing description/acceptance criteria to
`🔲 Todo` once those details are supplied. Preserve genuine existing
`✅ Done`, `🔄 In Progress`, and `⛔ Blocked` rows as-is.

Before finishing, check that every requirement in both specifications is
covered by a task or an explicit unresolved blocker, and no placeholder remains
blank. Report any stale handoff that needs a separate update; do not edit it.

## Requirement reconciliation
Before changing the backlog, compare each current requirement and acceptance example in both specifications with existing task descriptions and acceptance criteria, not just task titles or statuses. Use the current documents even when no previous spec revision is available. A Done status is historical evidence, not proof of coverage for a changed requirement.

Identify missing, partial, and contradictory coverage, including changed interfaces, error behavior, and formerly invalid inputs that are now valid. For example, an old completed task that rejects `^` does not cover a new requirement to support exponentiation. Plan the affected implementation, tests, help, and documentation, including removal or replacement of obsolete tests.

Keep protected existing rows unchanged; append new Todo follow-up tasks with fresh sequential IDs for changed or missing behavior, naming the affected earlier task IDs. Do not duplicate an existing pending task whose acceptance criteria already cover the current requirement. If preserved pending work contradicts the new scope, record the conflict as an explicit blocker on a new follow-up task requiring resolution before implementation; do not silently execute obsolete work.

Include a reconciliation table in the final response using columns `Requirement | Existing task IDs | Coverage or mismatch | New task IDs or blocker`. Use spec sections or acceptance examples as references when requirement IDs are absent. Account for every current requirement, and explain any contradiction and its follow-up task. Do not claim "no changes needed" without this reconciliation. Report a stale handoff for a separate update before implementation resumes; do not edit it.

## Constraints
- DO NOT edit source code — planning only.
- DO NOT run shell commands — this role has no execute access, enforced by
  the project's `PreToolUse` hook, not just this instruction.
- DO NOT mark a task `✅ Done` — only the implementer does that.
- ONLY edit `docs/tasks.md` (and `docs/functional-spec.md`/`docs/technical-spec.md`
  if clarifying scope).
