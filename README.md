# ai-session-kit

A vendorable framework for spec-driven, sprint-based AI coding sessions in VS Code (GitHub Copilot) and Cline (VS Code extension or CLI): a functional/technical spec, a sprint task list, and a handoff doc carry context between sessions, with a session-end lifecycle hook (Copilot's `Stop` hook; Cline's `TaskComplete`/`TaskCancel`/`SessionShutdown` hooks) that detects blockers and can optionally keep going headlessly.

This repo *is* the vendored core — you don't clone it standalone to use it, you vendor it into a real project (see Install).

## What's in here

```
scripts/                   vendored, read-only core
  check-handoff.sh         Copilot Stop hook entry point: detects Blocked tasks, notifies, or starts auto-continue
  check-handoff-cline.sh   Cline TaskComplete/TaskCancel/SessionShutdown hook entry point — same decision via lib/handoff-core.sh
  cline-tool-guard.sh      Cline PreToolUse hook: enforces planner/handoff-writer no-shell restriction + a command deny-list
  auto-continue.sh         headless continuation loop (GitHub Copilot CLI or Cline CLI)
  stop-auto-continue.sh    stops a running auto-continue loop and its current CLI child
  lib/handoff-core.sh      shared blocker-detection/notify/auto-continue-launch logic used by both hook entry points above

template/                  scaffold payload + installer
  create-scaffold-kit.sh   copies template/project/* into a consuming project's root
  gitignore.append         lines appended (not overwritten) to the consumer's .gitignore
  project/                 everything that lands in the consumer's repo root:
    AGENTS.md              always-on session conventions (read by both Copilot and Cline)
    notify.sh              notification stub (connect to email/Slack/etc.; no secrets are loaded by default)
    docs/
      functional-spec.md   what to build, for non-engineering review
      technical-spec.md    how to build it; also where frontend stack gets recorded
      tasks.md             sprint task table (Sprint/Task IDs + status); single source of truth for progress
      handoff.md           snapshot for the next session (State/Decisions/Open questions/Blockers/Next)
    .github/
      prompts/             /functional-spec, /technical-spec, /tasks, /implement, /handoff (Copilot)
      agents/              planner, implementer, handoff-writer (Copilot custom agents; scoped tool access per role)
      hooks/               Copilot Stop hook wiring (hardcoded to external/ai-session-kit/scripts/check-handoff.sh)
      instructions/        frontend.instructions.md (generated for projects with a UI; Copilot)
    .cline/
      skills/              functional-spec, technical-spec, tasks, handoff, planner, implementer, handoff-writer (Cline skills)
      hooks/               PreToolUse.sh, TaskComplete.sh, TaskCancel.sh, SessionShutdown.sh — discovered by the Cline CLI
    .clinerules/
      frontend.md          path-scoped frontend conventions (generated for projects with a UI)
      hooks/               same four hooks, no file extension — discovered by the Cline VS Code extension
```

## Install

### Prerequisites and safe execution

To run auto-continuously (auto-continue), first install and authenticate **GitHub Copilot CLI (`copilot`) or Cline CLI (`cline`)**, and make sure it is available on `PATH` in the environment where the kit runs. Installing only the VS Code extension is not sufficient for headless continuation.

