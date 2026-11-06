#!/bin/bash
# Shared by now.sh and check-write.sh: load the settings, resolve the time zone, read the clock.
# The file itself prints nothing.

TG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

# Load config.sh only when it parses. A broken settings file must not take the clock away:
# the defaults (system time zone) are used and TG_CONFIG_LOADED stays 0.
TG_CONFIG_LOADED=0
TG_TZ=""; TG_PATHS="*.md *.mdx *.txt *.rst *.org *.adoc"; TG_SHOW_USER=0
if [ -r "$TG_DIR/config.sh" ] && bash -n "$TG_DIR/config.sh" 2>/dev/null; then
  . "$TG_DIR/config.sh"
fi

# Decide which time zone to use.
#   TG_USE_TZ   = the IANA name to use, or empty for the system time zone
#   TG_TZ_NOTE  = a sentence to add when the requested zone could not be used
# date(1) does not fail on an unknown TZ name; it prints UTC without a word. So the name is checked
# against the zone files first, and an unknown name falls back to the system time zone, in the open.
tg_resolve_tz() {
  local want="${TIME_GUARD_TZ:-$TG_TZ}" d
  TG_USE_TZ=""; TG_TZ_NOTE=""
  [ -n "$want" ] || return 0
  case "$want" in
    *[!A-Za-z0-9_+/-]*|/*|*..*)
      TG_TZ_NOTE="The time zone set for time-guard is not a valid zone name, so the system time zone is shown."
      return 0 ;;
  esac
  for d in "${TZDIR:-}" /usr/share/zoneinfo /usr/lib/zoneinfo /usr/share/lib/zoneinfo; do
    [ -n "$d" ] && [ -f "$d/$want" ] && { TG_USE_TZ="$want"; return 0; }
  done
  TG_TZ_NOTE="The time zone set for time-guard ($want) was not found on this machine, so the system time zone is shown."
}

# Print the current time as one line, for example:
#   2026-10-09 (Fri) 07:04:31, UTC+09:00 (JST)
# Prints nothing and returns 1 when the clock could not be read in the expected form.
tg_now() {
  local raw z abbr
  tg_resolve_tz
  if [ -n "$TG_USE_TZ" ]; then
    raw=$(LC_ALL=C TZ="$TG_USE_TZ" date '+%Y-%m-%d (%a) %H:%M:%S|%z|%Z' 2>/dev/null)
  else
    raw=$(LC_ALL=C date '+%Y-%m-%d (%a) %H:%M:%S|%z|%Z' 2>/dev/null)
  fi
  case "$raw" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\ \([A-Z][a-z][a-z]\)\ [0-9][0-9]:[0-9][0-9]:[0-9][0-9]\|[+-][0-9][0-9][0-9][0-9]\|*) ;;
    *) return 1 ;;
  esac
  z=${raw#*|}; z=${z%%|*}
  abbr=$(printf '%s' "${raw##*|}" | LC_ALL=C tr -cd 'A-Za-z0-9+-')
  printf '%s, UTC%s:%s (%s)' "${raw%%|*}" "${z:0:3}" "${z:3:2}" "${abbr:-local}"
}

# Where the zone came from, as a short phrase.
tg_zone_source() {
  if [ -n "$TG_USE_TZ" ]; then printf 'time zone %s, set for time-guard' "$TG_USE_TZ"
  else printf 'time zone of this machine'; fi
}
