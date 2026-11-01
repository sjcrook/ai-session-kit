#!/usr/bin/env bash
# Scaffolds AGENTS.md, .github/*, docs/*, and notify.sh into a consuming project.
# Usage: external/ai-session-kit/template/create-scaffold-kit.sh [target-dir]
# Run from the consuming project's repo root; target defaults to the current directory.
# Vendor this repo at exactly 'external/ai-session-kit' -- the scaffolded Stop hook hardcodes that path.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_ROOT="$(cd "${1:-.}" && pwd)"

COPIED=()
SKIPPED_IDENTICAL=()
MANUAL_MERGE=()
PRESERVED_POLICY=()

# Copies $1 (source file) to $TARGET_ROOT/$2 (relative dest path), asking before
# overwriting anything that already exists and differs.
copy_one() {
  local src="$1" rel="$2"
  local dest="$TARGET_ROOT/$rel"

  if [[ "$rel" == "command-exceptions/command-exceptions.conf" && ( -e "$dest" || -L "$dest" ) ]]; then
    PRESERVED_POLICY+=("$rel")
    return
  fi
  if [[ ! -e "$dest" ]]; then
    mkdir -p "$(dirname "$dest")" || return 1
    cp "$src" "$dest" || return 1
    [[ -x "$src" ]] && chmod +x "$dest"
    COPIED+=("$rel")
    return
  fi

  if diff -q "$src" "$dest" >/dev/null 2>&1; then
    SKIPPED_IDENTICAL+=("$rel")
    return
  fi

  local reply="n"
  if [[ -t 0 ]]; then
    read -r -p "  '$rel' already exists and differs. Overwrite? [y/N] " reply
  fi

  if [[ "$reply" =~ ^[Yy]$ ]]; then
    cp "$dest" "$dest.bak.$(date +%Y%m%d%H%M%S)" || return 1
    cp "$src" "$dest" || return 1
    [[ -x "$src" ]] && chmod +x "$dest"
    COPIED+=("$rel (overwritten, backup kept)")
  else
    MANUAL_MERGE+=("$rel")
  fi
}

while IFS= read -r -d '' src; do
  rel="${src#"$SCRIPT_DIR"/project/}"
  if ! copy_one "$src" "$rel"; then
    echo "Failed to scaffold '$rel'." >&2
    exit 1
  fi
done < <(find "$SCRIPT_DIR/project" -type f -print0)

GI_SRC="$SCRIPT_DIR/gitignore.append"
GI_DEST="$TARGET_ROOT/.gitignore"
touch "$GI_DEST"
gitignore_added=0
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  if ! grep -qxF "$line" "$GI_DEST"; then
    echo "$line" >>"$GI_DEST"
    gitignore_added=$((gitignore_added + 1))
  fi
done <"$GI_SRC"

echo ""
echo "Scaffold complete."
echo "  Copied: ${#COPIED[@]}"
echo "  Already up to date: ${#SKIPPED_IDENTICAL[@]}"
echo "  Operator policy preserved: ${#PRESERVED_POLICY[@]}"
echo "  .gitignore lines added: $gitignore_added"

if [[ ${#MANUAL_MERGE[@]} -gt 0 ]]; then
  echo ""
  echo "These already existed, differ from the template, and were left untouched -- merge manually:"
  for f in "${MANUAL_MERGE[@]}"; do
    echo "  - $f"
  done
fi

echo ""
echo "Next steps:"
echo "  1. Fill in docs/functional-spec.md, then docs/technical-spec.md, then use the /tasks prompt to populate docs/tasks.md."
echo "  2. Implement notify.sh with a real notification (email/Slack/etc)."
echo "  3. Confirm this repo is vendored at exactly 'external/ai-session-kit' (the Stop hook hardcodes that path)."
echo "  4. Before unattended container use, mount command-exceptions/ and enforcement paths read-only; see the kit README."
