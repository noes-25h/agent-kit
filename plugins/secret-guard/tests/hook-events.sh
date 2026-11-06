#!/bin/bash
# Counts the hook lines that Claude Code writes to a stream-json log, for tests/live-check.sh.
# Sourced, not run. Needs: bash, jq.
#
# Why it exists: when Claude Code cannot start a hook, the tool call goes through as if no hook were
# there. A check that only looks at the result then says "not working" about a hook that never ran.
# These functions tell the two apart: "the hook did not run" and "the hook ran and did not help".
#
# The lines (claude -p --output-format stream-json --verbose --include-hook-events):
#   {"type":"system","subtype":"hook_started", "hook_id":..,"hook_name":"PreToolUse:Write","hook_event":"PreToolUse",..}
#   {"type":"system","subtype":"hook_response","hook_id":..,"hook_name":..,"hook_event":..,
#    "output":..,"stdout":..,"stderr":..,"exit_code":0,"outcome":"success"|"error"|"cancelled",..}
# A hook line does not say which plugin the hook belongs to. A result is counted for this plugin when
#   - no hook answered under that hook_name in the runs without the plugin, or
#   - the text of the result names the plugin (its own messages, or the path in a start failure).
# Results on the same events that fit neither rule are counted apart and never count as this plugin.
#
#   he_scan NAME_RE SIGN_RE WITHOUT_LOG... -- WITH_LOG...
#       NAME_RE  = regular expression for the hook_name values this plugin registers
#       SIGN_RE  = regular expression (case is ignored) for text only this plugin produces
#     sets HE_STARTED  hooks of this plugin that were started
#          HE_OK       ... that ran to the end (exit code 0, or 2 = the hook blocked the call)
#          HE_FAILED   ... that could not be started, crashed, or were cancelled
#          HE_SILENT   ... that were started and left no result
#          HE_OTHER    results on the same events that could not be tied to this plugin
#          HE_FAIL_TEXT  first line of the first failure (at most 300 characters)
#   he_gate RC
#       prints nothing; returns the exit code of the whole check:
#       2 when no hook of this plugin ran to the end, 2 when RC is 1 and some hook did not run to
#       the end, otherwise RC.

