#!/bin/bash
# Checks the part of live-check.sh that decides between "working", "not working" and "cannot tell".
# It does not call Claude Code. It writes small stream-json logs in the shape Claude Code uses for
# hook lines, runs the counting in tests/hook-events.sh on them, and checks the three verdicts.
# selftest.sh runs this file. This checks the counting only; it says nothing about a real session.
#
# Usage: bash tests/hook-events-test.sh            exit 0 = all passed / 1 = at least one check failed
#        bash tests/hook-events-test.sh LOG        also prints the counts for a log of your own
# Needs: bash, jq

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SAMPLE='PreToolUse:Write'   # one hook_name this plugin registers

command -v jq >/dev/null 2>&1 || { echo "jq was not found."; exit 1; }
. "$ROOT/tests/hook-events.sh" || { echo "Could not load tests/hook-events.sh."; exit 1; }
# The same expressions live-check.sh uses
eval "$(grep -E '^HE_(PLUGIN|NAME_RE|SIGN_RE)=' "$ROOT/tests/live-check.sh")"
[ -n "$HE_PLUGIN" ] && [ -n "$HE_NAME_RE" ] && [ -n "$HE_SIGN_RE" ] || { echo "live-check.sh does not set HE_PLUGIN, HE_NAME_RE and HE_SIGN_RE."; exit 1; }

T=$(mktemp -d "${TMPDIR:-/tmp}/hook-events-test.XXXXXX") || { echo "Could not create a temp folder."; exit 1; }
PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); echo "  ok   $1"; }
ng() { FAIL=$((FAIL+1)); echo "  FAIL $1"; }

EVENT="${SAMPLE%%:*}"
started() { jq -cn --arg i "$1" --arg n "$SAMPLE" --arg e "$EVENT" '{type:"system",subtype:"hook_started",hook_id:$i,hook_name:$n,hook_event:$e,uuid:("u-"+$i),session_id:"s"}'; }
# id exit-code outcome stdout stderr
response() {
  jq -cn --arg i "$1" --arg n "$SAMPLE" --arg e "$EVENT" --argjson x "$2" --arg o "$3" --arg so "$4" --arg se "$5" \
    '{type:"system",subtype:"hook_response",hook_id:$i,hook_name:$n,hook_event:$e,output:(if $se != "" then $se else $so end),stdout:$so,stderr:$se,exit_code:$x,outcome:$o,uuid:("r-"+$i),session_id:"s"}'
}
other()  { started "other-$1"; response "other-$1" 0 success '{}' ''; }   # a hook of some other plugin
rest()   { printf '%s\n' '{"type":"system","subtype":"init","plugins":[]}' '{"type":"result","subtype":"success","is_error":false,"result":"done"}'; }
# What Claude Code reports when it cannot create the data folder of the plugin (seen on 2.1.296)
NOSTART="Failed to run: EPERM: operation not permitted, mkdir '${HOME:-/home/you}/.claude/plugins/data/$HE_PLUGIN-inline'"
MINE="$HE_PLUGIN: a message from the hook"

# expect description "started ok failed silent other" gate-of-0 gate-of-1 without-log with-log
expect() {
  local g0 g1
  he_scan "$HE_NAME_RE" "$HE_SIGN_RE" "$5" -- "$6"
  he_gate 0; g0=$?
  he_gate 1; g1=$?
  if [ "$HE_STARTED $HE_OK $HE_FAILED $HE_SILENT $HE_OTHER" = "$2" ] && [ "$g0" = "$3" ] && [ "$g1" = "$4" ]; then
    ok "$1 (counts $2; protected -> exit $g0, not protected -> exit $g1)"
  else
    ng "$1 (expected counts $2 and exits $3/$4, got $HE_STARTED $HE_OK $HE_FAILED $HE_SILENT $HE_OTHER and $g0/$g1)"
  fi
}

rest > "$T/quiet.jsonl"
{ other a; rest; } > "$T/shared.jsonl"

echo "[hook lines] the hook ran"
{ started 1; response 1 0 success '' ''; rest; } > "$T/w.jsonl"
expect "ran, and no other hook answers on the event" "1 1 0 0 0" 0 1 "$T/quiet.jsonl" "$T/w.jsonl"
{ other a; started 1; response 1 0 success "$MINE" ''; rest; } > "$T/w.jsonl"
expect "ran next to a hook of another plugin, known by its own text" "1 1 0 0 1" 0 1 "$T/shared.jsonl" "$T/w.jsonl"
{ other a; started 1; response 1 2 error '' "$MINE"; rest; } > "$T/w.jsonl"
expect "ran and blocked the call (exit code 2) counts as ran" "1 1 0 0 1" 0 1 "$T/shared.jsonl" "$T/w.jsonl"

