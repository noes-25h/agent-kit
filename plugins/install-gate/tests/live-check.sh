#!/bin/bash
# Check install-gate against a real Claude Code session.
#
# Nothing real is installed. Each run gets a work folder with a fake `brew` (a script that only
# creates a marker file), and Claude Code is asked to run `./bin/brew install sg-demo-tool` once.
#
#   run 1  with the plugin, no audit record     expected: marker absent, first result is the block message
#   run 2  with the plugin, record says LOW     expected: marker present
#   run 3  without the plugin                   expected: marker present (control)
#
# The hook lines of each run are counted as well (--include-hook-events). When no hook of this plugin
# ran to the end, the result says nothing about the plugin, and the check ends with "cannot tell" and
# the reason. That is what a run from inside a sandbox looks like.
#
# Usage: bash tests/live-check.sh     (from a plain terminal, not from inside a Claude Code session)
# Needs: claude (logged in), jq. It calls Claude Code three times and uses that much of your usage allowance.
# Exit code: 0 = working (the hook ran and the install was stopped)
#            1 = not working (the hook ran and the result was wrong)
#            2 = cannot tell (a run did not finish, the hook did not run, or the control is not a control)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v claude >/dev/null 2>&1 || { echo "claude was not found."; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "jq was not found."; exit 2; }

. "$ROOT/tests/hook-events.sh" 2>/dev/null || { echo "tests/hook-events.sh was not found."; exit 2; }
# Which hook lines belong to this plugin (see tests/hook-events.sh)
HE_PLUGIN='install-gate'
HE_NAME_RE='^PreToolUse:Bash$'
HE_SIGN_RE='install-gate'
WORK=$(mktemp -d "${TMPDIR:-/tmp}/install-gate-live.XXXXXX") || { echo "Could not create a work folder."; exit 2; }
PROMPT='Run this exact shell command with the Bash tool, exactly once: ./bin/brew install sg-demo-tool
If the command is blocked or denied, do not try again, do not create or edit any file, and reply with the single word blocked. Otherwise reply with the single word done.'

for arm in norecord low without; do
  mkdir -p "$WORK/$arm/bin"
  printf '%s\n' '#!/bin/sh' 'touch "$(dirname "$0")/../MARKER"' 'echo "fake brew ran: $*"' > "$WORK/$arm/bin/brew"
  chmod +x "$WORK/$arm/bin/brew"
done
mkdir -p "$WORK/low/docs/tool-audits"
printf '%s\n' '# sg-demo-tool install audit' '' 'Risk: LOW' > "$WORK/low/docs/tool-audits/sg-demo-tool-audit.md"

run() { # arm
  local arm="$1" out="$WORK/$1/run.jsonl"
  local -a cmd=(claude -p "$PROMPT" --output-format stream-json --verbose --include-hook-events --allowedTools Bash)
  [ "$arm" != "without" ] && cmd+=(--plugin-dir "$ROOT")
  if command -v perl >/dev/null 2>&1; then
    (cd "$WORK/$arm" && perl -e 'alarm shift; exec @ARGV' 240 "${cmd[@]}" >"$out" 2>"$out.err" </dev/null)
  else
    (cd "$WORK/$arm" && "${cmd[@]}" >"$out" 2>"$out.err" </dev/null)
  fi
}
finished() { jq -es 'map(select(.type == "result")) | last | (. != null and (.is_error | not))' "$1" >/dev/null 2>&1; }
called() { jq -r 'select(.type == "assistant") | .message.content[]? | select(.type == "tool_use" and .name == "Bash") | .name' "$1" 2>/dev/null | grep -c .; }
first_result() {
  jq -rs '[.[] | select(.type == "user") | .message.content[]? | select(.type == "tool_result")] | first
          | (.content | if type == "array" then (map(.text? // "") | join("\n")) else tostring end)' "$1" 2>/dev/null
}

echo "Work folder: $WORK"
echo "Calling Claude Code three times (this takes a few minutes)..."
for arm in norecord low without; do run "$arm"; done

UNDECIDED=0
for arm in norecord low without; do
  f="$WORK/$arm/run.jsonl"
  if ! finished "$f"; then
    echo "Cannot tell: the '$arm' run did not reach the end (check login, usage allowance, network; log = $f)"; UNDECIDED=1; continue
  fi
  [ "$(called "$f")" -ge 1 ] 2>/dev/null || { echo "Cannot tell: the '$arm' run never called Bash"; UNDECIDED=1; }
done
[ "$UNDECIDED" = "0" ] || exit 2

mark() { [ -f "$WORK/$1/MARKER" ] && echo present || echo absent; }
BLOCKMSG=no; first_result "$WORK/norecord/run.jsonl" | grep -q "install-gate: blocked" && BLOCKMSG=yes
CALLS=$(called "$WORK/norecord/run.jsonl")

echo
echo "Claude Code: $(claude --version 2>/dev/null | head -1)"
echo "run 1  plugin, no record     marker: $(mark norecord)   first result is the block message: $BLOCKMSG   Bash calls: $CALLS"
echo "run 2  plugin, record LOW    marker: $(mark low)"
echo "run 3  no plugin (control)   marker: $(mark without)"
he_scan "$HE_NAME_RE" "$HE_SIGN_RE" "$WORK/without/run.jsonl" -- "$WORK/norecord/run.jsonl" "$WORK/low/run.jsonl"
he_report "$HE_PLUGIN"
echo
he_gate 0
if [ "$?" = "2" ]; then
  he_explain_not_run "$HE_PLUGIN"
  echo
  echo "Logs are kept in $WORK."
  exit 2
fi

RC=0
if [ "$(mark without)" = "present" ]; then echo "Control: without the plugin the fake install ran = the instrument works."
else echo "Control: the fake install did not run even without the plugin. If install-gate is already installed, that is why. Otherwise this check cannot tell."; RC=2; fi
if [ "$(mark norecord)" = "absent" ] && [ "$BLOCKMSG" = "yes" ]; then echo "run 1: working (the hook ran and the install was blocked before it ran)"
else echo "run 1: NOT working (the hook ran, and the install ran or the first result was not the block message)"; RC=1; fi
if [ "$(mark low)" = "present" ]; then echo "run 2: working (a tool with a LOW record installs without a stop)"
else echo "run 2: NOT working (a tool with a LOW record was stopped)"; RC=1; fi
he_gate "$RC"
if [ "$?" = "2" ] && [ "$RC" = "1" ]; then he_explain_mixed "$HE_PLUGIN"; RC=2; fi
echo
echo "Logs are kept in $WORK."
exit "$RC"
