#!/bin/bash
# Unit check for secret-guard.
# Builds fake keys at run time, feeds the hooks the same JSON that Claude Code sends them,
# and checks: blocked, passed, redacted, output shape preserved.
#
# A full pass here only tells you that the hook scripts are correct.
# Whether Claude Code actually calls the hooks, and whether it accepts the replaced output,
# can only be seen with tests/live-check.sh (the check against a real Claude Code session).
#
# Usage: bash tests/selftest.sh     exit 0 = all passed / 1 = at least one check failed
# Needs: bash, jq
# Fake keys are never printed (only names and results are).

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BLOCK="$ROOT/scripts/block.sh"
REDACT="$ROOT/scripts/redact.sh"
PASS=0; FAIL=0

command -v jq >/dev/null 2>&1 || { echo "jq was not found. Install jq and run this again."; exit 1; }
. "$ROOT/scripts/patterns.sh"
[ "${SG_PATTERNS_LOADED:-0}" = "1" ] || { echo "Could not load patterns.sh."; exit 1; }

ok()  { PASS=$((PASS+1)); echo "  ok   $1"; }
ng()  { FAIL=$((FAIL+1)); echo "  FAIL $1"; }
rep() { local n="$1" c="$2" s=""; while [ "$n" -gt 0 ]; do s="$s$c"; n=$((n-1)); done; printf '%s' "$s"; }

# One sample per row name. $2 = ok (must match) / short (one character short; must not match)
sg_sample() {
  local d=0; [ "$2" = "short" ] && d=1
  case "$1" in
    openai-project) printf 'sk-proj-%s'   "$(rep $((40-d)) a)" ;;
    openai-legacy)  printf 'sk-%s'        "$(rep $((40-d)) a)" ;;
    anthropic)      printf 'sk-ant-%s'    "$(rep $((20-d)) a)" ;;
    github-token)   printf 'ghp_%s'       "$(rep $((36-d)) a)" ;;
    github-fine)    printf 'github_pat_%s' "$(rep $((22-d)) a)" ;;
    aws-access-key) printf 'AKIA%s'       "$(rep $((16-d)) A)" ;;
    slack)          printf 'xoxb-%s'      "$(rep $((10-d)) a)" ;;
    google-api)     printf 'AIza%s'       "$(rep $((35-d)) a)" ;;
    npm)            printf 'npm_%s'       "$(rep $((36-d)) a)" ;;
    sendgrid)       printf 'SG.%s.%s'     "$(rep 22 a)" "$(rep $((43-d)) a)" ;;
    notion)         printf 'ntn_%s'       "$(rep $((40-d)) a)" ;;
    stripe-live)    printf 'sk_live_%s'   "$(rep $((20-d)) a)" ;;
    stripe-webhook) printf 'whsec_%s'     "$(rep $((20-d)) a)" ;;
    stripe-test)    printf 'sk_test_%s'   "$(rep $((20-d)) a)" ;;
    ghost-admin)    printf '%s:%s'        "$(rep 24 a)" "$(rep $((64-d)) a)" ;;
    *) return 1 ;;
  esac
}

pre()  { jq -cn --arg t "$1" --argjson i "$2" '{hook_event_name:"PreToolUse", tool_name:$t, tool_input:$i}'; }
post() { jq -cn --arg o "$1" --arg e "$2" '{hook_event_name:"PostToolUse", tool_name:"Bash", tool_input:{command:"x"}, tool_response:{stdout:$o, stderr:$e, interrupted:false, isImage:false}}'; }
fail_ev() { jq -cn --arg e "$1" '{hook_event_name:"PostToolUseFailure", tool_name:"Bash", tool_input:{command:"x"}, error:$e}'; }

# Check the exit code of block.sh
expect_block() { # description expected input-json [path to block.sh]
  printf '%s' "$3" | bash "${4:-$BLOCK}" >/dev/null 2>&1
  local rc=$?
  [ "$rc" = "$2" ] && ok "$1 (exit $rc)" || ng "$1 (expected exit $2, got $rc)"
}

