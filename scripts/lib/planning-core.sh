#!/usr/bin/env bash
# Shared planning approval check; assumes cwd is the consuming project root.

planning_task_scope() {
  awk -F '|' '
    /^\| *S[^|]*\| *T[^|]*\|/ {
      if (NF != 6) exit 1
      for (i=2; i<=5; i++) gsub(/^[[:space:]]+|[[:space:]]+$/, "", $i)
      if ($2 !~ /^S[0-9]+$/ || $3 !~ /^T[0-9]+$/ || $4 == "" || seen[$3]++) exit 1
      sub(/^[^[:alnum:]]*/, "", $5)
      if ($5 !~ /^(Todo|In Progress|Done|Blocked|Superseded)([[:space:]]|$)/) exit 1
      print $2 "|" $3 "|" $4 "|" ($5 ~ /^Superseded([[:space:]]|$)/ ? "Superseded" : "Work")
      count++
    }
    END { if (!count) exit 1 }
  ' "$1"
}

planning_check() {
  PLANNING_ERROR=""
  local review="docs/planning/review.md"
  local name approved_scope current_scope
  if [[ ! -r "$review" ]] ||
    [[ "$(grep -c '^Status:' "$review")" != 1 ]] ||
    ! grep -qx 'Status: Approved' "$review"; then
    PLANNING_ERROR="Planning approval is missing or pending. Run /tasks and explicitly approve its proposal before implementation."
    return 1
  fi
  for name in functional-spec technical-spec tasks; do
    if [[ ! -s "docs/$name.md" || ! -r "docs/$name.md" ||
      ! -s "docs/planning/$name.md" || ! -r "docs/planning/$name.md" ]]; then
      PLANNING_ERROR="Planning baseline or current documents are missing, empty, or unreadable. Run /tasks for reconciliation and explicit approval."
      return 1
    fi
    if [[ "$name" != tasks ]] && ! cmp -s "docs/$name.md" "docs/planning/$name.md"; then
      PLANNING_ERROR="Specifications differ from the approved planning baseline. Run /tasks and approve the updated plan."
      return 1
    fi
  done
  if ! approved_scope="$(planning_task_scope docs/planning/tasks.md)" ||
    ! current_scope="$(planning_task_scope docs/tasks.md)"; then
    PLANNING_ERROR="The planning backlog contains blank, duplicate, or malformed task rows. Run /tasks to repair and approve the plan."
    return 1
  fi
  if [[ "$approved_scope" != "$current_scope" ]]; then
    PLANNING_ERROR="Task scope or supersessions differ from the approved plan. Run /tasks and approve the updated backlog."
    return 1
  fi
}
