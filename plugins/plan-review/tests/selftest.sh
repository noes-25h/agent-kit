#!/bin/bash
# Structure check for plan-review.
# Reads the manifests, the skill, the two reviewer definitions, and the sample plan, and checks
# that they have the shape Claude Code loads and that the names line up with each other.
#
# A full pass here only tells you that the files are well formed.
# It does not tell you that Claude Code starts the reviewers, and it does not tell you that the
# reviewers find anything. This plugin is prompts. The only check of what the prompts do is
# tests/live-check.sh, which runs a real review on a plan with three planted flaws.
#
# Usage: bash tests/selftest.sh     exit 0 = all passed / 1 = at least one check failed
# Needs: bash, jq, grep, sed, awk

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0; FAIL=0
command -v jq >/dev/null 2>&1 || { echo "jq was not found. Install jq and run this again."; exit 1; }

ok()  { PASS=$((PASS+1)); echo "  ok   $1"; }
ng()  { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
check() { if [ "$1" = "0" ]; then ok "$2"; else ng "$2"; fi; }

# --- the record. If you change the definitions on purpose, change these lines to match. ---
PR_PLUGIN="plan-review"
PR_SKILL="plan-review"
PR_AGENTS="adversarial-reviewer best-path-reviewer"
PR_EXPECT_MODEL_adversarial_reviewer="sonnet"
PR_EXPECT_MODEL_best_path_reviewer="opus"
PR_EXPECT_EFFORT="high"
PR_EXPECT_FLAWS=3
# ------------------------------------------------------------------------------------------

SKILL="$ROOT/skills/$PR_SKILL/SKILL.md"
FIX="$ROOT/tests/fixtures"
COUNT="$ROOT/tests/lib/count-flaws.sh"

# Frontmatter helpers. The opening --- must be the first line of the file.
fm_open()   { [ "$(head -n 1 "$1" 2>/dev/null)" = "---" ]; }
fm_closed() { [ "$(grep -c '^---[[:space:]]*$' "$1" 2>/dev/null)" -ge 2 ]; }
fm()        { awk 'NR==1{ if ($0 != "---") exit; next } /^---[[:space:]]*$/{ exit } { print }' "$1"; }
body()      { awk 'NR==1 && $0=="---"{ infm=1; next } infm && /^---[[:space:]]*$/{ infm=0; next } !infm{ print }' "$1"; }
fmval()     { fm "$1" | sed -n "s/^$2:[[:space:]]*//p" | head -n 1 | sed -e 's/^"//' -e 's/"[[:space:]]*$//' -e 's/[[:space:]]*$//'; }
fmhas()     { fm "$1" | grep -q "^$2:"; }
has_item()  { printf '%s' "$1" | tr ',' '\n' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | grep -qx "$2"; }
ascii_only() { ! LC_ALL=C grep -q '[^[:print:][:space:]]' "$1"; }

echo "[1] manifests"
PJ="$ROOT/.claude-plugin/plugin.json"
jq -e . "$PJ" >/dev/null 2>&1; check $? "plugin.json parses"
[ "$(jq -r '.name // empty' "$PJ" 2>/dev/null)" = "$PR_PLUGIN" ]; check $? "plugin.json name is $PR_PLUGIN (every component is namespaced under it)"
jq -e '(.version | type == "string") and (.description | type == "string")' "$PJ" >/dev/null 2>&1; check $? "plugin.json has version and description"
jq -e '(has("agents") or has("skills") or has("commands")) | not' "$PJ" >/dev/null 2>&1; check $? "plugin.json does not replace the default agents/ and skills/ folders"
MJ="$ROOT/../../.claude-plugin/marketplace.json"
if [ -f "$MJ" ]; then
  jq -e . "$MJ" >/dev/null 2>&1; check $? "marketplace.json parses"
  src=$(jq -r --arg n "$PR_PLUGIN" '.plugins[]? | select(.name == $n) | .source' "$MJ" 2>/dev/null)
  [ -n "$src" ] && [ -f "$ROOT/../../$src/.claude-plugin/plugin.json" ]; check $? "marketplace.json lists $PR_PLUGIN and its source folder holds a plugin.json"
else
  echo "  skip marketplace.json (not next to this copy of the plugin; this is normal for an installed copy)"
fi

echo "[2] the two reviewer definitions"
models=""
for a in $PR_AGENTS; do
  f="$ROOT/agents/$a.md"
  [ -f "$f" ] || { ng "$a: agents/$a.md is missing"; continue; }
  fm_open "$f" && fm_closed "$f"; check $? "$a: frontmatter opens on the first line and is closed"
  [ "$(fmval "$f" name)" = "$a" ]; check $? "$a: name in the frontmatter equals the file name"
  case "$(fmval "$f" name)" in *:*|-*) ng "$a: name contains ':' or starts with '-'" ;; *) ok "$a: name has no ':' (reserved for the plugin prefix)" ;; esac
  [ -n "$(fmval "$f" description)" ]; check $? "$a: description is present"
  m=$(fmval "$f" model); models="$models $m"
  eval "want=\$PR_EXPECT_MODEL_$(printf '%s' "$a" | tr '-' '_')"
  [ -n "$m" ] && [ "$m" = "$want" ]; check $? "$a: model is fixed in the definition and matches the record ($want)"
  printf '%s' "$m" | grep -qE '^(sonnet|opus|haiku|fable|inherit|claude-[a-z0-9.-]+)$'; check $? "$a: model is a value Claude Code accepts"
  [ "$(fmval "$f" effort)" = "$PR_EXPECT_EFFORT" ]; check $? "$a: effort is fixed in the definition and matches the record ($PR_EXPECT_EFFORT)"
  printf '%s' "$(fmval "$f" effort)" | grep -qE '^(low|medium|high|xhigh|max)$'; check $? "$a: effort is a value Claude Code accepts"
  has_item "$(fmval "$f" disallowedTools)" Agent; check $? "$a: disallowedTools contains Agent (the reviewer cannot start subagents)"
  for t in Write Edit NotebookEdit; do
    has_item "$(fmval "$f" disallowedTools)" "$t"; check $? "$a: disallowedTools contains $t"
  done
  tools=$(fmval "$f" tools)
  [ -n "$tools" ] && ! has_item "$tools" Agent && ! has_item "$tools" Write && ! has_item "$tools" Edit; check $? "$a: tools is an explicit list with no Agent, Write, or Edit"
  has_item "$tools" Read; check $? "$a: tools contains Read"
  bad=""; for k in hooks mcpServers permissionMode initialPrompt; do fmhas "$f" "$k" && bad="$bad $k"; done
  [ -z "$bad" ]; check $? "$a: no field that Claude Code ignores for plugin subagents${bad:+ (found:$bad)}"
  unknown=$(fm "$f" | sed -n 's/^\([A-Za-z][A-Za-z-]*\):.*/\1/p' | grep -vxE 'name|description|model|effort|tools|disallowedTools|maxTurns|skills|memory|background|omitClaudeMd|isolation|color|experimental' | tr '\n' ' ')
  [ -z "$unknown" ]; check $? "$a: every frontmatter field is one Claude Code knows${unknown:+ (unknown: $unknown)}"
  body "$f" | grep -q '^## What to look for'; check $? "$a: has the section \"What to look for\""
  body "$f" | grep -q '^## How to report'; check $? "$a: has the section \"How to report\""
  body "$f" | grep -q 'Do not start subagents'; check $? "$a: the body also says not to start subagents"
  body "$f" | grep -q 'Do not change any file'; check $? "$a: the body says not to change files (Bash cannot be limited by the tool list)"
  body "$f" | sed -n '/^## How to report/,$p' | grep -q 'falsifier'; check $? "$a: the report format asks for a falsifier"
  body "$f" | sed -n '/^## How to report/,$p' | grep -qE 'at most [0-9]+ words'; check $? "$a: the report format has a length limit"
  lenses=$(body "$f" | sed -n '/^## What to look for/,/^## How to report/p' | grep -cE '^[0-9]+\. ')
  [ "$lenses" -ge 5 ] 2>/dev/null; check $? "$a: at least five numbered lenses (found $lenses)"
  ascii_only "$f"; check $? "$a: plain ASCII only"
  ! grep -q '!' "$f"; check $? "$a: no exclamation mark"
