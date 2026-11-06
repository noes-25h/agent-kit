#!/bin/bash
# session-memory / shared settings
# Sourced by inject.sh and paths.sh. Resolves where the records live.
#
# Defaults: the records sit in .memory/ at the project root.
# To change them, create .claude/session-memory.conf in the project with lines of the form key=value.
#
#   dir=.memory            folder that holds the records (relative to the project root)
#   now=now.md             where things stand (rewritten at every wrap-up)
#   decisions=decisions.md decision log, newest first
#   tasks=tasks.md         task list with "- [ ]" checkboxes
#   journal=journal        folder of daily records, one file per day named YYYY-MM-DD.md
#   today=today.md         the morning page
#   budget=6000            upper bound of the snapshot, in bytes (1000 to 9000)
#
# The file is parsed as text. It is never executed.
# A value that is empty, absolute, or contains a ".." segment is refused and the default is used.

SM_DEFAULT_BUDGET=6000
SM_MIN_BUDGET=1000
# Claude Code replaces hook output over 10,000 characters with a file path and a short preview.
# 9000 bytes leaves a margin. Bytes are never fewer than characters, in any script.
SM_MAX_BUDGET=9000

sm_trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

# 0 = usable as a path below the project root
sm_path_ok() {
  local v="$1"
  [ -n "$v" ] || return 1
  case "$v" in
    /*|"~"*) return 1 ;;
    ..|../*|*/..|*/../*) return 1 ;;
  esac
  return 0
}

# sm_load_config <project root>
# Sets SM_ROOT SM_CONF SM_DIR SM_NOW SM_DECISIONS SM_TASKS SM_JOURNAL SM_TODAY SM_BUDGET SM_WARN
sm_load_config() {
  SM_ROOT="$1"
  SM_CONF="$SM_ROOT/.claude/session-memory.conf"
  SM_DIR=".memory"; SM_NOW="now.md"; SM_DECISIONS="decisions.md"; SM_TASKS="tasks.md"
  SM_JOURNAL="journal"; SM_TODAY="today.md"; SM_BUDGET="$SM_DEFAULT_BUDGET"; SM_WARN=""

  [ -f "$SM_CONF" ] && [ -r "$SM_CONF" ] || return 0

  local line key val n=0
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n+1)); [ "$n" -gt 200 ] && break
    line="${line%$'\r'}"
    line="$(sm_trim "$line")"
    case "$line" in ''|'#'*) continue ;; esac
    case "$line" in *=*) ;; *) continue ;; esac
    key="$(sm_trim "${line%%=*}")"
    val="$(sm_trim "${line#*=}")"
    case "$val" in
      \"*\") val="${val#\"}"; val="${val%\"}" ;;
      \'*\') val="${val#\'}"; val="${val%\'}" ;;
    esac
    case "$key" in
      dir|now|decisions|tasks|journal|today)
        if sm_path_ok "$val"; then
          case "$key" in
            dir) SM_DIR="$val" ;;
            now) SM_NOW="$val" ;;
            decisions) SM_DECISIONS="$val" ;;
            tasks) SM_TASKS="$val" ;;
            journal) SM_JOURNAL="$val" ;;
            today) SM_TODAY="$val" ;;
          esac
        else
          SM_WARN="$SM_WARN $key"
        fi
        ;;
      budget)
        case "$val" in
          ''|*[!0-9]*) SM_WARN="$SM_WARN budget" ;;
          *)
            if [ "${#val}" -le 6 ] && [ "$val" -ge "$SM_MIN_BUDGET" ] && [ "$val" -le "$SM_MAX_BUDGET" ]; then
              SM_BUDGET="$val"
            else
              SM_WARN="$SM_WARN budget"
            fi
            ;;
        esac
        ;;
    esac
  done < "$SM_CONF"
  SM_WARN="$(sm_trim "$SM_WARN")"
  return 0
}

SM_CONFIG_LOADED=1
