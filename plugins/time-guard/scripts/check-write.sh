#!/bin/bash
# time-guard / PreToolUse (Write, Edit, MultiEdit, NotebookEdit)
# Looks at the text Claude is about to write. If it has time wording with no clock time or date
# next to it ("this morning" with no time in its sentence, "tomorrow" with no date in the text,
# "for hours"), it adds a note for Claude that carries the current time. The note arrives next to
# the tool result.
#
# It never blocks: always exit 0, and no permissionDecision is returned, so the permission flow of
# Claude Code is not touched. The write has already been allowed or denied by something else.

INPUT=$(cat)

# Without jq the input cannot be parsed. Say so and let the call through.
if ! command -v jq >/dev/null 2>&1; then
  printf '%s\n' '{"systemMessage":"time-guard: jq was not found, so the wording check is not active. The clock on each prompt still works. Install jq."}'
  exit 0
fi

case "$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)" in
  Write|Edit|MultiEdit|NotebookEdit) ;;
  *) exit 0 ;;
esac

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/lib.sh" 2>/dev/null
if [ "${TG_CONFIG_LOADED:-0}" != "1" ] || ! command -v tg_rows >/dev/null 2>&1; then
  printf '%s\n' '{"systemMessage":"time-guard: could not load the settings (scripts/config.sh), so the wording check is not active. Fix the file or reinstall the plugin."}'
  exit 0
fi

# File name filter. An empty name (a tool with no path field) is checked.
FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null)
BASE=$(printf '%s' "${FILE##*/}" | LC_ALL=C tr -d '\000-\037\177')
if [ -n "$BASE" ]; then
  MATCHED=0
  set -f
  for pat in $TG_PATHS; do
    # shellcheck disable=SC2254
    case "$BASE" in $pat) MATCHED=1; break ;; esac
  done
  set +f
  [ "$MATCHED" = "1" ] || exit 0
fi

# The text that is about to exist: every string in tool_input except the text being replaced
# and the path fields.
TEXT=$(printf '%s' "$INPUT" | jq -r '
  (.tool_input // {}) as $in
  | [ $in | paths(type == "string") as $p
      | select(($p | last) as $k | $k != "old_string" and $k != "file_path" and $k != "notebook_path")
      | $in | getpath($p) ]
  | join("\n")' 2>/dev/null)
[ -n "$TEXT" ] || exit 0

# A relative day ("tomorrow") is backed by a calendar date anywhere in the text: a date in a heading
# covers the whole text.
HAS_DATE=0; printf '%s' "$TEXT" | grep -qiE -e "$TG_HAS_DATE_RE" 2>/dev/null && HAS_DATE=1

# A time of day ("this morning") is backed only by a clock time or a date in the same sentence, so a
# "14:00 start." at the top of meeting notes does not hide a "this morning" further down.
# The text is cut into one sentence per line: a sentence ends at a line break, after 。, and after
# . ! ? followed by a space ("6 p.m." is first written "6 pm" so that it does not end one).
# A length such as 3時間 (three hours) is not a clock time, so 時間 is taken out first.
# What is left = the sentences with no clock time and no date; the time-of-day rows look only there.
UNBACKED=$(printf '%s\n' "$TEXT" \
  | sed -E 's/([0-9] ?[AaPp])\.([Mm])\./\1\2/g' \
  | sed 's/。/&\
/g' \
  | sed -E 's/([.!?])[[:space:]]+/\1\
/g' \
  | sed 's/時間//g' \
  | grep -viE -e "$TG_HAS_CLOCK_RE" -e "$TG_HAS_DATE_RE" 2>/dev/null)

HITS=""; N=0
while read -r kind name re; do
  [ -n "$re" ] || continue
  case "$kind" in
    clock) SRC_TEXT="$UNBACKED"; why="no clock time or date in the same sentence" ;;
    day)   [ "$HAS_DATE" = "1" ] && continue; SRC_TEXT="$TEXT"; why="no calendar date in the text" ;;
    span)  SRC_TEXT="$TEXT"; why="a length of time" ;;
    *) continue ;;
  esac
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    [ "$N" -ge 5 ] && break
    HITS="$HITS${HITS:+, }'$hit' ($why)"
    N=$((N+1))
  done <<EOF
$(printf '%s' "$SRC_TEXT" | grep -oiE -e "$re" 2>/dev/null | LC_ALL=C tr -d '\000-\011\013-\037\177' | awk '!seen[tolower($0)]++' | head -3)
EOF
done <<EOF
$(tg_rows)
EOF

[ -n "$HITS" ] || exit 0

NOW=$(tg_now) || NOW=""
tg_resolve_tz
if [ -n "$NOW" ]; then
  CLOCK="Current local time: $NOW ($(tg_zone_source))."
  [ -n "$TG_TZ_NOTE" ] && CLOCK="$CLOCK $TG_TZ_NOTE"
else
  CLOCK="The system clock could not be read, so no current time is given here."
fi

MSG="time-guard: the text being written${BASE:+ to $BASE} has time wording that is not backed by a value in the same text: $HITS. $CLOCK The write was not blocked."

jq -cn --arg m "$MSG" --arg f "${BASE:-a file}" --arg show "$TG_SHOW_USER" '
  { hookSpecificOutput: { hookEventName: "PreToolUse", additionalContext: $m } }
  + (if $show == "1"
     then { systemMessage: ("time-guard: time wording with no clock time or date next to it was found in the text written to " + $f + ". Claude was given the current time. The write was not blocked.") }
     else {} end)' 2>/dev/null
exit 0
