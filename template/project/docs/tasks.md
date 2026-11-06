# Tasks

IDs: `S<2-digit sprint>` / `T<3-digit task>`, assigned sequentially and never reused or renumbered. Every real task row starts with `| S.. | T.. |` — `scripts/check-handoff.sh` and `scripts/auto-continue.sh` anchor on that prefix to tell task rows apart from this legend line.

**Status values:** 🔲 Todo · 🔄 In Progress · YYYY-MM-DD (note) · ✅ Done · YYYY-MM-DD · ⛔ Blocked · <reason> · Superseded · replaced by T<id> / scope removed

**Planning approval:** `/tasks` handles initial and change planning using `.github/instructions/planning.instructions.md`. Review its persistent proposal in `docs/planning/review.md` and explicitly approve it before implementation. Approved copies of both specs and this backlog live in `docs/planning/`; only the planner updates them after approval. Changed specs or task scope require renewed approval; ordinary status-only progress does not. Before selecting or changing a task, the implementer runs `bash external/ai-session-kit/scripts/check-planning.sh` and stops if it fails.

**Superseded work:** only explicit planning approval may supersede obsolete unfinished tasks. Preserve their IDs/descriptions, record their replacement or removed scope, and never implement them or mark them Done. Resolve conflicting pending work during planning review, not after implementation starts.

**Task cells:** keep each task on one table row with no literal pipe characters inside cells; include description, acceptance criteria, and dependency references in the Description cell.

**Initial planning:** the three blank rows below are template placeholders, not a three-task limit or an implementation backlog. Run `/tasks` (or the tasks skill) before implementation. Fill placeholder descriptions with real, testable work while retaining their IDs, then append as many sequential tasks and sprints as needed to cover both specifications. A placeholder is a blank-description row that is Todo or blocked solely because its description/acceptance criteria are missing; once populated, set it to `🔲 Todo`. Never treat Done or In Progress rows, or rows with other blockers, as placeholders. Preserve genuine existing tasks and their statuses except explicitly approved supersessions of unfinished work.

**Forward test dependency:** if a task's test can only pass once a *later* task is implemented (the feature it exercises doesn't exist yet), don't mark it Done and don't skip it silently — leave it `🔄 In Progress · YYYY-MM-DD (depends on T0XX)`, implement T0XX, then return and finish it. This is a normal sequencing note, not a blocker, so it must not use the word "Blocked". Record the pair in `docs/handoff.md`'s "Next" section so it survives a session boundary.

**Blocking questions:** a question that blocks only one task is that task's blocker — mark it `⛔ Blocked · <reason>`. A question that blocks ALL further work (no task can safely proceed until it's answered) is a project-wide blocker — mark the next task to be worked `⛔ Blocked · <reason>` too, not just note it in `docs/handoff.md`. Blocker detection (the Stop hook / Cline's TaskComplete/TaskCancel/SessionShutdown hooks) only scans task rows here; a blocker noted only in `docs/handoff.md`'s "Blockers" section will never trigger a notification.

| Sprint | Task | Description | Status |
|---|---|---|---|
| S01 | T001 | | 🔲 Todo |
| S01 | T002 | | 🔲 Todo |
| S02 | T003 | | 🔲 Todo |
