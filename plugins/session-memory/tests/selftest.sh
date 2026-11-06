#!/bin/bash
# Unit check for session-memory.
# Builds throwaway repositories in the temp area (an empty one, one with records, one with very large
# records, and several broken ones), runs the session-start hook against each, and checks:
# something is injected, it fits the budget, the right slice is shown, and nothing makes the hook fail.
#
# A full pass here only tells you that the hook script is correct.
# Whether Claude Code calls the hook and hands its output to Claude can only be seen with
# tests/live-check.sh (the check against a real Claude Code session).
#
# Usage: bash tests/selftest.sh     exit 0 = all passed / 1 = at least one check failed
# Needs: bash, awk, grep, sed, head, tr, wc. perl is used when present (for one check).

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INJECT="$ROOT/scripts/inject.sh"
PATHS="$ROOT/scripts/paths.sh"
PASS=0; FAIL=0
CAP=10000        # the Claude Code cap on hook output, in characters
DEFAULT=6000     # the default budget of this plugin, in bytes

ok() { PASS=$((PASS+1)); echo "  ok   $1"; }
ng() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
bytes() { printf '%s\n' "$1" | LC_ALL=C wc -c | tr -d ' '; }
has() { printf '%s\n' "$1" | grep -qF -e "$2"; }
# UTF-8 validity is checked with perl (strict decoding). iconv is not used: on macOS it reports
# an error for some valid input when it is given more than one line at a time.
HAVE_PERL=0; perl -MEncode -e 1 >/dev/null 2>&1 && HAVE_PERL=1
valid_utf8() {
  printf '%s\n' "$1" | perl -MEncode -e 'local $/; my $d = <STDIN>; eval { Encode::decode("UTF-8", $d, Encode::FB_CROAK); 1 } or exit 1; exit 0' >/dev/null 2>&1
}

BASE="${TMPDIR:-/tmp}"
T=$(mktemp -d "${BASE%/}/session-memory-selftest.XXXXXX" 2>/dev/null) || { echo "Could not create a temp folder."; exit 1; }

# run <project root> [stdin text]   -> OUT, RC
run() {
  local input='{"hook_event_name":"SessionStart","source":"startup"}'
  [ "$#" -ge 2 ] && input="$2"
  OUT=$(printf '%s' "$input" | CLAUDE_PROJECT_DIR="$1" bash "$INJECT" 2>/dev/null)
  RC=$?
}
expect_rc0() { [ "$RC" = "0" ] && ok "$1: exit 0" || ng "$1: exit $RC (expected 0)"; }
expect_fit() { # description limit
  local b; b=$(bytes "$OUT")
  [ "$b" -le "$2" ] && ok "$1: $b bytes, within $2" || ng "$1: $b bytes, over $2"
}
expect_has() { has "$OUT" "$2" && ok "$1" || ng "$1 (missing: $2)"; }
expect_not() { has "$OUT" "$2" && ng "$1 (present: $2)" || ok "$1"; }
first_line() { printf '%s\n' "$OUT" | head -1; }
last_line() { printf '%s\n' "$OUT" | tail -1; }
expect_frame() {
  case "$(first_line)" in "[session-memory] "*) ok "$1: starts with the fixed header, not with {" ;; *) ng "$1: first line is not the fixed header" ;; esac
}

echo "[1] an empty repository"
mkdir -p "$T/empty"
run "$T/empty"
expect_rc0 "empty"
[ -n "$OUT" ] && ok "empty: something is injected" || ng "empty: nothing was injected"
[ "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" = "1" ] && ok "empty: one line only" || ng "empty: more than one line"
expect_frame "empty"
expect_has "empty: says that there are no records yet" "No records yet in .memory/"
expect_fit "empty" 400

echo "[2] a repository with records"
R="$T/normal"; mkdir -p "$R/.memory/journal"
cat > "$R/.memory/now.md" <<'EOF'
# Now

Updated: 2026-01-12 18:40

