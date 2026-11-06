#!/bin/bash
# Check judgment-index against real Claude Code sessions.
#
# Unpacks the sample index into an empty work folder, then sends scenarios from the sample
# roster to Claude Code (claude -p) in three arms and records, from the tool calls of each
# session, whether INDEX.md and a category file were opened.
#
#   without    the index files are in the folder; the plugin is not loaded
#   with       the same files, and the plugin is loaded (--plugin-dir)
#   with-line  the same as "with", plus the one line in CLAUDE.md that the README suggests
#
# Only tool calls are used for "was the index opened". The last line of each answer
# (OUTCOME: ...) is the session's own report and is shown as such.
#
# Usage: bash tests/live-check.sh            3 scenarios x 3 arms = 9 calls
#        bash tests/live-check.sh --n 5      more scenarios
#        bash tests/live-check.sh --ids 2,3  chosen scenarios
# Needs: claude (logged in), python3. Each call uses your usage allowance.
# Exit code: 0 = with the plugin the index was opened in every scenario
#            1 = it was not / 2 = cannot tell (a call did not finish, or no control)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v claude >/dev/null 2>&1 || { echo "claude was not found."; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 was not found."; exit 2; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/judgment-index-sample.XXXXXX") || { echo "Could not create a work folder."; exit 2; }
python3 "$ROOT/scripts/judgment.py" init --dir "$WORK/judgment" >/dev/null || { echo "Could not unpack the sample index into $WORK."; exit 2; }

python3 "$ROOT/scripts/judgment.py" measure --dir "$WORK/judgment" --plugin-dir "$ROOT" "$@"
