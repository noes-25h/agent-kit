#!/bin/bash
# install-gate / PreToolUse (Bash) wrapper.
# Runs gate.py. If gate.py cannot run or crashes, answer "ask" so the gate never opens silently.

INPUT=$(cat)
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

# Fast path: no package-manager word anywhere in the input -> nothing to gate.
# The word may be followed by a space, by a quote, or by a backslash (the input is JSON: a tab or a
# newline after the word arrives as \t or \n).
printf '%s' "$INPUT" | grep -qE "(brew|npm|pnpm|yarn|bun|pip[0-9.]*|pipx|uv|cargo|gem|claude|-m pip)([[:space:]]|\\\\|'|\")" || exit 0

ASK='{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"install-gate: the gate could not run (python3 is missing or failed), so it cannot tell whether this command installs something. Check the command before you approve."}}'

command -v python3 >/dev/null 2>&1 || { printf '%s\n' "$ASK"; exit 0; }
OUT=$(printf '%s' "$INPUT" | python3 "$DIR/gate.py" 2>/dev/null) || { printf '%s\n' "$ASK"; exit 0; }
[ -n "$OUT" ] && printf '%s\n' "$OUT"
exit 0
