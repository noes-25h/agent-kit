#!/bin/bash
# Check time-guard against a real Claude Code session.
#
# Creates an empty work folder and runs Claude Code (claude -p) "with the plugin" and "without".
#
#   path 1  the clock on the prompt
#           Claude is given no tools and is asked for the current date and time to the minute.
#           The plugin is told to use a time zone that differs from the one of this machine.
#           with = the answer is the system clock in that zone, without = it is not
#           -> the time reached Claude, and it came from the plugin.
#   path 2  the note on a write
#           Claude is asked to write a file that says "this morning" and then to copy any line it
#           was given that starts with "time-guard:".
#           with = the reply holds a phrase that exists only in the note, without = it does not
#           -> the note reached Claude. The write must succeed on both sides (nothing is blocked).
#
# Path 1 cannot be passed by guessing: the minute and the zone both have to match.
# Path 2 leans on Claude repeating a phrase; the phrase is one it cannot know unless the note arrived.
#
# The hook lines of each run are counted as well (--include-hook-events). When no hook of this plugin
# ran to the end, the result says nothing about the plugin, and the check ends with "cannot tell" and
# the reason. That is what a run from inside a sandbox looks like.
#
# Usage: bash tests/live-check.sh     (from a plain terminal, not from inside a Claude Code session)
# Needs: claude (logged in), jq. It calls Claude Code four times and uses that much of your usage allowance.
# Exit code: 0 = working (the hooks ran and the time and the note reached Claude)
#            1 = not working (the hooks ran and the time or the note did not reach Claude)
#            2 = cannot tell (a run did not finish, the hooks did not run, or the control is not a control)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v claude >/dev/null 2>&1 || { echo "claude was not found."; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "jq was not found."; exit 2; }

. "$ROOT/tests/hook-events.sh" 2>/dev/null || { echo "tests/hook-events.sh was not found."; exit 2; }
# Which hook lines belong to this plugin (see tests/hook-events.sh)
HE_PLUGIN='time-guard'
HE_NAME_RE='^(UserPromptSubmit|SessionStart)(:.*)?$|^PreToolUse:(Write|Edit|MultiEdit|NotebookEdit)$'
HE_SIGN_RE='time-guard|Current local time'
WORK=$(mktemp -d "${TMPDIR:-/tmp}/time-guard-live.XXXXXX") || { echo "Could not create a work folder."; exit 2; }
mkdir -p "$WORK/with" "$WORK/without"

# A zone whose offset differs from this machine, so that a right answer cannot come from anywhere else.
if [ "$(LC_ALL=C date '+%z')" = "+0000" ]; then ZONE="Asia/Tokyo"; else ZONE="UTC"; fi
[ "$(LC_ALL=C TZ="$ZONE" date '+%z')" != "$(LC_ALL=C date '+%z')" ] || { echo "Cannot tell: this machine has no zone files, so a second time zone cannot be shown."; exit 2; }

PHRASE='not backed by a value in the same text'
P_CLOCK='Do not use any tool. Reply with one line only: the current local date and time in the form YYYY-MM-DD HH:MM, taken from the context you were given. If you were not given a time of day, reply with the single word UNKNOWN.'
P_NOTE='Use the Write tool to create a file named notes.md in the current directory. Its content must be exactly this sentence: We fixed the build this morning. After the tool call, reply with the word DONE. Then, on a new line, copy word for word any line you were given that starts with "time-guard:". If you were given no such line, write NONE on that line.'

# arm name prompt [allowed-tool]
run() {
  local arm="$1" name="$2" prompt="$3" tool="${4:-}" out="$WORK/$1/$2.jsonl"
  local -a cmd=(claude -p "$prompt" --output-format stream-json --verbose --include-hook-events)
  [ -n "$tool" ] && cmd+=(--allowedTools "$tool")
  [ "$arm" = "with" ] && cmd+=(--plugin-dir "$ROOT")
  date '+%s' > "$out.t0"
  if command -v perl >/dev/null 2>&1; then
    (cd "$WORK/$arm" && TIME_GUARD_TZ="$ZONE" perl -e 'alarm shift; exec @ARGV' 240 "${cmd[@]}" >"$out" 2>"$out.err" </dev/null)
  else
    (cd "$WORK/$arm" && TIME_GUARD_TZ="$ZONE" "${cmd[@]}" >"$out" 2>"$out.err" </dev/null)
  fi
  date '+%s' > "$out.t1"
}

