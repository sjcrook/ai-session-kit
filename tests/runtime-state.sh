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

rm .ai-session/auto-continue.pid .ai-session/handoff-notifications.log
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