- Goal: NOW-GOAL-MARK ship the importer
- State: parser works, writer is half done
- Blocked on: nothing
- Entry point: src/import/writer.ts
EOF
{
  echo "# Decisions"; echo
  echo "## 2026-01-12 DEC-NEWEST use streaming writes"; echo "- Decided: streaming"; echo "- Why: DEC-BODY-MARK memory"; echo
  for i in 2 3 4 5; do echo "## 2026-01-0$i DEC-MID-$i"; echo "- Decided: x"; echo; done
  echo "## 2025-12-01 DEC-SIXTH"; echo "- Decided: y"; echo
  echo "## 2025-11-01 DEC-OLDEST"; echo "- Decided: z"
} > "$R/.memory/decisions.md"
cat > "$R/.memory/tasks.md" <<'EOF'
# Tasks
- [x] TASK-DONE-MARK set up the repository
- [ ] TASK-OPEN-1 finish the writer
  - [ ] TASK-OPEN-NESTED add a retry
* [ ] TASK-OPEN-STAR write the docs
- [X] TASK-DONE-UPPER pick a parser
Some prose that is not a task.
EOF
cat > "$R/.memory/journal/2026-01-11.md" <<'EOF'
# 2026-01-11

## Session 10:00

### Done
- old work

### Next
- NEXT-OLD-DAY
EOF
cat > "$R/.memory/journal/2026-01-12.md" <<'EOF'
# 2026-01-12

## Session 09:10

### Done
- DONE-MARK parser

### Learned
- LEARNED-MARK the input is not sorted

### Next
- NEXT-EARLY-SESSION

## Session 18:40

### Done
- writer skeleton

### Next
- NEXT-LATE-SESSION open src/import/writer.ts and finish flush()

### Notes
- AFTER-NEXT-MARK
EOF
echo "- NEXT-NOT-A-DATE" > "$R/.memory/journal/notes.md"
printf '### Next\n- NEXT-BAD-NAME\n' > "$R/.memory/journal/2026-01-99-draft.md"
run "$R"
expect_rc0 "records"
expect_frame "records"
[ "$(last_line)" = "[session-memory] End of snapshot." ] && ok "records: ends with the fixed footer" || ng "records: last line is not the fixed footer"
expect_fit "records" "$DEFAULT"
expect_has "now: the current state is shown" "NOW-GOAL-MARK"
expect_has "decisions: the newest entry is shown" "DEC-NEWEST"
expect_has "decisions: the fifth entry is shown" "DEC-MID-5"
expect_not "decisions: the sixth entry is left out" "DEC-SIXTH"
expect_not "decisions: the oldest entry is left out" "DEC-OLDEST"
expect_not "decisions: only titles are shown, not bodies" "DEC-BODY-MARK"
expect_has "decisions: says how many were left out" "... 2 older entries not shown"
expect_has "tasks: an open task is shown" "TASK-OPEN-1"
expect_has "tasks: a nested open task is shown" "TASK-OPEN-NESTED"
expect_has "tasks: an open task with a * bullet is shown" "TASK-OPEN-STAR"
expect_not "tasks: a finished task is left out" "TASK-DONE-MARK"
expect_not "tasks: a finished task with [X] is left out" "TASK-DONE-UPPER"
expect_has "next: the latest day is named" ".memory/journal/2026-01-12.md"
expect_has "next: the last session of the day is shown" "NEXT-LATE-SESSION"
expect_not "next: an earlier session of the same day is left out" "NEXT-EARLY-SESSION"
expect_not "next: an older day is left out" "NEXT-OLD-DAY"
expect_not "next: stops at the following heading" "AFTER-NEXT-MARK"
expect_not "next: done and learned stay in the file" "LEARNED-MARK"
expect_not "journal: a file that is not named by date is ignored" "NEXT-NOT-A-DATE"
expect_not "journal: a file with a malformed date name is ignored" "NEXT-BAD-NAME"