> **Warning:** Allowing an agent to do anything, including running any executable automatically, can modify or delete files and expose any credentials available to it. This applies to both manual sessions with automatic approvals and unattended auto-continue sessions. Run the consuming project with ai-session-kit inside a **Dev Container**, rather than directly on your host, before granting these permissions. See [dev-container-config](https://github.com/sjcrook/dev-container-config) for a starting point. A container is not a complete security boundary: limit mounted host directories and exposed credentials, and review the agent's permissions.

When using [dev-container-config](https://github.com/sjcrook/dev-container-config#generating-a-devcontainer-for-your-project), run that repo's interactive generator from the consuming project's root (assuming it is vendored at `external/dev-container-config`):

```bash
./external/dev-container-config/generate.sh
```

Answer the prompts to install **Node.js**. How you install Cline CLI depends on which toolchain you pick:

- **pnpm toolchain** (if available): installs a pinned pnpm version at build time and blocks bare `npm install`/`ci`/`i`/`add` shell-wide, redirecting to pnpm instead. Supply this for `postCreateCommand`:
  ```text
  pnpm add --global cline
  ```
  Confirmed directly: the generator's Dockerfile already puts a global bin directory on `PATH` at build time (`ENV PATH="/opt/devcontainer/bin:${PATH}"`), so no `remoteEnv` entry is needed.

- **Plain Node.js toolchain** (no pnpm): use `npm install -g cline` for `postCreateCommand` instead. Not verified here whether `PATH` needs a `remoteEnv` entry for npm's global bin directory in this case — check for your setup rather than assuming either way.

The generator writes a new answers file and generates the container configuration from your responses. To change these settings later, run `generate.sh` again and answer the prompts; do not manually edit the answers file or generated container files. See that repo's README for the full setup workflow.

Rebuild the container after generation, then authenticate the CLI inside it. If using Copilot instead, install and authenticate GitHub Copilot CLI inside the container rather than installing Cline.

### Vendor and scaffold

Vendor this repo at **exactly** `external/ai-session-kit` in the consuming project — both the Copilot Stop hook and the scaffolded Cline hook wrapper scripts hardcode that path.

```bash
git submodule add <this-repo-url> external/ai-session-kit
git submodule update --init --recursive
```

Then scaffold the host-owned files into the project root:

```bash
external/ai-session-kit/template/create-scaffold-kit.sh
```

Run it from the consuming project's repo root (or pass a target directory as the first argument). It's safe to re-run any time:

- Missing files are copied in.
- Files identical to the template are skipped.
- Files that already exist and differ are left untouched and listed at the end for you to merge manually — nothing is silently overwritten. Answer `y` at the prompt if you do want to overwrite (a timestamped `.bak` is kept).
- Recommended `.gitignore` lines (`.env`, auto-continue's log/PID files, the auto-continue flag, and Cline's active-role marker) are appended, not overwritten.

A fresh clone of a project that vendors this kit needs:

```bash
git clone --recurse-submodules <project-url>
# or, if already cloned:
git submodule update --init --recursive
```

## Day-to-day usage (GitHub Copilot)

This part happens in **VS Code's Copilot Chat panel** (not the standalone CLI — see "Where to start a session" below), since prompts, custom agents, and the Stop hook are chat-specific features.

1. Open Copilot Chat, make sure the mode/agent picker is set to **Agent**, then type `/functional-spec` and press enter — VS Code resolves this to `.github/prompts/functional-spec.prompt.md` (it shows up in the autocomplete list as you type `/`). It interviews you in the chat conversation and writes `docs/functional-spec.md`.
2. Do the same with `/technical-spec` — it reads the functional spec, interviews you further, and writes `docs/technical-spec.md`.
3. Run `/tasks` to turn both specs into a sprint task table in `docs/tasks.md`.
4. To implement a task, run `/implement` to start the `implementer` agent on the next task, or select the `implementer` agent in the agent picker and ask it to work on a task. It follows the project workflow in `AGENTS.md`: read the specs, task list, and handoff; mark the task In Progress; then complete it test-first and mark it Done only after its test passes.
5. When you stop working, run `/handoff` to summarize the session in `docs/handoff.md`. In an interactive session this is a manual step; the lifecycle hooks do not write the handoff. In auto-continue mode, each headless implementer invocation is explicitly prompted to update `docs/handoff.md` before finishing, but the file is not written by the lifecycle hook. before finishing, but that depends on the agent following its prompt.
6. If a task becomes blocked, the implementer should mark it `⛔ Blocked · <reason>` in `docs/tasks.md` immediately, rather than waiting for `/handoff`. The hooks detect that saved task status. When you later run `/handoff`, the handoff-writer can summarize the blocker in `docs/handoff.md` and correct task statuses based on what it can verify; it does not replace the implementer's immediate status update if you may be interrupted.

You can also run any prompt via the Command Palette: **Chat: Run Prompt...** → pick it from the list, or open the `.prompt.md` file in the editor and click its play button.

### Using the three custom agents (Copilot)

These are three specialized agents you can select in Copilot Chat. Each has a different job:

- **`planner`** breaks the specs into tasks or updates the task list. It does not implement features. `/tasks` selects this agent automatically.
- **`implementer`** works on one task at a time: it writes a failing test, implements the change, runs the test, and updates the task status. `/implement` selects this agent and starts the next task; you can also select the agent directly when you want to specify a task or provide more context.
- **`handoff-writer`** records the current state for the next session in `docs/handoff.md` and updates task statuses when needed. `/handoff` selects this agent automatically. Use it when you are ending a session, not to begin implementation.

To choose an agent yourself, open the agent picker next to the chat input and select its name before typing your request. Copilot limits which tools each agent can use: only `implementer` can run shell commands. The intended file scope for each agent is described in its instructions, but is not a filesystem restriction; for example, the other agents still have access to the edit tool.

### Frontend projects

For a project with a UI, `/technical-spec` creates frontend conventions for the chosen stack in both tool formats: `.github/instructions/frontend.instructions.md` for Copilot, with an `applyTo` glob, and `.clinerules/frontend.md` for Cline, with a `paths` glob in YAML frontmatter. Each tool automatically applies its matching instructions when frontend files are in context. See [Cline's conditional rules documentation](https://docs.cline.bot/customization/cline-rules).

## Day-to-day usage (Cline)

Use the same skills in the **Cline VS Code extension** or the **Cline CLI**. Enable hooks before relying on hook behavior (see "Enabling Cline hooks" below); the skills themselves need no setup.

1. In chat (or `cline "..."` on the CLI), type `run the functional-spec skill` (or similarly phrase a request mentioning it) — Cline resolves this to `.cline/skills/functional-spec/SKILL.md`. It interviews you and writes `docs/functional-spec.md`.
2. Do the same with the `technical-spec` skill — it reads the functional spec, interviews you further, and writes `docs/technical-spec.md`.
3. Use the `tasks` skill to turn both specs into a sprint task table in `docs/tasks.md`.
4. To implement a task, use the `implementer` skill. The project workflow in `AGENTS.md` says to read the specs, task list, and handoff first; mark the task In Progress; then work on one task test-first and mark it Done only after its test passes.
5. When you stop working, use the `handoff` skill to summarize the session in `docs/handoff.md`. In an interactive session this is a manual step: stopping a task/session does not automatically write the handoff. In auto-continue mode, each headless implementer invocation is explicitly prompted to update `docs/handoff.md` before finishing, but that depends on the agent following its prompt. Cline lifecycle hooks themselves only check task status and notify or optionally start auto-continue; they do not write the handoff.
6. If a task becomes blocked, the implementer should mark it `⛔ Blocked · <reason>` in `docs/tasks.md` immediately, rather than waiting for the handoff skill. The lifecycle hooks detect that saved task status. When you later run the `handoff` skill, it can summarize the blocker and correct task statuses based on what it can verify.

You can also trigger any skill directly with `/<skill-name>` in chat.

## Using the Cline roles (planner/implementer/handoff-writer)

Cline uses skills to provide these three roles. To limit shell access, the kit also uses a hook:

- When you use the `planner`, `implementer`, or `handoff-writer` skill, it records the selected role in `.cline/.active-role`. The `tasks` and `handoff` skills select `planner` and `handoff-writer` for you.
- A `PreToolUse` hook reads that role and blocks shell commands for `planner` and `handoff-writer`. The `implementer` role, or a session with no role selected, can run commands. This check applies in both the CLI and the VS Code extension.
- The same hook also enforces a command deny-list (`git push`, `rm -rf`, `sudo`) for every role, including `implementer` — see "Notifications and permissions" below.

To choose a role directly, ask for its skill (for example, `use the implementer skill`) and include the task you want it to do. Use `implementer` for starting or resuming implementation; use `handoff` at the end of a session.

### Enabling Cline hooks

Hooks must be turned on once per surface before any of the above enforcement takes effect:

- **VS Code extension**: open Cline's settings and check **"Enable Hooks"**.
- **CLI**: hooks are discovered and run automatically — no separate toggle.

The **CLI** reads hooks from `.cline/hooks/<Name>.sh`; the **VS Code extension** reads them from `.clinerules/hooks/<Name>` (without a file extension). The scaffold installs both layouts because the two Cline surfaces use different hook locations.

## Where to start a session: VS Code chat vs. CLI

**GitHub Copilot:** start interactive sessions (spec writing, planning, implementation) from VS Code's Copilot Chat panel. Prompts, custom agents, and the `Stop` hook are VS Code Chat features. The standalone `copilot` CLI does not run the Stop hook; in this kit it is used as the headless worker for auto-continue. You can also invoke it directly for a non-interactive task, for example `copilot -p "..." --allow-all-tools -s`, but that does not trigger the chat lifecycle hook.

**Cline:** either the VS Code extension or CLI can be used for interactive sessions. Enable hooks in the extension before relying on lifecycle behavior; the CLI discovers its hooks automatically (see "Enabling Cline hooks"). Auto-continue invokes the CLI headlessly; you can also run `cline "..."` directly for a one-shot non-interactive task.

## Stopping a session

- **Interactive chat session** (VS Code): use the stop button in the chat panel, or just close the request — this triggers Copilot's `Stop` hook, or Cline's `TaskCancel` hook if the active task was Cline's.
- **Interactive CLI session** (`copilot` or `cline` run directly in a terminal): press `Ctrl+C`.
- **A running auto-continue loop**: from the consuming project's root, run the vendored stop script to stop its current CLI child and the loop:
  ```bash
  external/ai-session-kit/scripts/stop-auto-continue.sh
  ```
  Then remove `.github/auto-continue-enabled` to prevent a later session's lifecycle hook from starting another loop (see "Session-end lifecycle: blocker notification and auto-continue"). Removing the flag alone does not stop a loop that is already running.

## What the CLI can use

The Copilot and Cline CLIs can read the shared `AGENTS.md`. The Copilot CLI also reads `.github/instructions/*.instructions.md`; Cline reads workspace rules under `.clinerules/` (including path-scoped rules) and skills under `.cline/skills/`. Copilot slash-command prompts are available in VS Code Chat, not as CLI commands. Cline's extension and CLI use different hook locations; see "Enabling Cline hooks".

## Session-end lifecycle: blocker notification and auto-continue

When the configured lifecycle hook runs, both backends use the same decision logic (`scripts/lib/handoff-core.sh`):

- **Copilot**: the `Stop` hook runs `scripts/check-handoff.sh`.
- **Cline**: `TaskComplete`, `TaskCancel`, and `SessionShutdown` hooks run `scripts/check-handoff-cline.sh`. The scaffold registers them for both Cline surfaces.

Both entry points make the same decision:

- **A `⛔ Blocked` task exists** → calls `./notify.sh "<subject>" "<message>"` (implement this with a real notification; it's a no-op stub until you do) and logs to `docs/.handoff-notifications.log`.
- **No blocker, auto-continue is off** → just reports that.
- **No blocker, auto-continue is on, tasks remain** → backgrounds `scripts/auto-continue.sh`, which runs the headless CLI against remaining tasks until it encounters a blocker, finishes the task list, detects no progress, or reaches its run limit. See [maintainer notes](misc/auto-continue-implementation.md) for how the loop is implemented.

First complete the [CLI prerequisites and Dev Container setup](#prerequisites-and-safe-execution) above.

Auto-continue is **off by default**. The `.github/auto-continue-enabled` flag applies to **both Copilot and Cline**. Create it to enable auto-continue, leave it empty to select an installed CLI automatically (Copilot is preferred), or write `copilot` or `cline` in it to select one. Remove it to disable auto-continue for future session ends:

```bash
touch .github/auto-continue-enabled        # on, auto-detect installed CLI (copilot preferred)
echo cline > .github/auto-continue-enabled # on, pin a specific CLI
rm .github/auto-continue-enabled           # off
```

Env var overrides (only take effect on manual/direct runs of `auto-continue.sh`, not the hook-triggered path, since hooks don't reliably propagate shell env vars):

| Variable | Purpose | Default |
|---|---|---|
| `AUTO_CONTINUE_CLI` | Force `copilot` or `cline` | unset — falls back to the flag file's contents, then auto-detect |
| `AUTO_CONTINUE_MAX_ITERATIONS` | Maximum number of headless CLI runs in one continuation loop (normally one task attempt per run) | `10` |

Each loop iteration is one separate headless CLI invocation; the agent is prompted to work on one task per invocation. The default limit is 10 invocations. Lower the limit for smaller batches.

### Task-table conventions auto-continue (and every session) relies on

See `docs/tasks.md`'s own legend for the full wording — summarized here because it affects how `scripts/lib/handoff-core.sh` and `auto-continue.sh` interpret the file:

- **Forward test dependency**: a task whose test can only pass once a *later* task exists is left `🔄 In Progress · <date> (depends on T0XX)`, not marked Done and not marked Blocked — this is a normal sequencing note, not a blocker, so it must not contain the word "Blocked" or it will spuriously trigger notification.
- **Blocker scope**: mark a task-specific blocker on that task's row. If a project-wide question blocks all work, mark the next task that would otherwise be worked with the same `⛔ Blocked · <reason>` status and say that it blocks all remaining work. The status format is the same in both cases. Hooks scan task rows, so a blocker written only in `docs/handoff.md` will not trigger notification.

## Updating

Pull upstream changes into a consuming project, from the consumer's repo root:

```bash
git submodule update --remote external/ai-session-kit   # fetches + fast-forwards to the submodule's remote HEAD
git add external/ai-session-kit                          # stage the new commit pointer
git commit -m "chore: update ai-session-kit"           # the pointer bump is a real commit in the consumer repo
```

`--remote` is the key flag — a plain `git submodule update` alone re-checks-out whatever commit the consumer repo currently *points at*, it won't move that pointer forward on its own. Equivalently, from inside the submodule itself: `cd external/ai-session-kit && git pull && cd - && git add external/ai-session-kit && git commit`.

Either way, re-run `create-scaffold-kit.sh` afterward to pick up new/changed host-owned files — it won't clobber anything you've customized (see Install).

## Notifications and permissions

- The scaffolded `notify.sh` is a logging stub; it does not send notifications or read `.env` by default. When adding a notification provider, store its API key in the consuming project's gitignored `.env` (or another secret store), not in source code. The stub includes a commented example for loading trusted, shell-compatible `.env` values; only enable it if that file is controlled by you.
- Auto-continue does not ask for approval on each tool call: Copilot runs with `--allow-all-tools`, and Cline runs with `--auto-approve true`. Limited command restrictions are safeguards, not a security boundary. Auto-continue can modify or delete project files. Use an appropriately isolated environment, such as a Dev Container, and limit its mounted files and credentials before enabling it.
- Agent file-scope limits are instructions, not a filesystem sandbox. Shell restrictions are enforced by Copilot's agent tool configuration and Cline's `PreToolUse` hook; neither substitutes for isolating the environment.
