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
- If an existing file differs from the current template, the scaffold checks
  `.ai-session-kit-manifest` — the kit commit this project was last scaffolded
  from — to tell an untouched file from a locally edited one:
  - Unchanged since that commit: the update is applied directly (no prompt).
  - Locally edited: a three-way merge combines the upstream and local changes
    when they don't overlap, keeping a timestamped backup of the pre-merge
    file for review. Overlapping edits are left for manual merging, untouched.
  - No recorded manifest, or the kit isn't a git checkout with that commit
    available: the file is left for manual merging unless you approve an
    overwrite at the prompt (the original behavior). Approved overwrites
    retain a timestamped backup.
- **Commit `.ai-session-kit-manifest`** alongside the scaffolded project files —
  without it, every update falls back to manual merging for anything you've touched.
- An existing command-exception policy is **always preserved**, without prompting
  to overwrite it, merging, or manifest tracking. A missing policy is created
  with no exceptions enabled.
- An existing `docs/planning/review.md` is also always preserved. Approved
  snapshots are project state, not scaffold templates, and are never overwritten
  by the scaffold.
- Recommended ignore entries are appended without replacing your `.gitignore`.
- You can pass a target directory to the scaffold script instead of running it
  from the project root.

Rerun the scaffold when updating the kit, and review any auto-merges or
reported differences — these are textual merges, not a guarantee that the
combined file is logically correct.

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

Use **Copilot Chat** and explicitly select the agent below before running each
workflow. This is the verified route when automatic prompt/agent selection is
unreliable. The same right-hand Chat panel can dispatch requests differently:
typing a slash command alone does not prove its workspace prompt or custom
agent was selected.

| Step | Select in agent picker | Enter in chat | Result |
|---|---|---|---|
| 1. Describe the project | Agent | `/functional-spec` | Functional specification |
| 2. Choose the design | Agent | `/technical-spec` | Technical specification |
| 3. Plan and review work | planner | `/tasks` | Proposed sprint/task list; explicitly approve before implementation |
| 4. Implement the next task | implementer | `/implement` | Tests, implementation, and task status |
| 5. Finish your session | handoff-writer | `/handoff` | Updated context for the next session |

Select the workspace prompt from suggestions when available. After a kit update
and scaffold, reload the VS Code window and start a fresh chat. If a custom
agent is missing from the picker, resolve workspace agent discovery before
proceeding. A `/tasks` response must reconcile requirements and request approval
with links to the review and backlog, not merely count completed tasks.

The installed `AGENTS.md` command mapping and `.github/copilot-instructions.md`
entry point provide best-effort guidance when commands arrive as literal text.
They are **not a verified substitute for agent selection**: automatic routing
failed in observed SDK/agent-host sessions, even after reloading. Reading role
instructions does not select the actual role or enforce its tool restrictions.
An explicit "read AGENTS.md" request can help diagnose loading, but is not the
recommended normal workflow. Installation tests validate installed guidance and
approval checks, not the chat interface's automatic routing.

If a kit workflow asks to read `AGENTS.md` outside the project, decline that
request and confirm the project root. The entry point's `../AGENTS.md` link is
relative to its containing `.github/` directory, not the shell working directory;
file tools should read `<repository-root>/AGENTS.md`.

For later sessions, use `/implement` to continue or specify a task to the
`implementer` agent.

`/implement` doesn't write a handoff — run `/handoff` before leaving the
conversation or starting a new one, not necessarily between every `/implement`
in the same conversation. A `docs/handoff.md` still showing the blank template
means no handoff has been recorded, not that no work has happened: check
`docs/tasks.md`'s actual statuses, since several completed or in-progress tasks
can exist with no handoff reflecting them yet. If you do populate a handoff's
"Next" list and later run more `/implement` sessions without updating it again,
treat `docs/tasks.md` as authoritative over a now-stale "Next" list.

Planning covers the full requested scope; the one-task implementation limit and
handoff's "Next" list do not restrict `/tasks`. The three blank task-template
rows are placeholders: `/tasks` fills them in place, retains their IDs, and adds
as many tasks and sprints as the specifications require. It may clear a
placeholder's blocker solely for missing description/acceptance criteria once
those details are supplied, but preserves genuine Done, In Progress, and Blocked
work, except unfinished work explicitly approved for supersession. The equivalent
Cline skills follow the same rules. Review and explicitly approve the backlog
before implementation and request a handoff update if planning made it stale.

