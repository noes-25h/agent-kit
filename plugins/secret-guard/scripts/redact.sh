#!/bin/bash
# secret-guard / PostToolUse and PostToolUseFailure (both for Bash)
#
# PostToolUse        If the output of a successful Bash command contains a key-shaped string,
#                    replace what Claude receives with a redacted copy.
# PostToolUseFailure The output of a failed Bash command cannot be replaced (Claude Code behavior).
#                    If it contains a key-shaped string, only notify the user and Claude.
#
# What this cannot do: the command has already run, and the raw transcript keeps the original output.
#                      If a real key was printed, rotate it even though it was redacted.

SG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
INPUT=$(cat)

# Without jq the input cannot be parsed. Return a fixed notice and let the call through
# (block.sh, the blocking side, works without jq).
if ! command -v jq >/dev/null 2>&1; then
  printf '%s\n' '{"systemMessage":"secret-guard: jq was not found, so output redaction is not active. Install jq."}'
  exit 0
fi

[ "$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)" = "Bash" ] || exit 0
EVENT=$(printf '%s' "$INPUT" | jq -r '.hook_event_name // empty' 2>/dev/null)

[ -r "$SG_DIR/patterns.sh" ] && . "$SG_DIR/patterns.sh"
if [ "${SG_PATTERNS_LOADED:-0}" != "1" ]; then
  printf '%s\n' '{"systemMessage":"secret-guard: could not load the detection patterns (scripts/patterns.sh), so output redaction is not active. Reinstall the plugin."}'
  exit 0
fi

sg_has_secret() {
  printf '%s' "$1" | grep -qE -e "$SG_REDACT_RE" -e "$SG_PEM_BEGIN_RE" 2>/dev/null
}

# Redact one string. Whether it ends with a newline is kept as it was.
sg_redact() {
  local val="$1" out
  out=$(printf '%s' "$val" \
        | sed -E "s/($SG_REDACT_RE)/$(printf '%s' "$SG_MARK" | sed 's/[][\/&]/\\&/g')/g" \
        | awk -v b="$SG_PEM_BEGIN_RE" -v e="$SG_PEM_END_RE" -v m="$SG_MARK" '
            skip { if ($0 ~ e) skip = 0; next }
            $0 ~ b { print m; if ($0 !~ e) skip = 1; next }
            { print }'
        printf x)
  out="${out%x}"
  case "$val" in
    *$'\n') ;;
    *) out="${out%$'\n'}" ;;
  esac
  printf '%s' "$out"
}

# --- failed command: notify only ---
if [ "$EVENT" = "PostToolUseFailure" ]; then
  ERR=$(printf '%s' "$INPUT" | jq -r '.error // empty' 2>/dev/null)
  sg_has_secret "$ERR" || exit 0
  jq -cn '{
    systemMessage: "secret-guard: the output of a failed command contained a key-shaped string. Failed output cannot be redacted, so Claude has received it. If the key is real, rotate it.",
    hookSpecificOutput: {
      hookEventName: "PostToolUseFailure",
      additionalContext: "secret-guard: the output of this command contains a key-shaped string. Do not quote it, reuse it, or write it to a file. Tell the user that a key appeared in the output."
    }
  }'
  exit 0
fi

[ "$EVENT" = "PostToolUse" ] || exit 0

# --- successful command: replace the output with a redacted copy ---
# tool_response is an object: {stdout, stderr, interrupted, isImage, ...}.
# The replacement must have the same shape, or Claude Code silently discards it.
# Redact each string field and put it back under the same key; leave every other field untouched.
TR=$(printf '%s' "$INPUT" | jq -c '.tool_response | select(type == "object")' 2>/dev/null)
[ -n "$TR" ] || exit 0
ALL=$(printf '%s' "$TR" | jq -r '[.[] | strings] | join("\n")' 2>/dev/null)
sg_has_secret "$ALL" || exit 0

OUT="$TR"
while IFS= read -r KEY; do
  [ -n "$KEY" ] || continue
  VAL=$(printf '%s' "$TR" | jq -j --arg k "$KEY" '.[$k]' 2>/dev/null; printf x); VAL="${VAL%x}"
  sg_has_secret "$VAL" || continue
  RED=$(sg_redact "$VAL"; printf x); RED="${RED%x}"
  OUT=$(printf '%s' "$OUT" | jq -c --arg k "$KEY" --arg v "$RED" '.[$k] = $v' 2>/dev/null) || OUT=""
  [ -n "$OUT" ] || break
done <<EOF
$(printf '%s' "$TR" | jq -r 'to_entries[] | select(.value | type == "string") | .key' 2>/dev/null)
EOF

# If rebuilding failed or something is still left, send no replacement and say so
# (never claim a raw value was redacted).
if [ -z "$OUT" ] || sg_has_secret "$(printf '%s' "$OUT" | jq -r '[.[] | strings] | join("\n")' 2>/dev/null)"; then
  jq -cn '{systemMessage: "secret-guard: Bash output contained a key-shaped string, but it could not be redacted. Claude has received it. If the key is real, rotate it."}'
  exit 0
fi

printf '%s' "$OUT" | jq -c '
  (.stdout //= "") | (.stderr //= "") | (.interrupted //= false) | (.isImage //= false)
  | {
      systemMessage: "secret-guard: Bash output contained a key-shaped string; what Claude receives was redacted. The command has already run and the raw transcript keeps the original output. If the key is real, rotate it.",
      hookSpecificOutput: { hookEventName: "PostToolUse", updatedToolOutput: . }
    }'
exit 0
