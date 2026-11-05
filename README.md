# ai-session-kit

Help your AI plan a project, work through tasks, and pick up where it left off.
Use **GitHub Copilot** or **Cline**, supervise each session, or let the AI
continue unattended until it finishes or needs help.

Use the kit alongside a **Dev Container**, especially for unattended work.
[dev-container-config](https://github.com/sjcrook/dev-container-config) generates
a restricted development environment that complements the kit: the kit organizes
the AI's work, while the container limits its access to your host and provides a
consistent toolchain. Configure read-only mounts to protect approvals and tooling.
A container does not protect the writable workspace from changes or deletion, so
limit exposed credentials and keep independent backups.

The kit adds instructions and four documents to your project:

| Document | What it answers |
|---|---|
| `docs/functional-spec.md` | What should we build? |
| `docs/technical-spec.md` | How should it work? |
| `docs/tasks.md` | What needs doing, and what is complete or blocked? |
| `docs/handoff.md` | Where should the next session start? |

You keep these files in your application's repository. During task implementation,
the AI is instructed to work on one task at a time, write tests first, and record progress before stopping.
Review its changes and test results; instructions do not guarantee correctness.

## Start here

- [Install in your project](#install-in-your-project)
- [Run your first session](#run-your-first-session)
- [Add or change functionality](#add-or-change-functionality)
- [Run unattended](#run-unattended)
- [Approve a restricted operation and resume](#approve-a-restricted-operation-and-resume)
- [Update the kit](#update-the-kit)
- [Troubleshooting](#troubleshooting)
- [Container protection](supplemental/reference.md#protecting-the-container)
- [Command policy reference](supplemental/reference.md#command-policy)

## Install in your project

You need a Git repository for your application and either Copilot Chat or Cline
in VS Code. Run the setup commands below **on the host, from your application's
repository root**, before opening a container with protected directories.

### Adding the kit for the first time

Add the kit as a Git submodule: a dependency stored at a specific revision inside
your project.

```bash
git submodule add https://github.com/sjcrook/ai-session-kit.git external/ai-session-kit
git submodule update --init --recursive
external/ai-session-kit/template/create-scaffold-kit.sh
```

Keep the path **exactly `external/ai-session-kit`**; the installed integrations
depend on it. Commit the submodule registration and the scaffolded project files.
The local approval policy and runtime files are ignored by default.

<details>
<summary>What does the scaffold create or overwrite?</summary>

It installs project instructions, planning documents, Copilot prompts and agents,
Cline skills and hooks, a notification stub, and a default command-exception file.

- Missing files are created; identical files are skipped.
- If an existing file differs, it is left for manual merging unless you approve
  an overwrite at the prompt. Approved overwrites retain a timestamped backup.
- An existing command-exception policy is **always preserved**, without prompting
  to overwrite it. A missing policy is created with no exceptions enabled.
- Recommended ignore entries are appended without replacing your `.gitignore`.
- You can pass a target directory to the scaffold script instead of running it
  from the project root.

Rerun the scaffold when updating the kit, and review any reported differences.

</details>

### Opening a project that already includes the kit

Do **not** add the submodule again. Download the project and its recorded
dependencies:

```bash
git clone --recurse-submodules <your-application-repository-url>
```

If you already cloned without submodules, run this inside that clone:

```bash
git submodule update --init --recursive
```

Then run the scaffold command above to create any missing local files, including
the default approval policy. A new clone contains committed project files, not
ignored files such as credentials or local approvals.

## Run your first session

Open the application in VS Code. Choose one of the following workflows.
The AI will ask about your requirements while preparing the specifications.

General questions do not activate the structured workflow. The agent should
answer normally, reading files only when relevant to your question, without
automatically loading the four project documents or updating tasks and handoffs.
Invoke a kit command/skill or explicitly ask for equivalent workflow work to
activate it; asking about a command is not the same as running it. An unrelated
question after a workflow command returns to ordinary conversation. Command
restrictions, approval requirements, and active role tool restrictions still
apply. Auto-continue explicitly requests implementation and retains its required
document reads.

### GitHub Copilot

Use **Copilot Chat in Agent mode**, not the standalone CLI, for these prompts:

| Step | Enter in chat | Result |
|---|---|---|
| 1. Describe the project | `/functional-spec` | Functional specification |
| 2. Choose the design | `/technical-spec` | Technical specification |
| 3. Break work into tasks | `/tasks` | Sprint/task list |
| 4. Implement the next task | `/implement` | Tests, implementation, and task status |
| 5. Finish your session | `/handoff` | Updated context for the next session |

For later sessions, use `/implement` to continue or specify a task to the
`implementer` agent.

Planning covers the full requested scope; the one-task implementation limit and
handoff's "Next" list do not restrict `/tasks`. The three blank task-template
rows are placeholders: `/tasks` fills them in place, retains their IDs, and adds
as many tasks and sprints as the specifications require. It may clear a
placeholder's blocker solely for missing description/acceptance criteria once
those details are supplied, but preserves genuine Done, In Progress, and Blocked
work. The equivalent Cline skills follow the same rules. Review the backlog
before implementation and request a handoff update if planning made it stale.

<details>
<summary>Choosing an agent or running a prompt another way</summary>

The agent picker offers `planner` for task planning, `implementer` for code and
tests, and `handoff-writer` for recording progress. The prompts select the
appropriate agent for you. Only the implementer has shell-tool access.

You can also use **Chat: Run Prompt...** in the Command Palette, or open a
prompt file and click its play button.

</details>

### Cline

Hook setup depends on how you run Cline:

- **VS Code extension:** turn on **Enable Hooks** in Cline's settings.
- **Command-line interface (CLI):** no separate setting is needed; it discovers
  the installed hooks automatically.

Ask Cline to run these skills in order:

| Step | Enter in chat |
|---|---|
| 1. Describe the project | `run the functional-spec skill` |
| 2. Choose the design | `run the technical-spec skill` |
| 3. Break work into tasks | `run the tasks skill` |
| 4. Implement the next task | `run the implementer skill` |
| 5. Finish your session | `run the handoff skill` |

You can also use `/<skill-name>`, such as `/implementer`. The same skills are
available in the CLI; for example, `cline "run the implementer skill"`.

**Before ending an implementation session, request the handoff.** Stopping a session
does not automatically write it. If work is blocked, the AI should record the
reason in the task list immediately, rather than waiting for the handoff.
General conversation does not require a handoff. Installed lifecycle hooks still
check task state and may notify or launch auto-continue when enabled; these
instructions do not disable those hooks.

## Add or change functionality

Treat the specifications as living documents and completed tasks as historical
records. After an initial implementation:

1. Use `/functional-spec` to describe the approved new or changed behavior and
  acceptance examples, preserving requirements that still apply.
2. Use `/technical-spec` to update the affected design, interfaces, data,
  compatibility, and verification requirements.
3. Run `/tasks` to reconcile the current specifications against existing task
  descriptions and acceptance criteria. Changed behavior needs new follow-up
  tasks with fresh IDs, not reopened or rewritten completed tasks. Include
  updates to tests that assert behavior the new requirements replace.
4. Review the planner's requirement-coverage table and new tasks, then request
  `/handoff` to refresh its "Next" list before `/implement` or auto-continue.

Use the equivalent skills in Cline. A completed task is not proof that its
acceptance criteria cover a revised requirement: a task that rejected an operator
does not cover a later requirement to support it. The planner must report these
mismatches, even without an older spec revision, and must not report "no changes
needed" without a requirement reconciliation. Repeating `/tasks` should not
duplicate follow-up tasks that already cover the current scope.

These are agent instructions, not a deterministic requirements checker. Review
the reconciliation before implementation. Existing installations must receive
the updated planning prompts, agents, and skills via the [kit update
procedure](#update-the-kit); updating this repository alone does not change
previously scaffolded files.

## Run unattended

Auto-continue starts separate AI sessions to work through successive tasks.
It stops when the task list is complete, any task is marked Blocked, a CLI
invocation fails or reports an abort, progress stalls, or the run limit is reached.
The default limit is **10 sessions**, normally one task attempt per session.

> **Before enabling unattended work:** run in a suitably restricted Dev Container,
> limit credentials and host mounts, and keep independent backups. The AI can
> modify or delete the writable workspace, including host-mounted files.
> Command filters are guardrails, not a sandbox. Follow the
> [protected-mount setup](supplemental/reference.md#protecting-the-container) and
> [verification checklist](supplemental/reference.md#verification-checklist).

### Prepare the environment

Inside the container, install and authenticate **Copilot CLI (`copilot`) or Cline
CLI (`cline`)**. Installing only the VS Code extension is not enough. Confirm the
selected command is available in the terminal where automation will run.

[dev-container-config](https://github.com/sjcrook/dev-container-config) can generate
the container configuration. Use its generator rather than hand-editing generated
files; see [CLI installation](supplemental/reference.md#cli-installation) for
Cline and Copilot installation commands for pnpm and npm toolchains.

If you want notifications when intervention is needed, connect the project's
`notify.sh` to your email or messaging service. It only logs until you configure it.
Keep notification credentials out of source control.

### Start automation

From the application's root **inside the container**, select a CLI and launch:

```bash
echo cline > .github/auto-continue-enabled
external/ai-session-kit/scripts/auto-continue.sh
```

Use `copilot` instead of `cline` to select Copilot. The command runs in the
terminal and appends output to `.ai-session/auto-continue.log`.

The kit creates `.ai-session/` in your application's root for logs and the
running worker's PID file. This directory is writable and ignored by Git;
project specifications and progress documents remain in `docs/`.

The enable file also allows configured session-end hooks to start a background
loop after interactive work. Auto-continue is off until you create that file.
Do not run competing workers in the same workspace.

<details>
<summary>Automatic CLI selection and smaller batches</summary>

An empty enable file selects an installed CLI automatically, preferring Copilot:

```bash
touch .github/auto-continue-enabled
```

For a direct launch limited to three sessions:

```bash
AUTO_CONTINUE_MAX_ITERATIONS=3 external/ai-session-kit/scripts/auto-continue.sh
```

See [continuation settings](supplemental/reference.md#continuation-settings) for CLI
selection overrides and session-end behavior.

</details>

### Stop automation

First remove the enable file to prevent a session-end hook from launching another
loop, then stop the recorded loop and its current CLI child:

```bash
rm -f .github/auto-continue-enabled
external/ai-session-kit/scripts/stop-auto-continue.sh
```

Removing the enable file alone does **not** stop an existing loop. For an
interactive session, use the chat stop button or press `Ctrl+C` in the CLI.
Once the active request has stopped, ask the AI to run the handoff workflow as a
new request, then close the session. If stopping the CLI exits it, reopen the
conversation if supported. After an interruption, especially if you must start
a new session without the previous conversation, use the saved recovery workflow:

- **Copilot Chat:** enter `/recover-handoff`; it selects the handoff writer.
- **Cline:** enter `/recover-handoff` or `run the recover-handoff skill`.

It reviews saved documents, available changes, and recorded results, then writes
confirmed progress, uncertainties, and next steps into the handoff. It does not
run tests or resume implementation, and records verification it cannot perform.
Keep auto-continue disabled and workers stopped while recovery runs. Use ordinary
`/handoff` for a normal session ending where the conversation is still available.

## Approve a restricted operation and resume

By default, the kit restricts `git push`, `rm -rf`, and `sudo` on its supported
execution paths. If a necessary operation is rejected, **you can approve the
permission and let the AI continue**; you do not have to implement the task yourself.

**Approvals must be controlled from the host.** Mount `command-exceptions/`
read-only, along with the tooling and hook directories that enforce the policy,
before relying on approvals. A policy the agent
can edit is not trusted approval. See the [mount guide](supplemental/reference.md#mount-example).

Once those protections are in place, follow these steps when the AI stops because
a necessary operation was denied:

1. [Stop automation](#stop-automation).
2. **For auto-continue with either Copilot or Cline**, read
   `.ai-session/auto-continue.log` for the rejection or error. **For an interactive
   session**, check the tool's conversation panel or CLI terminal output. Cline
   guard denials are also recorded in the log when logging is available.
3. On the host, edit `command-exceptions/command-exceptions.conf`. For example:

   ```text
   allow-recursive-delete
   ```

4. In the container, run `/prepare-resume <task_id>` (e.g.,
   `/prepare-resume T032`). In Cline, you can also ask it to
   `run the prepare-resume skill for T032`. Confirm that workers are stopped
   when asked. The workflow checks the visible policy against the rejection,
   verifies available saved state, and prepares the affected task and handoff.
   It asks for missing evidence rather than guessing and preserves unrelated
   blockers. It does not run commands or resume implementation.
5. Start automation only after it reports `Ready to resume <task_id>` and no
   other Blocked task rows remain. The AI reruns necessary validation and marks the task
   Done only after its acceptance tests pass.
6. When the permission is no longer needed, stop the worker and remove the
   exception from the host.

> **Approving recursive deletion allows `rm -rf` to delete files and directories
> anywhere the container user has write access, including your host-mounted
> project.** The approval is not limited to temporary files.

<details>
<summary>Other exceptions and differences between Cline and Copilot</summary>

| Entry | Restriction relaxed |
|---|---|
| `allow-recursive-delete` | `rm -rf` |
| `allow-git-push` | `git push` |
| `allow-sudo` | `sudo` |

Use one exact name per line. Approving deletion does not approve pushing or
sudo, and does not override role restrictions.

Cline reads policy for each shell call. Headless Copilot launched by the kit
reads it at each invocation; restart a running invocation after a permission
change. Independently launched Copilot sessions have their own permission controls.

See [policy syntax](supplemental/reference.md#syntax-and-errors),
[matching limits](supplemental/reference.md#batches-and-matching-limits), and
[backend differences](supplemental/reference.md#backend-differences) for details.

</details>

## Update the kit

Stop workers. From the application's root **on the host**, fetch a newer kit
revision and refresh the scaffold:

```bash
git submodule update --remote external/ai-session-kit
external/ai-session-kit/template/create-scaffold-kit.sh
```

Review the changes and merge any existing scaffold files reported as different,
especially project instructions and the Cline implementer skill. Existing
approvals are preserved. Commit the updated submodule reference and intended
project changes.

For example, if you updated the kit and merged changes to the project
instructions and Cline implementer skill, run these commands from your
application's root:

```bash
git add external/ai-session-kit AGENTS.md .cline/skills/implementer/SKILL.md
git diff --cached
git commit -m "chore: update ai-session-kit and project instructions"
```

Adjust the file list to include only the scaffold changes you reviewed and want
to keep. `git diff --cached` shows everything currently staged; review it before
committing, including anything staged earlier. Do not include local approvals
or credentials.

A plain `git submodule update --init --recursive` restores the revision already
recorded by the application; `--remote` selects a newer revision from the
submodule's configured remote branch.

Protected directories can be updated from the host. Recreate the container if
mount configuration or mount-source directories change. See
[Git and protected files](supplemental/reference.md#git-and-protected-files) for details.

## Troubleshooting

| Symptom | First action |
|---|---|
| Cline stops before completing a task | Look for `cline-tool-guard: denied` in `.ai-session/auto-continue.log`; review permission before restarting. |
| `[abort] aborted by another client` | Treat it as interruption, not success. The message alone does not prove a competing client exists. Check guard diagnostics first. |
| No CLI found | Install/authenticate the CLI and check its availability inside the container, not just on the host. |
| Automation will not proceed | Check all task rows for Blocked status. A blocker only in the handoff does not trigger task-based notification. |
| Policy error | Correct the host-side policy using the documented names; invalid policy prevents shell execution. |
| Approval edit is not visible | Check contents inside the container; recreate it if host file replacement or file sharing left a stale mount. |

A rejected Cline command batch does not run at all, although earlier calls may
have run. Do not infer completion from an exit code of zero or a hook displaying
“Completed.” Inspect saved state and test results.

## Further reference

- [Container protection and mount setup](supplemental/reference.md#protecting-the-container)
- [Command policy](supplemental/reference.md#command-policy)
- [Cline and Copilot policy differences](supplemental/reference.md#backend-differences)
- [Continuation settings](supplemental/reference.md#continuation-settings)
- [Maintainer reference and offline tests](supplemental/reference.md#maintainer-reference)