echo "[3] a repository with very large records"
H="$T/huge"; mkdir -p "$H/.memory/journal"
{
  awk 'BEGIN { printf "HUGE-LINE-START "; for (i = 0; i < 50000; i++) printf "x"; printf "\n" }'
  awk 'BEGIN { for (i = 1; i <= 5000; i++) printf "- NOW-LINE-%d filler filler filler filler filler filler filler filler\n", i }'
} > "$H/.memory/now.md"
awk 'BEGIN { print "# Decisions"; for (i = 1; i <= 2000; i++) printf "## 2026-01-01 HUGE-DEC-%d a decision title of ordinary length for this check\n- Decided: something\n\n", i }' > "$H/.memory/decisions.md"
awk 'BEGIN { for (i = 1; i <= 3000; i++) printf "- [ ] HUGE-TASK-%d an open task of ordinary length for this check\n", i }' > "$H/.memory/tasks.md"
awk 'BEGIN { print "# 2026-01-12\n\n## Session 09:00\n\n### Next"; for (i = 1; i <= 500; i++) printf "- HUGE-NEXT-%d\n", i }' > "$H/.memory/journal/2026-01-12.md"
run "$H"
expect_rc0 "huge"
expect_frame "huge"
expect_fit "huge" "$DEFAULT"
expect_fit "huge (against the Claude Code cap)" "$CAP"
expect_has "huge: the section for the current state is present" "## Where things stand"
expect_has "huge: the section for decisions is present" "## Recent decisions"
expect_has "huge: the section for tasks is present" "## Open tasks"
expect_has "huge: the section for next is present" "## Next, from the latest daily record"
[ "$(last_line)" = "[session-memory] End of snapshot." ] && ok "huge: the footer is still there" || ng "huge: the footer was lost"
expect_has "huge: a 50,000-byte line is cut, and its start is kept" "HUGE-LINE-START xxxx"
printf '%s\n' "$OUT" | awk 'length($0) > 420 { bad = 1 } END { exit bad }' && ok "huge: no line is longer than 420 bytes" || ng "huge: a long line got through"
expect_has "huge: the first decision is shown" "HUGE-DEC-1 "
expect_has "huge: says how many decisions were left out" "... 1995 older entries not shown"
expect_has "huge: the first task is shown" "HUGE-TASK-1 "
printf '%s\n' "$OUT" | grep -qE '^  \.\.\. 29[0-9][0-9] more open tasks not shown' && ok "huge: says how many tasks were left out" || ng "huge: no count of tasks left out"
printf '%s\n' "$OUT" | grep -qE '^  \.\.\. [0-9]+ more lines not shown' && ok "huge: says how many lines were left out" || ng "huge: no count of lines left out"
expect_has "huge: says that only the start of an oversized file was read" "only the first 262144 were looked at"
# The file has 5,001 lines. About 3,000 of them fit in the 262,144 bytes that are read.
MORE=$(printf '%s\n' "$OUT" | sed -n 's/^  \.\.\. \([0-9][0-9]*\) more lines not shown.*/\1/p' | head -1)
[ -n "$MORE" ] && [ "$MORE" -gt 2000 ] && [ "$MORE" -lt 3500 ] && ok "huge: an oversized file is read only up to the limit ($MORE lines counted as left out, not about 4,975)" || ng "huge: an oversized file was read past the limit (lines left out: ${MORE:-none})"
expect_not "huge: the cut-at-budget line is not needed when sections keep to their share" "The snapshot was cut here"

