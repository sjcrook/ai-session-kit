# Configuration and technical reference

Start with the [user guide](../README.md) for installation and everyday use.
This reference covers deployment protection, policy semantics, and integration
details needed when configuring or maintaining the kit.

## Protecting the container

The kit does not create or certify container mounts. Configure them through your
Dev Container generator before unattended work, and verify them as the agent user.
Keep Docker sockets, privileged modes, unrelated writable host directories, and
unnecessary credentials out of the container. Preserve independent backups of
the writable workspace.

An approval file is trustworthy only when the agent cannot change it or the code
that enforces it. A writable alias to a protected host path defeats that protection.
Read-only file permissions alone are not equivalent to a read-only mount.

### Recommended access

| Paths in the application | Access inside the container |
|---|---|
| `command-exceptions/` | Read-only; operator updates from host |
| `external/`, or individual vendored tooling directories | Read-only |
| Actual submodule Git metadata directories | Read-only |
| `.devcontainer/` and configuration inputs outside it | Read-only |
| `.cline/hooks/`, `.clinerules/hooks/`, `.github/hooks/` | Read-only |
| `.cline/skills/`, `.github/agents/`, `.github/prompts/`, stable instructions | Read-only during ordinary implementation |
| Application source/tests, task list, handoff, `.ai-session/` runtime files | Read/write |
| `.cline/.active-role`, `.github/auto-continue-enabled`, PID state | Read/write |

Do not protect all of `.cline/`, `.github/`, or the application's `docs/`
indiscriminately: they contain mutable workflow state. Frontend instruction files
may also need creation during planning; prepare them before protecting those paths.

The file `.cline/.active-role` records the role currently selected by Cline,
such as `planner`, `implementer`, or `handoff-writer`. The agent must be able to
update this file when changing roles, so leave it writable. This means role
selection guides the workflow but is not a permission that only you can grant:
the agent can change its recorded role. Making the guard read-only does not
change that. Operator-approved command exceptions do not override the role check.

### Mount example

The following example shows read-only mounts in a Dev Container configuration.
It assumes your project appears at `/workspace` inside the container and its
submodule Git metadata is stored in `.git/modules` on the host. If your setup
uses different paths, adjust the mount targets and metadata source accordingly.

```json
{
  "mounts": [
    "source=${localWorkspaceFolder}/command-exceptions,target=/workspace/command-exceptions,type=bind,readonly",
    "source=${localWorkspaceFolder}/external,target=/workspace/external,type=bind,readonly",
    "source=${localWorkspaceFolder}/.git/modules,target=/workspace/.git/modules,type=bind,readonly",
    "source=${localWorkspaceFolder}/.devcontainer,target=/workspace/.devcontainer,type=bind,readonly",
    "source=${localWorkspaceFolder}/.cline/hooks,target=/workspace/.cline/hooks,type=bind,readonly",
    "source=${localWorkspaceFolder}/.clinerules/hooks,target=/workspace/.clinerules/hooks,type=bind,readonly",
    "source=${localWorkspaceFolder}/.github/hooks,target=/workspace/.github/hooks,type=bind,readonly",
    "source=${localWorkspaceFolder}/.cline/skills,target=/workspace/.cline/skills,type=bind,readonly",
    "source=${localWorkspaceFolder}/.github/agents,target=/workspace/.github/agents,type=bind,readonly",
    "source=${localWorkspaceFolder}/.github/prompts,target=/workspace/.github/prompts,type=bind,readonly",
    "source=${localWorkspaceFolder}/AGENTS.md,target=/workspace/AGENTS.md,type=bind,readonly"
  ]
}
```

All source paths must exist before container creation. This fragment illustrates
the required mounts; use your generator's supported inputs rather than
hand-editing generated configuration.

Read-only bind mounts work for Linux containers on macOS, Windows, and Linux
hosts. Remote Docker hosts require source paths on that host; arbitrary local
bind mounts are not available in Codespaces in the same way.

