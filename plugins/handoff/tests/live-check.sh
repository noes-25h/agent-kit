#!/bin/bash
# Run the handoff skill in a real Claude Code session and count the expected points it meets.
#
# Copies the fixture repo (a migration that stopped at 2 of 5, with one undecided item and one
# small one-off) into an empty work folder twice. session-notes.md stands in for the conversation
# history of the session that stopped.
#   with      claude -p "/handoff:handoff --plans-dir handoff --tasks-file TODO.md ...", plugin loaded with --plugin-dir
#   without   claude -p with a plain request for the same handoff, no plugin
# The files each run wrote and its final reply are scored against tests/fixtures/stopped-session/expected.tsv.
#
# What the number means: how many keyword patterns were matched. It is not a judgment of whether
# the next session could actually run the sheet, and one run is one sample.
#
# STATUS: run to the end against a real session once, on 2026-10-19 with Claude Code 2.1.303
# (exit 0). The scoring half is also exercised by selftest.sh with hand-written files.
#
# Usage: bash tests/live-check.sh
# Needs: claude (logged in), jq. It calls Claude Code twice and uses that much of your usage allowance.
# Exit code: 0 = the with-plugin run met MIN points or more / 1 = fewer / 2 = cannot tell

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIX="$ROOT/tests/fixtures/stopped-session"
SKILL_CMD="handoff:handoff"
command -v claude >/dev/null 2>&1 || { echo "claude was not found."; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "jq was not found."; exit 2; }
. "$ROOT/tests/lib/score.sh" || { echo "Could not load tests/lib/score.sh."; exit 2; }
MIN=$(score_min "$FIX/expected.tsv"); [ -n "$MIN" ] || { echo "expected.tsv has no MIN line."; exit 2; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/handoff-live.XXXXXX") || { echo "Could not create a work folder."; exit 2; }
for arm in with without; do
  mkdir -p "$WORK/$arm" && cp -R "$FIX/repo" "$WORK/$arm/repo" || { echo "Could not copy the fixture."; exit 2; }
done

P_WITH="/$SKILL_CMD --plans-dir handoff --tasks-file TODO.md The record of the session that stopped is session-notes.md. Treat it as the history of this session."
P_WITHOUT='session-notes.md is the record of a session that stopped partway. Write what the next session needs in order to continue, as a file under handoff/, and put anything that needs a decision in TODO.md. Do not do the remaining work yourself.'

# The files that a handoff must leave alone
sums() { (cd "$1" && find services README.md test.sh -type f -exec cksum {} + | sort); }

# arm prompt
run() {
  local arm="$1" prompt="$2" out="$WORK/$1/run.jsonl"
  local -a cmd=(claude -p "$prompt" --output-format stream-json --verbose --allowedTools "Read,Grep,Glob,Write,Edit")
  [ "$arm" = "with" ] && cmd+=(--plugin-dir "$ROOT")
  sums "$WORK/$arm/repo" > "$WORK/$arm/before.sums"
  if command -v perl >/dev/null 2>&1; then
    (cd "$WORK/$arm/repo" && perl -e 'alarm shift; exec @ARGV' 600 "${cmd[@]}" >"$out" 2>"$out.err" </dev/null)
  else
    (cd "$WORK/$arm/repo" && "${cmd[@]}" >"$out" 2>"$out.err" </dev/null)
  fi
  sums "$WORK/$arm/repo" > "$WORK/$arm/after.sums"
}

# Did the run reach the end (a result was emitted and it is not an error)?
finished() { jq -es 'map(select(.type == "result")) | last | (. != null and (.is_error | not))' "$1" >/dev/null 2>&1; }
# The final reply
reply() { jq -rs 'map(select(.type == "result")) | last | .result // ""' "$1" 2>/dev/null; }
# Was the plugin skill known to the session? The start-up message is searched as text for the command name.
listed() { jq -c 'select(.type == "system" and .subtype == "init")' "$1" 2>/dev/null | grep -qF -e "$SKILL_CMD"; }

echo "Work folder: $WORK"
echo "Calling Claude Code twice (this can take several minutes)..."
run with "$P_WITH"
run without "$P_WITHOUT"

for arm in with without; do
  if ! finished "$WORK/$arm/run.jsonl"; then
    echo "Cannot tell: the $arm run did not reach the end (check login, usage allowance, network; log = $WORK/$arm/run.jsonl)"
    exit 2
  fi
  reply "$WORK/$arm/run.jsonl" > "$WORK/$arm/reply.txt"
  [ -s "$WORK/$arm/reply.txt" ] || { echo "Cannot tell: the $arm run ended with an empty reply."; exit 2; }
done
if ! listed "$WORK/with/run.jsonl"; then
  echo "Cannot tell: the session did not list /$SKILL_CMD at start-up, so the with-plugin run may not have used the skill."
  exit 2
fi
listed "$WORK/without/run.jsonl" && echo "Note: the without-plugin run also lists /$SKILL_CMD. The plugin is installed on this machine, so the two runs are not a clean comparison."

echo
echo "Claude Code: $(claude --version 2>/dev/null | head -1)"
for arm in with without; do
  CH=1; cmp -s "$WORK/$arm/before.sums" "$WORK/$arm/after.sums" && CH=0
  echo
  echo "[$arm plugin]"
  score_points "$FIX/expected.tsv" "$WORK/$arm/reply.txt" "$WORK/$arm/repo" "$CH"
  echo "  points met: $SCORE_MET of $SCORE_TOTAL"
  [ "$arm" = "with" ] && W_MET=$SCORE_MET
  [ "$arm" = "without" ] && N_MET=$SCORE_MET
done

echo
echo "with plugin: $W_MET / without plugin: $N_MET / MIN: $MIN"
echo "The without-plugin number is there for comparison. A capable model meets several points with no skill at all."
echo "Replies, written files, and logs are kept in $WORK. Read the instruction sheet; the count is keyword matching."
[ "$W_MET" -ge "$MIN" ] && exit 0
exit 1