J="$T/multibyte"; mkdir -p "$J/.memory"
awk 'BEGIN { for (i = 1; i <= 400; i++) { printf "- 記録%d ", i; for (k = 0; k < 150; k++) printf "現在地と決定と次の一手"; printf "\n" } }' > "$J/.memory/now.md"
awk 'BEGIN { for (i = 1; i <= 50; i++) { printf "- [ ] 課題%d ", i; for (k = 0; k < 100; k++) printf "\360\237\247\255道標"; printf "\n" } }' > "$J/.memory/tasks.md"
run "$J"
expect_rc0 "multi-byte"
expect_fit "multi-byte" "$DEFAULT"
expect_has "multi-byte: content is shown" "記録1 "
if [ "$HAVE_PERL" = "1" ]; then
  valid_utf8 "$OUT" && ok "multi-byte: no character is cut in half (the output is valid UTF-8)" || ng "multi-byte: a character was cut in half (invalid UTF-8)"
  printf '%s\n' "$OUT" | grep -q ' \.\.\.$' && ok "multi-byte: long lines were in fact cut" || ng "multi-byte: no line was cut, so the check above proves nothing"
else
  echo "  skip multi-byte: perl with Encode was not found, so UTF-8 validity was not checked"
fi

echo "[4] settings"
S="$T/custom"; mkdir -p "$S/.claude" "$S/docs/log/days" "$S/.memory"
printf '%s\n' '# my layout' 'dir = docs/log' 'now=STATE.md' 'decisions="ADR.md"' 'tasks=TODO.md' 'journal=days' 'budget=2000' > "$S/.claude/session-memory.conf"
echo "- CUSTOM-NOW-MARK" > "$S/docs/log/STATE.md"
echo "## 2026-01-12 CUSTOM-DEC-MARK" > "$S/docs/log/ADR.md"
echo "- [ ] CUSTOM-TASK-MARK" > "$S/docs/log/TODO.md"
printf '### Next\n- CUSTOM-NEXT-MARK\n' > "$S/docs/log/days/2026-01-12.md"
echo "- DEFAULT-PLACE-MARK" > "$S/.memory/now.md"
run "$S"
expect_rc0 "custom"
expect_has "custom: the current state is read from the configured file" "CUSTOM-NOW-MARK"
expect_has "custom: decisions are read from the configured file" "CUSTOM-DEC-MARK"
expect_has "custom: tasks are read from the configured file" "CUSTOM-TASK-MARK"
expect_has "custom: next is read from the configured folder" "CUSTOM-NEXT-MARK"
expect_not "custom: the default folder is no longer read" "DEFAULT-PLACE-MARK"
expect_fit "custom: budget=2000" 2000

B="$T/smallbudget"; mkdir -p "$B/.claude"; cp -R "$H/.memory" "$B/.memory"
echo "budget=2000" > "$B/.claude/session-memory.conf"
run "$B"
expect_fit "large records with budget=2000" 2000
expect_has "large records with budget=2000: all four sections still present" "## Next, from the latest daily record"

L="$T/longname"; LD="$(awk 'BEGIN { for (i = 0; i < 200; i++) printf "a" }')"
mkdir -p "$L/.claude" "$L/$LD/$LD/$LD/journal"
printf 'dir=%s\nbudget=2000\n' "$LD/$LD/$LD" > "$L/.claude/session-memory.conf"
cp "$H/.memory/now.md" "$H/.memory/decisions.md" "$H/.memory/tasks.md" "$L/$LD/$LD/$LD/"
cp "$H/.memory/journal/2026-01-12.md" "$L/$LD/$LD/$LD/journal/"
run "$L"
expect_rc0 "600-byte folder name"
expect_fit "600-byte folder name with budget=2000 (headings alone exceed their share)" 2000
expect_frame "600-byte folder name"
expect_has "600-byte folder name: the records are still shown, cut to fit" "HUGE-LINE-START"
expect_has "600-byte folder name: the cut is announced" "The snapshot was cut here to stay within 2000 bytes."

