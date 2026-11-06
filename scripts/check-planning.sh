#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/planning-core.sh"

if ! planning_check; then
  printf '%s\n' "$PLANNING_ERROR" >&2
  exit 1
fi
printf '%s\n' 'Planning approval is current.'
