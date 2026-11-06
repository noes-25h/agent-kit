#!/bin/bash
# Structure check for the handoff plugin.
#
# This product is a prompt. A script cannot tell whether a prompt works.
# What this check does see: the manifests load, the skill file has the frontmatter and the sections
# it is supposed to have, nothing tied to the 25h environment leaked in, and the fixture that
# live-check.sh scores against is well formed.
#
# A full pass here says the files are intact. It says nothing about what Claude does with them.
# For that, run tests/live-check.sh (it calls a real Claude Code session).
#
# Usage: bash tests/selftest.sh     exit 0 = all passed / 1 = at least one check failed
# Needs: bash, jq, grep, sed, awk

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLUGIN="handoff"
SKILL="handoff"
FIXTURE="stopped-session"
SKILL_FILE="$ROOT/skills/$SKILL/SKILL.md"
FIX="$ROOT/tests/fixtures/$FIXTURE"

# Headings the skill must have, each exactly once. The last six are the headings of the instruction sheet template.
REQUIRED_SECTIONS='## When to use
## When not to use
## Settings
## Step 1. Collect what is left
## Step 2. Sort each item into one of three exits
## Step 3A. Write the instruction sheet
## Step 3B. Write a standalone prompt
## Step 3C. Leave a note
## Step 4. Present on one page
## Rules
## 0. Re-check at start
## Stop conditions
## Not in this run
## Allowed and forbidden paths
## When to halt
## When finished'

# Sentences that carry a rule. If one is edited away, the behaviour changes without any heading changing.
REQUIRED_PHRASES='It does not edit anything else and does not carry out the remaining work.
Neither is present: do not create a file.
When in doubt, choose C.
If even one of them no longer holds, stop and report.
If a premise fails: do not decide how to repair it.
Negative test:
Starting the run is the user'"'"'s action.
Its first sentence is always a re-check:
The first sentence names what is not decided.
Do not leave out section 0.'

# Frontmatter keys that the Claude Code skills page lists (https://code.claude.com/docs/en/skills, "Frontmatter reference").
KNOWN_KEYS=' name description when_to_use argument-hint arguments disable-model-invocation user-invocable allowed-tools disallowed-tools model effort context agent background hooks paths shell metadata license compatibility '

# Words that belong to the environment this skill came from, plus wording the product does not use.
FORBIDDEN='\[\[|guarantee|never again|urgent|hurry|!'

PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); echo "  ok   $1"; }
ng() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }

command -v jq >/dev/null 2>&1 || { echo "jq was not found. Install jq and run this again."; exit 1; }
. "$ROOT/tests/lib/score.sh" 2>/dev/null || { echo "Could not load tests/lib/score.sh."; exit 1; }

echo "[1] manifests"
PJ="$ROOT/.claude-plugin/plugin.json"
if jq -e . "$PJ" >/dev/null 2>&1; then ok "plugin.json is valid JSON"; else ng "plugin.json is missing or is not valid JSON"; fi
[ "$(jq -r '.name // empty' "$PJ" 2>/dev/null)" = "$PLUGIN" ] && ok "plugin.json name is $PLUGIN" || ng "plugin.json name is not $PLUGIN"
jq -e '(.version | type == "string") and (.description | type == "string" and length > 0)' "$PJ" >/dev/null 2>&1 && ok "plugin.json has version and description" || ng "plugin.json lacks version or description"
MJ="$ROOT/../../.claude-plugin/marketplace.json"
if [ -f "$MJ" ]; then
  SRC=$(jq -r --arg p "$PLUGIN" '.plugins[]? | select(.name == $p) | .source' "$MJ" 2>/dev/null)
  [ -n "$SRC" ] && ok "marketplace.json lists $PLUGIN" || ng "marketplace.json does not list $PLUGIN"
  [ -n "$SRC" ] && [ -f "$ROOT/../../$SRC/.claude-plugin/plugin.json" ] && ok "the marketplace source path leads to a plugin.json" || ng "the marketplace source path does not lead to a plugin.json"
else
  echo "  note marketplace.json is not next to this plugin (running from an installed copy); its two checks are skipped"
fi

echo "[2] skill frontmatter"
if [ ! -f "$SKILL_FILE" ]; then
  ng "skills/$SKILL/SKILL.md is missing"
  FM=""; BODY=""
else
  ok "skills/$SKILL/SKILL.md exists"
  [ "$(head -1 "$SKILL_FILE")" = "---" ] && ok "the file starts with a frontmatter fence" || ng "the first line is not ---"
  FM=$(awk 'NR==1 && $0=="---"{f=1; next} f && $0=="---"{exit} f{print}' "$SKILL_FILE")
  BODY=$(awk 'NR==1 && $0=="---"{f=1; next} f==1 && $0=="---"{f=2; next} f==2{print}' "$SKILL_FILE")