X="$T/badconf"; mkdir -p "$X/proj/.claude" "$X/proj/.memory" "$X/outside"
echo "- OUTSIDE-MARK" > "$X/outside/now.md"
echo "- INSIDE-MARK" > "$X/proj/.memory/now.md"
printf '%s\n' 'dir=../outside' 'budget=99999' > "$X/proj/.claude/session-memory.conf"
run "$X/proj"
expect_not "a folder with .. is refused (nothing outside the project is read)" "OUTSIDE-MARK"
expect_has "a refused folder falls back to the default" "INSIDE-MARK"
expect_has "refused settings are named in the snapshot" "Ignored settings in .claude/session-memory.conf: dir budget"
expect_fit "budget=99999 is refused" "$DEFAULT"
printf 'dir=%s\n' "$X/outside" > "$X/proj/.claude/session-memory.conf"
run "$X/proj"
expect_not "an absolute folder is refused" "OUTSIDE-MARK"
printf '%s\n' 'now=$(touch PWNED-BY-CONF)' 'tasks=`touch PWNED-BY-CONF`' 'journal=x; touch PWNED-BY-CONF' > "$X/proj/.claude/session-memory.conf"
(cd "$X/proj" && run "$X/proj")
[ -z "$(find "$X" -name 'PWNED-BY-CONF*' 2>/dev/null)" ] && ok "the settings file is read as text and never executed" || ng "a command in the settings file was executed"
printf 'budget=12abc\nunknown=1\nno equals sign here\n\n' > "$X/proj/.claude/session-memory.conf"
run "$X/proj"
expect_rc0 "a settings file with junk lines"
expect_has "a settings file with junk lines still loads the records" "INSIDE-MARK"

echo "[5] broken input"
run "$R" 'this is not json'
expect_rc0 "hook input that is not JSON"; expect_has "hook input that is not JSON: records still shown" "NOW-GOAL-MARK"
run "$R" ''
expect_rc0 "empty hook input"; expect_has "empty hook input: records still shown" "NOW-GOAL-MARK"
OUT=$(CLAUDE_PROJECT_DIR="$R" bash "$INJECT" </dev/null 2>/dev/null); RC=$?
expect_rc0 "hook input closed"
OUT=$(CLAUDE_PROJECT_DIR="$R" bash "$INJECT" <&- 2>/dev/null); RC=$?
expect_rc0 "no stdin at all"; expect_has "no stdin at all: records still shown" "NOW-GOAL-MARK"

run "$T/does-not-exist"
expect_rc0 "a project folder that does not exist"
expect_has "a project folder that does not exist: says there are no records" "No records yet"
OUT=$(cd "$R" && env -u CLAUDE_PROJECT_DIR bash "$INJECT" </dev/null 2>/dev/null); RC=$?
expect_has "without CLAUDE_PROJECT_DIR the current folder is used" "NOW-GOAL-MARK"

K="$T/broken"; mkdir -p "$K/.memory/now.md" "$K/.memory/journal/2026-01-12.md"
echo "this is a file where a folder was expected" > "$K/.memory/tasks.md"
echo "## 2026-01-12 BROKEN-DEC-MARK" > "$K/.memory/decisions.md"
run "$K"
expect_rc0 "a folder where a file is expected"
expect_has "a folder where a file is expected: the readable records are still shown" "BROKEN-DEC-MARK"
expect_has "a task file with no checkbox says so" "no open tasks"

N="$T/binary"; mkdir -p "$N/.memory/journal"
head -c 300000 /dev/urandom > "$N/.memory/now.md" 2>/dev/null
head -c 100000 /dev/urandom > "$N/.memory/decisions.md" 2>/dev/null
{ printf '### Next\n'; head -c 50000 /dev/urandom; } > "$N/.memory/journal/2026-01-12.md" 2>/dev/null
printf -- '- [ ] BIN-TASK \000\001\002 with control bytes\033[31m\r\n' > "$N/.memory/tasks.md"
run "$N"
expect_rc0 "binary records"
expect_frame "binary records"
expect_fit "binary records" "$DEFAULT"
[ "$(printf '%s\n' "$OUT" | LC_ALL=C tr -d '\011\012\040-\176\200-\377' | LC_ALL=C wc -c | tr -d ' ')" = "0" ] && ok "binary records: no control bytes reach the snapshot" || ng "binary records: control bytes got through"
expect_has "binary records: a readable task next to control bytes is shown" "BIN-TASK"

