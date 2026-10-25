# Tasks

IDs: `S<2-digit sprint>` / `T<3-digit task>`, assigned sequentially and never reused or renumbered. Every real task row starts with `| S.. | T.. |` — `scripts/check-handoff.sh` and `scripts/auto-continue.sh` anchor on that prefix to tell task rows apart from this legend line.

**Status values:** 🔲 Todo · 🔄 In Progress · YYYY-MM-DD (note) · ✅ Done · YYYY-MM-DD · ⛔ Blocked · <reason>

**Forward test dependency:** if a task's test can only pass once a *later* task is implemented (the feature it exercises doesn't exist yet), don't mark it Done and don't skip it silently — leave it `🔄 In Progress · YYYY-MM-DD (depends on T0XX)`, implement T0XX, then return and finish it. This is a normal sequencing note, not a blocker, so it must not use the word "Blocked". Record the pair in `docs/handoff.md`'s "Next" section so it survives a session boundary.

**Blocking questions:** a question that blocks only one task is that task's blocker — mark it `⛔ Blocked · <reason>`. A question that blocks ALL further work (no task can safely proceed until it's answered) is a project-wide blocker — mark the next task to be worked `⛔ Blocked · <reason>` too, not just note it in `docs/handoff.md`. Blocker detection (the Stop hook / Cline's TaskComplete/TaskCancel/SessionShutdown hooks) only scans task rows here; a blocker noted only in `docs/handoff.md`'s "Blockers" section will never trigger a notification.

| Sprint | Task | Description | Status |
|---|---|---|---|
| S01 | T001 | | 🔲 Todo |
| S01 | T002 | | 🔲 Todo |
| S02 | T003 | | 🔲 Todo |
