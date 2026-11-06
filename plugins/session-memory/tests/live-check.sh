#!/bin/bash
# Check session-memory against a real Claude Code session.
#
# Creates throwaway project folders, writes records that contain a code generated at run time,
# and runs Claude Code (claude -p) with every tool disabled. Claude can only know the code if the
# session-start hook delivered it, so the reply is evidence of delivery and not Claude's opinion.
#
#   arm "without"     records present, plugin not loaded    the code must NOT come back (control)
#   arm "with"        records present, plugin loaded        the code must come back
#   arm "with-large"  very large records, plugin loaded     the code on line 1 must come back,
#                                                           the code on line 4000 must not
#
# The third arm is the one that matters most. Hook output over 10,000 characters is replaced by
# Claude Code with a file path and a short preview. If the budget in this plugin were wrong,
# selftest would still pass and this arm would fail.
#
# The hook lines of each run are counted as well (--include-hook-events). When no hook of this plugin
# ran to the end, the result says nothing about the plugin, and the check ends with "cannot tell" and
# the reason. That is what a run from inside a sandbox looks like.
#
# Usage: bash tests/live-check.sh     (from a plain terminal, not from inside a Claude Code session)
# Needs: claude (logged in), jq. It calls Claude Code three times and uses that much of your usage allowance.
# Exit code: 0 = delivered (the hook ran and its output reached Claude)
#            1 = not delivered (the hook ran and its output did not reach Claude as it should)
#            2 = cannot tell (a run did not finish, the hook did not run, or the control is not a control)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v claude >/dev/null 2>&1 || { echo "claude was not found."; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "jq was not found."; exit 2; }

. "$ROOT/tests/hook-events.sh" 2>/dev/null || { echo "tests/hook-events.sh was not found."; exit 2; }
# Which hook lines belong to this plugin (see tests/hook-events.sh)
HE_PLUGIN='session-memory'
HE_NAME_RE='^SessionStart(:.*)?$'
HE_SIGN_RE='session-memory'
WORK=$(mktemp -d "${TMPDIR:-/tmp}/session-memory-live.XXXXXX") || { echo "Could not create a work folder."; exit 2; }
SEED="$(date +%s)$$"
CODE_A="SM-CANARY-A${SEED}"
CODE_B="SM-CANARY-B${SEED}"

for arm in without with; do
  mkdir -p "$WORK/$arm/.memory"
  printf '# Now\n\n- Goal: check delivery. The code is %s\n- Entry point: none\n' "$CODE_A" > "$WORK/$arm/.memory/now.md"
done
mkdir -p "$WORK/with-large/.memory/journal"
awk -v a="$CODE_A" -v b="$CODE_B" 'BEGIN {
  printf "- The code is %s\n", a
  for (i = 2; i <= 6000; i++) {
    if (i == 4000) printf "- The second code is %s\n", b
    else printf "- line %d filler filler filler filler filler filler filler filler filler\n", i
  }
}' > "$WORK/with-large/.memory/now.md"
awk 'BEGIN { print "# Decisions"; for (i = 1; i <= 3000; i++) printf "## 2026-01-01 decision %d with a title of ordinary length\n- Decided: x\n\n", i }' > "$WORK/with-large/.memory/decisions.md"
awk 'BEGIN { for (i = 1; i <= 3000; i++) printf "- [ ] task %d with a description of ordinary length\n", i }' > "$WORK/with-large/.memory/tasks.md"
awk 'BEGIN { print "### Next"; for (i = 1; i <= 2000; i++) printf "- next %d\n", i }' > "$WORK/with-large/.memory/journal/2026-01-12.md"

PROMPT='Do not use any tool. Look only at the context you were given before this message. If it contains one or more codes that start with SM-CANARY-, reply with every such code, one per line, and nothing else. If it contains none, reply with the single word NONE.'

run() {
  local arm="$1" out="$WORK/$1/run.jsonl"
  local -a cmd=(claude -p "$PROMPT" --output-format stream-json --verbose --include-hook-events --tools "")
  [ "$arm" != "without" ] && cmd+=(--plugin-dir "$ROOT")
  if command -v perl >/dev/null 2>&1; then
    (cd "$WORK/$arm" && perl -e 'alarm shift; exec @ARGV' 240 "${cmd[@]}" >"$out" 2>"$out.err" </dev/null)
  else
    (cd "$WORK/$arm" && "${cmd[@]}" >"$out" 2>"$out.err" </dev/null)
  fi
}