C="$T/crlf"; mkdir -p "$C/.memory/journal"
printf '# 2026-01-12\r\n\r\n### Next\r\n- CRLF-NEXT-MARK\r\n' > "$C/.memory/journal/2026-01-12.md"
printf '## 2026-01-12 CRLF-DEC-MARK\r\n' > "$C/.memory/decisions.md"
run "$C"
expect_has "CRLF line endings: the Next heading is still matched" "CRLF-NEXT-MARK"

U="$T/unreadable"; mkdir -p "$U/.memory"
echo "- UNREADABLE-MARK" > "$U/.memory/now.md"; chmod 000 "$U/.memory/now.md"
echo "- [ ] READABLE-TASK-MARK" > "$U/.memory/tasks.md"
run "$U"
expect_rc0 "an unreadable file"
if [ "$(id -u)" = "0" ]; then echo "  skip an unreadable file: running as root, so the file is readable anyway"
else expect_not "an unreadable file is skipped" "UNREADABLE-MARK"; fi
expect_has "an unreadable file: the other records are still shown" "READABLE-TASK-MARK"
chmod 600 "$U/.memory/now.md"

G="$T/jsonish"; mkdir -p "$G/.memory"
printf '{"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": "JSONISH-MARK"}}\n' > "$G/.memory/now.md"
run "$G"
case "$OUT" in '{'*) ng "a record that looks like hook JSON makes the output start with {" ;; *) ok "a record that looks like hook JSON does not make the output start with {" ;; esac
expect_has "a record that looks like hook JSON is shown as plain text" "JSONISH-MARK"

E="$T/emptyfiles"; mkdir -p "$E/.memory/journal"
: > "$E/.memory/now.md"; : > "$E/.memory/decisions.md"; : > "$E/.memory/tasks.md"; : > "$E/.memory/journal/2026-01-12.md"
run "$E"
expect_rc0 "records that are all empty files"
expect_has "an empty file is reported as empty" "(empty)"
expect_has "a decision log with no entries says so" "no entries found"
expect_has "a daily record with no Next section says so" "has no \"Next\" section"

echo "[6] the paths helper used by the two skills"
PO=$(bash "$PATHS" "$S" 2>/dev/null); PRC=$?
[ "$PRC" = "0" ] && ok "paths: exit 0" || ng "paths: exit $PRC"
OUT="$PO"
expect_has "paths: the configured folder is reported" "memory_dir: $S/docs/log (exists)"
expect_has "paths: the configured file names are reported" "now_file: $S/docs/log/STATE.md (exists)"
expect_has "paths: today's date comes from the system clock" "date: $(date +%Y-%m-%d)"
expect_has "paths: today's record is named by date" "journal_today: $S/docs/log/days/$(date +%Y-%m-%d).md"
expect_has "paths: the previous record is found" "journal_previous: $S/docs/log/days/2026-01-12.md"
OUT=$(bash "$PATHS" "$T/empty" 2>/dev/null)
expect_has "paths: a repository with no records reports the default folder as not created" "memory_dir: $T/empty/.memory (not created yet)"
expect_has "paths: no previous record" "journal_previous: none"
OUT=$(cd "$R" && bash "$PATHS" '${CLAUDE_PROJECT_DIR}' 2>/dev/null)
expect_has "paths: a placeholder that was not substituted falls back to the current folder" "project_root: $R"
expect_not "paths: the literal placeholder is not used as a path" 'project_root: ${CLAUDE'
[ -z "$(find "$T/empty" -mindepth 1 2>/dev/null)" ] && ok "paths and hook: nothing was created in the empty repository" || ng "something was created in the empty repository"

