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

Planning approval in `docs/planning/` is separate from operator command
exceptions. The planner needs write access to record reviewed snapshots; the
implementer is instructed not to modify them. The continuation check compares
those writable snapshots with current documents, so this is a workflow guard,
not independent proof of human authorization. For stronger separation, protect
`docs/planning/` read-only during implementation and reopen it only for supervised
planning. Do not make it permanently read-only while expecting `/tasks` to
record approval.

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
| Cline | `cline --version` | Run `cline auth` and follow its provider/model setup; check installed-version help if this command differs. |
| Copilot | `copilot --version` | Run `copilot`, then use `/login` if prompted. |

Copilot CLI requires Copilot access, and organization policy may restrict its
use. Do not assume signing in to a VS Code extension also authenticates its CLI.

If you omitted automatic installation, you can run the approved command manually
inside the container. Also add it through the generator for future container
creation. Change settings through the generator's supported workflow; do not
hand-edit generated configuration.

### Trust and permissions checklist

These are independent checks; completing one does not complete the others.

| Check | Setup and verification |
|---|---|
| VS Code workspace trust | In the Dev Container window, open the actual project and run **Workspaces: Manage Workspace Trust**. Review it before trusting; do not globally disable trust checks. |
| Copilot CLI authentication | As the worker's container user, run `copilot` and complete sign-in if needed. VS Code extension sign-in alone is insufficient. |
| Copilot CLI folder trust | Trust and remember the actual container path; see the instructions below. Check that CLI output does not report skipped repository hooks. |
| Cline CLI authentication | Run `cline auth` from the container project and configure the provider/model. Use `cline --help`, `cline config`, or `cline doctor` to diagnose setup, without sharing credentials. |
| Cline tool permissions and hooks | The kit uses `--auto-approve true` for unattended CLI calls. This grants tool approval, not folder trust or a sandbox. Verify the installed CLI invokes the kit's `.cline/hooks` and that a harmless guard-input probe is rejected. The VS Code Cline extension separately requires **Enable Hooks**. |
| Independent enforcement | Verify read-only mounts, absence of writable aliases, and current planning approval using the container verification checklist. |

