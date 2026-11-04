---
description: "Break down docs/functional-spec.md and docs/technical-spec.md into sprint tasks and update docs/tasks.md"
agent: planner
---
Read [docs/functional-spec.md](../../docs/functional-spec.md), [docs/technical-spec.md](../../docs/technical-spec.md), and the current [docs/tasks.md](../../docs/tasks.md). Plan the full backlog, not just the handoff's "Next" tasks; implementation session limits do not apply.

Add or revise tasks so each one has a concrete description and testable acceptance criteria and is small and independently testable (TDD-sized), following an Agile, sprint-based methodology. Fill the blank template placeholders in place, retaining their `S<2-digit>`/`T<3-digit>` IDs, then append as many sequential tasks and sprints as needed. The three template rows are not a task limit. Follow the placeholder definition in docs/tasks.md: reset only a placeholder blocked solely for missing description/acceptance criteria to `🔲 Todo` once those details are supplied. Preserve genuine existing `✅ Done`, `🔄 In Progress`, and `⛔ Blocked` rows as-is.

If a task's test can only pass once a later task exists, say so explicitly in its description rather than leaving it implicit. Before finishing, check that every requirement in both specifications is covered by a task or an explicit unresolved blocker, and no placeholder remains blank. Report any stale handoff that needs a separate update; do not implement code or mark tasks Done.