he_scan() {
  local name_re="$1" sign_re="$2"; shift 2
  local -a base=() with=()
  while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do [ -f "$1" ] && base+=("$1"); shift; done
  [ "$#" -gt 0 ] && shift
  while [ "$#" -gt 0 ]; do [ -f "$1" ] && with+=("$1"); shift; done

  HE_STARTED=0; HE_OK=0; HE_FAILED=0; HE_SILENT=0; HE_OTHER=0; HE_FAIL_TEXT=""
  [ "${#with[@]}" -gt 0 ] || return 0

  local shared='[]' out
  if [ "${#base[@]}" -gt 0 ]; then
    shared=$(cat "${base[@]}" | jq -Rnc --arg ev "$name_re" '
      [inputs | fromjson? | select(type == "object" and .type == "system")
       | select(.subtype == "hook_started" or .subtype == "hook_response")
       | (.hook_name // "") | select(test($ev))] | unique' 2>/dev/null) || shared='[]'
    [ -n "$shared" ] || shared='[]'
  fi

  out=$(cat "${with[@]}" | jq -Rnr --arg ev "$name_re" --arg sig "$sign_re" --argjson shared "$shared" '
    def text: [.output, .stdout, .stderr] | map(strings) | join("\n");
    def alone: (.hook_name // "") as $n | ($shared | index($n)) == null;
    def mine: alone or (text | test($sig; "i"));
    def ran: (.exit_code == 0 and .outcome != "cancelled")
             or (.exit_code == 2 and .outcome != "cancelled" and (text | test("^Failed to run") | not));
    [inputs | fromjson? | select(type == "object" and .type == "system")
     | select(.subtype == "hook_started" or .subtype == "hook_response")
     | select((.hook_name // "") | test($ev))] as $h
    | ($h | map(select(.subtype == "hook_response"))) as $r
    | ($r | map(.hook_id)) as $answered
    | ($h | map(select(.subtype == "hook_started" and alone and ((.hook_id) as $i | ($answered | index($i)) == null))) | length) as $silent
    | ($r | map(select(mine))) as $m
    | ($m | map(select(ran)) | length) as $ok
    | ($m | map(select(ran | not))) as $bad
    | ($bad | first // {} | ((.stderr // "") | if . == "" then "" else . end) as $e
       | (if $e != "" then $e else (.output // "") end)
       | split("\n") | map(select(test("[^[:space:]]"))) | first // ""
       | gsub("[[:cntrl:]]"; " ") | .[0:300]) as $why
    | "\($ok + ($bad | length) + $silent) \($ok) \($bad | length) \($silent) \(($r | length) - ($m | length))", $why
  ' 2>/dev/null) || return 0
  [ -n "$out" ] || return 0
  read -r HE_STARTED HE_OK HE_FAILED HE_SILENT HE_OTHER <<EOF
$(printf '%s\n' "$out" | sed -n 1p)
EOF
  HE_FAIL_TEXT=$(printf '%s\n' "$out" | sed -n 2p)
  case "$HE_STARTED$HE_OK$HE_FAILED$HE_SILENT$HE_OTHER" in
    ''|*[!0-9]*) HE_STARTED=0; HE_OK=0; HE_FAILED=0; HE_SILENT=0; HE_OTHER=0 ;;
  esac
  return 0
}

he_gate() {
  local rc="$1"
  [ "${HE_OK:-0}" -ge 1 ] 2>/dev/null || return 2
  if [ "$rc" = "1" ] && [ $(( ${HE_FAILED:-0} + ${HE_SILENT:-0} )) -ge 1 ]; then return 2; fi
  return "$rc"
}

# The lines a person reads. PLUGIN = the name of the plugin.
he_report() {
  echo "hooks of $1 in the runs with the plugin: started $HE_STARTED, ran to the end $HE_OK, failed to run $HE_FAILED, left no result $HE_SILENT"
  [ "$HE_OTHER" = "0" ] || echo "        results on the same events that could not be tied to $1: $HE_OTHER (other hooks on this machine answer on those events too)"
  [ -z "$HE_FAIL_TEXT" ] || echo "        first failure: $HE_FAIL_TEXT"
}

# Printed when he_gate returns 2 because no hook ran to the end.
he_explain_not_run() {
  local why="$HE_FAIL_TEXT"
  if [ -z "$why" ]; then
    if [ "$HE_SILENT" != "0" ]; then why="it was started and left no result"
    elif [ "$HE_OTHER" != "0" ]; then why="Claude Code recorded no result that belongs to $1"
    else why="Claude Code recorded no hook for it"; fi
  fi
  echo "Cannot tell: the hook did not run: $why"
  echo "This is not a verdict on $1. The tool calls went through because no hook was there to answer."
  case "$HE_FAIL_TEXT" in
    *EPERM*|*"peration not permitted"*|*EACCES*|*"ermission denied"*)
      echo "The line above is what a sandbox looks like: Claude Code could not create the data folder of the plugin"
      echo "(a folder under .claude/plugins/data in your home folder), so it did not start the hook." ;;
    *)
      echo "How to tell a sandbox: the failure says EPERM or \"operation not permitted\" and names a folder under"
      echo ".claude/plugins/data in your home folder. A check started from inside a Claude Code session, or from any"
      echo "tool that limits writes to your home folder, ends like that." ;;
  esac
  echo "Open a plain terminal (not a Claude Code session, no sandbox) and run this check again."
}

# Printed when he_gate returns 2 because a "NOT working" row sits next to hooks that did not run.
he_explain_mixed() {
  echo "Cannot tell: some hooks of $1 did not run to the end (failed to run $HE_FAILED, left no result $HE_SILENT),"
  echo "so a \"NOT working\" row above may come from a hook that did not run and not from the plugin."
  echo "Open a plain terminal (not a Claude Code session, no sandbox) and run this check again."
}