The planner stores its proposal and requirement reconciliation in
`docs/planning/review.md`. Only after your explicit approval does it save verbatim
copies of both specs and the backlog in `docs/planning/` and mark the review
Approved. Commit this directory with the project documents; you do not maintain
duplicate specs yourself. If you decline, cancel, or defer approval, the review
stays Pending and implementation waits. You can return to `/tasks` later to
review and approve the current proposal.

<details>
<summary>Choosing an agent or running a prompt another way</summary>

The agent picker offers `planner` for task planning, `implementer` for code and
tests, and `handoff-writer` for recording progress. Workspace prompts declare
their intended agent, but automatic selection is not reliable in every chat
execution path; verify the picker explicitly. Planner and handoff-writer custom
agents omit shell tools; the general Agent used for specification work and the
implementer have different tool availability.

You can also use **Chat: Run Prompt...** in the Command Palette, or open a
prompt file and click its play button. These are invocation options, not proof
that a particular interface expanded the prompt or selected its declared agent.

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

Cline's tasks and planner skills use native file tools only, including for
writing the role marker, inspecting the repository, and saving approved
snapshots. They must not invoke shell tools for setup or verification.
With hooks enabled, a shell attempt is rejected and may cancel the task;
the diagnostic is recorded in `.ai-session/auto-continue.log`.
The implementer, not the planner, runs `check-planning.sh`.

**Before ending an implementation session, request the handoff.** Stopping a session
does not automatically write it, and running the implementer skill again in the
same conversation doesn't either — only request it before leaving the
conversation or starting a new one. If work is blocked, the AI should record the
reason in the task list immediately, rather than waiting for the handoff. A
`docs/handoff.md` still showing the blank template means no handoff has been
recorded, not that no work has happened — check `docs/tasks.md`'s actual
statuses, and treat them as authoritative over a stale "Next" list.
General conversation does not require a handoff. Installed lifecycle hooks still
check task state and may notify or launch auto-continue when enabled; these
instructions do not disable those hooks.

## Add or change functionality

Treat the specifications as living documents and completed tasks as historical
records. Disable auto-continue and stop unattended workers before specification
or planning changes; re-enable it only after approval and the handoff update.
For example, to add exponentiation to an existing calculator:

1. Enter `/functional-spec Add exponentiation.` The agent reads the existing
  spec, asks about missing behavior, preserves unrelated requirements, and
  replaces contradictory old behavior. Review the changes. With just
  `/functional-spec`, it asks what to build for a blank spec or what to
  add/change for a populated one. Wholesale scope replacement needs confirmation.
2. Enter `/technical-spec`. It reads the full functional spec and existing
  design, compares with the approved baseline when available, and discovers
  affected code/tests itself. You need not repeat requirements or know component
  names. Answer genuine design questions and review its coverage and changes.
3. Enter `/tasks`. For an initial backlog it plans the whole project. For an
  existing backlog it compares specs against the last approved snapshots,
  inspects affected code/tests/help/docs, and proposes follow-up work. It also
  checks all current requirements so unchanged omissions are not missed. With
  no baseline, it reports that limitation and performs full reconciliation
  rather than inventing a change history.
4. Review the persistent reconciliation and tasks, including obsolete tests
  and conflicting pending work. Explicitly approve the exact plan when asked,
  or request revisions. Completed tasks remain unchanged; approved obsolete
  unfinished tasks become Superseded, never falsely Done. The planner records
  approved snapshots only after approval.
5. Enter `/handoff`, without extra wording, to refresh context and "Next" from
  actual eligible tasks and approval state. Then enter `/implement` to work one
  task; repeat for the remaining work and run `/handoff` when ending the session.

Use the equivalent skills in Cline. A completed task is not proof that its
acceptance criteria cover a revised requirement: a task that rejected an operator
does not cover a later requirement to support it. The planner must report these
mismatches, even without an older spec revision, and must not report "no changes
needed" without a requirement reconciliation. Repeating `/tasks` should not
duplicate follow-up tasks that already cover the current scope.

