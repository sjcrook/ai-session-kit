# Project Guidelines

## Workflow Scope
- General conversation is the default. Activate the structured workflow only when the user invokes a kit command/skill or explicitly requests equivalent specification, planning, task implementation, handoff, recovery, or resume-preparation work. Discussing a command or asking how something works is not an instruction to run it.
- Do not automatically read project documents, select tasks, change task statuses, or write a handoff for a general question. Read files only when relevant to answering that question. A previous workflow command does not make later unrelated questions workflow requests.
- The workflow startup, task methodology, ending, and session task limits below apply only to the corresponding workflow work, not general conversation. Safety and tool-use restrictions apply to every request.
- Auto-continue requests explicitly activate the implementation workflow.
- For specification, planning, handoff, recovery, and resume-preparation requests, read only the context required by the invoked prompt or skill. For equivalent plain-language requests, use the matching workflow's context and role restrictions.
- Specification and planning commands (`/functional-spec`, `/technical-spec`, `/tasks`, and the equivalent skills or planner role) prepare or revise project documents, not implementation. They may cover the full requested scope regardless of the handoff's "Next" list; the one-task/TDD execution rules and 1-3-task session limits below apply only to implementation sessions.
- Planning must not implement code or mark tasks Done. Follow the active role's file-editing restrictions; request a separate handoff update if planning makes the current handoff stale.

## Implementation Session Start
- When starting or resuming task implementation, read `docs/functional-spec.md`, `docs/technical-spec.md`, `docs/tasks.md`, and `docs/handoff.md` before selecting or changing a task.
- Work only the task(s) listed under "Next" in `docs/handoff.md` — don't scope-creep into later sprints. If `docs/handoff.md` is still the unedited template (e.g. `State` still reads `{What exists right now...}`), this is the first session: start from the first `🔲 Todo` row in `docs/tasks.md` instead.
- If the task you'd pick up is already `🔄 In Progress`, don't assume the previous session finished or even safely started it — check `git status`/`git diff` and run the test suite first to find the real state before resuming or restarting it.

## Implementation Methodology
- Agile, sprint-based: work exactly one task from `docs/tasks.md` at a time, in the order sprints/tasks are listed unless told otherwise. The moment you start one, set its status to `🔄 In Progress · <today's date> (<short note of what you're about to do>)` — this is the only durable breadcrumb if the session is interrupted before `docs/handoff.md` gets updated.
- Test-driven: write a failing test before implementation code, for every task, and do not move on to the next task until that task's own test passes. Set a task's status to `✅ Done · <today's date>` only when its test passes.

## Always-On Safety and Tool Use
- Use file-editing tools to create or edit source and tests, not shell heredocs. Cline's command guard scans the entire shell payload, including file content: a test's teardown or a documentation example can trigger a denied-command pattern even when the shell would only write that text. Keep file edits separate from shell execution; never bypass the deny-list with alternate spellings or obfuscation. If a necessary operation is denied and no permitted workflow can complete the task, mark it Blocked with the reason.
- The default `git push`, `rm -rf`, and `sudo` restrictions apply even to temporary cleanup and test setup, unless the operator grants the corresponding named exception in `command-exceptions/command-exceptions.conf`. Never create, edit, or redirect that policy or its enforcement files. Using an operator-granted exception is permitted; it does not override role restrictions. Cline checks each shell tool call; headless Copilot launched by the kit snapshots policy at each invocation, so restart it after a policy change. An unapproved match anywhere in a Cline batch rejects the whole tool call and may end the task. Prefer existing test fixtures and their established cleanup conventions. For session-created artifacts, plan cleanup of explicitly identified individual files and then empty directories; never substitute another spelling, interpreter, or wrapper to perform a denied operation.
- On resumption after a denial, check `.ai-session/auto-continue.log` (or hook stderr if logging was unavailable) and verify real state; do not assume any rejected batch ran. Do not retry a denied operation without the required operator approval. If permission has changed, reassess only the affected blocker, record remaining work in `docs/handoff.md`, and rerun necessary validation; do not clear unrelated blockers or mark work Done without passing its acceptance tests. Report any necessary operation with no permitted workflow as a blocker. A cancelled task is not completed work.

The task-status and handoff bookkeeping in this safety section applies only when working on a workflow task. For other requests, report denials or blockers directly without creating task or handoff entries. Command restrictions and approval requirements remain in force regardless of workflow activation.

## Implementation Dependencies and Blockers
- Forward test dependency: if a task's test can only pass once a *later* task is implemented (the feature it exercises doesn't exist yet), do not mark it Done and do not skip it silently — leave it `🔄 In Progress · <today's date> (depends on T0XX)`, implement T0XX, then return and finish it. Record the pair in `docs/handoff.md`'s "Next" section so it survives a session boundary. See `docs/tasks.md`'s legend for the exact convention.
- If a task can't be completed, mark it `⛔ Blocked · <reason>` in `docs/tasks.md` instead of guessing or skipping silently. An unanswered question that blocks only this task is that task's blocker. A question that blocks ALL further work (no task can safely proceed until it's answered) is a project-wide blocker: mark the next task to be worked `⛔ Blocked · <reason>` too — blocker detection only scans task rows in `docs/tasks.md`, so leaving it solely in `docs/handoff.md`'s "Blockers" section will not trigger notification. If the question doesn't block any task, leave it under "Open questions" in `docs/handoff.md` instead and carry it forward unchanged until it's answered.

## Ending a Workflow Session
- For general conversation, do not perform the workflow updates below. For an active workflow, follow the invoked prompt/skill's edit restrictions (for example, `/implement` requests a separate `/handoff`).
- Update `docs/tasks.md` (status of completed items, in-progress notes, blockers).
- Update `docs/handoff.md` using its template: State / Decisions since last session / Open questions / Blockers / Next (1-3 tasks).
- In VS Code Copilot Chat, a `Stop` hook (`.github/hooks/handoff-check.json`) checks `docs/tasks.md` for `⛔ Blocked` items and notifies via `notify.sh` — see `external/ai-session-kit/scripts/check-handoff.sh`. In Cline (CLI and VS Code extension), the equivalent lifecycle hooks are `.cline/hooks/{TaskComplete,TaskCancel,SessionShutdown}.sh` and `.clinerules/hooks/{TaskComplete,TaskCancel,SessionShutdown}` (no file extension — both locations are required; each Cline surface only reads hooks from its own directory), which call the same check via `external/ai-session-kit/scripts/check-handoff-cline.sh`. Implement `notify.sh` with a real notification (email/Slack/etc); it's a stub until you do.

## Implementation Session Limits
- Keep sessions short: treat one task as the normal unit of work and stop — update `docs/handoff.md` and end the session — rather than continuing into a second or third task just because more are ready, even in auto-continue mode where each iteration is already scoped to one task.
- Keep each session scoped to 1-3 tasks.

## Token Efficiency
- Don't re-read files already read earlier in the same session; prefer targeted edits over full-file rewrites.

## Frontend
If this project has a UI, `.github/instructions/frontend.instructions.md` holds Copilot's conventions (`applyTo` glob), and `.clinerules/frontend.md` holds Cline's equivalent (`paths` glob in YAML frontmatter). Both are created by the `/technical-spec` prompt or skill once the stack is chosen — don't hand-write them before that decision exists.

## Build and Test
{Fill in once the project is scaffolded: install/build/test commands.}