# Does the replacement satisfy the Bash output shape? 0 = yes
shape_ok() {
  printf '%s' "$1" | jq -e '
    .hookSpecificOutput.hookEventName == "PostToolUse"
    and (.systemMessage | type == "string")
    and (.hookSpecificOutput.updatedToolOutput
         | type == "object"
           and (.stdout | type == "string") and (.stderr | type == "string")
           and (.interrupted | type == "boolean") and (.isImage | type == "boolean"))' >/dev/null 2>&1
}
has_secret() { printf '%s' "$1" | grep -qE -e "$SG_REDACT_RE" -e "$SG_PEM_BEGIN_RE"; }

echo "[1] every row of the table: a matching sample and a one-character-short sample"
while read -r name tier re; do
  [ -n "$name" ] || continue
  tok=$(sg_sample "$name" ok) || { ng "$name: no sample in selftest (add one to sg_sample)"; continue; }
  near=$(sg_sample "$name" short)
  want=0; [ "$tier" = "B" ] && want=2
  expect_block "$name: before execution (tier $tier)" "$want" "$(pre Bash "$(jq -cn --arg c "echo $tok" '{command:$c}')")"
  expect_block "$name: one character short passes" 0 "$(pre Bash "$(jq -cn --arg c "echo $near" '{command:$c}')")"

  out=$(post "before $tok after"$'\n' "" | bash "$REDACT" 2>/dev/null)
  got=$(printf '%s' "$out" | jq -j '.hookSpecificOutput.updatedToolOutput.stdout // empty' 2>/dev/null; printf x); got="${got%x}"
  if shape_ok "$out" && ! has_secret "$got" && [ "$got" = "before $SG_MARK after"$'\n' ] ; then ok "$name: output redacted (surrounding text and newline unchanged)"
  else ng "$name: output redaction"; fi

  out=$(post "before $near after" "" | bash "$REDACT" 2>/dev/null)
  [ -z "$out" ] && ok "$name: one character short is not redacted" || ng "$name: redacted a one-character-short sample"
done <<EOF
$(sg_rows)
EOF

echo "[2] PEM private keys"
PB="-----BEGIN RSA PRIVATE ""KEY-----"; PE="-----END RSA PRIVATE ""KEY-----"
expect_block "a write that contains the header line is blocked" 2 "$(pre Write "$(jq -cn --arg c "$PB"$'\nAAAA\n'"$PE" '{file_path:"/tmp/k.pem", content:$c}')")"
out=$(post "head"$'\n'"$PB"$'\nBODYLINE1\nBODYLINE2\n'"$PE"$'\ntail\n' "" | bash "$REDACT" 2>/dev/null)
got=$(printf '%s' "$out" | jq -j '.hookSpecificOutput.updatedToolOutput.stdout // empty' 2>/dev/null; printf x); got="${got%x}"
[ "$got" = "head"$'\n'"$SG_MARK"$'\ntail\n' ] && shape_ok "$out" && ok "header through footer is redacted, text around it is kept" || ng "PEM range redaction"
out=$(post "head"$'\n'"$PB"$'\nBODYLINE1\nBODYLINE2\n' "" | bash "$REDACT" 2>/dev/null)
got=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.updatedToolOutput.stdout // empty' 2>/dev/null)
case "$got" in *BODYLINE*) ng "key body left in output when the footer is missing" ;; "head"*) ok "with no footer, everything to the end is redacted" ;; *) ng "redaction with a missing footer" ;; esac