Directory mounts are preferable where practical. An individual file mount can
retain old content when a host editor replaces the file; recreate the container
after such replacement. With any policy edit, confirm the container sees the new
contents before restarting work. In-place updates were verified in a bounded
Docker Desktop fixture, but file-sharing and editor behavior vary.

### Submodule metadata

A submodule's working tree and Git metadata are usually separate. On the host,
discover the actual metadata location for each protected submodule:

```bash
git -C external/ai-session-kit rev-parse --absolute-git-dir
```

Conventional submodules store metadata under the parent's `.git/modules/`.
Protecting that directory covers their configuration, refs, objects, and hooks.
Linked worktrees, nested submodules, and separate Git directories may use other
paths. Mount the actual metadata paths read-only at their corresponding container
locations, without writable aliases.

### Verification checklist

Before granting exceptions, verify in the actual container:

1. Application files and runtime-state paths remain writable.
2. Mount information shows protected paths are read-only. Creating a uniquely
   named disposable probe file in each protected directory must fail. Never
   overwrite existing files as a test.
3. No writable aliases, Docker socket, or privilege-escalation path expose the
   protected resources.
4. Check that the Cline guard rejects a sample deletion request when no exceptions
   are enabled. From your application's root inside the container, run:

   ```bash
   printf '%s\n' '{"toolName":"run_commands","command":"rm -rf /example"}' |
     bash external/ai-session-kit/scripts/cline-tool-guard.sh
   ```

   This sends the text `rm -rf /example` to the guard for inspection; it does
   **not** run that deletion command. Expect a response containing
   `"cancel": true` and a reason naming `rm -rf`. The recorded Cline role must
   be `implementer`, or no role selected; a planner or handoff-writer role would
   reject shell requests for a different reason.
5. After enabling `allow-recursive-delete` from the host, confirm the container
   sees the policy edit and rerun the same check. Expect `"cancel": false` and an
   log entry in `.ai-session/auto-continue.log` saying
   `allowed by operator exception`. This records that your approval allowed a
   request the guard would otherwise reject; it is not an error.
   Then remove `allow-recursive-delete` from the policy file on the host, check
   that the container sees the updated file, and run the check again.
   Expect `"cancel": true`, showing that deletion is restricted again.
6. For Copilot launched by auto-continue, stop and restart the worker after a
   policy change: its permissions are set when each CLI invocation starts.
   Cline reads the policy before each shell-tool call, so it does not need a
   restart to read an edit. However, if a rejection already ended its request,
   start a new request using the documented resume workflow.
   Before unattended use, check your selected tool's behavior in a separate test
   project containing only disposable files. Verify that a restricted operation
   is blocked without approval and allowed with approval. Do not test deletion
   against your real application files. The guard check above tests Cline's
   script directly; it does not prove that Cline is invoking the hook or that
   Copilot is applying its permissions.

Offline tests cannot establish mount protection or live CLI/provider behavior.

## Git and protected files

Read-only mounts do not change tracked Git permissions or automatically exclude
files from commits. Keep the parent repository's remaining Git metadata writable
if the agent needs staging and commits.

Status, diff, and log normally work. Staging and committing application changes
also work, including reading protected files changed from the host. Updating a
protected submodule requires host-side access.

Pulls, checkouts, merges, and rebases can fail when they need to write protected
paths, potentially after changing other files. Do such maintenance on the host,
with workers stopped, and inspect state after a failed operation.

Update submodules on the host, review them, and commit their chosen references in
the application. Directory-mounted changes normally appear without a rebuild;
recreate the container for changed mount layout or replaced mount-source
directories. Do not update enforcement during an active run.

The scaffold adds `command-exceptions/` to your application's `.gitignore` so
your local approvals are not normally included in commits. This does not make
the directory read-only; the container mount provides that protection.

Git will still include changes to a policy file if you previously added it to
the repository, and `git add -f` can add an ignored file. Do not use force-add
for approvals. Before committing, run `git diff --cached` and check that it
does not include your local policy file. If the file was already added to Git,
remove it from Git's tracking while keeping your local copy:

```bash
git rm --cached command-exceptions/command-exceptions.conf
```

