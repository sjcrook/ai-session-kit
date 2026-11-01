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
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/command-policy.sh"

payload="$(cat)"
tool_name="$(printf '%s' "$payload" | sed -n 's/.*"toolName"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
role="$(tr -d '[:space:]' <"$ROLE_FILE" 2>/dev/null || true)"

record_diagnostic() {
  local diagnostic="$(date -u +%FT%TZ) cline-tool-guard: $1 tool=$tool_name role=${role:-none}: $2"
  DIAGNOSTIC_LOCATION="See hook stderr for the diagnostic."
  if mkdir -p .ai-session; then
    if printf '%s\n' "$diagnostic" >>.ai-session/auto-continue.log; then
      DIAGNOSTIC_LOCATION="See .ai-session/auto-continue.log for the diagnostic."
    else
      printf '%s\n' "cline-tool-guard: could not write .ai-session/auto-continue.log" "$diagnostic" >&2
    fi
  else
    printf '%s\n' "cline-tool-guard: could not create .ai-session runtime directory" "$diagnostic" >&2
  fi
}

deny() {
  local reason="$1 The entire tool call was rejected, including all commands in a batch; Cline may end the active task. Do not retry or disguise the denied operation."
  record_diagnostic denied "$reason"
  echo "{\"cancel\": true, \"errorMessage\": \"$reason $DIAGNOSTIC_LOCATION\"}"
  exit 0
}

if [[ "$tool_name" == "run_commands" || "$tool_name" == "execute_command" ]]; then
  if [[ "$role" == "planner" || "$role" == "handoff-writer" ]]; then
    deny "The '$role' role does not run shell commands — see .cline/skills/$role/SKILL.md."
  fi
  if ! command_policy_load; then
    deny "Command policy error: $COMMAND_POLICY_ERROR No shell commands are permitted until the operator corrects the policy."
  fi

  # Deny-list safety net for every role (including implementer/none) — mirrors
  # the git push*/rm -rf*/sudo * patterns the Copilot CLI backend denies via
  # --deny-tool. Matched against the whole raw tool-call payload rather than a
  # hand-parsed command field: simple substring/regex matching here is
  # deliberately conservative (it can over-block) rather than fragile (trying
  # to hand-parse a JSON command array without a jq dependency this repo
  # doesn't otherwise require).
  permitted_rules=()
  for rule in 'git push' 'rm -rf' 'sudo'; do
    case "$rule" in
      'git push') pattern='git[[:space:]]+push' ;;
      'rm -rf') pattern='rm[[:space:]]+-rf' ;;
      sudo) pattern='sudo[[:space:]]' ;;
    esac
    if printf '%s' "$payload" | grep -Ei "$pattern" >/dev/null; then
      if command_policy_allows "$rule"; then
        permitted_rules+=("$rule")
      else
        deny "Command matches a denied pattern: $rule. This applies to temporary cleanup and file content too. Use file-editing tools for source/test content; ask the operator to review command-exceptions/command-exceptions.conf if permission is needed."
      fi
    fi
  done
  for ((i = 0; i < ${#permitted_rules[@]}; i++)); do
    record_diagnostic "allowed by operator exception" "${permitted_rules[i]} (command-exceptions/command-exceptions.conf)."
  done
fi

echo '{"cancel": false}'