`bash external/ai-session-kit/scripts/check-planning.sh` checks that approval
exists, both specs match the approved snapshots (ignoring only an optional final
newline), and task IDs/order/descriptions
and supersessions match the approved backlog. Normal status-only progress does
not invalidate approval. The implementer is instructed to run this check before
changing a task; lifecycle hooks refuse continuation and the unattended worker
checks again before every invocation. Changed scope requires `/tasks` and
renewed explicit approval. No separate `/change-tasks` command is needed.

Planning judgments and recording the developer's approval are agent instructions,
not a deterministic requirements checker or a security boundary. The snapshots
prove correspondence to a reviewed plan, not that its coverage or code is correct.
Review the reconciliation before implementation. Existing installations must
receive the updated prompts, agents, skills, shared instructions, and pending
review template via the [kit update procedure](#update-the-kit). Their first
`/tasks` run establishes an explicitly approved baseline; implementation waits
until then. Updating this repository alone does not change previously scaffolded
files.

## Run unattended

Auto-continue starts separate AI sessions to work through successive tasks.
It stops when planning approval is missing/pending/stale, the task list is
complete (Done or Superseded), any task is marked Blocked, a CLI
invocation fails or reports an abort, progress stalls, or the run limit is reached.
The default limit is **10 sessions**, normally one task attempt per session.

> **Before enabling unattended work:** run in a suitably restricted Dev Container,
> limit credentials and host mounts, and keep independent backups. The AI can
> modify or delete the writable workspace, including host-mounted files.
> Command filters are guardrails, not a sandbox. Follow the
> [protected-mount setup](supplemental/reference.md#protecting-the-container) and
> [verification checklist](supplemental/reference.md#verification-checklist).

### Prepare the environment

Complete these separate checks in the Dev Container before enabling automation:

1. **VS Code workspace trust:** open the correct container project, run
   **Workspaces: Manage Workspace Trust**, and trust it only after reviewing
   its contents. Do not disable Restricted Mode globally.
2. **CLI authentication:** install and sign in to the CLI inside the container,
   as the user that will run the worker. Extension sign-in is not proof of CLI
   sign-in.
3. **CLI trust and permissions:** Copilot needs remembered folder trust for
   the container project path. Cline needs provider setup and functioning kit
   hooks; its documented setup does not specify an equivalent remembered-folder
   trust list. Auto-approval is permission to run tools, not workspace trust.
4. **Enforcement and planning:** verify protected mounts and active hooks,
   then run `bash external/ai-session-kit/scripts/check-planning.sh`. It must
   pass before implementation.

See the [trust and permissions checklist](supplemental/reference.md#trust-and-permissions-checklist)
for setup commands and version-specific details.

Inside the container, install and authenticate **Copilot CLI (`copilot`) or Cline
CLI (`cline`)**. Installing only the VS Code extension is not enough. Confirm the
selected command is available in the terminal where automation will run.

For Copilot, also establish CLI folder trust for the project's **container path**.
VS Code workspace trust does not establish Copilot CLI trust. From the project
root, run `copilot` interactively and, after reviewing the repository's
configuration and hooks, choose to trust and remember this folder when prompted.
Remembered trust is needed for later hook-launched workers, which do not have an
interactive terminal. See [CLI folder trust](supplemental/reference.md#copilot-cli-folder-trust).
Do not use `--allow-all` or `COPILOT_ALLOW_ALL=true` merely to establish trust:
they grant additional permissions.

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
loop, then stop the recorded loop and its CLI descendants:

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
especially project instructions and the Cline implementer skill. Files that were
auto-merged (an untouched file fast-forwarded, or a non-conflicting local edit
was combined with an upstream change) still need review — check the diff and
remove the `.bak` once confirmed. Existing approvals are preserved. Commit the
updated submodule reference, the refreshed `.ai-session-kit-manifest`, and
intended project changes.

For example, if you updated the kit and merged changes to the project
instructions and Cline implementer skill, run these commands from your
application's root:

```bash
git add external/ai-session-kit .ai-session-kit-manifest AGENTS.md .cline/skills/implementer/SKILL.md
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