Review and commit that removal so future commits no longer include the policy.

## CLI installation

Choose **Cline**, **Copilot**, or both. For each tool, the VS Code extension
provides the chat interface, while its separate CLI runs unattended tasks.
Install the CLI inside the Dev Container, not just on the host.

### 1. Configure installation before opening the container

If using [dev-container-config](https://github.com/sjcrook/dev-container-config),
run its generator from your application's root on the host:

```bash
./external/dev-container-config/generate.sh
```

The generator asks about Node.js first, then pnpm, then `postCreateCommand`,
and later extra VS Code extensions, with other prompts in between.
Follow that order using the settings below: select the toolchain, enter the CLI
installation command, then add the extension IDs.
That command runs automatically when the container is created; you do not need
to repeat the installation manually after startup.

Use the command for the toolchain you selected. The pnpm toolchain blocks bare
npm installation commands, so do not use the npm examples in that environment.

#### Cline

Select Node.js when prompted. At `postCreateCommand`, enter the installation
command for your selected toolchain:

| Selected toolchain | `postCreateCommand` |
|---|---|
| pnpm | `pnpm add --global cline` |
| Plain Node.js/npm | `npm install -g cline` |

Later, at `Extra VS Code extensions`, add `saoudrizwan.claude-dev`.

#### Copilot

Select **Node.js 22 or later** when prompted. Use the approved CLI installation
command below at `postCreateCommand`. Later, at `Extra VS Code extensions`,
include the GitHub Copilot extensions your VS Code setup uses
(`GitHub.copilot` and `GitHub.copilot-chat`) if they are not installed as part of your VS Code build.

Copilot's package needs installation scripts to run. GitHub explicitly warns
that installing with `ignore-scripts=true` needs an override. The generator's
pnpm 12 toolchain carries the supplied script policy into pnpm's configuration;
bootstrapping pnpm does **not** enable scripts for subsequently installed tools.
Therefore a plain `pnpm add --global @github/copilot` is not a reliable setup
when your policy disables scripts.

**`ignore-scripts=true` is a default, not a restriction that only you can lift.**
Command-line options or environment variables can override it. Making `.npmrc`
or pnpm's configuration read-only prevents editing those files, but does not
prevent these overrides. This helps avoid accidental script execution; it does
not stop an agent with shell access from enabling scripts.

If you choose to allow Copilot's installation script, use:

| Selected toolchain | `postCreateCommand` |
|---|---|
| pnpm 12 | `pnpm --ignore-scripts=false --allow-build=@github/copilot add --global @github/copilot` |
| Plain Node.js/npm | `npm_config_ignore_scripts=false npm install -g @github/copilot` |

The pnpm command enables scripts for this installation and names Copilot as the
package allowed to run its installation script. Other packages with unapproved
scripts can still cause installation to fail; do not solve that by approving
all package scripts. pnpm's `--allow-build` option also records package build
approval, rather than merely downloading the package.
Neither command changes the default `ignore-scripts` setting for future installs.
The npm command does not provide pnpm's package-by-package approval control.

Copilot has no special protection here: someone with shell access can substitute
another package and allow its scripts too. `postCreateCommand` has no special
authority; the same commands can run in a container terminal. The request to
approve scripts yourself is guidance, not an enforced human-only approval check.
Requiring your approval would need additional enforcement that the agent cannot
change or bypass.

Keep the generator's registry and minimum-release-age requirements in place.
If the registry lacks the package or no eligible version is available, resolve
that through your approved package process rather than bypassing the policy.
If installation scripts may not be approved at all, use an administrator-approved
image or binary installation instead of these commands.

See [GitHub's Copilot CLI installation instructions](https://docs.github.com/en/copilot/how-tos/copilot-cli/set-up-copilot-cli/install-copilot-cli),
[pnpm's installation options](https://pnpm.io/cli/add#--allow-build), and
[pnpm's script settings](https://pnpm.io/settings/build#ignorescripts).

### 2. Create or rebuild the container

Finish the generator workflow, then open or rebuild the Dev Container. Wait for
`postCreateCommand` to finish and check its output for installation errors.
If installing both CLIs, combine their approved installation commands with
`&&` so a failed installation does not silently continue to the next one.

For the generated pnpm toolchain, the global executable directory is already
on `PATH`. If a CLI is not found, check the installation output and container
configuration rather than assuming the VS Code extension supplied it.

### 3. Verify and sign in inside the container

Open a container terminal and check the CLI you installed:

| Tool | Installation check | Sign-in |
|---|---|---|
| Cline | `cline --version` | Run `cline` and follow its provider/authentication setup. |
| Copilot | `copilot --version` | Run `copilot`, then use `/login` if prompted. |

Copilot CLI requires Copilot access, and organization policy may restrict its
use. Do not assume signing in to a VS Code extension also authenticates its CLI.

If you omitted automatic installation, you can run the approved command manually
inside the container. Also add it through the generator for future container
creation. Change settings through the generator's supported workflow; do not
hand-edit generated configuration.

## Command policy

The fixed location is `command-exceptions/command-exceptions.conf`, relative to
the application root. The scaffold creates it with no grants if missing and
always preserves existing policy, even when other files are overwritten.
There is no environment-variable override for its location.

Supported names:

| Entry | Default restriction relaxed |
|---|---|
| `allow-recursive-delete` | `rm -rf` |
| `allow-git-push` | `git push` |
| `allow-sudo` | `sudo` |

These settings allow the listed commands generally, not just for a particular
file or folder. For example, `allow-recursive-delete` permits `rm -rf` against
any writable location, not only the folder you had in mind. Allowing `sudo` does
not give the agent privileges that the operating system has withheld.

### Syntax and errors

These rules apply to the contents of `command-exceptions/command-exceptions.conf`
and explain what happens if that file is missing or cannot be read correctly.
To allow a command listed above, put its corresponding setting in the file,
for example:

```text
# Allow recursive deletion
allow-recursive-delete
```

- Put one setting per line, spelled exactly as shown in the table above.
- Blank lines, full-line `#` comments, surrounding spaces/tabs, CRLF endings,
  and duplicate names are accepted.
- Inline comments, arbitrary patterns, and unknown names are invalid.
- The directory and file must not be symlinks; the file must be regular and
  readable. The parser reads data, never executes or sources it.
- Missing directory/file or empty policy grants no exceptions.
- Invalid or unreadable policy rejects Cline shell calls and stops auto-continue
  before either CLI launches, with an explicit diagnostic.
- Non-shell editing tools remain available. Mount protection, not an instruction
  alone, prevents policy or enforcement edits.

### Batches and matching limits

All matched rules need approval. A Cline batch containing `rm -rf` and `git push`
is rejected if only deletion is approved. No commands in the rejected call run;
earlier calls may have run.

The guard scans the entire submitted text, not every action a program performs.
A heredoc writing a test containing `rm -rf` can match even when it only writes
text. Conversely, submitting `bash tests/run.sh` does not inspect the script's
internal commands. Use editing tools for source/test changes; do not disguise
denied operations with alternate spellings, interpreters, or wrappers.

### Backend differences

| Execution path | Policy enforcement |
|---|---|
| Cline CLI/extension with hooks enabled | One snapshot per shell call; existing textual matching and cancellation |
| Copilot CLI launched by auto-continue | Read before each invocation; native `--deny-tool` flags omitted for approved classes |
| Independently launched Copilot CLI or Copilot Chat | Not governed by this policy integration; use that surface's controls |

Cline observes edits on subsequent calls, not retroactively on approved calls.
Copilot flags stay fixed for the invocation: stop/restart after granting or
revoking permission. Native Copilot matching and Cline scanning are not identical.

Cline logs exceptions used by an allowed call; Copilot logs enabled exceptions at
launch. Neither diagnostic logs raw command arguments. Cline logs the first
unapproved match in `git push`, `rm -rf`, `sudo` order. Runtime writers create
`.ai-session/` when needed. If the guard cannot create it or write the log,
it reports to hook stderr.

Policy exceptions do not add automatic retries or a pause/resume state machine.
See the [approval and recovery procedure](../README.md#approve-a-restricted-operation-and-resume).

## Continuation settings

The application-relative `.github/auto-continue-enabled` file controls
session-end launching for both backends. Its contents select `cline` or `copilot`;
empty means auto-detect, preferring Copilot. Removing it prevents future
hook-triggered launches but does not stop a running loop.

Overrides for direct/manual launches:

| Variable | Purpose | Default |
|---|---|---|
| `AUTO_CONTINUE_CLI` | Select `copilot` or `cline` | Enable-file contents, then auto-detection |
| `AUTO_CONTINUE_MAX_ITERATIONS` | Maximum headless invocations per loop | `10` |

Setting `AUTO_CONTINUE_CLI` in a terminal affects scripts launched from that
terminal. It does not necessarily affect runs started automatically by VS Code
when an AI session ends, because VS Code may not have that terminal's settings.
For those automatic runs, choose the CLI by writing its name into
`.github/auto-continue-enabled`. For example, run this from the application root
to enable automatic continuation with Cline:

```bash
printf 'cline\n' > .github/auto-continue-enabled
```

Use `copilot` instead of `cline` to select Copilot.

Each invocation is prompted to implement one task, test-first, and update the
handoff. Hooks do not write that handoff. The loop stops for task blockers,
completion, CLI failure/abort, two consecutive unchanged-task-list comparisons,
or the iteration cap. It prevents another loop from starting while its recorded
PID is alive, but this is not coordination for independently launched clients.

### Session-end hooks and notifications

**The handoff workflow and the automatic check are different operations.**
Before ending an interactive session, you must request `/handoff` in Copilot
Chat or ask Cline to run the handoff skill. That workflow asks the AI to record
progress and next steps in `docs/handoff.md` and update the task list.

The session-end hooks run automatically, but they do **not** run that workflow
or write a handoff. Despite their names, the `check-handoff` scripts check the
already-saved task list to decide whether to notify you or start continuation.
They cannot reconstruct progress that the AI has not saved.

Copilot Chat's `Stop` hook calls the kit's `check-handoff.sh`. Cline's
`TaskComplete`, `TaskCancel`, and `SessionShutdown` hooks call
`check-handoff-cline.sh`. Both use `lib/handoff-core.sh` to:

1. Notify if any saved task row is Blocked.
2. Otherwise launch auto-continue if enabled and unfinished tasks remain.
3. Otherwise report that there is nothing to launch.

Cancellation can therefore trigger a continuation attempt while enabled.
Disable the enable file before stopping workers or intervening manually.
Copilot CLI does not run the VS Code Chat Stop hook; the continuation loop drives
its successive invocations directly.

The application's `notify.sh` receives a subject and message. Its default stub
only logs; configure a real provider for unattended alerts. Store secrets outside
source control. It does not load `.env` by default; only enable shell sourcing
for trusted shell-compatible configuration.

| Application-relative log | Contents |
|---|---|
| `.ai-session/auto-continue.log` | Worker output, continuation decisions, guard diagnostics |
| `.ai-session/handoff-notifications.log` | Blocker notifications and notification-stub activity |

### Task status conventions

The following are instructions for the **AI implementer and handoff writer**,
not steps you normally need to perform yourself. The project's agent instructions
and workflows tell the AI to maintain these statuses as it works and records a
handoff. The hooks only read the saved statuses; they do not update them or
verify that the AI recorded them correctly.

The application's task table in `docs/tasks.md` is the source of truth.
Blocker detection scans task rows, not free text in the handoff.

- Record task-specific blockers on that task.
- For a project-wide blocker, mark the next task Blocked too.
- For a normal dependency on a later task, leave the current task In Progress
  with `(depends on T0XX)` and record the pair in the handoff. Do not use the word
  `Blocked` for that normal sequencing note.
- Permission changes do not prove completion. Reassess only the resolved blocker
  and rerun acceptance tests; do not clear unrelated blockers.

## Integration details

Cline CLI reads `.cline/hooks/<Name>.sh`; the extension reads
`.clinerules/hooks/<Name>` without an extension. Both layouts are installed.
Enable hooks in the extension's settings; CLI discovery is automatic.

Cline skills select `planner`, `implementer`, or `handoff-writer` by writing
`.cline/.active-role`. The tasks and handoff skills select the corresponding
roles. Planner and handoff-writer shell calls are rejected; implementer or no
selected role may run commands subject to policy.

Copilot custom agents restrict tool access, with shell access only for the
implementer. Intended file scopes are instructions, not filesystem restrictions.

Both CLIs can read `AGENTS.md`. Copilot also reads
`.github/instructions/*.instructions.md`; Cline uses `.clinerules/` and
`.cline/skills/`. Copilot slash-command prompts belong to VS Code Chat.

For interrupted sessions, `/recover-handoff` uses the Copilot handoff-writer
agent or Cline's recover-handoff skill. Unlike a normal handoff, it explicitly
reconstructs progress from saved evidence without assuming conversation history
or rerunning tests. It requires auto-continue to be disabled and workers stopped,
reports inaccessible evidence, and changes only the handoff and supported task
status cells (plus Cline's initial role marker). See the
[recovery instructions](../README.md#stop-automation). Rerun the scaffold from
the host to install the new prompt and skill before reopening protected mounts.

After operator approval, `/prepare-resume <task_id>` uses the same no-shell
handoff role to compare the visible policy with the specified task's rejection.
It requires stopped-worker confirmation, asks for missing or ambiguous denial
evidence, preserves unrelated blockers, and prepares only that task's status and
the handoff. Readiness means permission to attempt remaining work, not passing
tests or completed implementation. Other Blocked rows still prevent automation.
It does not launch automation or execute the rejected operation. See the
[approval procedure](../README.md#approve-a-restricted-operation-and-resume).

For frontend projects, technical planning creates stack-specific conventions in
`.github/instructions/frontend.instructions.md` and `.clinerules/frontend.md`.
Their `applyTo` and `paths` patterns control when the tools load them.

### Cline cancellation

The shell guard uses `cancel` / `errorMessage` responses. Rejection can end the
active task; a hook displaying “Completed” does not establish task completion.
Cline can report `[abort]` while exiting zero. Auto-continue detects that output,
stops with exit code 1, and notifies rather than retrying to the no-progress cap.

If no guard denial explains interruption, inspect Cline diagnostics and version,
and check whether another client is using the same session. An idle window alone
does not establish a conflict.

The current [Cline SDK plugin API](https://docs.cline.bot/sdk/plugins) documents
`beforeTool` returning `{ skip: true, reason }` for model-visible rejection.
That is not this kit's shell-hook contract and does not establish compatibility
with its supported CLI/extension installations. No migration to that API is
implemented; returning `cancel: false` for an unapproved operation is not recovery.

## Maintainer reference

| Kit path | Responsibility |
|---|---|
| `scripts/cline-tool-guard.sh` | Cline role and command checks |
| `scripts/auto-continue.sh` | Headless continuation and CLI invocation |
| `scripts/stop-auto-continue.sh` | Stops the recorded loop and CLI child |
| `scripts/check-handoff*.sh` | Session-end entry points |
| `scripts/lib/handoff-core.sh` | Shared blocker/notification/launch logic |
| `scripts/lib/command-policy.sh` | Shared operator policy reader |
| `template/project/` | Files copied into the application |
| `template/create-scaffold-kit.sh` | Scaffold installation and preservation |
| `template/gitignore.append` | Application ignore entries |

Run offline regression checks from the kit repository:

```bash
bash tests/cline-tool-guard.sh
bash tests/auto-continue.sh
bash tests/scaffold.sh
bash tests/runtime-state.sh
```

They use synthetic payloads, mock CLIs, and temporary scaffold targets, without
provider credentials or real agent runs. Actual container and CLI behavior
requires the separate [verification checklist](#verification-checklist).

See also the [continuation implementation notes](../misc/auto-continue-implementation.md).