done
set -- $models
[ "$#" = "2" ] && [ "$1" != "$2" ]; check $? "the two reviewers run on different models"
extra=$(ls "$ROOT/agents" 2>/dev/null | grep -c '\.md$')
[ "$extra" = "2" ]; check $? "agents/ holds exactly the two definitions (found $extra .md files; every .md file there is loaded as an agent)"

echo "[3] the skill"
if [ -f "$SKILL" ]; then
  fm_open "$SKILL" && fm_closed "$SKILL"; check $? "SKILL.md: frontmatter opens on the first line and is closed"
  [ "$(fmval "$SKILL" name)" = "$PR_SKILL" ]; check $? "SKILL.md: name is $PR_SKILL (the command is /$PR_PLUGIN:$PR_SKILL)"
  d=$(fmval "$SKILL" description)
  [ -n "$d" ] && [ "${#d}" -le 1536 ]; check $? "SKILL.md: description is present and within the 1,536 character listing limit (${#d})"
  printf '%s' "$(fmval "$SKILL" effort)" | grep -qE '^(low|medium|high|xhigh|max)$'; check $? "SKILL.md: effort is a value Claude Code accepts"
  for s in "When to run" "Steps" "Limits"; do
    body "$SKILL" | grep -q "^## $s"; check $? "SKILL.md: has the section \"$s\""
  done
  steps=$(body "$SKILL" | sed -n '/^## Steps/,/^## Limits/p' | grep -cE '^[0-9]+\. \*\*')
  [ "$steps" = "4" ]; check $? "SKILL.md: four numbered steps (found $steps)"
  for a in $PR_AGENTS; do
    grep -q "subagent_type: $PR_PLUGIN:$a" "$SKILL"; check $? "SKILL.md: starts $PR_PLUGIN:$a by its plugin-scoped name"
  done
  # Every scoped name the skill mentions must resolve to a definition in agents/
  unresolved=""
  for ref in $(grep -oE "subagent_type: [A-Za-z0-9_-]+(:[A-Za-z0-9_-]+)*" "$SKILL" | sed 's/^subagent_type: //' | sort -u); do
    pfx="${ref%%:*}"; nm="${ref#*:}"
    if [ "$pfx" = "$ref" ] || [ "$pfx" != "$(jq -r '.name // empty' "$PJ" 2>/dev/null)" ] || [ ! -f "$ROOT/agents/$nm.md" ] || [ "$(fmval "$ROOT/agents/$nm.md" name)" != "$nm" ]; then
      unresolved="$unresolved $ref"
    fi
  done
  [ -z "$unresolved" ]; check $? "SKILL.md: every subagent_type resolves to <plugin name>:<agent name>${unresolved:+ (unresolved:$unresolved)}"
  grep -q 'Do not pass `model` or `effort`' "$SKILL"; check $? "SKILL.md: says not to pass model or effort in the call"
  grep -q 'in one message' "$SKILL"; check $? "SKILL.md: says to start both reviewers in one message"
  for r in adopt rebut defer escalate; do
    grep -q "\*\*$r\*\*" "$SKILL"; check $? "SKILL.md: has the ruling \"$r\""
  done
  grep -q 'No finding is dropped without a ruling' "$SKILL"; check $? "SKILL.md: says no finding is dropped without a ruling"
  grep -q '^   ## Adversarial review (' "$SKILL" && grep -q '^   ## Best-path review (' "$SKILL"; check $? "SKILL.md: gives the two headings to append to the plan file"
  grep -q 'Do not tell the reviewers how the plan came about' "$SKILL"; check $? "SKILL.md: says not to pass the history to the reviewers"
  ascii_only "$SKILL"; check $? "SKILL.md: plain ASCII only"
  ! grep -q '!' "$SKILL"; check $? "SKILL.md: no exclamation mark"
