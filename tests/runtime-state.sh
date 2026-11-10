#!/usr/bin/env bash
set -euo pipefail

KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/ai-session-kit-runtime-test.XXXXXX")"
trap 'find "$TEST_ROOT" -depth -delete' EXIT
cd "$TEST_ROOT"

bash "$KIT_ROOT/template/project/notify.sh" "Example subject" "Example message"
[[ ! -e docs ]]
grep -F 'Example subject' .ai-session/handoff-notifications.log >/dev/null
echo 'PASS: notification stub creates runtime storage without project documents'

mkdir docs
printf '| S01 | T001 | Example | Blocked |\n' >docs/tasks.md
rm .ai-session/handoff-notifications.log
rmdir .ai-session
source "$KIT_ROOT/scripts/lib/handoff-core.sh"
handoff_core_run "$KIT_ROOT/scripts"
grep -F 'BLOCKED' .ai-session/handoff-notifications.log >/dev/null
[[ "$HANDOFF_MESSAGE" == *'.ai-session/handoff-notifications.log'* ]]
echo 'PASS: blocker detection creates and reports the runtime notification log'

bash "$KIT_ROOT/scripts/stop-auto-continue.sh" >stop-output
grep -F 'No auto-continue PID file found' stop-output >/dev/null
printf invalid >.ai-session/auto-continue.pid
if bash "$KIT_ROOT/scripts/stop-auto-continue.sh" >stop-output 2>&1; then
  echo 'Invalid runtime PID unexpectedly accepted.' >&2
  exit 1
fi
grep -F '.ai-session/auto-continue.pid' stop-output >/dev/null
echo 'PASS: stop script uses the new runtime PID path'

mkdir .cline
printf handoff-writer >.cline/.active-role
result="$(printf '{}' | bash "$KIT_ROOT/scripts/check-handoff-cline.sh" TaskComplete)"
[[ "$result" == *'"cancel": false'* ]]
[[ "$(cat .cline/.active-role)" == none ]]
[[ "$(grep -c ' BLOCKED$' .ai-session/handoff-notifications.log)" == 2 ]]
rm .cline/.active-role
rmdir .cline
echo 'PASS: lifecycle cleanup preserves the real blocker notification check'

project="$TEST_ROOT/lifecycle"
vendor="$project/external/ai-session-kit/scripts"
mkdir -p "$vendor/lib" "$project/.cline/hooks" "$project/.clinerules/hooks"
cp "$KIT_ROOT/scripts/check-handoff-cline.sh" "$vendor/"
cp "$KIT_ROOT/scripts/lib/workflow-runtime.sh" "$vendor/lib/"
cat >"$vendor/lib/handoff-core.sh" <<'EOF'
handoff_core_run() {
  HANDOFF_MESSAGE="Checked continuation."
  if [[ -e .cline/.active-role ]]; then
    [[ "$(cat .cline/.active-role)" == none ]] || return 1
  fi
  echo checked >>checks
  if [[ -f launch-next ]]; then
    printf implementer >.cline/.active-role
  fi
}
EOF
for event in TaskComplete TaskCancel SessionShutdown; do
  for layout in .cline .clinerules; do
    hook="$layout/hooks/$event"
    [[ "$layout" != .cline ]] || hook="$hook.sh"
    cp "$KIT_ROOT/template/project/$hook" "$project/$hook"
    (
      cd "$project"
      for role in planner handoff-writer implementer; do
        printf '%s' "$role" >.cline/.active-role
        result="$(printf '{}' | bash "$hook")"
        [[ "$result" == *'"cancel": false'* ]]
        [[ "$(cat .cline/.active-role)" == none ]]
        result="$(printf '{"toolName":"run_commands","command":"git status"}' | bash "$KIT_ROOT/scripts/cline-tool-guard.sh")"
        [[ "$result" == '{"cancel": false}' ]]
      done
      printf '{}' | bash "$hook" >/dev/null
      [[ "$(cat .cline/.active-role)" == none ]]
      touch launch-next
      printf handoff-writer >.cline/.active-role
      printf '{}' | bash "$hook" >/dev/null
      if [[ "$event" == TaskComplete ]]; then
        [[ "$(cat .cline/.active-role)" == implementer ]]
      else
        [[ "$(cat .cline/.active-role)" == none ]]
      fi
      rm launch-next .cline/.active-role
      printf '{}' | bash "$hook" >/dev/null
      [[ ! -e .cline/.active-role ]]
      if [[ "$event" == TaskComplete ]]; then
        [[ "$(wc -l <checks | tr -d '[:space:]')" == 6 ]]
        [[ ! -e .ai-session/continuation-paused ]]
        rm checks
      else
        [[ ! -e checks ]]
        [[ -s .ai-session/continuation-paused ]]
      fi

      mkdir .cline/.active-role
      if printf '{}' | bash "$hook" >hook-output 2>hook-error; then
        echo 'Role reset failure unexpectedly accepted.' >&2
        exit 1
      fi
      grep -F 'Cannot reset .cline/.active-role' hook-error >/dev/null
      [[ ! -e checks ]]
      rmdir .cline/.active-role
      rm -f .ai-session/continuation-paused
    )
  done
done
echo 'PASS: both hook layouts distinguish completion from cancellation/shutdown and report cleanup failures'

(
  cd "$project"
  export AI_SESSION_RUN_ID=worker-new AI_SESSION_ITERATION=2
  printf 'worker-new:2\n' >.ai-session/cline-owner
  printf implementer >.cline/.active-role
  for identity in worker-old ""; do
    AI_SESSION_RUN_ID="$identity" bash "$vendor/check-handoff-cline.sh" TaskCancel <<< '{}' >hook-output 2>hook-error
    [[ "$(cat .cline/.active-role)" == implementer ]]
    [[ ! -e .ai-session/continuation-paused && ! -e checks ]]
    grep -F 'ownership mismatch' hook-error >/dev/null
  done
  bash "$vendor/check-handoff-cline.sh" TaskComplete <<< '{}' >hook-output
  [[ "$(cat .cline/.active-role)" == none ]]
  bash "$vendor/check-handoff-cline.sh" SessionShutdown <<< '{}' >hook-output
  [[ ! -e .ai-session/continuation-paused ]]
  [[ "$(wc -l <checks | tr -d '[:space:]')" == 1 ]]
  grep -F '"event":"role_released"' .ai-session/workflow-events.jsonl >/dev/null
)
echo 'PASS: stale/unowned hooks cannot clear a worker role; post-completion shutdown is ignored for its verified iteration'

rm .ai-session/auto-continue.pid .ai-session/handoff-notifications.log .ai-session/workflow-events.jsonl
rmdir .ai-session
touch .ai-session
if bash "$KIT_ROOT/template/project/notify.sh" >failure-output 2>&1; then
  echo 'Notification directory creation failure unexpectedly accepted.' >&2
  exit 1
fi
grep -F 'Cannot create .ai-session runtime directory' failure-output >/dev/null
if handoff_core_run "$KIT_ROOT/scripts" >failure-output 2>&1; then
  echo 'Blocker logging directory creation failure unexpectedly accepted.' >&2
  exit 1
fi
grep -F 'Cannot create .ai-session runtime directory' failure-output >/dev/null
if bash "$KIT_ROOT/scripts/auto-continue.sh" >failure-output 2>&1; then
  echo 'Worker directory creation failure unexpectedly accepted.' >&2
  exit 1
fi
grep -F 'Cannot create .ai-session runtime directory' failure-output >/dev/null
echo 'PASS: runtime directory failures are explicit'
