#!/usr/bin/env bash
set -euo pipefail

KIT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/ai-session-kit-stop-test.XXXXXX")"
worker=""
unrelated=""
cleanup() {
  for process in "$worker" "$unrelated"; do
    if [[ -n "$process" ]]; then
      kill -CONT "$process" 2>/dev/null || true
      kill -TERM "$process" 2>/dev/null || true
      wait "$process" 2>/dev/null || true
    fi
  done
  find "$TEST_ROOT" -depth -delete
}
trap cleanup EXIT
cd "$TEST_ROOT"
mkdir .ai-session

sleep 120 &
unrelated=$!
printf '%s\n' "$unrelated" >.ai-session/auto-continue.pid
if bash "$KIT_ROOT/scripts/stop-auto-continue.sh" >output 2>&1; then
  echo 'Unrelated process unexpectedly accepted as a worker.' >&2
  exit 1
fi
grep -F 'refusing to signal it' output >/dev/null
kill -0 "$unrelated"
echo 'PASS: an unrelated recorded PID is not signaled'

cat >auto-continue.sh <<'FIXTURE'
#!/usr/bin/env bash
set -eu
echo "$$" >.ai-session/auto-continue.pid
trap 'rm -f .ai-session/auto-continue.pid' EXIT
bash -c 'echo "$$" >child.pid; sleep 120 & echo "$!" >grandchild.pid; wait' &
wait
FIXTURE
bash ./auto-continue.sh &
worker=$!
for ((i = 0; i < 100; i++)); do
  [[ ! -s child.pid || ! -s grandchild.pid ]] || break
  sleep 0.05
done
[[ -s child.pid && -s grandchild.pid ]]
child="$(cat child.pid)"
grandchild="$(cat grandchild.pid)"
kill -0 "$child"
kill -0 "$grandchild"
bash "$KIT_ROOT/scripts/stop-auto-continue.sh" >output
wait "$worker" 2>/dev/null || true
worker=""

for process in "$child" "$grandchild"; do
  for ((i = 0; i < 100; i++)); do
    state="$(ps -p "$process" -o stat= 2>/dev/null || true)"
    [[ -n "$state" && "$state" != *Z* ]] || break
    sleep 0.05
  done
  [[ -z "$state" || "$state" == *Z* ]]
done
[[ ! -e .ai-session/auto-continue.pid ]]
kill -0 "$unrelated"
grep -F 'and its CLI descendants' output >/dev/null
echo 'PASS: worker, CLI child, and grandchild stop without signaling unrelated processes'

rm child.pid grandchild.pid
bash ./auto-continue.sh &
worker=$!
for ((i = 0; i < 100; i++)); do
  [[ ! -s child.pid || ! -s grandchild.pid ]] || break
  sleep 0.05
done
[[ -s child.pid && -s grandchild.pid ]]
child="$(cat child.pid)"
grandchild="$(cat grandchild.pid)"
[[ "$(cat .ai-session/auto-continue.pid)" == "$worker" ]]
bash "$KIT_ROOT/scripts/stop-auto-continue.sh" >output
wait "$worker" 2>/dev/null || true
worker=""
[[ ! -e .ai-session/auto-continue.pid ]]
for process in "$child" "$grandchild"; do
  state="$(ps -p "$process" -o stat= 2>/dev/null || true)"
  [[ -z "$state" || "$state" == *Z* ]]
done
echo 'PASS: a fresh worker can start and stop after interruption'
