#!/usr/bin/env bash
# Shared helper for create-scaffold-kit.sh: attempts a non-destructive
# three-way merge of an upstream template update against a locally modified
# destination file, using the template content the file was last scaffolded
# from (the "base"). Requires git; never writes to <current> itself.
#
# scaffold_merge_attempt <current> <base> <other> <out>
#   <current> - the project's existing file ("mine")
#   <base>    - the template content last scaffolded for this file ("orig")
#   <other>   - the new template content ("theirs")
#   <out>     - path to write the merge result to when the merge is clean
#
# Returns:
#   0 - clean merge (no conflicting hunks); <out> contains the merged content
#   1 - conflicting hunks; <out> is not written and must not be used
#   2 - git is unavailable or the merge could not be attempted
scaffold_merge_attempt() {
  local current="$1" base="$2" other="$3" out="$4"
  command -v git >/dev/null 2>&1 || return 2

  local status=0
  git merge-file --stdout "$current" "$base" "$other" >"$out" 2>/dev/null || status=$?

  if [[ $status -eq 0 ]]; then
    return 0
  elif [[ $status -ge 1 && $status -le 127 ]]; then
    # git merge-file's exit status is the conflict count, truncated to 127;
    # anything higher is a wrapped negative (error) return.
    return 1
  else
    return 2
  fi
}
