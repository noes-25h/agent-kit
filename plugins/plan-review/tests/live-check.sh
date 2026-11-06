#!/bin/bash
# Check plan-review against a real Claude Code session.
#
# Copies the sample plan (three planted flaws) and its material into an empty work folder, runs
# Claude Code once (claude -p) with this plugin, asks it to review the plan with the skill, and
# then reads the recorded session. It does not use Claude's own account of what happened.
#
#   wiring   were both reviewers started, by their plugin-scoped names, with no model passed?
#   flaws    how many of the three planted flaws does each reviewer's report name?
#   trace    did the plan file receive the two review sections?
#
# Usage: bash tests/live-check.sh               run a review and score it
#        bash tests/live-check.sh --replay DIR  score a run that is already recorded in DIR
#                                               (DIR holds run.jsonl and plan.md)
# Needs: claude (logged in), jq. One run starts one session and two reviewers (one on Sonnet,
#        one on Opus, both at high effort) and uses that much of your usage allowance.
# Exit code: 0 = wiring correct, every planted flaw named by at least one reviewer, trace present
#            1 = wiring wrong, or a flaw named by neither reviewer, or trace absent
#            2 = cannot tell
#
# The flaw count is a keyword count (see tests/lib/count-flaws.sh). Read the reports in the work
# folder before you rely on it. One run is one sample: a model can miss a flaw on one run and
# name it on the next.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIX="$ROOT/tests/fixtures"
COUNT="$ROOT/tests/lib/count-flaws.sh"
ADV="plan-review:adversarial-reviewer"
BEST="plan-review:best-path-reviewer"
command -v jq >/dev/null 2>&1 || { echo "jq was not found."; exit 2; }

if [ "$1" = "--replay" ]; then
  WORK="$2"
  [ -f "$WORK/run.jsonl" ] && [ -f "$WORK/plan.md" ] || { echo "Cannot tell: $WORK does not hold run.jsonl and plan.md."; exit 2; }
  echo "Scoring the recorded run in $WORK (Claude Code is not called)."
else
  command -v claude >/dev/null 2>&1 || { echo "claude was not found."; exit 2; }
  WORK=$(mktemp -d "${TMPDIR:-/tmp}/plan-review-live.XXXXXX") || { echo "Could not create a work folder."; exit 2; }
  mkdir -p "$WORK/reference"
  cp "$FIX/flawed-plan.md" "$WORK/plan.md" && cp "$FIX/reference/"* "$WORK/reference/" || { echo "Could not copy the sample plan."; exit 2; }
  PROMPT='Use the plan-review:plan-review skill to review the plan in ./plan.md. The material the plan must agree with is in ./reference/. Record the rulings in ./plan.md as the skill describes. Do not ask me anything: where the skill says to escalate, write the question under the rulings instead.'
  echo "Work folder: $WORK"
  echo "Running one review with two reviewers (this takes several minutes)..."
  CMD=(claude -p "$PROMPT" --output-format stream-json --verbose --plugin-dir "$ROOT" --allowedTools "Skill,Agent,Read,Grep,Glob,Edit")
  if command -v perl >/dev/null 2>&1; then
    (cd "$WORK" && perl -e 'alarm shift; exec @ARGV' 1200 "${CMD[@]}" >"$WORK/run.jsonl" 2>"$WORK/run.err" </dev/null)
  else
    (cd "$WORK" && "${CMD[@]}" >"$WORK/run.jsonl" 2>"$WORK/run.err" </dev/null)
  fi
fi
RUN="$WORK/run.jsonl"

# Did the run reach the end (a result was emitted and it is not an error)?
jq -es 'map(select(.type == "result")) | last | (. != null and (.is_error | not))' "$RUN" >/dev/null 2>&1 \
  || { echo "Cannot tell: the run did not reach the end (check login, usage allowance, network; log = $RUN)"; exit 2; }

