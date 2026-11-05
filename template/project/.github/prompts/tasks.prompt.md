---
description: "Break down docs/functional-spec.md and docs/technical-spec.md into sprint tasks and update docs/tasks.md"
agent: planner
---
Read [docs/functional-spec.md](../../docs/functional-spec.md), [docs/technical-spec.md](../../docs/technical-spec.md), and the current [docs/tasks.md](../../docs/tasks.md). Plan the full backlog, not just the handoff's "Next" tasks; implementation session limits do not apply.

Add or revise tasks so each one has a concrete description and testable acceptance criteria and is small and independently testable (TDD-sized), following an Agile, sprint-based methodology. Fill the blank template placeholders in place, retaining their `S<2-digit>`/`T<3-digit>` IDs, then append as many sequential tasks and sprints as needed. The three template rows are not a task limit. Follow the placeholder definition in docs/tasks.md: reset only a placeholder blocked solely for missing description/acceptance criteria to `🔲 Todo` once those details are supplied. Preserve genuine existing `✅ Done`, `🔄 In Progress`, and `⛔ Blocked` rows as-is.

If a task's test can only pass once a later task exists, say so explicitly in its description rather than leaving it implicit. Before finishing, check that every requirement in both specifications is covered by a task or an explicit unresolved blocker, and no placeholder remains blank. Report any stale handoff that needs a separate update; do not implement code or mark tasks Done.

## Requirement reconciliation
Before changing the backlog, compare each current requirement and acceptance example in both specifications with existing task descriptions and acceptance criteria, not just task titles or statuses. Use the current documents even when no previous spec revision is available. A Done status is historical evidence, not proof of coverage for a changed requirement.

Identify missing, partial, and contradictory coverage, including changed interfaces, error behavior, and formerly invalid inputs that are now valid. For example, an old completed task that rejects `^` does not cover a new requirement to support exponentiation. Plan the affected implementation, tests, help, and documentation, including removal or replacement of obsolete tests.

Keep protected existing rows unchanged; append new Todo follow-up tasks with fresh sequential IDs for changed or missing behavior, naming the affected earlier task IDs. Do not duplicate an existing pending task whose acceptance criteria already cover the current requirement. If preserved pending work contradicts the new scope, record the conflict as an explicit blocker on a new follow-up task requiring resolution before implementation; do not silently execute obsolete work.

Include a reconciliation table in the final response using columns `Requirement | Existing task IDs | Coverage or mismatch | New task IDs or blocker`. Use spec sections or acceptance examples as references when requirement IDs are absent. Account for every current requirement, and explain any contradiction and its follow-up task. Do not claim "no changes needed" without this reconciliation. Report a stale handoff for a separate update before implementation resumes; do not edit it.
