#!/bin/bash
# secret-guard / PreToolUse
# Blocks a tool call that contains a key-shaped string, before it runs (exit 2).
# The reason goes to stderr, which Claude Code passes to Claude. The value itself is never printed.

INPUT=$(cat)

SG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
[ -r "$SG_DIR/patterns.sh" ] && . "$SG_DIR/patterns.sh"
if [ "${SG_PATTERNS_LOADED:-0}" != "1" ]; then
  # Patterns unreadable = nothing can be checked. Block instead of letting the call through.
  echo "secret-guard: could not load the detection patterns (scripts/patterns.sh), so this call was blocked. Reinstall the plugin." >&2
  exit 2
fi

# Scan the strings that are about to be executed or written.
# old_string (the text being replaced, which goes away) and file_path are skipped;
# otherwise an edit that removes a key would be blocked too.
# Without jq, or if jq fails, scan the whole input (fall to the broad side).
TEXT=""
if command -v jq >/dev/null 2>&1; then
  TEXT=$(printf '%s' "$INPUT" | jq -r '
    (.tool_input // {}) as $in
    | [ $in | paths(type == "string") as $p
        | select(($p | last) as $k | $k != "old_string" and $k != "file_path")
        | $in | getpath($p) ]
    | join("\n")' 2>/dev/null) || TEXT="$INPUT"
else
  TEXT="$INPUT"
fi
[ -n "$TEXT" ] || exit 0

sg_stop() {
  echo "secret-guard: blocked this call because it contains a string that matches the $1 key pattern. Do not write the value inline; read it from an environment variable or a secret store instead." >&2
  exit 2
}

while read -r name tier re; do
  [ "$tier" = "B" ] || continue
  printf '%s' "$TEXT" | grep -qE -e "$re" 2>/dev/null && sg_stop "$name"
done <<EOF
$(sg_rows)
EOF

printf '%s' "$TEXT" | grep -qE -e "$SG_PEM_BEGIN_RE" 2>/dev/null && sg_stop "private-key"

if [ "$SG_BLOCK_LITERALS" = "1" ]; then
  printf '%s' "$TEXT" | grep -qE -e "$SG_LITERAL_RE" 2>/dev/null && sg_stop "password-literal"
fi

exit 0
