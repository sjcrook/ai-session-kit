#!/usr/bin/env bash
# Stop hook: notify if the session ended with a Blocked task in docs/tasks.md.
# Vendored, read-only — assumes invocation cwd is the project root (the Stop hook sets this).
#
# Core logic lives in lib/handoff-core.sh, shared with check-handoff-cline.sh
# (Cline's TaskComplete/TaskCancel/SessionShutdown hooks) so both backends make
# the same decision from the same docs/tasks.md state. This wrapper only adds
# Copilot's {"systemMessage": ...} hook-output contract.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/handoff-core.sh
source "$SCRIPT_DIR/lib/handoff-core.sh"
source "$SCRIPT_DIR/lib/workflow-runtime.sh"

handoff_core_run "$SCRIPT_DIR"
printf '{"systemMessage": %s}\n' "$(workflow_json_string "$HANDOFF_MESSAGE")"

exit 0
