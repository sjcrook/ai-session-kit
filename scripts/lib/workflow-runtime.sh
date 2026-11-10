#!/usr/bin/env bash
# Shared runtime diagnostics. Never pass tool payloads or command text here.

workflow_json_string() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\t'/\\t}"
  printf '"%s"' "$value"
}

workflow_event() {
  local event="$1" detail="$2" entry
  entry="{\"time\":\"$(date -u +%FT%TZ)\",\"event\":$(workflow_json_string "$event"),\"pid\":$$,\"run\":$(workflow_json_string "${AI_SESSION_RUN_ID:-unavailable}"),\"iteration\":$(workflow_json_string "${AI_SESSION_ITERATION:-unavailable}"),\"detail\":$(workflow_json_string "$detail")}"
  if ! mkdir -p .ai-session || ! printf '%s\n' "$entry" >>.ai-session/workflow-events.jsonl; then
    printf 'Cannot write .ai-session/workflow-events.jsonl; event follows:\n%s\n' "$entry" >&2
    return 1
  fi
}

workflow_pause() {
  local reason="$1"
  if ! mkdir -p .ai-session; then
    printf 'Cannot persist continuation pause: %s\n' "$reason" >&2
    return 1
  fi
  if [[ ! -e .ai-session/continuation-paused ]] &&
    ! printf '%s\n' "$reason" >.ai-session/continuation-paused; then
    printf 'Cannot persist continuation pause: %s\n' "$reason" >&2
    return 1
  fi
  if [[ ! -f .ai-session/continuation-paused || ! -s .ai-session/continuation-paused ]]; then
    printf 'Continuation pause exists but is not a nonempty regular file; inspect .ai-session/continuation-paused.\n' >&2
    return 1
  fi
  workflow_event continuation_paused "$reason Explicit developer restart with auto-continue.sh --resume is required."
}

workflow_read_role() {
  WORKFLOW_ROLE=missing
  if [[ -e .cline/.active-role || -L .cline/.active-role ]]; then
    if [[ ! -f .cline/.active-role || ! -r .cline/.active-role ]] ||
      ! WORKFLOW_ROLE="$(tr -d '[:space:]' <.cline/.active-role)"; then
      printf 'Cannot read .cline/.active-role.\n' >&2
      return 1
    fi
    case "$WORKFLOW_ROLE" in
      planner|implementer|handoff-writer|none|"") ;;
      *) printf 'Invalid .cline/.active-role; select the intended role with file tools.\n' >&2; return 1 ;;
    esac
  fi
}

workflow_observe_role() {
  local previous=unrecorded
  if [[ -f .ai-session/last-observed-role ]]; then
    previous="$(cat .ai-session/last-observed-role)" || return 1
    case "$previous" in
      planner|implementer|handoff-writer|none|missing|"") ;;
      *) printf 'Invalid saved role observation; treating it as unrecorded.\n' >&2; previous=unrecorded ;;
    esac
  fi
  if [[ "$previous" != "$WORKFLOW_ROLE" ]]; then
    workflow_event role_observed "previous=$previous current=$WORKFLOW_ROLE source=PreToolUse; observation only, writer unknown" || return 1
    if ! printf '%s\n' "$WORKFLOW_ROLE" >.ai-session/last-observed-role; then
      printf 'Cannot write .ai-session/last-observed-role.\n' >&2
      return 1
    fi
  fi
}

# Worker descendants inherit an iteration identity. Interactive Cline hooks do
# not have a verified identity contract; do not infer one from arbitrary JSON.
workflow_owner_matches() {
  WORKFLOW_OWNERSHIP=unavailable
  if [[ -e .ai-session/cline-owner ]]; then
    local owner
    if [[ ! -f .ai-session/cline-owner || ! -r .ai-session/cline-owner ]] ||
      ! owner="$(cat .ai-session/cline-owner)"; then
      printf 'Cannot read .ai-session/cline-owner.\n' >&2
      return 1
    fi
    if [[ -z "${AI_SESSION_RUN_ID:-}" || "$owner" != "$AI_SESSION_RUN_ID:${AI_SESSION_ITERATION:-}" ]]; then
      WORKFLOW_OWNERSHIP=mismatch
      return 1
    fi
    WORKFLOW_OWNERSHIP=worker
  elif [[ -n "${AI_SESSION_RUN_ID:-}" ]]; then
    WORKFLOW_OWNERSHIP=mismatch
    return 1
  fi
}
