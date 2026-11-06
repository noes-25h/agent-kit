#!/bin/bash
# session-memory / paths
# Prints where the records live and what the date is, one "key: value" per line.
# The two skills read this so that they never guess a path or a time.
#
# Usage: bash scripts/paths.sh [project root]
# Without an argument it uses CLAUDE_PROJECT_DIR, then the current folder.
# It only reads. It creates nothing.

SM_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
[ -r "$SM_HERE/config.sh" ] && . "$SM_HERE/config.sh"
if [ "${SM_CONFIG_LOADED:-0}" != "1" ]; then
  echo "error: could not load scripts/config.sh. Reinstall the plugin."
  exit 0
fi

ROOT="${1:-${CLAUDE_PROJECT_DIR:-$PWD}}"
# A placeholder that was not substituted arrives as literal text. Fall back to the current folder.
case "$ROOT" in *'${'*) ROOT="${CLAUDE_PROJECT_DIR:-$PWD}" ;; esac
sm_load_config "$ROOT"
MEM="$SM_ROOT/$SM_DIR"

state() { if [ -e "$1" ]; then echo "exists"; else echo "not created yet"; fi; }

TODAY=$(date +%Y-%m-%d)
J="$MEM/$SM_JOURNAL"
PREV=""
if [ -d "$J" ]; then
  PREV=$(ls -1 "$J" 2>/dev/null | grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}\.md$' | sort | awk -v t="$TODAY.md" '$0 < t' | tail -1)
fi

echo "project_root: $SM_ROOT"
echo "date: $TODAY"
echo "time: $(date +%H:%M)"
echo "weekday: $(date +%A)"
echo "memory_dir: $MEM ($(state "$MEM"))"
echo "now_file: $MEM/$SM_NOW ($(state "$MEM/$SM_NOW"))"
echo "decisions_file: $MEM/$SM_DECISIONS ($(state "$MEM/$SM_DECISIONS"))"
echo "tasks_file: $MEM/$SM_TASKS ($(state "$MEM/$SM_TASKS"))"
echo "journal_dir: $J ($(state "$J"))"
echo "journal_today: $J/$TODAY.md ($(state "$J/$TODAY.md"))"
if [ -n "$PREV" ]; then
  echo "journal_previous: $J/$PREV"
else
  echo "journal_previous: none"
fi
echo "today_file: $MEM/$SM_TODAY ($(state "$MEM/$SM_TODAY"))"
if [ -f "$SM_CONF" ]; then
  echo "settings_file: $SM_CONF (exists)"
else
  echo "settings_file: $SM_CONF (not created; defaults are in use)"
fi
[ -n "$SM_WARN" ] && echo "ignored_settings: $SM_WARN (defaults used for these)"
echo "snapshot_budget_bytes: $SM_BUDGET"
exit 0
