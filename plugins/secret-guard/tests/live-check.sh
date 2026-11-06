#!/bin/bash
# Check secret-guard against a real Claude Code session.
#
# Creates an empty work folder, runs Claude Code (claude -p) three times "with the plugin" and three times "without" (one per path),
# and counts how many fake keys are left in the tool results that Claude received.
# Claude's own account of what it saw is not used.
#
#   path 1  output of a successful Bash command   with = 0 and without >= 1 means redaction works
#   path 2  output of a failed Bash command       counts only (cannot be redacted; see "What it does not protect")
#   path 3  writing a file that contains a key    with = no key in the file and without = key in the file means blocking works
#
# The hook lines of each run are counted as well (--include-hook-events). When no hook of this plugin
# ran to the end, a key that got through says nothing about the plugin, and the check ends with
# "cannot tell" and the reason. That is what a run from inside a sandbox looks like.
#
# Usage: bash tests/live-check.sh     (from a plain terminal, not from inside a Claude Code session)
# Needs: claude (logged in), jq. It calls Claude Code six times and uses that much of your usage allowance.
# Exit code: 0 = working (the hooks ran and the keys were stopped)
#            1 = not working (the hooks ran and a key got through)
#            2 = cannot tell (a run did not finish, the hooks did not run, or the control is not a control)
# Fake keys are built at run time. Only counts are printed.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v claude >/dev/null 2>&1 || { echo "claude was not found."; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "jq was not found."; exit 2; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/secret-guard-live.XXXXXX") || { echo "Could not create a work folder."; exit 2; }
. "$ROOT/tests/hook-events.sh" 2>/dev/null || { echo "tests/hook-events.sh was not found."; exit 2; }
# Which hook lines belong to this plugin (see tests/hook-events.sh)
HE_PLUGIN='secret-guard'
HE_NAME_RE='^(PreToolUse:(Bash|Write|Edit|MultiEdit|NotebookEdit)|PostToolUse:Bash|PostToolUseFailure:Bash)$'
HE_SIGN_RE='secret-guard'
RE='ghp_0{40}'
MARK='REDACTED-BY-SECRET-GUARD'

for arm in with without; do
  mkdir -p "$WORK/$arm"
  # The key-shaped string only comes into existence when these two scripts run
  printf '%s\n' "printf 'value: gh%s_%040d\\n' p 0" > "$WORK/$arm/emit-ok.sh"
  printf '%s\n' "printf 'value: gh%s_%040d\\n' p 0" "exit 3" > "$WORK/$arm/emit-fail.sh"
done

P_OK='Run this exact shell command with the Bash tool, once, and then reply with the single word done: sh ./emit-ok.sh'
P_FAIL='Run this exact shell command with the Bash tool, once, and then reply with the single word done: sh ./emit-fail.sh'
P_WRITE='Use the Write tool to create a file named out.txt in the current directory. Its content must be the four characters ghp_ immediately followed by forty zero digits, and nothing else. Then reply with the single word done.'

# arm name prompt allowed-tool
run() {
  local arm="$1" name="$2" prompt="$3" tool="$4" out="$WORK/$1/$2.jsonl"
  local -a cmd=(claude -p "$prompt" --output-format stream-json --verbose --include-hook-events --allowedTools "$tool")
  [ "$arm" = "with" ] && cmd+=(--plugin-dir "$ROOT")
  if command -v perl >/dev/null 2>&1; then
    (cd "$WORK/$arm" && perl -e 'alarm shift; exec @ARGV' 240 "${cmd[@]}" >"$out" 2>"$out.err" </dev/null)
  else
    (cd "$WORK/$arm" && "${cmd[@]}" >"$out" 2>"$out.err" </dev/null)
  fi
}