else
  ng "skills/$PR_SKILL/SKILL.md is missing"
fi

echo "[4] nothing left that only works inside 25h"
for f in "$SKILL" "$ROOT/agents/"*.md; do
  [ -f "$f" ] || continue
  n=$(grep -c '\[\[' "$f")
  [ "$n" = "0" ]; check $? "$(basename "$f"): no pointer to a 25h file or term (found $n lines)"
done

echo "[5] the sample plan and the counter"
PLAN="$FIX/flawed-plan.md"; TSV="$FIX/flaws.tsv"
[ -f "$PLAN" ] && [ -f "$TSV" ] && [ -f "$COUNT" ]; check $? "flawed-plan.md, flaws.tsv, and count-flaws.sh are present"
rows=$(grep -vcE '^(#|$)' "$TSV" 2>/dev/null)
[ "$rows" = "$PR_EXPECT_FLAWS" ]; check $? "flaws.tsv lists $PR_EXPECT_FLAWS flaws (found $rows)"
PLAN_LOWER=$(tr '[:upper:]' '[:lower:]' < "$PLAN" 2>/dev/null)
while IFS=$'\t' read -r id anchor subject problem desc; do
  case "$id" in ''|'#'*) continue ;; esac
  [ -n "$anchor" ] && printf '%s' "$PLAN_LOWER" | grep -qF -e "$anchor"; check $? "flaw $id is still planted in flawed-plan.md"
  [ -n "$desc" ]; check $? "flaw $id has a description"
