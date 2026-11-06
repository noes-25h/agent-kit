#!/bin/bash
# Counts how many expected points a run met. Sourced by selftest.sh and live-check.sh.
#
# score_points EXPECTED REPLY_FILE REPO_DIR CHANGED
#   EXPECTED    the expected.tsv of a fixture (id, kind, pattern, description; tab-separated)
#   REPLY_FILE  a file holding the final reply of the run
#   REPO_DIR    the copy of the fixture repo that the run worked in
#   CHANGED     0 when no pre-existing file in REPO_DIR changed during the run, 1 otherwise
# Prints one line per point and sets SCORE_MET and SCORE_TOTAL.
#
# Kinds:
#   reply        pattern is searched in the reply
#   file:GLOB    pattern is searched in the files that GLOB matches inside REPO_DIR
#   untouched    met when CHANGED is 0
# Line breaks are turned into spaces before matching. Patterns are extended regex, case-insensitive.
# This is keyword matching. It does not judge whether the reasoning behind a keyword is right.

score_points() {
  local exp="$1" reply="$2" repo="$3" changed="$4" id kind pat desc text hit
  SCORE_MET=0; SCORE_TOTAL=0
  while IFS=$'\t' read -r id kind pat desc; do
    case "$id" in ''|\#*) continue ;; esac
    SCORE_TOTAL=$((SCORE_TOTAL+1)); hit=0
    case "$kind" in
      reply)
        text=$(tr '\n' ' ' < "$reply" 2>/dev/null)
        printf '%s' "$text" | grep -qiE -e "$pat" && hit=1 ;;
      file:*)
        text=$(cd "$repo" 2>/dev/null && cat ${kind#file:} 2>/dev/null | tr '\n' ' ')
        [ -n "$text" ] && printf '%s' "$text" | grep -qiE -e "$pat" && hit=1 ;;
      untouched)
        [ "$changed" = "0" ] && hit=1 ;;
    esac
    if [ "$hit" = "1" ]; then SCORE_MET=$((SCORE_MET+1)); echo "  met     $id: $desc"
    else echo "  missed  $id: $desc"; fi
  done < "$exp"
}

# The MIN value written in an expected.tsv comment line ("# MIN=8"). Prints nothing when absent.
score_min() { sed -n 's/^# MIN=\([0-9][0-9]*\)$/\1/p' "$1" | head -1; }