echo "[hook lines] the hook failed to run"
{ other a; started 1; response 1 1 error '' "$NOSTART"; rest; } > "$T/w.jsonl"
expect "could not be started (the sandbox case) is \"cannot tell\", never \"not working\"" "1 0 1 0 1" 2 2 "$T/shared.jsonl" "$T/w.jsonl"
out=$(he_explain_not_run "$HE_PLUGIN")
printf '%s\n' "$out" | sed -n 1p | grep -q '^Cannot tell: the hook did not run: Failed to run: EPERM' && printf '%s\n' "$out" | grep -q 'what a sandbox looks like' && printf '%s\n' "$out" | grep -q 'plain terminal' \
  && ok "the reason is one line with the failure, then the sandbox note and what to do" || ng "wording of the reason"
{ started 1; response 1 1 error '' "$NOSTART"; rest; } > "$T/w.jsonl"
expect "could not be started, no other hook around" "1 0 1 0 0" 2 2 "$T/quiet.jsonl" "$T/w.jsonl"
{ started 1; response 1 127 error '' 'bash: no such file'; rest; } > "$T/w.jsonl"
expect "crashed" "1 0 1 0 0" 2 2 "$T/quiet.jsonl" "$T/w.jsonl"
{ started 1; response 1 0 cancelled '' ''; rest; } > "$T/w.jsonl"
expect "cancelled" "1 0 1 0 0" 2 2 "$T/quiet.jsonl" "$T/w.jsonl"
{ started 1; rest; } > "$T/w.jsonl"
expect "started and left no result" "1 0 0 1 0" 2 2 "$T/quiet.jsonl" "$T/w.jsonl"
{ started 1; response 1 0 success '' ''; started 2; response 2 1 error '' "$NOSTART"; rest; } > "$T/w.jsonl"
expect "one ran and one failed: \"working\" stands, \"not working\" becomes \"cannot tell\"" "2 1 1 0 0" 0 2 "$T/quiet.jsonl" "$T/w.jsonl"

echo "[hook lines] the hook was never started"
rest > "$T/w.jsonl"
expect "no hook line at all" "0 0 0 0 0" 2 2 "$T/quiet.jsonl" "$T/w.jsonl"
out=$(he_explain_not_run "$HE_PLUGIN")
printf '%s\n' "$out" | sed -n 1p | grep -q '^Cannot tell: the hook did not run: Claude Code recorded no hook for it$' && printf '%s\n' "$out" | grep -q 'How to tell a sandbox' \
  && ok "the reason says that no hook was recorded, and how to tell a sandbox" || ng "wording when nothing was recorded"
{ other a; rest; } > "$T/w.jsonl"
expect "only a hook of another plugin answered: it is not counted for this plugin" "0 0 0 0 1" 2 2 "$T/shared.jsonl" "$T/w.jsonl"
: > "$T/w.jsonl"
expect "an empty log" "0 0 0 0 0" 2 2 "$T/quiet.jsonl" "$T/w.jsonl"
expect "a log that does not exist" "0 0 0 0 0" 2 2 "$T/quiet.jsonl" "$T/none.jsonl"

echo "[hook lines] reading"
{ echo 'not json'; started 1; echo '{"type":"system","subtype":"hook_response"'; response 1 0 success '' ''; rest; } > "$T/w.jsonl"
expect "lines that are not JSON are skipped" "1 1 0 0 0" 0 1 "$T/quiet.jsonl" "$T/w.jsonl"
{ jq -cn '{type:"system",subtype:"hook_started",hook_id:"x",hook_name:"Stop",hook_event:"Stop"}'; jq -cn '{type:"system",subtype:"hook_response",hook_id:"x",hook_name:"Stop",hook_event:"Stop",output:"",stdout:"",stderr:"",exit_code:0,outcome:"success"}'; rest; } > "$T/w.jsonl"
expect "a hook on an event this plugin does not register is not counted" "0 0 0 0 0" 2 2 "$T/quiet.jsonl" "$T/w.jsonl"

# The temp folder is left in the OS temp area (it holds only the small logs written above)

if [ -n "${1:-}" ]; then
  echo
  echo "Counts for $1 (no log without the plugin was given, so every hook on these events is counted):"
  he_scan "$HE_NAME_RE" "$HE_SIGN_RE" -- "$1"; he_report "$HE_PLUGIN"
  echo "Counts for $1 (only results whose text names $HE_PLUGIN):"
  he_scan "$HE_NAME_RE" "$HE_SIGN_RE" "$1" -- "$1"; he_report "$HE_PLUGIN"
  he_gate 1; echo "a \"not protected\" result on this log would end with exit $?"
fi

echo
echo "hook-events-test: ok $PASS / FAIL $FAIL"
[ "$FAIL" = "0" ]
