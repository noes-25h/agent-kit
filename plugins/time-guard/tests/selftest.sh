#!/bin/bash
# Unit check for time-guard.
# Feeds the hooks the same JSON that Claude Code sends them and checks: the time they return is the
# time on the system clock, the time zone follows the environment and the setting, the returned
# value has the shape Claude Code accepts, and the wording check never blocks.
#
# A full pass here only tells you that the hook scripts are correct.
# Whether Claude Code actually calls the hooks, and whether the time reaches Claude,
# can only be seen with tests/live-check.sh (the check against a real Claude Code session).
#
# Usage: bash tests/selftest.sh     exit 0 = all passed / 1 = at least one check failed
# Needs: bash, jq

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NOW_SH="$ROOT/scripts/now.sh"
CHECK_SH="$ROOT/scripts/check-write.sh"
PASS=0; FAIL=0

command -v jq >/dev/null 2>&1 || { echo "jq was not found. Install jq and run this again."; exit 1; }
unset TIME_GUARD_TZ   # the checks set it themselves
. "$ROOT/scripts/lib.sh"
[ "${TG_CONFIG_LOADED:-0}" = "1" ] || { echo "Could not load scripts/config.sh."; exit 1; }

TMP=$(mktemp -d "${TMPDIR:-/tmp}/time-guard-selftest.XXXXXX" 2>/dev/null) || { echo "Could not create a temp folder."; exit 1; }
# The checks below run against a copy of the scripts in which the three settings are put back to
# their defaults, so that your own settings do not change what is being checked. The wording table
# is yours, as it is. Section [0] looks at your settings as they are.
REAL_NOW="$ROOT/scripts/now.sh"
mkdir -p "$TMP/base" && cp "$ROOT"/scripts/*.sh "$TMP/base/"
sed -e 's|^TG_TZ=.*|TG_TZ=""|' -e 's|^TG_PATHS=.*|TG_PATHS="*.md *.mdx *.txt *.rst *.org *.adoc"|' -e 's|^TG_SHOW_USER=.*|TG_SHOW_USER=0|' "$ROOT/scripts/config.sh" > "$TMP/base/config.sh"
NOW_SH="$TMP/base/now.sh"
CHECK_SH="$TMP/base/check-write.sh"
SRC="$TMP/base"

ok() { PASS=$((PASS+1)); echo "  ok   $1"; }
ng() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }

# The clock, read by this file on its own (not through the hooks), to the minute.
stamp() {
  if [ -n "$1" ]; then LC_ALL=C TZ="$1" date '+%Y-%m-%d (%a) %H:%M'
  else LC_ALL=C date '+%Y-%m-%d (%a) %H:%M'; fi
}
offset() {
  local z
  if [ -n "$1" ]; then z=$(LC_ALL=C TZ="$1" date '+%z'); else z=$(LC_ALL=C date '+%z'); fi
  printf 'UTC%s:%s' "${z:0:3}" "${z:3:2}"
}

# run_now EVENT EXPECT_ZONE [VAR=value ...]
# Sets OUT (raw), RC, TXT (additionalContext), B and A (the clock just before and just after).
run_now() {
  local ev="$1" ez="$2"; shift 2
  B=$(stamp "$ez")
  OUT=$(printf '{}' | env "$@" bash "$NOW_SH" "$ev" 2>/dev/null); RC=$?
  A=$(stamp "$ez")
  TXT=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)
}
on_clock() { case "$1" in *"Current local time: $B:"*|*"Current local time: $A:"*) return 0 ;; esac; return 1; }

# Does the clock output have the shape Claude Code accepts for this event? 0 = yes
now_shape_ok() { # event json
  printf '%s' "$2" | jq -e --arg ev "$1" '
    (keys == ["hookSpecificOutput"])
    and (.hookSpecificOutput | keys == ["additionalContext", "hookEventName"])
    and .hookSpecificOutput.hookEventName == $ev
    and (.hookSpecificOutput.additionalContext | type == "string" and length > 0 and length < 10000)' >/dev/null 2>&1
}
# Does the wording note have an accepted shape, and does it leave the permission flow alone? 0 = yes
note_shape_ok() {
  printf '%s' "$1" | jq -e '
    ((keys - ["hookSpecificOutput", "systemMessage"]) == [])
    and (.hookSpecificOutput | keys == ["additionalContext", "hookEventName"])
    and .hookSpecificOutput.hookEventName == "PreToolUse"
    and (.hookSpecificOutput.additionalContext | type == "string" and length > 0 and length < 10000)' >/dev/null 2>&1
}

pre() { jq -cn --arg t "$1" --argjson i "$2" '{hook_event_name:"PreToolUse", tool_name:$t, tool_input:$i}'; }
wr()  { pre Write "$(jq -cn --arg p "$1" --arg c "$2" '{file_path:$p, content:$c}')"; }
# run_check JSON [VAR=value ...]   Sets OUT, RC, TXT. ALL_RC collects every exit code seen.
ALL_RC=""
run_check() {
  local in="$1"; shift
  OUT=$(printf '%s' "$in" | env "$@" bash "$CHECK_SH" 2>/dev/null); RC=$?
  ALL_RC="$ALL_RC $RC"
  TXT=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)
}
fires()  { [ "$RC" = "0" ] && note_shape_ok "$OUT" && ok "$1" || ng "$1 (expected a note; exit $RC)"; }
silent() { [ "$RC" = "0" ] && [ -z "$OUT" ] && ok "$1" || ng "$1 (expected nothing; exit $RC)"; }

# One sample per row name of the wording table.
tg_sample() {
  case "$1" in
    en-part-of-day)  printf 'We fixed the build this afternoon.' ;;
    en-night)        printf 'The migration ran last night.' ;;
    ja-part-of-day)  printf '夕方に確認した。' ;;
    en-relative-day) printf 'The release goes out tomorrow.' ;;
    ja-relative-day) printf '明日リリースする。' ;;
    en-length)       printf 'We worked on this for hours.' ;;
    ja-length)       printf '丸一日かかった。' ;;
    *) return 1 ;;
  esac
}

echo "[0] your settings, as they are in scripts/config.sh"
echo "       TG_TZ=\"$TG_TZ\"  TG_PATHS=\"$TG_PATHS\"  TG_SHOW_USER=$TG_SHOW_USER"
tg_resolve_tz
if [ -n "$TG_TZ" ] && [ -z "$TG_USE_TZ" ]; then
  ng "TG_TZ=\"$TG_TZ\" is not a zone this machine knows; the system time zone would be shown instead"
else
  KEEP_NOW="$NOW_SH"; NOW_SH="$REAL_NOW"
  run_now UserPromptSubmit "$TG_USE_TZ"
  now_shape_ok UserPromptSubmit "$OUT" && on_clock "$TXT" && ok "with your settings, the clock gives the system time in ${TG_USE_TZ:-the time zone of this machine}" || ng "with your settings, the clock output is wrong"
  NOW_SH="$KEEP_NOW"
fi
case "$TG_SHOW_USER" in 0|1) ok "TG_SHOW_USER is 0 or 1" ;; *) ng "TG_SHOW_USER must be 0 or 1" ;; esac
[ -n "$TG_PATHS" ] && ok "TG_PATHS is not empty" || ng "TG_PATHS is empty, so the wording check looks at no named file"

echo "[1] the clock on every prompt"
run_now UserPromptSubmit ""
[ "$RC" = "0" ] && now_shape_ok UserPromptSubmit "$OUT" && ok "UserPromptSubmit: accepted shape, exit 0" || ng "UserPromptSubmit: shape or exit code (exit $RC)"
on_clock "$TXT" && ok "UserPromptSubmit: the time is the system clock, to the minute" || ng "UserPromptSubmit: the time differs from the system clock"
case "$TXT" in *"$(offset "")"*) ok "UserPromptSubmit: the UTC offset is the one of this machine" ;; *) ng "UserPromptSubmit: UTC offset" ;; esac
run_now SessionStart ""
[ "$RC" = "0" ] && now_shape_ok SessionStart "$OUT" && ok "SessionStart: accepted shape, exit 0" || ng "SessionStart: shape or exit code (exit $RC)"
on_clock "$TXT" && ok "SessionStart: the time is the system clock, to the minute" || ng "SessionStart: the time differs from the system clock"
OUT=$(bash "$NOW_SH" plain </dev/null 2>/dev/null); B=$(stamp ""); A="$B"
case "$OUT" in "Current local time: "*) on_clock "$OUT" && ok "plain: one line of text with the system time" || ng "plain: the time differs from the system clock" ;; *) ng "plain: did not print the time line" ;; esac
[ "$(printf '%s\n' "$OUT" | grep -c .)" = "1" ] && ok "plain: exactly one line" || ng "plain: more or fewer than one line"
OUT=$(printf '{}' | bash "$NOW_SH" SomeOtherEvent 2>/dev/null); RC=$?
[ "$RC" = "0" ] && [ -z "$OUT" ] && ok "an event it was not written for returns nothing" || ng "reacted to an unknown event"

echo "[2] the time zone follows the environment and the setting"
ZA="Asia/Tokyo"; ZB="America/New_York"
run_now UserPromptSubmit "$ZA" TZ="$ZA"; TA="$TXT"
on_clock "$TXT" && ok "TZ environment variable ($ZA) is followed" || ng "TZ environment variable ($ZA) is not followed"
run_now UserPromptSubmit "$ZB" TZ="$ZB"; TB="$TXT"
on_clock "$TXT" && ok "TZ environment variable ($ZB) is followed" || ng "TZ environment variable ($ZB) is not followed"
[ -n "$TA" ] && [ "${TA%%. This value*}" != "${TB%%. This value*}" ] && ok "the two zones give different local times (no zone is fixed in the scripts)" || ng "two zones gave the same local time"
run_now UserPromptSubmit "$ZB" TZ="$ZA" TIME_GUARD_TZ="$ZB"
on_clock "$TXT" && ok "TIME_GUARD_TZ wins over the environment" || ng "TIME_GUARD_TZ is not used"
case "$TXT" in *"$(offset "$ZB")"*"time zone $ZB, set for time-guard"*) ok "the text names the zone and where it was set" ;; *) ng "the text does not name the configured zone" ;; esac
run_now UserPromptSubmit "UTC" TIME_GUARD_TZ="UTC"
on_clock "$TXT" && case "$TXT" in *"UTC+00:00"*) true ;; *) false ;; esac && ok "TIME_GUARD_TZ=UTC gives UTC+00:00" || ng "TIME_GUARD_TZ=UTC"
run_now UserPromptSubmit "$ZA" TZ="$ZA" TIME_GUARD_TZ="Mars/Olympus_Mons"
on_clock "$TXT" && case "$TXT" in *"was not found on this machine"*) true ;; *) false ;; esac && ok "an unknown zone name falls back to the system zone and says so (not UTC without a word)" || ng "unknown zone name: silent or wrong time"
run_now UserPromptSubmit "$ZA" TZ="$ZA" TIME_GUARD_TZ='Bad"Zone\name'
now_shape_ok UserPromptSubmit "$OUT" && on_clock "$TXT" && case "$TXT" in *"not a valid zone name"*) true ;; *) false ;; esac && ok "a zone name with a quote or backslash: JSON stays valid, system zone, says so" || ng "invalid zone name broke the output"
run_now UserPromptSubmit "$ZA" TZ="$ZA" TIME_GUARD_TZ='../../etc/passwd'
on_clock "$TXT" && case "$TXT" in *"not a valid zone name"*) true ;; *) false ;; esac && ok "a zone name that walks out of the zone folder is refused" || ng "path-like zone name was used"

if [ -n "$TMP" ]; then
  for v in cfgzone broken nocfg anyfile showuser; do mkdir -p "$TMP/$v" && cp "$SRC"/*.sh "$TMP/$v/"; done
  sed 's|^TG_TZ=.*|TG_TZ="'"$ZB"'"|' "$SRC/config.sh" > "$TMP/cfgzone/config.sh"
  printf 'TG_TZ="unterminated\n' > "$TMP/broken/config.sh"
  rm -f "$TMP/nocfg/config.sh"
  sed 's|^TG_PATHS=.*|TG_PATHS="*"|' "$SRC/config.sh" > "$TMP/anyfile/config.sh"
  sed 's|^TG_SHOW_USER=.*|TG_SHOW_USER=1|' "$SRC/config.sh" > "$TMP/showuser/config.sh"

  KEEP_NOW="$NOW_SH"
  NOW_SH="$TMP/cfgzone/now.sh"
  run_now UserPromptSubmit "$ZB" TZ="$ZA"
  on_clock "$TXT" && ok "TG_TZ in config.sh is followed" || ng "TG_TZ in config.sh is not followed"
  run_now UserPromptSubmit "UTC" TZ="$ZA" TIME_GUARD_TZ="UTC"
  on_clock "$TXT" && ok "TIME_GUARD_TZ wins over config.sh" || ng "TIME_GUARD_TZ did not win over config.sh"
  NOW_SH="$TMP/broken/now.sh"
  run_now UserPromptSubmit ""
  now_shape_ok UserPromptSubmit "$OUT" && on_clock "$TXT" && case "$TXT" in *"could not be loaded"*) true ;; *) false ;; esac && ok "config.sh with a syntax error -> the clock still works and says the defaults are in use" || ng "broken config.sh took the clock away"
  NOW_SH="$TMP/nocfg/now.sh"
  run_now SessionStart ""
  now_shape_ok SessionStart "$OUT" && on_clock "$TXT" && ok "config.sh missing -> the clock still works" || ng "missing config.sh took the clock away"
  NOW_SH="$KEEP_NOW"

  # A PATH without jq: the clock must not depend on it.
  mkdir -p "$TMP/bin-nojq"
  for c in bash cat date dirname tr env; do p=$(command -v "$c") && ln -s "$p" "$TMP/bin-nojq/$c"; done
  B=$(stamp ""); OUT=$(printf '{}' | PATH="$TMP/bin-nojq" bash "$NOW_SH" UserPromptSubmit 2>/dev/null); A=$(stamp "")
  TXT=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)
  now_shape_ok UserPromptSubmit "$OUT" && on_clock "$TXT" && ok "no jq -> the clock still works" || ng "no jq: the clock stopped"

  # A date command that answers with something that is not a time.
  mkdir -p "$TMP/bin-baddate"
  for c in bash cat dirname tr env grep jq awk head sed; do p=$(command -v "$c") && ln -s "$p" "$TMP/bin-baddate/$c"; done
  printf '#!/bin/bash\necho "date: illegal time format"\n' > "$TMP/bin-baddate/date"; chmod +x "$TMP/bin-baddate/date"
  OUT=$(printf '{}' | PATH="$TMP/bin-baddate" bash "$NOW_SH" UserPromptSubmit 2>/dev/null); RC=$?
  [ "$RC" = "0" ] && [ -z "$OUT" ] && ok "the clock cannot be read -> nothing is returned (no made-up time)" || ng "returned text although the clock could not be read"
else
  ng "could not create a temp folder"
fi

echo "[3] every row of the wording table"
while read -r kind name re; do
  [ -n "$name" ] || continue
  s=$(tg_sample "$name") || { ng "$name: no sample in selftest (add one to tg_sample)"; continue; }
  B=$(stamp ""); run_check "$(wr /w/notes.md "$s")"; A=$(stamp "")
  fires "$name ($kind): a note is returned"
  case "$TXT" in *"Current local time: $B:"*|*"Current local time: $A:"*) ok "$name: the note carries the system time" ;; *) ng "$name: the note has no current time" ;; esac
  case "$kind" in
    clock) run_check "$(wr /w/notes.md "14:30 $s")"; silent "$name: skipped when a clock time is in the same sentence"
           run_check "$(wr /w/notes.md "2026-10-09 $s")"; silent "$name: skipped when a date is in the same sentence"
           run_check "$(wr /w/notes.md "$(printf '14:30\n%s' "$s")")"; fires "$name: a clock time on another line does not skip it"
           run_check "$(wr /w/notes.md "2026-10-09. $s")"; fires "$name: a date in another sentence does not skip it" ;;
    day)   run_check "$(wr /w/notes.md "$s (2026-10-10)")"; silent "$name: skipped when a calendar date is written"
           run_check "$(wr /w/notes.md "14:30. $s")"; fires "$name: a clock time alone does not skip it" ;;
    span)  run_check "$(wr /w/notes.md "2026-10-09 14:30. $s")"; fires "$name: not skipped by a date and a clock time" ;;
    *)     ng "$name: unknown kind $kind" ;;
  esac
done <<EOF
$(tg_rows)
EOF

echo "[4] what is skipped and what is not"
run_check "$(wr /w/notes.md 'This Morning the tests passed.')"; fires "capital letters are matched"
run_check "$(wr /w/notes.md 'We met this evening at 6 pm.')"; silent "'6 pm' counts as a clock time"
run_check "$(wr /w/notes.md '午後3時に確認した。')"; silent "'3時' counts as a clock time"
run_check "$(wr /w/notes.md '明日 (10月10日) に出す。')"; silent "'10月10日' counts as a calendar date"
run_check "$(wr /w/notes.md 'A good morning routine. The overnight job. Tomorrowland. Yesterdays.')"; silent "near words pass (morning routine, overnight, Tomorrowland)"
# Meeting notes: a clock time at the top must not hide a time of day in another sentence (the hole fixed on 2026-10-22).
run_check "$(wr /w/minutes.md "$(printf '14:00 開始。\n今朝の障害の件を共有した。')")"
fires "minutes: '14:00 開始。' on the first line does not hide '今朝' on the next"
case "$TXT" in *"'今朝'"*) ok "minutes: the note names '今朝'" ;; *) ng "minutes: the note does not name '今朝'" ;; esac
run_check "$(wr /w/minutes.md '14:00 開始。今朝の障害の件を共有した。')"; fires "minutes: a clock time in the sentence before, on the same line, does not hide '今朝'"
run_check "$(wr /w/minutes.md 'Started at 14:00. We went over the outage from this morning.')"; fires "minutes: 'Started at 14:00.' does not hide 'this morning' in the next sentence"
run_check "$(wr /w/minutes.md "$(printf '## 2026-10-20 14:00\n- 今朝の障害の件\n- 明日までに直す')")"; fires "minutes: a date and time in the heading do not hide '今朝' in a list item"
case "$TXT" in *"'明日'"*) ng "minutes: '明日' was listed although the heading has a date" ;; *) ok "minutes: '明日' is still covered by the date in the heading" ;; esac
run_check "$(wr /w/notes.md '今朝、3時間かけて直した。')"; fires "'3時間' is a length, not a clock time"
run_check "$(wr /w/notes.md '今朝 9 時に直した。')"; silent "'9 時' with a space counts as a clock time"
run_check "$(wr /w/notes.md '10 月 20 日の午後に確認した。')"; silent "'10 月 20 日' with spaces counts as a date, and a date in the same sentence skips '午後'"
run_check "$(wr /w/notes.md 'At 6 p.m. we met this evening.')"; silent "'6 p.m.' does not end the sentence"
run_check "$(wr /w/notes.md 'The parser reads the header and returns a list.')"; silent "text with no time wording returns nothing"
run_check "$(wr /w/src/app.py 'print("see you tomorrow")')"; silent "a file name outside TG_PATHS is not checked (.py)"
run_check "$(wr /w/docs.md/app.py 'see you tomorrow')"; silent "the folder name is not what is matched (docs.md/app.py)"
run_check "$(wr /w/NOTES.txt 'see you tomorrow')"; fires "a .txt file is checked"
T='It broke last night.'
run_check "$(pre Edit "$(jq -cn --arg c "$T" '{file_path:"/w/a.md", old_string:"x", new_string:$c}')")"; fires "Edit new_string is checked"
run_check "$(pre Edit "$(jq -cn --arg c "$T" '{file_path:"/w/a.md", old_string:$c, new_string:"It broke during the deploy."}')")"; silent "wording only in Edit old_string passes (an edit that fixes it)"
run_check "$(pre MultiEdit "$(jq -cn --arg c "$T" '{file_path:"/w/a.md", edits:[{old_string:"x", new_string:"y"},{old_string:"z", new_string:$c}]}')")"; fires "nested edits[].new_string is checked"
run_check "$(pre MultiEdit "$(jq -cn --arg c "$T" '{file_path:"/w/a.md", edits:[{old_string:$c, new_string:"y"}]}')")"; silent "wording only in nested edits[].old_string passes"
run_check "$(pre NotebookEdit "$(jq -cn --arg c "$T" '{notebook_path:"/w/a.ipynb", new_source:$c}')")"; silent "a notebook is outside TG_PATHS by default"
run_check "$(pre Write "$(jq -cn --arg c "$T" '{some_future_field:$c}')")"; fires "a call with no path field is checked"
run_check "$(pre Bash "$(jq -cn --arg c "echo $T > a.md" '{command:$c}')")"; silent "tools other than the four return nothing"
run_check '{"hook_event_name":"PreToolUse","tool_name":"Write"}'; silent "missing tool_input does not crash"
run_check "$(wr /w/a.md "$(printf 'He said "tomorrow"\n\tand\\then last night \033[31m.')")"; fires "quotes, tabs, backslashes and an escape character in the text: JSON stays valid"
printf '%s' "$TXT" | LC_ALL=C grep -q "$(printf '\033')" && ng "a control character from the text reached the note" || ok "control characters from the text do not reach the note"
run_check "$(wr /w/a.md 'this morning this afternoon this evening tonight last night earlier today late at night yesterday tomorrow for hours all day long')"
n=$(printf '%s' "$TXT" | grep -o "' (" | grep -c .)
[ "$n" = "5" ] && ok "at most five wordings are listed" || ng "listed $n wordings (expected 5)"
run_check "$(wr "$(printf '/w/we\033[2Jird.md')" 'see you tomorrow')"; fires "a control character in the file name: JSON stays valid"
printf '%s' "$OUT" | LC_ALL=C grep -q "$(printf '\033')" && ng "a control character from the file name reached the output" || ok "control characters from the file name do not reach the output"

echo "[5] it never blocks and never touches the permission flow"
run_check "$(wr /w/notes.md 'We fixed it this morning.')"
printf '%s' "$OUT" | jq -e '(.hookSpecificOutput | has("permissionDecision") or has("updatedInput")) or has("decision") or has("continue")' >/dev/null 2>&1 && ng "the note carries a decision field" || ok "the note carries no decision field"
printf '%s' "$OUT" | jq -e 'has("systemMessage")' >/dev/null 2>&1 && ng "a notice is shown on screen by default" || ok "by default nothing is shown on screen (only Claude receives the note)"
case "$TXT" in *"The write was not blocked."*) ok "the note says the write was not blocked" ;; *) ng "the note does not say the write was not blocked" ;; esac
if [ -n "$TMP" ]; then
  KEEP_CHECK="$CHECK_SH"
  CHECK_SH="$TMP/showuser/check-write.sh"
  run_check "$(wr /w/notes.md 'We fixed it this morning.')"
  note_shape_ok "$OUT" && printf '%s' "$OUT" | jq -e '(.systemMessage | type == "string") and (.hookSpecificOutput | has("systemMessage") | not)' >/dev/null 2>&1 && ok "TG_SHOW_USER=1 -> a notice at the top level, next to the note" || ng "TG_SHOW_USER=1"
  CHECK_SH="$TMP/anyfile/check-write.sh"
  run_check "$(wr /w/src/app.py 'see you tomorrow')"; fires "TG_PATHS=\"*\" -> every file name is checked"
  CHECK_SH="$TMP/cfgzone/check-write.sh"
  B=$(stamp "$ZB"); run_check "$(wr /w/notes.md 'We fixed it this morning.')" TZ="$ZA"; A=$(stamp "$ZB")
  case "$TXT" in *"Current local time: $B:"*|*"Current local time: $A:"*) ok "the note uses the zone from config.sh" ;; *) ng "the note ignores the zone from config.sh" ;; esac

  echo "[6] which way it falls when something is broken"
  CHECK_SH="$TMP/nocfg/check-write.sh"
  run_check "$(wr /w/notes.md 'We fixed it this morning.')"
  [ "$RC" = "0" ] && printf '%s' "$OUT" | jq -e '(.systemMessage | type == "string") and (has("hookSpecificOutput") | not)' >/dev/null 2>&1 && ok "config.sh missing -> the wording check says it is off and lets the call through" || ng "wording check with config.sh missing"
  CHECK_SH="$TMP/broken/check-write.sh"
  run_check "$(wr /w/notes.md 'We fixed it this morning.')"
  [ "$RC" = "0" ] && printf '%s' "$OUT" | jq -e '(.systemMessage | type == "string") and (has("hookSpecificOutput") | not)' >/dev/null 2>&1 && ok "config.sh with a syntax error -> the wording check says it is off and lets the call through" || ng "wording check with a broken config.sh"
  CHECK_SH="$KEEP_CHECK"
  OUT=$(printf '%s' "$(wr /w/notes.md 'We fixed it this morning.')" | PATH="$TMP/bin-nojq" bash "$CHECK_SH" 2>/dev/null); RC=$?; ALL_RC="$ALL_RC $RC"
  [ "$RC" = "0" ] && printf '%s' "$OUT" | jq -e '(.systemMessage | type == "string") and (has("hookSpecificOutput") | not)' >/dev/null 2>&1 && ok "no jq -> the wording check says it is off and lets the call through" || ng "wording check with no jq"
  OUT=$(printf '%s' "$(wr /w/notes.md 'We fixed it this morning.')" | PATH="$TMP/bin-baddate" bash "$CHECK_SH" 2>/dev/null); RC=$?; ALL_RC="$ALL_RC $RC"
  TXT=$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)
  note_shape_ok "$OUT" && case "$TXT" in *"could not be read"*) true ;; *) false ;; esac && case "$TXT" in *"Current local time"*) false ;; *) true ;; esac && ok "the clock cannot be read -> the note says so and gives no time" || ng "note when the clock cannot be read"
  # The work folder is left in the OS temp area (it holds only copies of the scripts and symlinks)
fi
case "$ALL_RC" in *[1-9]*) ng "a call to the wording check ended with a non-zero exit code:$ALL_RC" ;; *) ok "every call to the wording check ended with exit 0" ;; esac

echo "[7] checking the checker (do the shape checks reject broken output?)"
now_shape_ok UserPromptSubmit '{"additionalContext":"Current local time: x"}' && ng "accepts additionalContext at the top level" || ok "additionalContext at the top level is rejected"
now_shape_ok SessionStart '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"x"}}' && ng "accepts a wrong event name" || ok "a wrong event name is rejected"
now_shape_ok UserPromptSubmit '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":""}}' && ng "accepts empty context" || ok "empty context is rejected"
now_shape_ok UserPromptSubmit '{"decision":"block","hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"x"}}' && ng "accepts a blocking decision" || ok "a blocking decision on the prompt is rejected"
note_shape_ok '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"x","permissionDecision":"allow"}}' && ng "accepts a permission decision" || ok "a note with a permission decision is rejected"

echo "[8] the wiring file and the skill"
HJ="$ROOT/hooks/hooks.json"
[ "$(jq -r '.hooks | keys | join(" ")' "$HJ" 2>/dev/null)" = "PreToolUse SessionStart UserPromptSubmit" ] && ok "hooks.json wires exactly three events" || ng "hooks.json: the set of events changed"
for ev in UserPromptSubmit SessionStart; do
  cmd=$(jq -r --arg e "$ev" '.hooks[$e][0].hooks[0].command' "$HJ" 2>/dev/null)
  case "$cmd" in *'"${CLAUDE_PLUGIN_ROOT}"/scripts/now.sh '"$ev") ok "$ev runs now.sh with its own event name" ;; *) ng "$ev: now.sh is given another event name (Claude Code drops output whose event name does not match)" ;; esac
done
cmd=$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$HJ" 2>/dev/null)
case "$cmd" in *'"${CLAUDE_PLUGIN_ROOT}"/scripts/check-write.sh') ok "PreToolUse runs check-write.sh" ;; *) ng "PreToolUse: wrong command" ;; esac
[ "$(jq -r '.hooks.PreToolUse[0].matcher' "$HJ" 2>/dev/null)" = "Write|Edit|MultiEdit|NotebookEdit" ] && ok "PreToolUse is limited to the four writing tools" || ng "PreToolUse matcher changed"
jq -e '[.hooks.UserPromptSubmit[], .hooks.SessionStart[] | has("matcher")] == [false, false]' "$HJ" >/dev/null 2>&1 && ok "the two clock events have no matcher (they run on every prompt and every session start)" || ng "a matcher was added to a clock event"
for f in now.sh check-write.sh lib.sh config.sh; do [ -r "$ROOT/scripts/$f" ] || ng "scripts/$f is missing"; done
SK="$ROOT/skills/now/SKILL.md"
if [ -r "$SK" ] && head -1 "$SK" | grep -q '^---$' && grep -q '^name: now$' "$SK" && grep -q '^description: ' "$SK"; then ok "the skill has a name and a description"; else ng "skills/now/SKILL.md: frontmatter"; fi
grep -qF '!`bash "${CLAUDE_PLUGIN_ROOT}/scripts/now.sh" plain`' "$SK" 2>/dev/null && ok "the skill reads the time through scripts/now.sh (same zone setting as the hooks)" || ng "the skill does not call scripts/now.sh plain"

echo "[9] rows of the wording table (has a row quietly gone?)"
# If you change the table yourself, change this line to match.
TG_EXPECT_ROWS="clock:en-night clock:en-part-of-day clock:ja-part-of-day day:en-relative-day day:ja-relative-day span:en-length span:ja-length"
now_rows=$(tg_rows | awk 'NF>=3 {print $1 ":" $2}' | sort | tr '\n' ' ' | sed 's/ $//')
[ "$now_rows" = "$TG_EXPECT_ROWS" ] && ok "the rows match the record" || ng "the rows differ from the record (if you changed the table, update TG_EXPECT_ROWS)"

echo "[10] how live-check.sh tells \"the hook did not run\" from \"the hook ran and did not help\""
# Sample hook lines in the shape Claude Code writes them, not a real session (tests/hook-events-test.sh).
bash -n "$ROOT/tests/live-check.sh" 2>/dev/null && grep -q -- '--include-hook-events' "$ROOT/tests/live-check.sh" \
  && ok "live-check.sh parses and asks Claude Code for the hook lines" || ng "live-check.sh does not parse, or does not ask for the hook lines"
HE_OUT=$(bash "$ROOT/tests/hook-events-test.sh" 2>&1); HE_RC=$?
if [ "$HE_RC" = "0" ]; then ok "the three verdicts on sample hook lines: ran, failed to run, never started ($(printf '%s\n' "$HE_OUT" | grep -c '^  ok ') cases)"
else printf '%s\n' "$HE_OUT" | grep '^  FAIL ' | sed 's/^/  /'; ng "the three verdicts on sample hook lines (run tests/hook-events-test.sh to see all cases)"; fi

echo
echo "Result: ok $PASS / FAIL $FAIL"
[ "$FAIL" = "0" ] || exit 1
echo "The hook scripts behave correctly. To see whether Claude Code actually calls them, run tests/live-check.sh."