echo "[3] which input fields are scanned"
T=$(sg_sample github-token ok)
expect_block "Write content" 2 "$(pre Write "$(jq -cn --arg c "token=$T" '{file_path:"/tmp/a.txt", content:$c}')")"
expect_block "Edit new_string" 2 "$(pre Edit "$(jq -cn --arg c "$T" '{file_path:"/tmp/a.txt", old_string:"x", new_string:$c}')")"
expect_block "key only in Edit old_string passes (an edit that removes a key)" 0 "$(pre Edit "$(jq -cn --arg c "$T" '{file_path:"/tmp/a.txt", old_string:$c, new_string:"TOKEN_FROM_ENV"}')")"
expect_block "nested edits[].new_string" 2 "$(pre MultiEdit "$(jq -cn --arg c "$T" '{file_path:"/tmp/a.txt", edits:[{old_string:"x", new_string:"y"},{old_string:"z", new_string:$c}]}')")"
expect_block "key only in nested edits[].old_string passes" 0 "$(pre MultiEdit "$(jq -cn --arg c "$T" '{file_path:"/tmp/a.txt", edits:[{old_string:$c, new_string:"y"}]}')")"
expect_block "a field with an unknown name is still scanned" 2 "$(pre NotebookEdit "$(jq -cn --arg c "$T" '{notebook_path:"/tmp/a.ipynb", some_future_field:$c}')")"
expect_block "an ordinary command with no key passes" 0 "$(pre Bash '{"command":"git status && ls -la"}')"
expect_block "a git commit hash (40 hex digits) passes" 0 "$(pre Bash "$(jq -cn --arg c "git show $(rep 40 a)" '{command:$c}')")"
expect_block "missing tool_input does not crash" 0 '{"hook_event_name":"PreToolUse","tool_name":"Bash"}'
expect_block "a password literal passes by default" 0 "$(pre Write '{"file_path":"/tmp/f.json","content":"{\"password\": \"example\"}"}')"

echo "[4] redaction keeps the shape"
out=$(post "$T" "warn: $T"$'\n' | bash "$REDACT" 2>/dev/null)
so=$(printf '%s' "$out" | jq -j '.hookSpecificOutput.updatedToolOutput.stdout' 2>/dev/null; printf x); so="${so%x}"
se=$(printf '%s' "$out" | jq -j '.hookSpecificOutput.updatedToolOutput.stderr' 2>/dev/null; printf x); se="${se%x}"
[ "$so" = "$SG_MARK" ] && ok "no newline is added to stdout that had none" || ng "trailing newline changed (stdout)"
[ "$se" = "warn: $SG_MARK"$'\n' ] && ok "stderr is redacted too, and not emptied" || ng "stderr handling"
out=$(jq -cn --arg o "$T" '{hook_event_name:"PostToolUse", tool_name:"Bash", tool_response:{stdout:$o, stderr:"", interrupted:true, isImage:false, extraFutureKey:{a:1}}}' | bash "$REDACT" 2>/dev/null)
printf '%s' "$out" | jq -e '.hookSpecificOutput.updatedToolOutput | .interrupted == true and .extraFutureKey.a == 1' >/dev/null 2>&1 && ok "non-string fields and unknown fields are untouched" || ng "another field changed"
out=$(jq -cn --arg o "$T" '{hook_event_name:"PostToolUse", tool_name:"Bash", tool_response:{stdout:$o}}' | bash "$REDACT" 2>/dev/null)
shape_ok "$out" && ok "all four fields are returned even when the input lacks some" || ng "missing fields were not filled in"
printf '%s' "$out" | jq -e '(.hookSpecificOutput | has("systemMessage")) | not' >/dev/null 2>&1 && ok "the warning sits at the top level" || ng "warning placement"
out=$(post "nothing here" "" | bash "$REDACT" 2>/dev/null)
[ -z "$out" ] && ok "output with no key returns nothing" || ng "reacted to output with no key"
out=$(jq -cn --arg o "$T" '{hook_event_name:"PostToolUse", tool_name:"Read", tool_response:{stdout:$o}}' | bash "$REDACT" 2>/dev/null)
[ -z "$out" ] && ok "tools other than Bash return nothing (out of scope)" || ng "reacted to a tool other than Bash"

echo "[5] failed command: notify only"
out=$(fail_ev "Exit code 1"$'\n'"$T" | bash "$REDACT" 2>/dev/null)
printf '%s' "$out" | jq -e '
  (.systemMessage | type == "string")
  and .hookSpecificOutput.hookEventName == "PostToolUseFailure"
  and (.hookSpecificOutput.additionalContext | type == "string")
  and (.hookSpecificOutput | has("updatedToolOutput") | not)' >/dev/null 2>&1 && ok "notifies the user and Claude, sends no replacement" || ng "notice on failure"
has_secret "$out" && ng "the notice contains the key" || ok "the notice does not contain the key"
out=$(fail_ev "Exit code 1"$'\n'"no such file" | bash "$REDACT" 2>/dev/null)
[ -z "$out" ] && ok "a failure with no key returns nothing" || ng "reacted to a failure with no key"

