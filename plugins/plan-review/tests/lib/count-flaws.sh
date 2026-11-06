#!/bin/bash
# Count how many of the planted flaws a piece of review text names.
#
# Usage: bash count-flaws.sh <flaws.tsv> <text-file>
# Prints one line per flaw ("found" or "missed"), then "found N of M".
# Exit code: 0 = counted / 2 = could not count (file missing, no rows, bad pattern)
#
# This is a keyword counter. "found" means: one line of the text has a word for the subject of the
# flaw and a word that says something is wrong. It does not mean the reviewer understood the flaw.
# Read the matching lines yourself before you rely on the number.

TSV="$1"; TEXT="$2"
[ -f "$TSV" ] && [ -f "$TEXT" ] || { echo "count-flaws: file not found"; exit 2; }

LOWER=$(tr '[:upper:]' '[:lower:]' < "$TEXT")
N=0; M=0; BAD=0
while IFS=$'\t' read -r id anchor subject problem desc; do
  case "$id" in ''|'#'*) continue ;; esac
  M=$((M+1))
  if [ -z "$subject" ] || [ -z "$problem" ]; then echo "  bad row      $id"; BAD=1; continue; fi
  # Both patterns must compile (grep exits 2 on a bad pattern)
  printf 'x\n' | grep -qE -e "(^|[^a-z0-9])($subject)" 2>/dev/null; [ "$?" = "2" ] && { echo "  bad pattern  $id"; BAD=1; continue; }
  printf 'x\n' | grep -qE -e "(^|[^a-z0-9])($problem)([^a-z0-9]|\$)" 2>/dev/null; [ "$?" = "2" ] && { echo "  bad pattern  $id"; BAD=1; continue; }
  if printf '%s\n' "$LOWER" | grep -E -e "(^|[^a-z0-9])($subject)" 2>/dev/null \
       | grep -qE -e "(^|[^a-z0-9])($problem)([^a-z0-9]|\$)" 2>/dev/null; then
    N=$((N+1)); echo "  found   $id"
  else
    echo "  missed  $id"
  fi
done < "$TSV"

[ "$M" -gt 0 ] || { echo "count-flaws: no rows in $TSV"; exit 2; }
[ "$BAD" = "0" ] || exit 2
echo "found $N of $M"