# Did the run reach the end (a result was emitted and it is not an error)?
finished() { jq -es 'map(select(.type == "result")) | last | (. != null and (.is_error | not))' "$1" >/dev/null 2>&1; }
# The final reply
reply() { jq -rs 'map(select(.type == "result")) | last | .result // empty' "$1" 2>/dev/null; }
# How many times a tool was called
called() { jq -r --arg t "$2" 'select(.type == "assistant") | .message.content[]? | select(.type == "tool_use" and .name == $t) | .name' "$1" 2>/dev/null | grep -c .; }
# One epoch second as "YYYY-MM-DD HH:MM" in ZONE (BSD date, then GNU date)
fmt() { LC_ALL=C TZ="$ZONE" date -r "$1" '+%Y-%m-%d %H:%M' 2>/dev/null || LC_ALL=C TZ="$ZONE" date -d "@$1" '+%Y-%m-%d %H:%M' 2>/dev/null; }
# Is the time in the reply one of the minutes the run lived through? Prints 1 or 0.
on_clock() {
  local f="$1" got e t0 t1
  got=$(reply "$f" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}' | head -1)
  [ -n "$got" ] || { echo 0; return; }
  t0=$(cat "$f.t0"); t1=$(cat "$f.t1")
  e=$((t0 - 60))
  while [ "$e" -le $((t1 + 60)) ]; do
    [ "$(fmt "$e")" = "$got" ] && { echo 1; return; }
    e=$((e + 60))
  done
  echo 0
}
has_phrase() { reply "$1" | grep -cF -e "$PHRASE"; }

echo "Work folder: $WORK"
echo "Time zone given to the plugin for this check: $ZONE"
echo "Calling Claude Code four times (this takes a few minutes)..."
for arm in with without; do
  run "$arm" clock "$P_CLOCK"
  run "$arm" note  "$P_NOTE" Write
done

UNDECIDED=0
for arm in with without; do
  for name in clock note; do
    f="$WORK/$arm/$name.jsonl"
    if ! finished "$f"; then
      echo "Cannot tell: $arm/$name did not run to the end (check login, usage allowance, network; log = $f)"
      UNDECIDED=1
      continue
    fi
    if [ "$name" = "note" ]; then
      [ "$(called "$f" Write)" -ge 1 ] 2>/dev/null || { echo "Cannot tell: $arm/note never called Write"; UNDECIDED=1; }
    fi
  done
done
[ "$UNDECIDED" = "0" ] || exit 2

W_CLOCK=$(on_clock "$WORK/with/clock.jsonl");   N_CLOCK=$(on_clock "$WORK/without/clock.jsonl")
W_NOTE=$(has_phrase "$WORK/with/note.jsonl");   N_NOTE=$(has_phrase "$WORK/without/note.jsonl")
W_FILE=0; grep -q 'this morning' "$WORK/with/notes.md" 2>/dev/null && W_FILE=1
N_FILE=0; grep -q 'this morning' "$WORK/without/notes.md" 2>/dev/null && N_FILE=1

echo
echo "Claude Code: $(claude --version 2>/dev/null | head -1)"
echo "                                                        with plugin   without plugin"
echo "path 1  reply is the system clock in $ZONE (1 = yes)        $W_CLOCK              $N_CLOCK"
echo "path 2  reply holds the phrase from the note (count)      $W_NOTE              $N_NOTE"
echo "        the file was written (1 = yes)                    $W_FILE              $N_FILE"
he_scan "$HE_NAME_RE" "$HE_SIGN_RE" "$WORK"/without/*.jsonl -- "$WORK"/with/*.jsonl
he_report "$HE_PLUGIN"
echo
he_gate 0
if [ "$?" = "2" ]; then
  he_explain_not_run "$HE_PLUGIN"
  echo
  echo "Logs are kept in $WORK."
  exit 2
fi

RC=0
if [ "$N_CLOCK" = "0" ] && [ "$N_NOTE" = "0" ]; then
  echo "Control (without plugin): Claude had no clock time and no note = the instrument works."
else
  echo "Control (without plugin): the time or the note showed up on this side as well. If time-guard is already installed, that is why."
  echo "If it is not installed, this check cannot tell."
  RC=2
fi
if [ "$W_CLOCK" = "1" ]; then echo "path 1: working (the hook ran and the time from the plugin reached Claude, in the zone that was set)"
else echo "path 1: NOT working (the hook ran and Claude did not answer with the system clock in $ZONE)"; RC=1; fi
if [ "$W_NOTE" -ge 1 ]; then echo "path 2: working (the hook ran and the note on the write reached Claude)"
else echo "path 2: NOT working (the hook ran and the note on the write did not reach Claude)"; RC=1; fi
if [ "$W_FILE" = "1" ] && [ "$N_FILE" = "1" ]; then echo "path 2: the write went through on both sides (nothing was blocked)"
else echo "path 2: the file is missing on one side (with = $W_FILE, without = $N_FILE). time-guard is not meant to block a write"; [ "$W_FILE" = "1" ] || RC=1; fi
he_gate "$RC"
if [ "$?" = "2" ] && [ "$RC" = "1" ]; then he_explain_mixed "$HE_PLUGIN"; RC=2; fi
echo
echo "Logs are kept in $WORK."
exit "$RC"
