#!/bin/sh
# Counts the service configs that use the new key (timeout_ms) and no longer use the old one (timeout).
# Prints "N of 5 migrated". Exit 0 only when all five are migrated.
cd "$(dirname "$0")" || exit 2
n=0
for f in services/*.conf; do
  if grep -q '^timeout_ms=' "$f" && ! grep -q '^timeout=' "$f"; then n=$((n+1)); fi
done
echo "$n of 5 migrated"
[ "$n" = "5" ]