done < "$TSV"
! grep -qiE 'checksum|sha[0-9]*sum|md5|verif' "$FIX/reference/backup.sh" 2>/dev/null && [ -f "$FIX/reference/backup.sh" ]; check $? "reference/backup.sh has no checksum step (the first flaw is real)"
grep -q '40 GB' "$FIX/reference/ops-notes.md" 2>/dev/null && grep -q '20 Mbit/s' "$FIX/reference/ops-notes.md" 2>/dev/null; check $? "reference/ops-notes.md holds the two numbers of the second flaw"
s3=$(grep -nE '^3\. Delete' "$PLAN" | cut -d: -f1); s4=$(grep -nE '^4\. Run the new job' "$PLAN" | cut -d: -f1)
[ -n "$s3" ] && [ -n "$s4" ] && [ "$s3" -lt "$s4" ]; check $? "in flawed-plan.md the delete step comes ahead of the first run (the third flaw is real)"
! grep -qiE 'planted|on purpose|flaws\.tsv|live-check|sample' "$PLAN" "$FIX/reference/"* 2>/dev/null; check $? "the plan and its material do not tell the reviewers that this is a test"

out=$(bash "$COUNT" "$TSV" "$FIX/sample-review-hit.txt" 2>&1); rc=$?
[ "$rc" = "0" ] && printf '%s\n' "$out" | grep -qx "found $PR_EXPECT_FLAWS of $PR_EXPECT_FLAWS"; check $? "counter: a review that names all the flaws scores $PR_EXPECT_FLAWS of $PR_EXPECT_FLAWS"
out=$(bash "$COUNT" "$TSV" "$FIX/sample-review-miss.txt" 2>&1); rc=$?
[ "$rc" = "0" ] && printf '%s\n' "$out" | grep -qx "found 0 of $PR_EXPECT_FLAWS"; check $? "counter: a review that only names the subjects scores 0"
out=$(bash "$COUNT" "$TSV" "$PLAN" 2>&1); rc=$?
[ "$rc" = "0" ] && printf '%s\n' "$out" | grep -qx "found 0 of $PR_EXPECT_FLAWS"; check $? "counter: the plan itself scores 0 (quoting the plan does not count as finding a flaw)"
out=$(bash "$COUNT" "$TSV" "$SKILL" 2>&1); rc=$?
[ "$rc" = "0" ] && printf '%s\n' "$out" | grep -qx "found 0 of $PR_EXPECT_FLAWS"; check $? "counter: unrelated text scores 0"
bash "$COUNT" "$TSV" "$FIX/does-not-exist.txt" >/dev/null 2>&1; [ "$?" = "2" ]; check $? "counter: a missing file is \"could not count\", not 0 found"

echo "[6] live-check.sh"
LC="$ROOT/tests/live-check.sh"
[ -f "$LC" ] && bash -n "$LC" 2>/dev/null; check $? "live-check.sh is present and parses"
for a in $PR_AGENTS; do
  grep -q "$PR_PLUGIN:$a" "$LC" 2>/dev/null; check $? "live-check.sh looks for $PR_PLUGIN:$a"
