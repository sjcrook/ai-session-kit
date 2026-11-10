#!/usr/bin/env bash
# Scaffolds AGENTS.md, .github/*, docs/*, and notify.sh into a consuming project.
# Usage: external/ai-session-kit/template/create-scaffold-kit.sh [target-dir]
# Run from the consuming project's repo root; target defaults to the current directory.
# Vendor this repo at exactly 'external/ai-session-kit' -- the scaffolded Stop hook hardcodes that path.
#
# Files that already exist and differ from the current template are reconciled
# against '.ai-session-kit-manifest' -- the kit commit this project was last
# scaffolded from. If a file is unchanged since that commit, the update is
# applied directly. If it was locally edited, a three-way merge (via
# scripts/lib/scaffold-merge.sh) combines upstream and local changes when they
# don't overlap; overlapping edits are left for manual merge, untouched. A
# project with no recorded manifest (or no git history to look up) falls back
# to the original ask-or-leave-for-manual-merge behavior. Commit
# '.ai-session-kit-manifest' alongside the scaffolded files.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_ROOT="$(cd "${1:-.}" && pwd)"
KIT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFEST_FILE="$TARGET_ROOT/.ai-session-kit-manifest"

# shellcheck source=../scripts/lib/scaffold-merge.sh
source "$KIT_ROOT/scripts/lib/scaffold-merge.sh"

KIT_GIT_ROOT="$(cd "$KIT_ROOT" && git rev-parse --show-toplevel 2>/dev/null || true)"
CURRENT_KIT_COMMIT=""
[[ -n "$KIT_GIT_ROOT" ]] && CURRENT_KIT_COMMIT="$(git -C "$KIT_GIT_ROOT" rev-parse HEAD 2>/dev/null || true)"
PREV_KIT_COMMIT=""
[[ -f "$MANIFEST_FILE" ]] && PREV_KIT_COMMIT="$(tr -d '[:space:]' <"$MANIFEST_FILE")"

COPIED=()
SKIPPED_IDENTICAL=()
AUTO_MERGED=()
MANUAL_MERGE=()
PRESERVED_POLICY=()
PRESERVED_PLANNING=()

# Copies $1 (source file) to $TARGET_ROOT/$2 (relative dest path). A missing
# destination is copied directly. An existing, identical destination is left
# alone. An existing destination that differs is reconciled against the
# recorded base commit (see the file header) when possible; otherwise this
# asks before overwriting, same as a project with no recorded base.
copy_one() {
  local src="$1" rel="$2"
  local dest="$TARGET_ROOT/$rel"

  if [[ "$rel" == "docs/planning/review.md" && ( -e "$dest" || -L "$dest" ) ]]; then
    PRESERVED_PLANNING+=("$rel")
    return
  fi
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

  if [[ -n "$PREV_KIT_COMMIT" && -n "$KIT_GIT_ROOT" ]]; then
    local base_tmp merged_tmp
    base_tmp="$(mktemp)" || return 1
    if git -C "$KIT_GIT_ROOT" show "$PREV_KIT_COMMIT:template/project/$rel" >"$base_tmp" 2>/dev/null; then
      if diff -q "$base_tmp" "$dest" >/dev/null 2>&1; then
        # No local edits since the recorded base: the upstream update applies directly.
        cp "$src" "$dest" || { rm -f "$base_tmp"; return 1; }
        [[ -x "$src" ]] && chmod +x "$dest"
        COPIED+=("$rel (updated)")
        rm -f "$base_tmp"
        return
      fi

      merged_tmp="$(mktemp)" || { rm -f "$base_tmp"; return 1; }
      if scaffold_merge_attempt "$dest" "$base_tmp" "$src" "$merged_tmp"; then
        cp "$dest" "$dest.bak.$(date +%Y%m%d%H%M%S)" || { rm -f "$base_tmp" "$merged_tmp"; return 1; }
        cp "$merged_tmp" "$dest" || { rm -f "$base_tmp" "$merged_tmp"; return 1; }
        [[ -x "$src" ]] && chmod +x "$dest"
        AUTO_MERGED+=("$rel")
      else
        MANUAL_MERGE+=("$rel (local and upstream changes conflict)")
      fi
      rm -f "$base_tmp" "$merged_tmp"
      return
    fi
    rm -f "$base_tmp"
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

# Record the kit commit this run scaffolded from, so a future update can tell
# an untouched file from a locally edited one. Left unwritten (prior value
# kept, or file simply absent) when the kit isn't a git checkout.
if [[ -n "$CURRENT_KIT_COMMIT" ]]; then
  printf '%s\n' "$CURRENT_KIT_COMMIT" >"$MANIFEST_FILE"
fi

echo ""
echo "Scaffold complete."
echo "  Copied: ${#COPIED[@]}"
echo "  Already up to date: ${#SKIPPED_IDENTICAL[@]}"
echo "  Auto-merged (upstream + local changes combined; backup kept): ${#AUTO_MERGED[@]}"
echo "  Operator policy preserved: ${#PRESERVED_POLICY[@]}"
echo "  Planning review preserved: ${#PRESERVED_PLANNING[@]}"
echo "  .gitignore lines added: $gitignore_added"

if [[ ${#AUTO_MERGED[@]} -gt 0 ]]; then
  echo ""
  echo "These had local edits but no conflicting upstream changes, so both were combined -- review the merge and remove the .bak once confirmed:"
  for f in "${AUTO_MERGED[@]}"; do
    echo "  - $f"
  done
fi

if [[ ${#MANUAL_MERGE[@]} -gt 0 ]]; then
  echo ""
  echo "These already existed, differ from the template, and were left untouched -- merge manually:"
  for f in "${MANUAL_MERGE[@]}"; do
    echo "  - $f"
  done
fi

echo ""
echo "Next steps:"
echo "  1. Use /functional-spec, /technical-spec, and /tasks; explicitly approve the planning proposal before implementation."
echo "  2. Implement notify.sh with a real notification (email/Slack/etc)."
echo "  3. Confirm this repo is vendored at exactly 'external/ai-session-kit' (the Stop hook hardcodes that path)."
echo "  4. Before unattended container use, mount command-exceptions/ and enforcement paths read-only; see the kit README."
echo "  5. Check readiness without changing state: bash external/ai-session-kit/scripts/workflow-status.sh"
echo "     After interruption, inspect affected edits/tests before explicitly restarting with auto-continue.sh --resume."
