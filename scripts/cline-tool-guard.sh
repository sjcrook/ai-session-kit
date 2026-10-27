#!/usr/bin/env bash
# Cline PreToolUse hook: enforces (1) a role-based restriction mirroring the
# planner/implementer/handoff-writer Copilot custom agents (.github/agents/),
# and (2) a dangerous-command deny-list for shell execution.
#
# (2) replaces the CLINE_COMMAND_PERMISSIONS environment variable that
# auto-continue.sh used to set for the Cline backend: confirmed empirically
# (not just from docs) that it has no effect at all — a command matching its
# deny pattern ran anyway. Cline's CLI has no built-in command allow/deny
# list; a PreToolUse hook that can actually cancel the tool call is the only
# mechanism that works.
#
# Installed under BOTH .cline/hooks/PreToolUse.sh (discovered by the Cline
# CLI) and .clinerules/hooks/PreToolUse with no file extension (discovered by
# the Cline VS Code extension) — each surface only reads hooks from its own
# directory convention, confirmed empirically. Both copies must stay
# byte-identical.
#
# Role state lives in .cline/.active-role, a plain-text file written by the
# planner/implementer/handoff-writer skills and by the tasks/handoff workflow
# skills (.cline/skills/*/SKILL.md) as their first step. Enforcement reads
# this file fresh on every tool call rather than any Cline conversation/task
# state, so it is confirmed to work identically whether the call comes from a
# resumed task, a brand-new task, the CLI, or the VS Code extension.
#
# Vendored, read-only — assumes invocation cwd is the project root (confirmed
# empirically: Cline spawns hook subprocesses with cwd set to the workspace
# root regardless of where the `cline` process/extension itself runs from).
set -uo pipefail

ROLE_FILE=".cline/.active-role"

payload="$(cat)"
tool_name="$(printf '%s' "$payload" | sed -n 's/.*"toolName"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
role="$(tr -d '[:space:]' <"$ROLE_FILE" 2>/dev/null || true)"

deny() {
  local reason="$1 The entire tool call was rejected, including all commands in a batch; Cline may end the active task. Do not retry or disguise the denied operation."
  local diagnostic="$(date -u +%FT%TZ) cline-tool-guard: denied tool=$tool_name role=${role:-none}: $reason"
  local location="See hook stderr for the diagnostic."
  if [[ -d docs ]]; then
    if printf '%s\n' "$diagnostic" >>docs/.auto-continue.log; then
      location="See docs/.auto-continue.log for the diagnostic."
    else
      printf '%s\n' "cline-tool-guard: could not write docs/.auto-continue.log" "$diagnostic" >&2
    fi
  else
    printf '%s\n' "$diagnostic" >&2
  fi
  echo "{\"cancel\": true, \"errorMessage\": \"$reason $location\"}"
  exit 0
}

if [[ "$tool_name" == "run_commands" || "$tool_name" == "execute_command" ]]; then
  if [[ "$role" == "planner" || "$role" == "handoff-writer" ]]; then
    deny "The '$role' role does not run shell commands — see .cline/skills/$role/SKILL.md."
  fi

  # Deny-list safety net for every role (including implementer/none) — mirrors
  # the git push*/rm -rf*/sudo * patterns the Copilot CLI backend denies via
  # --deny-tool. Matched against the whole raw tool-call payload rather than a
  # hand-parsed command field: simple substring/regex matching here is
  # deliberately conservative (it can over-block) rather than fragile (trying
  # to hand-parse a JSON command array without a jq dependency this repo
  # doesn't otherwise require).
  for rule in 'git push' 'rm -rf' 'sudo'; do
    case "$rule" in
      'git push') pattern='git[[:space:]]+push' ;;
      'rm -rf') pattern='rm[[:space:]]+-rf' ;;
      sudo) pattern='sudo[[:space:]]' ;;
    esac
    if printf '%s' "$payload" | grep -Ei "$pattern" >/dev/null; then
      deny "Command matches a denied pattern: $rule. This applies to temporary cleanup and file content too. Use file-editing tools for source/test content; if no permitted workflow exists, report the blocker."
    fi
  done
fi

echo '{"cancel": false}'