# Did the run reach the end (a result was emitted and it is not an error)?
finished() {
  jq -es 'map(select(.type == "result")) | last | (. != null and (.is_error | not))' "$1" >/dev/null 2>&1
}
# How many times a tool was called
called() {
  jq -r --arg t "$2" 'select(.type == "assistant") | .message.content[]? | select(.type == "tool_use" and .name == $t) | .name' "$1" 2>/dev/null | grep -c .
}
# The text of the tool results that Claude received
results() {
  jq -r 'select(.type == "user") | .message.content[]? | select(.type == "tool_result")
         | (.content | if type == "array" then (map(.text? // "") | join("\n")) else tostring end)' "$1" 2>/dev/null
}
count() { grep -oE -e "$1" | grep -c .; }

echo "Work folder: $WORK"
echo "Calling Claude Code six times (this takes a few minutes)..."
for arm in with without; do
  run "$arm" ok    "$P_OK"    Bash
  run "$arm" fail  "$P_FAIL"  Bash
  run "$arm" write "$P_WRITE" Write
done

UNDECIDED=0
for arm in with without; do
  for name in ok fail write; do
    f="$WORK/$arm/$name.jsonl"
    if ! finished "$f"; then
      echo "Cannot tell: $arm/$name did not run to the end (check login, usage allowance, network; log = $f)"
      UNDECIDED=1
      continue
    fi
    tool=Bash; [ "$name" = "write" ] && tool=Write
    [ "$(called "$f" "$tool")" -ge 1 ] 2>/dev/null || { echo "Cannot tell: $arm/$name never called $tool"; UNDECIDED=1; }
  done
done
[ "$UNDECIDED" = "0" ] || exit 2

W_OK=$(results "$WORK/with/ok.jsonl" | count "$RE");       N_OK=$(results "$WORK/without/ok.jsonl" | count "$RE")
W_OK_MARK=$(results "$WORK/with/ok.jsonl" | count "$MARK")
W_FAIL=$(results "$WORK/with/fail.jsonl" | count "$RE");   N_FAIL=$(results "$WORK/without/fail.jsonl" | count "$RE")
W_FILE=0; [ -f "$WORK/with/out.txt" ] && W_FILE=$(count "$RE" < "$WORK/with/out.txt")
N_FILE=0; [ -f "$WORK/without/out.txt" ] && N_FILE=$(count "$RE" < "$WORK/without/out.txt")

echo
echo "Claude Code: $(claude --version 2>/dev/null | head -1)"
echo "                                                  with plugin   without plugin"
echo "path 1  keys left in successful output                $W_OK              $N_OK"
echo "        redaction marks                               $W_OK_MARK              -"
echo "path 2  keys left in failed output                    $W_FAIL              $N_FAIL"
echo "path 3  keys in the written file                      $W_FILE              $N_FILE"
he_scan "$HE_NAME_RE" "$HE_SIGN_RE" "$WORK"/without/*.jsonl -- "$WORK"/with/*.jsonl
HE_FAIL_TEXT=$(printf '%s' "$HE_FAIL_TEXT" | sed -E "s/$RE/[key]/g")
he_report "$HE_PLUGIN"
echo
he_gate 0
if [ "$?" = "2" ]; then
  he_explain_not_run "$HE_PLUGIN"
  echo
  echo "Logs are kept in $WORK. The logs on the without-plugin side contain the fake key as is."
  exit 2
fi

RC=0
if [ "$N_OK" -ge 1 ] && [ "$N_FILE" -ge 1 ]; then
  echo "Control (without plugin): the key reached Claude and was written to the file = the instrument works."
else
  echo "Control (without plugin): no key was left on this side either. If secret-guard is already installed, that is why."
  echo "If it is not installed, this check cannot tell."
  RC=2
fi
if [ "$W_OK" = "0" ] && [ "$W_OK_MARK" -ge 1 ]; then echo "path 1: working (the hook ran and the key in successful output did not reach Claude)"
else echo "path 1: NOT working (the hook ran and the key in successful output still reached Claude)"; RC=1; fi
if [ "$W_FILE" = "0" ]; then echo "path 3: working (the hook ran and the write that contained a key was blocked)"
else echo "path 3: NOT working (the hook ran and a file containing the key was still written)"; RC=1; fi
if [ "$W_FAIL" -ge 1 ]; then echo "path 2: the key in failed output reached Claude (this path cannot be redacted; only a notice is sent)"
else echo "path 2: the key in failed output did not reach Claude"; fi
he_gate "$RC"
if [ "$?" = "2" ] && [ "$RC" = "1" ]; then he_explain_mixed "$HE_PLUGIN"; RC=2; fi
echo
echo "Logs are kept in $WORK. The logs on the without-plugin side contain the fake key as is."
exit "$RC"
