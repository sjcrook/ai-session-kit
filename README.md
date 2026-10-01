# ai-session-kit

A vendorable framework for spec-driven, sprint-based AI coding sessions in VS Code (GitHub Copilot) and Cline: a functional/technical spec, a sprint task list, and a handoff doc carry context between sessions, with a `Stop` hook that detects blockers and can optionally keep going headlessly.

This repo *is* the vendored core — you don't clone it standalone to use it, you vendor it into a real project (see Install).

## What's in here

```
scripts/                   vendored, read-only core
  check-handoff.sh         Stop hook entry point: detects BLOCKED tasks, notifies, or starts auto-continue
  auto-continue.sh         headless continuation loop (GitHub Copilot CLI or Cline CLI)

template/                  scaffold payload + installer
  create-scaffold-kit.sh   copies template/project/* into a consuming project's root
  gitignore.append         lines appended (not overwritten) to the consumer's .gitignore
  project/                 everything that lands in the consumer's repo root:
    AGENTS.md              always-on session conventions
    notify.sh              notification stub (implement with email/Slack/etc.)
    docs/
      functional-spec.md   what to build, for non-engineering review
      technical-spec.md    how to build it; also where frontend stack gets recorded
      tasks.md             sprint checklist; single source of truth for progress
      handoff.md           snapshot for the next session (State/Decisions/Open questions/Blockers/Next)
    .github/
      prompts/             /functional-spec, /technical-spec, /tasks, /handoff
      agents/              planner, implementer, handoff-writer (scoped tool access per role)
      hooks/               Stop hook wiring (hardcoded to vendor/ai-session-kit/scripts/check-handoff.sh)
```

## Install

Vendor this repo at **exactly** `vendor/ai-session-kit` in the consuming project — the scaffolded Stop hook hardcodes that path.

```bash
git submodule add <this-repo-url> vendor/ai-session-kit
git submodule update --init --recursive
```

Then scaffold the host-owned files into the project root:

```bash
vendor/ai-session-kit/template/create-scaffold-kit.sh
```

Run it from the consuming project's repo root (or pass a target directory as the first argument). It's safe to re-run any time:

- Missing files are copied in.
- Files identical to the template are skipped.
- Files that already exist and differ are left untouched and listed at the end for you to merge manually — nothing is silently overwritten. Answer `y` at the prompt if you do want to overwrite (a timestamped `.bak` is kept).
- Recommended `.gitignore` lines (`.env`, the two log files, the auto-continue flag) are appended, not overwritten.

A fresh clone of a project that vendors this kit needs:

```bash
git clone --recurse-submodules <project-url>
# or, if already cloned:
git submodule update --init --recursive
```

## Day-to-day usage

This part happens in **VS Code's Copilot Chat panel** (not the standalone CLI — see "Where to start a session" below), since prompts, custom agents, and the Stop hook are chat-specific features.

1. Open Copilot Chat, make sure the mode/agent picker is set to **Agent**, then type `/functional-spec` and press enter — VS Code resolves this to `.github/prompts/functional-spec.prompt.md` (it shows up in the autocomplete list as you type `/`). It interviews you in the chat conversation and writes `docs/functional-spec.md`.
2. Do the same with `/technical-spec` — it reads the functional spec, interviews you further, and writes `docs/technical-spec.md` (and `.github/instructions/frontend.instructions.md` if the project has a UI).
3. Run `/tasks` to turn both specs into a sprint checklist in `docs/tasks.md`.
4. Work sessions follow `AGENTS.md`: read the specs/tasks/handoff first, work one task test-first, check it off, update `docs/handoff.md` before ending — or run `/handoff` to do that for you.
5. If a task can't be finished, mark it `- [ ] T<id>: BLOCKED: <reason>` in `docs/tasks.md` instead of guessing.

You can also run any prompt via the Command Palette: **Chat: Run Prompt...** → pick it from the list, or open the `.prompt.md` file in the editor and click its play button.

### Using the three custom agents

Two ways, both in the Copilot Chat panel:

- **Automatically**: some prompts already delegate to one via their frontmatter (`tasks.prompt.md` has `agent: planner`, `handoff.prompt.md` has `agent: handoff-writer`) — running `/tasks` or `/handoff` invokes the right agent for you with no extra step.
- **Manually**: open the agent/mode picker (the dropdown next to the chat input, normally showing "Agent"/"Ask"/"Edit") and select `planner`, `implementer`, or `handoff-writer` by name, then type your request directly — useful when you want, say, the implementer's TDD-only persona without going through a prompt file.

The point of having three is tool scoping, not ceremony: `planner` can't touch source code, `handoff-writer` can't touch source code either, only `implementer` has `execute` access to actually run tests.

## Where to start a session: VS Code chat vs. CLI