done
# The scoring is tried on a hand-written recorded session (fixtures/sample-run). This checks the
# arithmetic of the scoring. It says nothing about what a real session records.
# The sample is kept as run.ndjson. live-check.sh reads run.jsonl in its work folder, so each copy
# below is written under that name.
SAMPLE="$FIX/sample-run/run.ndjson"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/plan-review-selftest.XXXXXX" 2>/dev/null) || TMP=""
if [ -n "$TMP" ] && [ -f "$SAMPLE" ] && [ -f "$FIX/sample-run/plan.md" ]; then
  mkdir -p "$TMP/good" "$TMP/barename" "$TMP/model" "$TMP/notrace" "$TMP/unfinished" "$TMP/oneflaw"
  for d in good barename model notrace unfinished oneflaw; do cp "$SAMPLE" "$TMP/$d/run.jsonl"; cp "$FIX/sample-run/plan.md" "$TMP/$d/"; done
  out=$(bash "$LC" --replay "$TMP/good" 2>&1); rc=$?
  [ "$rc" = "0" ]; check $? "scoring: the sample session scores as working (exit $rc)"
  printf '%s\n' "$out" | grep -q 'adversarial (.*): found 2 of 3' && printf '%s\n' "$out" | grep -q 'best-path (.*): found 1 of 3' && printf '%s\n' "$out" | grep -qx '  found 3 of 3'
  check $? "scoring: reports are read per reviewer (2 of 3, 1 of 3, together 3 of 3)"
  printf '%s\n' "$out" | grep -q 'both starts are in the same message'; check $? "scoring: sees that both reviewers were started in one message"
  sed 's/"subagent_type":"plan-review:best-path-reviewer"/"subagent_type":"best-path-reviewer"/' "$SAMPLE" > "$TMP/barename/run.jsonl"
  bash "$LC" --replay "$TMP/barename" >/dev/null 2>&1; rc=$?
  [ "$rc" = "1" ]; check $? "scoring: a reviewer started without the plugin prefix is \"not working\" (exit $rc)"
  sed 's/"subagent_type":"plan-review:adversarial-reviewer",/"subagent_type":"plan-review:adversarial-reviewer","model":"haiku",/' "$SAMPLE" > "$TMP/model/run.jsonl"
  bash "$LC" --replay "$TMP/model" >/dev/null 2>&1; rc=$?
  [ "$rc" = "1" ]; check $? "scoring: a start that passes a model is \"not working\" (exit $rc)"
  grep -v '^## Best-path review (' "$FIX/sample-run/plan.md" > "$TMP/notrace/plan.md"
  bash "$LC" --replay "$TMP/notrace" >/dev/null 2>&1; rc=$?
  [ "$rc" = "1" ]; check $? "scoring: a plan file without both review sections is \"not working\" (exit $rc)"
  grep -v '"type":"result"' "$SAMPLE" > "$TMP/unfinished/run.jsonl"
  bash "$LC" --replay "$TMP/unfinished" >/dev/null 2>&1; rc=$?
  [ "$rc" = "2" ]; check $? "scoring: a session that did not reach the end is \"cannot tell\" (exit $rc)"
  sed 's/Swap steps 3 and 4\. Step 3 removes the cron entry and the local archives before the new job has run once, and that cannot be undone\./Give the job a second recipient for its failure message, and write the name of that recipient into the ops notes./' "$SAMPLE" > "$TMP/oneflaw/run.jsonl"
  bash "$LC" --replay "$TMP/oneflaw" >/dev/null 2>&1; rc=$?
  [ "$rc" = "1" ]; check $? "scoring: a flaw named by neither reviewer is reported as missed (exit $rc)"
  # The same session as recorded when the reviewers end with SubagentHandback: the tool result is a
  # pointer, and the report is on handbackReport / handback_report
  HB="$FIX/sample-run/run-handback.ndjson"
  mkdir -p "$TMP/handback" "$TMP/pointer"
  cp "$HB" "$TMP/handback/run.jsonl"; cp "$FIX/sample-run/plan.md" "$TMP/handback/"
  out=$(bash "$LC" --replay "$TMP/handback" 2>&1); rc=$?
  [ "$rc" = "0" ] && printf '%s\n' "$out" | grep -q 'adversarial (.*): found 2 of 3' && printf '%s\n' "$out" | grep -q 'best-path (.*): found 1 of 3'
  check $? "scoring: a report handed back with SubagentHandback is read from the handback (exit $rc)"
  jq -c 'del(.tool_use_result.handbackReport) | del(.handback_report)' "$HB" > "$TMP/pointer/run.jsonl"; cp "$FIX/sample-run/plan.md" "$TMP/pointer/"
  bash "$LC" --replay "$TMP/pointer" >/dev/null 2>&1; rc=$?
  [ "$rc" = "2" ]; check $? "scoring: a pointer to a handback that was not recorded is \"cannot tell\", not a miss (exit $rc)"
  # A reviewer that ran in the background: the tool result only says it was launched, and the report
  # is the summary of the task notification
  mkdir -p "$TMP/background"
  jq -c 'if .handback_report then .summary = .handback_report.text else . end | del(.tool_use_result.handbackReport) | del(.handback_report)' "$HB" > "$TMP/background/run.jsonl"; cp "$FIX/sample-run/plan.md" "$TMP/background/"
  out=$(bash "$LC" --replay "$TMP/background" 2>&1); rc=$?
  [ "$rc" = "0" ] && printf '%s
' "$out" | grep -q 'adversarial (.*): found 2 of 3' && printf '%s
' "$out" | grep -q 'best-path (.*): found 1 of 3'
  check $? "scoring: a report from a background reviewer is read from the task notification (exit $rc)"
  # The work folder is left in the OS temp area (it holds only copies of the sample session)
else
  ng "could not create a temp folder, or fixtures/sample-run is missing"
fi

echo
echo "Result: ok $PASS / FAIL $FAIL"
[ "$FAIL" = "0" ] || exit 1
echo "The files are well formed. Whether the reviewers start and what they find can only be seen with tests/live-check.sh."
