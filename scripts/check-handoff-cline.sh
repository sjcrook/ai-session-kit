#!/usr/bin/env bash
# Cline lifecycle hook entry point: reads and discards the hook's JSON payload
# from stdin, runs the same blocker/auto-continue check as check-handoff.sh
# (Copilot's Stop hook) via the shared lib/handoff-core.sh, and emits Cline's
# required {"cancel": false} hook-output contract.
#
# Installed under BOTH .cline/hooks/<Name>.sh (discovered by the Cline CLI) and
# .clinerules/hooks/<Name> with no file extension (discovered by the Cline
# VS Code extension) — confirmed empirically that each surface only reads
# hooks from its own directory convention, not the other's.
#
# Registered for all three of TaskComplete, TaskCancel, and SessionShutdown
# because which one fires depends on the surface and how the session ended:
#   - Normal completion: TaskComplete fires on both the CLI and the extension.
#   - VS Code extension "Cancel" button: TaskCancel fires; SessionShutdown does not.
#   - Headless CLI killed by SIGINT (e.g. auto-continue.sh's loop being torn
#     down): SessionShutdown fires; TaskCancel does not.
# Registering all three guarantees this check still runs exactly once per
# session end regardless of which surface or termination path was used, and
# the underlying handoff_core_run logic is itself idempotent (re-reading
# docs/tasks.md and docs/.auto-continue.pid-style state), so an edge case
# where more than one of these fires for the same termination is harmless.
#
# Vendored, read-only — assumes invocation cwd is the project root. Confirmed
# empirically that Cline spawns hook subprocesses with cwd set to the
# workspace root regardless of where the `cline`/extension process itself was
# launched from, matching the same assumption check-handoff.sh already makes.
set -uo pipefail
cat >/dev/null # discard the hook JSON payload; none of its fields are needed here

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/handoff-core.sh
source "$SCRIPT_DIR/lib/handoff-core.sh"

handoff_core_run "$SCRIPT_DIR" || true
echo '{"cancel": false}'

exit 0
