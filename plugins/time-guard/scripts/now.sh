#!/bin/bash
# time-guard / UserPromptSubmit and SessionStart
# Reads the system clock and hands the current local date and time to Claude as context.
#
#   now.sh UserPromptSubmit   on every prompt (JSON with additionalContext)
#   now.sh SessionStart       when a session starts, resumes, is cleared, or is compacted (same shape)
#   now.sh plain              one line of plain text; used by the bundled skill and for checking by hand
#
# It never blocks and always exits 0. If the clock cannot be read it prints nothing,
# so Claude gets no time at all instead of a wrong one.
# The JSON is built with printf from a fixed set of characters, so jq is not needed here.

EVENT="${1:-plain}"

case "$EVENT" in
  UserPromptSubmit) WHEN="read from the system clock when this prompt was submitted"; cat >/dev/null 2>&1 ;;
  SessionStart)     WHEN="read from the system clock when this session started, resumed, or was compacted"; cat >/dev/null 2>&1 ;;
  plain)            WHEN="read from the system clock just now" ;;
  *) exit 0 ;;
esac

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/lib.sh" 2>/dev/null
command -v tg_now >/dev/null 2>&1 || exit 0

NOW=$(tg_now) || exit 0
[ -n "$NOW" ] || exit 0
tg_resolve_tz   # tg_now ran in a subshell; set TG_USE_TZ and TG_TZ_NOTE here as well

TEXT="Current local time: $NOW. This value was $WHEN ($(tg_zone_source)). Dates and times that appear earlier in this conversation were read earlier and are older than this value."
[ -n "$TG_TZ_NOTE" ] && TEXT="$TEXT $TG_TZ_NOTE"
[ "$TG_CONFIG_LOADED" = "1" ] || TEXT="$TEXT The time-guard settings file (scripts/config.sh) could not be loaded, so the defaults are in use."

if [ "$EVENT" = "plain" ]; then
  printf '%s\n' "$TEXT"
  exit 0
fi

# Every part of TEXT is a fixed sentence, digits from date(1), or a zone name that passed the
# character check in lib.sh. As a last guard, print nothing if a quote, a backslash, or a control
# character got in anyway: Claude Code drops malformed JSON without a word.
case "$TEXT" in *\"*|*\\*|*[[:cntrl:]]*) exit 0 ;; esac
printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' "$EVENT" "$TEXT"
exit 0