echo "[6] which way it falls when something is broken"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/secret-guard-selftest.XXXXXX" 2>/dev/null) || TMP=""
if [ -n "$TMP" ]; then
  mkdir -p "$TMP/nopat" "$TMP/bin"
  cp "$BLOCK" "$REDACT" "$TMP/nopat/"
  expect_block "patterns.sh missing -> the blocking side blocks" 2 "$(pre Bash '{"command":"ls"}')" "$TMP/nopat/block.sh"
  out=$(post "$T" "" | bash "$TMP/nopat/redact.sh" 2>/dev/null)
  printf '%s' "$out" | jq -e '(.systemMessage | type == "string") and (has("hookSpecificOutput") | not)' >/dev/null 2>&1 && ok "patterns.sh missing -> the redacting side notifies and lets it through" || ng "redacting side with patterns.sh missing"

  # Build a PATH without jq (only the tools that are needed)
  for c in bash cat grep sed awk dirname; do p=$(command -v "$c") && ln -s "$p" "$TMP/bin/$c"; done
  E_OLD=$(pre Edit "$(jq -cn --arg c "$T" '{file_path:"/tmp/a.txt", old_string:$c, new_string:"y"}')")
  printf '%s' "$E_OLD" | PATH="$TMP/bin" bash "$BLOCK" >/dev/null 2>&1; rc=$?
  [ "$rc" = "2" ] && ok "no jq -> the whole input is scanned (a key in old_string blocks too = broad side)" || ng "no jq: did not fall to the broad side (exit $rc)"
  printf '%s' "$(pre Bash '{"command":"ls"}')" | PATH="$TMP/bin" bash "$BLOCK" >/dev/null 2>&1; rc=$?
  [ "$rc" = "0" ] && ok "no jq -> a call with no key still passes" || ng "no jq: everything is blocked (exit $rc)"
  out=$(post "$T" "" | PATH="$TMP/bin" bash "$REDACT" 2>/dev/null)
  printf '%s' "$out" | jq -e '(.systemMessage | type == "string") and (has("hookSpecificOutput") | not)' >/dev/null 2>&1 && ok "no jq -> the redacting side notifies and lets it through" || ng "redacting side with no jq"
  # The work folder is left in the OS temp area (it holds only copies of the hooks and symlinks)
else
  ng "could not create a temp folder"
fi

echo "[7] checking the checker (does the shape check reject broken output?)"
shape_ok '{"systemMessage":"m","hookSpecificOutput":{"hookEventName":"PostToolUse","updatedToolOutput":"plain text"}}' && ng "accepts a plain string" || ok "a plain-string replacement is rejected"
shape_ok '{"systemMessage":"m","hookSpecificOutput":{"hookEventName":"PostToolUse","updatedToolOutput":{"stdout":"x"}}}' && ng "accepts missing fields" || ok "a replacement with missing fields is rejected"
shape_ok '{"systemMessage":"m","hookSpecificOutput":{"hookEventName":"PostToolUse","updatedToolOutput":{"stdout":"x","stderr":"","interrupted":"false","isImage":false}}}' && ng "accepts a wrong type" || ok "a replacement with a wrong type is rejected"

echo "[8] tiers of the table (has a blocking row quietly become redact-only?)"
# If you change the table yourself, change these two lines to match.
SG_EXPECT_B="anthropic aws-access-key github-fine github-token google-api notion npm openai-legacy openai-project sendgrid slack stripe-live stripe-webhook"
SG_EXPECT_R="ghost-admin stripe-test"
now_b=$(sg_rows | awk '$2=="B"{print $1}' | sort | tr '\n' ' ' | sed 's/ $//')
now_r=$(sg_rows | awk '$2=="R"{print $1}' | sort | tr '\n' ' ' | sed 's/ $//')
[ "$now_b" = "$SG_EXPECT_B" ] && ok "blocking rows match the record" || ng "blocking rows differ from the record (if you changed the table, update SG_EXPECT_B)"
[ "$now_r" = "$SG_EXPECT_R" ] && ok "redact-only rows match the record" || ng "redact-only rows differ from the record (if you changed the table, update SG_EXPECT_R)"

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
echo "The hook scripts behave correctly. To see whether Claude Code actually calls them, run tests/live-check.sh."