# Reviewer starts made by the main session: message id, tool_use id, subagent_type, model, effort
jq -r 'select(.type == "assistant" and (.parent_tool_use_id == null)) | .message.id as $m
       | .message.content[]? | select(.type == "tool_use" and (.name == "Agent" or .name == "Task"))
       | [$m, .id, (.input.subagent_type // "-"), (.input.model // "-"), (.input.effort // "-")] | @tsv' "$RUN" > "$WORK/starts.tsv" 2>/dev/null

# The report that came back for one tool_use id.
# A reviewer that ends with SubagentHandback (Claude Code 2.1.303 and later) hands its report over
# out of band: the tool result then holds only a short pointer ("This agent's report was delivered
# to you as a message ..."), and the report itself is recorded as handbackReport on that tool
# result and as handback_report on the task notification. The handback is read first.
# A reviewer that runs in the background (seen on Claude Code 2.1.314) returns only "Async agent
# launched" as its tool result, and its report is the summary of the task notification.
# The text of the tool result is the fallback for sessions with neither.
report() {
  local hb
  hb=$(jq -rs --arg id "$1" '
        ( [ .[] | select(.type == "user" and .tool_use_result != null)
                | select(any(.message.content[]?; .type == "tool_result" and .tool_use_id == $id))
                | (.tool_use_result.handbackReport.text? // empty) ]
        + [ .[] | select(.type == "system" and .subtype == "task_notification" and .tool_use_id == $id)
                | (.handback_report.text? // empty) ] )
        | map(select(type == "string" and length > 0)) | first // empty' "$RUN" 2>/dev/null)
  if [ -n "$hb" ]; then printf '%s\n' "$hb"; return; fi
  local nt
  nt=$(jq -rs --arg id "$1" '[ .[] | select(.type == "system" and .subtype == "task_notification" and .tool_use_id == $id)
                               | (.summary? // empty) ] | map(select(type == "string" and length > 0)) | first // empty' "$RUN" 2>/dev/null)
  if [ -n "$nt" ]; then printf '%s\n' "$nt"; return; fi
  jq -r --arg id "$1" 'select(.type == "user") | .message.content[]? | select(.type == "tool_result" and .tool_use_id == $id)
         | (.content | if type == "array" then (map(.text? // "") | join("\n")) else tostring end)' "$RUN" 2>/dev/null
}
# A tool result that only points at a handed-back report the session did not record
is_pointer() { grep -q "report was delivered to you as a message" "$1"; }
starts_of() { awk -F'\t' -v t="$1" '$3 == t' "$WORK/starts.tsv"; }

RC=0; UNDECIDED=0
N_ADV=$(starts_of "$ADV" | grep -c .); N_BEST=$(starts_of "$BEST" | grep -c .)
N_OTHER=$(awk -F'\t' -v a="$ADV" -v b="$BEST" '$3 != a && $3 != b' "$WORK/starts.tsv" | grep -c .)
N_MODEL=$(awk -F'\t' '$4 != "-" || $5 != "-"' "$WORK/starts.tsv" | grep -c .)
MSG_ADV=$(starts_of "$ADV" | head -n 1 | cut -f1); MSG_BEST=$(starts_of "$BEST" | head -n 1 | cut -f1)

echo
echo "Claude Code: $(claude --version 2>/dev/null | head -n 1)"
echo "wiring"
echo "  starts of $ADV:  $N_ADV"
echo "  starts of $BEST:    $N_BEST"
echo "  starts of any other subagent:                $N_OTHER"
echo "  starts that passed a model or an effort:     $N_MODEL"
if [ "$N_ADV" -ge 1 ] && [ "$N_BEST" -ge 1 ]; then echo "  both reviewers were started by their plugin-scoped names"
else echo "  NOT working: a reviewer was never started by its plugin-scoped name"; RC=1; fi
if [ "$N_MODEL" = "0" ]; then echo "  no start overrode the model or the effort of a definition"
else echo "  NOT working: a start passed a model or an effort, which overrides the definition"; RC=1; fi
if [ -n "$MSG_ADV" ] && [ "$MSG_ADV" = "$MSG_BEST" ]; then echo "  both starts are in the same message (started together)"
else echo "  the two starts are not in the same message, or the message ids could not be read (reported only, not scored)"; fi

echo "flaws (planted: $(grep -vcE '^(#|$)' "$FIX/flaws.tsv"))"
: > "$WORK/report-both.txt"
for pair in "adversarial:$ADV" "best-path:$BEST"; do
  label="${pair%%:*}"; type="${pair#*:}"
  : > "$WORK/report-$label.txt"
  for id in $(starts_of "$type" | cut -f2); do report "$id" >> "$WORK/report-$label.txt"; done
  cat "$WORK/report-$label.txt" >> "$WORK/report-both.txt"
  size=$(wc -c < "$WORK/report-$label.txt" | tr -d ' ')
  if [ "$size" -lt 200 ]; then
    echo "  $label: cannot tell (the report that came back is $size bytes; the reviewer may have run in the background)"
    UNDECIDED=1
  elif is_pointer "$WORK/report-$label.txt"; then
    echo "  $label: cannot tell (the tool result points at a handed-back report that the session did not record)"
    UNDECIDED=1
  else
    echo "  $label ($size bytes): $(bash "$COUNT" "$FIX/flaws.tsv" "$WORK/report-$label.txt" | tail -n 1)"
  fi
done
BOTH=$(bash "$COUNT" "$FIX/flaws.tsv" "$WORK/report-both.txt"); BOTH_RC=$?
echo "  by at least one reviewer:"
printf '%s\n' "$BOTH" | sed 's/^/  /'
[ "$BOTH_RC" = "0" ] || UNDECIDED=1
if [ "$UNDECIDED" = "0" ]; then
  printf '%s\n' "$BOTH" | tail -n 1 | grep -qE '^found ([0-9]+) of \1$' || { echo "  a planted flaw was named by neither reviewer on this run"; RC=1; }
fi

echo "trace"
H_ADV=$(grep -c '^## Adversarial review (' "$WORK/plan.md"); H_BEST=$(grep -c '^## Best-path review (' "$WORK/plan.md")
echo "  \"## Adversarial review (\" headings in plan.md: $H_ADV"
echo "  \"## Best-path review (\" headings in plan.md:   $H_BEST"
if [ "$H_ADV" -ge 1 ] && [ "$H_BEST" -ge 1 ]; then
  echo "  both sections were appended to the plan file"
  sed -n '/^## Adversarial review (/,$p' "$WORK/plan.md" > "$WORK/trace.txt"
  echo "  rulings in the trace: adopt $(grep -oi 'adopt' "$WORK/trace.txt" | grep -c .), rebut $(grep -oi 'rebut' "$WORK/trace.txt" | grep -c .), defer $(grep -oi 'defer' "$WORK/trace.txt" | grep -c .), escalate $(grep -oi 'escalate' "$WORK/trace.txt" | grep -c .) (word counts, reported only)"
else
  echo "  NOT working: the plan file did not receive both review sections"; RC=1
fi

echo
echo "The reports and the recorded session are kept in $WORK."
if [ "$RC" = "1" ]; then exit 1; fi
if [ "$UNDECIDED" = "1" ]; then echo "Cannot tell: a reviewer report could not be read from the recorded session."; exit 2; fi
echo "On this run: wiring correct, every planted flaw named by at least one reviewer, trace present."
exit 0