**Start interactive sessions (spec writing, planning, implementation) from VS Code's Copilot Chat panel, not the standalone CLI.** Prompts, custom agents, and the `Stop` hook are chat-specific — confirmed the standalone `copilot` CLI has no hook/lifecycle concept in its `--help` output at all, so a session you start from a bare terminal `copilot` invocation never triggers `check-handoff.sh`, blocker notification, or auto-continue.

What the CLI *is* for here: it's the headless worker that `auto-continue.sh` invokes on your behalf after a chat session ends cleanly — you don't normally invoke it yourself. The exception is deliberately running one task non-interactively for testing, e.g. `copilot -p "..." --allow-all-tools -s`.

## Stopping a session

- **Interactive chat session** (VS Code): use the stop button in the chat panel, or just close the request — this is what triggers the `Stop` hook.
- **Interactive CLI session** (`copilot` or `cline` run directly in a terminal): `Ctrl+C`.
- **A running auto-continue loop** (backgrounded by the hook, so there's no terminal to `Ctrl+C`): it writes its PID to `docs/.auto-continue.pid` on start and removes it on exit.
  ```bash
  pid=$(cat docs/.auto-continue.pid 2>/dev/null)
  if [ -n "$pid" ]; then
    pkill -P "$pid"   # stop whichever CLI invocation is currently running
    kill "$pid"       # stop the loop itself so it doesn't start another iteration
  fi
  ```
  Also `rm .github/auto-continue-enabled` so the *next* session's Stop hook doesn't start a new loop.

## Does the CLI read the same project files as VS Code chat?

Verified directly rather than assumed:

- **`copilot` CLI**: yes to `AGENTS.md` and `.github/instructions/*.instructions.md` — confirmed with `copilot instruction list`, which lists both as discovered sources. Custom agents are supported too, via `copilot --agent <name> -p "..."` (documented in `copilot --help`), matching names defined in `.github/agents/*.agent.md`. Prompts (`.prompt.md`, the `/functional-spec`-style slash commands) have **no CLI equivalent** — there's no `copilot prompt` subcommand or flag; they're a VS Code chat UI feature only.
- **`cline` CLI**: its native, documented convention is `.clinerules`, not `AGENTS.md` — I haven't verified whether it also reads `AGENTS.md`/`.github/agents` the same way, so don't assume parity here. Check with `cline doctor` or the current Cline docs before relying on it.

## Stop hook: blocker notification and auto-continue

Every session end runs `scripts/check-handoff.sh`:

- **A `BLOCKED` task exists** → calls `./notify.sh "<subject>" "<message>"` (implement this with a real notification; it's a no-op stub until you do) and logs to `docs/.handoff-notifications.log`.
- **No blocker, auto-continue is off** → just reports that.
- **No blocker, auto-continue is on, tasks remain** → backgrounds `scripts/auto-continue.sh`, which loops a headless CLI (GitHub Copilot CLI or Cline CLI) against the next task until one is `BLOCKED`, none remain, or a max-iteration cap is hit.

Auto-continue is **off by default** — it runs unattended shell commands via `--allow-all-tools` (Copilot) / `--auto-approve true` (Cline). To enable it:

```bash
touch .github/auto-continue-enabled        # on, auto-detect installed CLI (copilot preferred)
echo cline > .github/auto-continue-enabled # on, pin a specific CLI
rm .github/auto-continue-enabled           # off
```

Env var overrides (only take effect on manual/direct runs of `auto-continue.sh`, not the hook-triggered path, since hooks don't reliably propagate shell env vars):

| Variable | Purpose | Default |
|---|---|---|
| `AUTO_CONTINUE_CLI` | Force `copilot` or `cline` | unset — falls back to the flag file's contents, then auto-detect |
| `AUTO_CONTINUE_MAX_ITERATIONS` | Cap task-iterations per Stop event | `3` |

Deny-lists (`git push`, `rm -rf`, etc.) are applied on a best-effort basis per CLI — treat auto-continue as genuinely unattended and only enable it on a project/branch you're comfortable with that.

## Updating

Pull upstream changes into a consuming project, from the consumer's repo root:

```bash
git submodule update --remote vendor/ai-session-kit   # fetches + fast-forwards to the submodule's remote HEAD
git add vendor/ai-session-kit                          # stage the new commit pointer
git commit -m "chore: update ai-session-kit"           # the pointer bump is a real commit in the consumer repo
```

`--remote` is the key flag — a plain `git submodule update` alone re-checks-out whatever commit the consumer repo currently *points at*, it won't move that pointer forward on its own. Equivalently, from inside the submodule itself: `cd vendor/ai-session-kit && git pull && cd - && git add vendor/ai-session-kit && git commit`.

Either way, re-run `create-scaffold-kit.sh` afterward to pick up new/changed host-owned files — it won't clobber anything you've customized (see Install).

## Security notes

- `notify.sh` and any project-specific scripts it calls should load secrets from `.env` (gitignored), never hardcode them.
- Review what `--allow-all-tools` / `--auto-approve true` actually permit before enabling auto-continue; it executes shell commands with no human approval step.