# Did the run reach the end (a result was emitted and it is not an error)?
finished() { jq -es 'map(select(.type == "result")) | last | (. != null and (.is_error | not))' "$1" >/dev/null 2>&1; }
# How many tool calls Claude made (must be 0, otherwise Claude could have read the file itself)
tool_calls() { jq -r 'select(.type == "assistant") | .message.content[]? | select(.type == "tool_use") | .name' "$1" 2>/dev/null | grep -c .; }
# Everything Claude said
said() {
  jq -r 'if .type == "assistant" then (.message.content[]? | select(.type == "text") | .text)
         elif .type == "result" then (.result // "" | tostring) else empty end' "$1" 2>/dev/null
}
count() { grep -oF -e "$1" | grep -c .; }

echo "Work folder: $WORK"
echo "Calling Claude Code three times (this takes a minute or two)..."
for arm in without with with-large; do run "$arm"; done

UNDECIDED=0
for arm in without with with-large; do
  f="$WORK/$arm/run.jsonl"
  if ! finished "$f"; then
    echo "Cannot tell: $arm did not run to the end (check login, usage allowance, network; log = $f)"
    UNDECIDED=1; continue
  fi
  if [ "$(tool_calls "$f")" != "0" ]; then
    echo "Cannot tell: $arm used a tool, so the reply does not show what the hook delivered (log = $f)"
    UNDECIDED=1
  fi
done
[ "$UNDECIDED" = "0" ] || exit 2

N_A=$(said "$WORK/without/run.jsonl" | count "$CODE_A")
W_A=$(said "$WORK/with/run.jsonl" | count "$CODE_A")
L_A=$(said "$WORK/with-large/run.jsonl" | count "$CODE_A")
L_B=$(said "$WORK/with-large/run.jsonl" | count "$CODE_B")
HOOK_BYTES=$(CLAUDE_PROJECT_DIR="$WORK/with-large" bash "$ROOT/scripts/inject.sh" </dev/null 2>/dev/null | LC_ALL=C wc -c | tr -d ' ')

echo
echo "Claude Code: $(claude --version 2>/dev/null | head -1)"
echo "                                             times the code came back"
echo "without plugin   code on line 1                    $N_A"
echo "with plugin      code on line 1                    $W_A"
echo "with plugin, large records   code on line 1        $L_A"
echo "with plugin, large records   code on line 4000     $L_B"
echo "size of the hook output for the large records: $HOOK_BYTES bytes"
he_scan "$HE_NAME_RE" "$HE_SIGN_RE" "$WORK/without/run.jsonl" -- "$WORK/with/run.jsonl" "$WORK/with-large/run.jsonl"
he_report "$HE_PLUGIN"
echo

RC=0
if [ "$N_A" = "0" ]; then
  echo "Control (without plugin): the code did not reach Claude = the instrument works."
else
  echo "Control (without plugin): the code reached Claude without the plugin."
  echo "If session-memory is already installed, or another hook or CLAUDE.md loads .memory/, that is why."
  echo "Cannot tell: with a control like this, the other rows prove nothing. No verdict is given."
  echo
  echo "Logs are kept in $WORK."
  exit 2
fi
he_gate 0
if [ "$?" = "2" ]; then
  he_explain_not_run "$HE_PLUGIN"
  echo
  echo "Logs are kept in $WORK."
  exit 2
fi
if [ "$W_A" -ge 1 ]; then echo "delivery: working (the hook ran and the snapshot reached Claude at session start)"
else echo "delivery: NOT working (the hook ran and the snapshot did not reach Claude)"; RC=1; fi
if [ "$L_A" -ge 1 ] && [ "$L_B" = "0" ]; then echo "large records: working (the top of the records reached Claude, the rest stayed in the files)"
elif [ "$L_A" = "0" ]; then echo "large records: NOT working (nothing from the large records reached Claude; the snapshot may be over the cap)"; RC=1
else echo "large records: NOT working (line 4000 reached Claude, so the snapshot is not a thin slice)"; RC=1; fi
he_gate "$RC"
if [ "$?" = "2" ] && [ "$RC" = "1" ]; then he_explain_mixed "$HE_PLUGIN"; RC=2; fi
echo
echo "Logs are kept in $WORK."
exit "$RC"