echo "[7] what the plugin declares"
grep -q '"SessionStart"' "$ROOT/hooks/hooks.json" && grep -q 'scripts/inject.sh' "$ROOT/hooks/hooks.json" && ok "hooks.json wires SessionStart to scripts/inject.sh" || ng "hooks.json does not wire SessionStart to scripts/inject.sh"
for s in wrap-up morning; do
  f="$ROOT/skills/$s/SKILL.md"
  if [ -f "$f" ] && head -1 "$f" | grep -q '^---$' && grep -q "^name: $s\$" "$f" && grep -q '^description: ' "$f"; then ok "skill $s: has a name and a description"; else ng "skill $s: SKILL.md is missing or has no name and description"; fi
  grep -q 'scripts/paths.sh' "$f" 2>/dev/null && ok "skill $s: takes its paths from scripts/paths.sh" || ng "skill $s: does not use scripts/paths.sh"
done
# The formats that the wrap-up skill writes must be the formats that the hook reads.
W="$T/skillformat"; mkdir -p "$W/.memory/journal"
awk '/^```markdown$/ { on = 1; n++; next } /^```$/ { on = 0 } on { print > (dir "/block" n ".md") }' dir="$W" "$ROOT/skills/wrap-up/SKILL.md"
cp "$W/block1.md" "$W/.memory/journal/2026-01-12.md" 2>/dev/null
cp "$W/block2.md" "$W/.memory/now.md" 2>/dev/null
cp "$W/block3.md" "$W/.memory/decisions.md" 2>/dev/null
run "$W"
expect_has "the daily record template in the wrap-up skill is read by the hook" "The first thing to do next time"
expect_has "the template for the current state in the wrap-up skill is read by the hook" "Entry point:"
expect_has "the decision template in the wrap-up skill is read by the hook" "- YYYY-MM-DD Short title of the decision"

echo "[8] checking the checker"
[ "$(bytes "0123456789")" = "11" ] && ok "the byte counter counts 10 characters and a newline as 11" || ng "the byte counter is off"
[ "$(bytes "$(printf '\343\201\202')")" = "4" ] && ok "the byte counter counts one 3-byte character and a newline as 4" || ng "the byte counter counts characters, not bytes"
if [ "$HAVE_PERL" = "1" ]; then
  valid_utf8 "$(printf 'ab\343\201\202')" && ok "the UTF-8 check accepts a whole character" || ng "the UTF-8 check rejects a whole character"
  valid_utf8 "$(printf 'ab\343\201')" && ng "the UTF-8 check accepts half a character" || ok "the UTF-8 check rejects half a character"
fi
OUT="$(awk 'BEGIN { for (i = 0; i < 7000; i++) printf "y" }')"
[ "$(bytes "$OUT")" -le "$DEFAULT" ] && ng "the budget check accepts 7,000 bytes" || ok "the budget check rejects 7,000 bytes"

# The work folder is left in the OS temp area (it holds only the throwaway repositories built above).

echo "[9] how live-check.sh tells \"the hook did not run\" from \"the hook ran and did not help\""
# Sample hook lines in the shape Claude Code writes them, not a real session (tests/hook-events-test.sh).
bash -n "$ROOT/tests/live-check.sh" 2>/dev/null && grep -q -- '--include-hook-events' "$ROOT/tests/live-check.sh" \
  && ok "live-check.sh parses and asks Claude Code for the hook lines" || ng "live-check.sh does not parse, or does not ask for the hook lines"
HE_OUT=$(bash "$ROOT/tests/hook-events-test.sh" 2>&1); HE_RC=$?
if [ "$HE_RC" = "0" ]; then ok "the three verdicts on sample hook lines: ran, failed to run, never started ($(printf '%s\n' "$HE_OUT" | grep -c '^  ok ') cases)"
else printf '%s\n' "$HE_OUT" | grep '^  FAIL ' | sed 's/^/  /'; ng "the three verdicts on sample hook lines (run tests/hook-events-test.sh to see all cases)"; fi

echo
echo "Result: ok $PASS / FAIL $FAIL"
[ "$FAIL" = "0" ] || exit 1
echo "The hook script behaves correctly. To see whether Claude Code hands its output to Claude, run tests/live-check.sh."
