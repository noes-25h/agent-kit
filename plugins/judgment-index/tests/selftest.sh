#!/bin/bash
# Check the tool of judgment-index without calling Claude Code.
#
#   part 1  the checks are fed good and broken samples (python3 scripts/judgment.py selftest)
#   part 2  the command line is driven the way the README tells a person to drive it:
#           init -> check -> break a row -> check fails -> repair -> rename a scene -> check fails -> toc -> check passes
#
# Usage: bash tests/selftest.sh
# Needs: python3 (3.8 or later). Nothing else.
# Exit code: 0 = every check behaved as expected / 1 = at least one did not

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL="$ROOT/scripts/judgment.py"
command -v python3 >/dev/null 2>&1 || { echo "python3 was not found."; exit 1; }

OK=0; FAIL=0
# label expected-exit-code command...
expect() {
  local label="$1" want="$2"; shift 2
  "$@" >/dev/null 2>&1; local got=$?
  if [ "$got" = "$want" ]; then OK=$((OK+1)); echo "  ok   $label (exit $got)"
  else FAIL=$((FAIL+1)); echo "  FAIL $label (exit $got, expected $want)"; fi
}

echo "== part 1: the checks against good and broken samples"
python3 "$TOOL" selftest; P1=$?

echo
echo "== part 2: the command line, from an empty project"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/judgment-index-selftest.XXXXXX") || { echo "Could not create a work folder."; exit 1; }
mkdir "$WORK/.git"
J="$WORK/judgment"
cd "$WORK" || exit 1

expect "check before init cannot tell"                      2 python3 "$TOOL" check
expect "init unpacks the index and it passes check"         0 python3 "$TOOL" init
expect "the copied tool passes check on its own folder"     0 python3 "$J/_judgment.py" check
expect "the copied tool lists the scenario roster"          0 python3 "$J/_judgment.py" scenarios

cp "$J/01_choose.md" "$WORK/keep.md"
printf '\n### CH03 - a row written without a rule\n\n- **Decider**: agent\n- **Strength**: A\n- **Source**: owner decision 2026-01-01 (n=1)\n' >> "$J/01_choose.md"
python3 "$J/_judgment.py" toc >/dev/null 2>&1
expect "a row with no Rule and an unchecked A fails check"  1 python3 "$J/_judgment.py" check
cp "$WORK/keep.md" "$J/01_choose.md"
expect "after the row is removed check passes again"        0 python3 "$J/_judgment.py" check

sed 's/^### CH01 .*/### CH01 - a scene that was renamed by hand/' "$WORK/keep.md" > "$J/01_choose.md"
expect "a renamed scene fails toc --check"                  1 python3 "$J/_judgment.py" toc --check
expect "the same drift fails check"                         1 python3 "$J/_judgment.py" check
expect "toc regenerates the table of contents"              0 python3 "$J/_judgment.py" toc
expect "after toc, check passes"                            0 python3 "$J/_judgment.py" check

mv "$J/15_allocate.md" "$WORK/moved.md"
expect "a category that INDEX.md lists but is gone fails"   1 python3 "$J/_judgment.py" check
mv "$WORK/moved.md" "$J/15_allocate.md"
expect "after it is put back check passes"                  0 python3 "$J/_judgment.py" check

expect "measure refuses to run without the plugin path"     2 python3 "$J/_judgment.py" measure --arms with --n 1

echo
echo "Work folder kept: $WORK"
echo "selftest.sh: part 1 exit $P1 / part 2 ok $OK, FAIL $FAIL"
[ "$P1" = "0" ] && [ "$FAIL" = "0" ]