fi
[ -n "$BODY" ] && ok "the frontmatter is closed and a body follows" || ng "the frontmatter is not closed, or the body is empty"
fm_val() { printf '%s\n' "$FM" | sed -n "s/^$1:[[:space:]]*//p" | head -1 | sed 's/^"\(.*\)"$/\1/'; }
[ "$(fm_val name)" = "$SKILL" ] && ok "name is $SKILL (the command is /$PLUGIN:$SKILL)" || ng "name is not $SKILL"
DESC=$(fm_val description); WHEN=$(fm_val when_to_use)
[ -n "$DESC" ] && ok "description is present" || ng "description is missing or empty"
DLEN=$(printf '%s%s' "$DESC" "$WHEN" | wc -m | tr -d ' ')
[ "$DLEN" -le 1536 ] && ok "description is $DLEN characters (the listing cuts at 1536)" || ng "description is $DLEN characters, over the 1536 cut"
[ -n "$(fm_val argument-hint)" ] && ok "argument-hint is present" || ng "argument-hint is missing"
case " low medium high xhigh max " in *" $(fm_val effort) "*) ok "effort is one of the documented levels" ;; *) ng "effort is missing or is not a documented level" ;; esac
[ -n "$(fm_val model)" ] && ok "model is stated" || ng "model is not stated"
BADKEYS=""
for k in $(printf '%s\n' "$FM" | sed -n 's/^\([A-Za-z_-][A-Za-z_-]*\):.*/\1/p'); do
  case "$KNOWN_KEYS" in *" $k "*) ;; *) BADKEYS="$BADKEYS $k" ;; esac
done
[ -z "$BADKEYS" ] && ok "every frontmatter key is one the skills page lists" || ng "frontmatter keys the skills page does not list:$BADKEYS"

echo "[3] required sections"
while IFS= read -r h; do
  [ -n "$h" ] || continue
  n=$(printf '%s\n' "$BODY" | grep -cxF -e "$h")
  [ "$n" = "1" ] && ok "$h" || ng "$h (found $n times, expected 1)"
done <<EOF
$REQUIRED_SECTIONS
EOF

echo "[4] rules carried by single sentences"
while IFS= read -r p; do
  [ -n "$p" ] || continue
  printf '%s\n' "$BODY" | grep -qF -e "$p" && ok "$p" || ng "missing: $p"
done <<EOF
$REQUIRED_PHRASES
EOF
printf '%s\n' "$BODY" | grep -qF '$ARGUMENTS' && ok 'the body receives $ARGUMENTS' || ng 'the body has no $ARGUMENTS placeholder'

echo "[5] nothing environment-specific, no promises"
HITS=$(grep -nE -e "$FORBIDDEN" "$SKILL_FILE" 2>/dev/null | head -5)
[ -z "$HITS" ] && ok "no forbidden word in SKILL.md" || { ng "forbidden word in SKILL.md"; printf '%s\n' "$HITS" | sed 's/^/         /'; }

echo "[6] fixture and expected points"
EXP="$FIX/expected.tsv"
if [ -f "$EXP" ]; then
  ok "expected.tsv exists"
  ROWS=0; BAD=""
  while IFS=$'\t' read -r id kind pat desc; do
    case "$id" in ''|\#*) continue ;; esac
    ROWS=$((ROWS+1))
    [ -n "$kind" ] && [ -n "$pat" ] && [ -n "$desc" ] || { BAD="$BAD $id(columns)"; continue; }
    case "$kind" in reply|untouched|file:?*) ;; *) BAD="$BAD $id(kind)"; continue ;; esac
    [ "$kind" = "untouched" ] && continue
    printf 'x' | grep -qiE -e "$pat" 2>/dev/null; [ $? -le 1 ] || BAD="$BAD $id(pattern)"
  done < "$EXP"
  [ -z "$BAD" ] && ok "all $ROWS rows have four columns, a known kind, and a pattern that compiles" || ng "bad rows:$BAD"
  MIN=$(score_min "$EXP")
  [ -n "$MIN" ] && [ "$MIN" -ge 1 ] && [ "$MIN" -le "$ROWS" ] && ok "MIN is $MIN of $ROWS" || ng "MIN is missing or is outside 1..$ROWS"
else
  ng "expected.tsv is missing"; ROWS=0
fi
[ -d "$FIX/repo" ] && [ -n "$(find "$FIX/repo" -type f | head -1)" ] && ok "the fixture repo has files" || ng "the fixture repo is missing or empty"

echo "[7] checking the checker (does the scoring tell a good reply from an empty one?)"
if [ -f "$EXP" ] && [ -f "$FIX/sample-reply.txt" ]; then
  score_points "$EXP" "$FIX/sample-reply.txt" "$FIX/sample-result" 0 >/dev/null
  [ "$SCORE_MET" = "$ROWS" ] && ok "the hand-written sample reply meets all $ROWS points" || ng "the hand-written sample reply meets $SCORE_MET of $ROWS points"
  NEUTRAL=$(mktemp "${TMPDIR:-/tmp}/$PLUGIN-selftest.XXXXXX") && {
    echo "I looked at the files and everything seems fine." > "$NEUTRAL"
    score_points "$EXP" "$NEUTRAL" "$FIX/no-such-dir" 1 >/dev/null
    [ "$SCORE_MET" = "0" ] && ok "a reply that says nothing meets 0 points" || ng "a reply that says nothing meets $SCORE_MET points"
  } || ng "could not create a temporary file"
else
  ng "expected.tsv or sample-reply.txt is missing"
fi

echo
echo "Result: ok $PASS / FAIL $FAIL"
[ "$FAIL" = "0" ] || exit 1
echo "The files are intact. This does not show what Claude does with the skill; for that, run tests/live-check.sh."