The current [Cline CLI documentation](https://docs.cline.bot/usage/cli-overview)
does not describe a Copilot-style remembered-folder trust setup. Do not invent
a `trustedFolders` setting for Cline or assume Copilot trust applies to it.
Follow any additional prompts or requirements shown by the installed version.
CLI configuration and authentication may need restoration when a container is
recreated; the container generator does not automatically confer project trust.

### Copilot CLI folder trust

CLI sign-in and folder trust are separate from VS Code authentication and
workspace trust. Establish both as the same container user that runs
auto-continue, from the actual container project root (for example `/workspace`).
Run `copilot` interactively, review the repository configuration, and select
the option to trust and remember the folder when prompted. This permits loading
repository configuration; it does not remove the kit's command deny rules or
read-only mounts.

In Copilot CLI 1.0.107, remembered folders are stored in `trustedFolders` in
`~/.copilot/config.json` (or the configured Copilot home), not `settings.json`.
`copilot config trustedFolders` cannot read or change that value. Preserve
existing settings; do not replace the configuration with a trust-only file.
Re-establish trust after recreating a container if its CLI user state was lost.

An interactive launch may show the signed-in session without offering a trust
prompt. That alone does not prove remembered trust. In this version, if no prompt
is offered, the operator can add the reviewed absolute project path to the
`trustedFolders` array in the CLI user's `config.json`, preserving every other
setting and existing trusted folder. The file can contain comments; do not feed
it to a strict JSON parser or replace it with a new minimal file. Verify the
saved entry, then start a new CLI session. Do not store CLI user configuration
or credentials in the project or commit them.

For a supervised, single prompt-mode invocation, this version also supports
`copilot --trust-folder -p "<prompt>"`. That trusts only the resolved working
directory for that invocation, without saving trust or granting tool/path/URL
permissions. It does not establish trust for later sessions launched by the
kit. Prefer remembered folder trust for ordinary unattended use rather than a
temporary shell wrapper.

Check the actual runtime output. A warning that repository hooks were skipped
because the folder is not trusted means hook behavior has not been validated.
Stop the worker, establish trust, and restart. Do not use `--allow-all` or
`COPILOT_ALLOW_ALL=true` simply to suppress this warning: those also approve
additional permissions.

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

Setting these variables in a terminal affects scripts launched directly from
that terminal. Do not assume they reach VS Code or Cline lifecycle hooks:
a live Cline CLI 3.0.73 check used the default limit even when its starter
session was launched with `AUTO_CONTINUE_MAX_ITERATIONS=3`.
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
or the iteration cap. An atomic `.ai-session/auto-continue.lock` directory
serializes runner startup and stays held until PID/output cleanup finishes.
Cline versions may load both installed hook layouts; simultaneous callbacks
must still produce only one worker. This does not coordinate independently
launched chat or CLI clients.

Normal exit and `stop-auto-continue.sh` release the lock. A crash or forced kill
may leave it behind. A lock with no live recorded PID causes an explicit startup
failure, not automatic lock removal: another worker may still be publishing its
PID. Disable hook launching first, verify that no auto-continue worker or its CLI
descendants are running, then remove only the empty lock directory:

```bash
rmdir .ai-session/auto-continue.lock
```

If it is not empty, inspect it rather than deleting recursively. Do not remove
a lock based solely on a missing/stale PID file, or while startup is in progress.
A stale PID file without a lock is still handled automatically for compatibility
with older runners.

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
`check-handoff-cline.sh`, with the event name supplied by the wrapper. Normal
completion uses `lib/handoff-core.sh` to:

1. Refuse continuation if an interruption pause is present.
2. Notify if any saved task row is Blocked.
3. Check shared planning/task readiness; launch only when approved, enabled,
   unfinished work remains, and no live recorded worker exists.
4. Otherwise explain why no worker was started.

Cline cancellation/shutdown never launch continuation. They persist a pause,
as do guard rejections, CLI abort/failure, and stopping a live worker.
Disable the enable file before intervening manually.
Copilot's generic Stop callback does not establish whether the developer
cancelled; do not claim Cline-specific cancellation detection for that surface.
Use `stop-auto-continue.sh` for the worker and disable launching before
cancelling interactive Copilot work.
The continuation loop drives successive Copilot CLI invocations directly;
it does not depend on the VS Code Chat Stop hook. CLI repository-hook support
depends on the installed version and folder trust. Do not infer that the Chat
hook ran merely because the CLI found `.github/hooks`; verify the actual
session-end launch in the client you use.

The application's `notify.sh` receives a subject and message. Its default stub
only logs; configure a real provider for unattended alerts. Store secrets outside
source control. It does not load `.env` by default; only enable shell sourcing
for trusted shell-compatible configuration.

| Application-relative log | Contents |
|---|---|
| `.ai-session/auto-continue.log` | Worker output, continuation decisions, guard diagnostics |
| `.ai-session/handoff-notifications.log` | Blocker notifications and notification-stub activity |
| `.ai-session/workflow-events.jsonl` | Structured role observations, tool rejections, lifecycle events, and continuation decisions |

### Runtime diagnostics and ownership

Run `bash external/ai-session-kit/scripts/workflow-status.sh` from the application
root for a read-only summary. It uses the same planning/task readiness checks as
continuation and never repairs markers, locks, approval, or task statuses.
Readiness is not evidence that current acceptance tests pass.

Events include UTC time, event name, process ID, worker run/iteration when
available, and a diagnostic description. Commands, tool payloads, and
file contents are not copied into this event stream. The existing worker output
log can still contain CLI output; protect it accordingly.

`role_observed` records a change seen at PreToolUse, not proof of who wrote it.
`role_selected` identifies worker initialization; `role_released` identifies
hook cleanup. `lifecycle_received`, `lifecycle_ownership`, `lifecycle_ignored`,
`tool_rejected`, and continuation events distinguish rejection from later cleanup.
Logging failures are reported on stderr; lifecycle handlers skip continuation
when their required diagnostics or cleanup cannot be persisted.

Worker descendants inherit a run/iteration identity, stored in
`.ai-session/cline-owner`. A mismatched or unowned terminal hook cannot clear a
worker-owned marker or trigger continuation. A verified iteration's shutdown
after TaskComplete is ignored as a duplicate. Worker cleanup removes only its
own ownership records. This is coordination, not independent authorization.

Interactive Cline hook identity has not been verified. Those events explicitly
report unavailable ownership and rely on one active workflow per workspace;
late interactive events cannot be proven safe against another interactive
workflow. Do not infer identity from arbitrary hook JSON or claim concurrent
workflow support. Hooks omitted by a crash/forced kill cannot be reconstructed.

`.ai-session/continuation-paused` preserves the first interruption reason until
restart; later cancellation/abort events remain in the event stream rather than
overwriting the original rejection.
Normal starts and hooks refuse to continue while it exists. After inspecting
affected files/tests and resolving the cause, the developer runs:

```bash
bash external/ai-session-kit/scripts/auto-continue.sh --resume
```

Only this explicit start clears the pause; planning, blockers, command policy,
and worker locking are still checked. An agent is instructed never to clear the
pause or invoke this restart autonomously. Older scaffolded wrappers that omit
an event name are treated as unknown interruptions: update both hook layouts.

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

Both `.cline/hooks/<Name>.sh` and `.clinerules/hooks/<Name>` are installed for
client compatibility. Do not assume a client reads only one layout: live Cline
CLI 3.0.73 discovered and executed both, producing duplicate callbacks. The
runner's atomic lock prevents those callbacks from starting competing workers.
Enable hooks in the extension's settings and verify discovery in the installed
client; CLI discovery was automatic in the tested version.

Cline skills select `planner`, `implementer`, or `handoff-writer` by writing
`.cline/.active-role`. The tasks and handoff skills select the corresponding
roles. Planner and handoff-writer shell calls are rejected; implementer or no
selected role may run commands subject to policy.

Roles are temporary workflow state, not the next session's default. Workflows
release their role by writing `none` with a file-editing tool as their final file
operation, including when stopping for an unmet precondition. The Cline
TaskComplete, TaskCancel, and SessionShutdown handler also resets an existing
marker when ownership permits. Only TaskComplete checks continuation; the other
events pause it. A reset failure is reported and skips the continuation check. Auto-continue still selects
`implementer` before launching its next Cline task.

A crash or forced termination may skip cleanup hooks. Before any shell command,
including orientation, a new request must select its intended role using file
tools; a resumed restricted task retains or reselects its restricted role.
Never reset on every tool call or use `none` to bypass a live restricted workflow.
The marker is workspace-wide: do not run concurrent Cline tasks/workers in one
workspace. The neutral `none` role still enforces command policy.

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
status cells (plus Cline's role selection and cleanup marker). See the
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

## Verified workflow checks

Live checks were completed on 2026-11-06 and 2026-11-07 using disposable
Node.js sum-CLI projects, including `ai-session-kit-test-2` mounted at `/workspace`
in a restricted Dev Container. The final Cline stop/resume check used released
kit commit `8925981` and Cline CLI 3.0.73. These are observed results for the
tested clients and environment, not certification of every version or project.

| Check | Observed result |
|---|---|
| Initial and change planning | Copilot with explicitly selected planner and Cline prepared reviewed proposals without implementing them. |
| Approval and reconciliation | Pending plans blocked execution; explicit approval advanced verified snapshots. Repeated change planning preserved task history without duplicate follow-ups. |
| Copilot direct continuation | Three successive tasks completed; independently verified 17 passing tests and normal worker cleanup. |
| Copilot Chat session-end launch | A handoff session automatically launched a worker that completed approved T004; 18 tests passed. This verifies Chat launching, not every Copilot CLI lifecycle hook. |
| Copilot live stop/resume | Stopped a worker with T005 In Progress, verified process-tree termination, then resumed that task; 19 tests passed. |
| Cline live planner enforcement | Planner shell calls were rejected by the installed hooks. The CLI reported an abort despite exit status 0; guard diagnostics established the denial. |
| Cline direct continuation | Runner reset the stale planner role to implementer, completed T006 and exited; 20 tests passed. |
| Cline duplicate lifecycle callbacks | T007 exposed two simultaneous workers. After the atomic-lock fix, real T008 lifecycle launching produced exactly one worker and one CLI invocation; the duplicate was rejected. 22 tests passed and PID/lock cleanup was verified. |
| Cline live stop/resume | Automatically launched T009, stopped after In Progress but before test writes, and verified all recorded worker/descendant PIDs exited. Source/test/README hashes and the 22-test baseline were unchanged. A fresh bounded worker resumed the same task without resetting history; 23 tests passed. |
| Offline runner regressions | All seven kit suites passed on macOS. Linux checks covered simultaneous startup, abandoned locks, legacy PID compatibility, process-tree stopping and restart. Twelve simultaneous starts launched exactly one CLI. |

Final independent checks found current planning approval, no remaining worker
or continuation CLI, and no PID file or lock directory. Automatic launching was disabled
after testing. The fixture's kit submodule was clean at the released commit.

### Remaining limitations

- **Copilot command routing:** automatic bare `/tasks` routing was unreliable.
  Explicit planner selection was verified; reading a role file alone does not
  enforce its tool permissions. Best-effort command mapping is not a dispatcher.
- **Instruction following:** T006 used a shell write for test code and a
  deliberately wrong expectation to manufacture a red phase. The final test
  passed, but that was not a clean workflow pass. Revised guidance requires
  editing tools and honest regression-only results; T007-T009 followed it in
  the observed runs. Instructions still do not guarantee compliance.
- **Hook environment:** Cline hook-launched workers used the default 10-session
  cap despite a three-session override on the starter invocation. Do not assume
  terminal environment overrides reach lifecycle hooks.
- **Approval and isolation:** agent-writable planning snapshots are consistency
  guards, not a security boundary. Container restrictions do not protect the
  writable workspace from deletion; keep independent backups.
- **Coverage boundaries:** stop/resume was tested before new test contents were
  saved, not at every possible interruption point. Crash/forced-kill lock
  recovery was covered by offline abandoned-lock tests, not a live client crash.
  Real notification delivery, all extension/CLI versions, larger projects and
  independently launched competing clients were not validated by these checks.
- **Fixture provenance:** files accidentally deleted during container recreation
  were recovered from saved evidence before later checks. T005's final assertions
  were reconstructed from approved acceptance criteria where the excerpt was
  incomplete, then independently tested.

Use these results as a baseline for a supervised pilot on a real project.
Review actual changes, tests and saved state before enabling unattended work.

## Maintainer reference

| Kit path | Responsibility |
|---|---|
| `scripts/cline-tool-guard.sh` | Cline role and command checks |
| `scripts/auto-continue.sh` | Headless continuation and CLI invocation |
| `scripts/stop-auto-continue.sh` | Pauses the recorded loop and signals its CLI descendants by PID before stopping the loop |
| `scripts/check-handoff*.sh` | Session-end entry points |
| `scripts/lib/handoff-core.sh` | Shared blocker/notification/launch logic |
| `scripts/lib/command-policy.sh` | Shared operator policy reader |
| `scripts/lib/workflow-runtime.sh` | Structured diagnostics, continuation pause, and worker hook ownership |
| `scripts/lib/workflow-readiness.sh` | Shared planning/task readiness and next-step guidance |
| `scripts/workflow-status.sh` | Read-only developer readiness and recovery summary |
| `template/project/` | Files copied into the application |
| `template/create-scaffold-kit.sh` | Scaffold installation and preservation |
| `template/gitignore.append` | Application ignore entries |

Run offline regression checks from the kit repository:

```bash
bash tests/cline-tool-guard.sh
bash tests/auto-continue.sh
bash tests/scaffold.sh
bash tests/runtime-state.sh
bash tests/workflow-status.sh
```

They use synthetic payloads, mock CLIs, and temporary scaffold targets, without
provider credentials or real agent runs. Actual container and CLI behavior
requires the separate [verification checklist](#verification-checklist).

See also the [continuation implementation notes](../misc/auto-continue-implementation.md).
