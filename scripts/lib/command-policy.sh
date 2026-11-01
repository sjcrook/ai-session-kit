#!/usr/bin/env bash
# Policy paths are relative to the consuming project root, never caller-configurable.
command_policy_load() {
  COMMAND_POLICY_ALLOW_DELETE=false
  COMMAND_POLICY_ALLOW_PUSH=false
  COMMAND_POLICY_ALLOW_SUDO=false
  COMMAND_POLICY_ERROR=""
  local directory="command-exceptions"
  local file="$directory/command-exceptions.conf"
  local content entry extra line line_number=0

  if [[ -L "$directory" || ( -e "$directory" && ! -d "$directory" ) ]]; then
    COMMAND_POLICY_ERROR="command-exceptions must be a directory, not a symlink or another file type."
    return 1
  fi
  [[ -d "$directory" ]] || return 0
  if [[ ! -r "$directory" || ! -x "$directory" ]]; then
    COMMAND_POLICY_ERROR="Cannot read or traverse command-exceptions."
    return 1
  fi
  [[ -e "$file" || -L "$file" ]] || return 0
  if [[ -L "$file" || ! -f "$file" || ! -r "$file" ]]; then
    COMMAND_POLICY_ERROR="command-exceptions/command-exceptions.conf must be a readable regular file, not a symlink."
    return 1
  fi
  if ! content="$(cat "$file")"; then
    COMMAND_POLICY_ERROR="Could not read command-exceptions/command-exceptions.conf."
    return 1
  fi
  while IFS= read -r line; do
    line_number=$((line_number + 1))
    IFS=$' \t\r' read -r entry extra <<<"$line"
    case "$entry" in
      ''|\#*) continue ;;
    esac
    if [[ -n "$extra" ]]; then
      COMMAND_POLICY_ERROR="Invalid command exception at line $line_number; use one named exception per line."
      return 1
    fi
    case "$entry" in
      allow-recursive-delete) COMMAND_POLICY_ALLOW_DELETE=true ;;
      allow-git-push) COMMAND_POLICY_ALLOW_PUSH=true ;;
      allow-sudo) COMMAND_POLICY_ALLOW_SUDO=true ;;
      *)
        COMMAND_POLICY_ERROR="Unknown command exception at line $line_number."
        return 1
        ;;
    esac
  done <<<"$content"
}

command_policy_allows() {
  case "$1" in
    'rm -rf') [[ "$COMMAND_POLICY_ALLOW_DELETE" == true ]] ;;
    'git push') [[ "$COMMAND_POLICY_ALLOW_PUSH" == true ]] ;;
    sudo) [[ "$COMMAND_POLICY_ALLOW_SUDO" == true ]] ;;
    *) return 1 ;;
  esac
}
