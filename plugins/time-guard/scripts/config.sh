#!/bin/bash
# Settings for time-guard. This is the only file you edit.
# now.sh and check-write.sh read it through lib.sh. The file itself executes nothing.
# After you edit it, run tests/selftest.sh.

# Time zone. Empty = use the time zone of the machine (and of the TZ environment variable, if set).
# To fix it, write an IANA name such as "Europe/Berlin" or "Asia/Tokyo".
# The environment variable TIME_GUARD_TZ, when set, wins over this line.
# A name that this machine does not know is not used: the system time zone is shown and the text says so.
TG_TZ=""

# Which files the wording check looks at. Space-separated shell patterns, matched against the
# file name (not the folder). "*" = every file.
TG_PATHS="*.md *.mdx *.txt *.rst *.org *.adoc"

# 1 = also show a one-line notice on screen when the wording check finds something.
# 0 = only Claude receives the note.
TG_SHOW_USER=0

# Wording table. One row = one pattern: kind, name, and the rest of the line is a regex
# (grep -E syntax, matched without regard to case; spaces are allowed).
# Kind:
#   clock = a time-of-day claim. Skipped when the same sentence has a clock time (TG_HAS_CLOCK_RE)
#           or a calendar date (TG_HAS_DATE_RE). A sentence ends at a line break, after 。, and
#           after . ! ? followed by a space. A clock time in another sentence does not skip it.
#   day   = a relative day. Skipped when the text has a calendar date anywhere (TG_HAS_DATE_RE).
#   span  = a claim about how long something took. Never skipped.
# When you add a row, add a sample with the same name to tg_sample in tests/selftest.sh, and update
# TG_EXPECT_ROWS near the end of that file. selftest fails on a row that has no sample.
tg_rows() {
  cat <<'TG_TABLE'
clock  en-part-of-day   \<this (morning|afternoon|evening)\>
clock  en-night         \<(tonight|last night|earlier today|late at night)\>
clock  ja-part-of-day   今朝|午前|午後|夕方|今晩|深夜|未明|昼休み
day    en-relative-day  \<(yesterday|tomorrow)\>
day    ja-relative-day  昨日|明日|昨夜|今夜
span   en-length        \<(for hours|all day long|the whole day|half a day|hours of work)\>
span   ja-length        半日かけて|丸一日|数時間にわたって|数時間に渡って|何時間も
TG_TABLE
}

# What counts as "a clock time is written": 14:30, 9時, 9 時, 3 pm (a length such as 3時間 is not one)
TG_HAS_CLOCK_RE='[0-9]{1,2}:[0-9]{2}|[0-9]{1,2} ?時|[0-9]{1,2} ?[ap]\.?m\.?\>'
# What counts as "a calendar date is written": 2026-10-09, 2026/10/09, 10月9日, 10 月 9 日
TG_HAS_DATE_RE='[0-9]{4}[-/][0-9]{1,2}[-/][0-9]{1,2}|[0-9]{1,2} ?月 ?[0-9]{1,2} ?日'

# Set only when the file was read to the end.
TG_CONFIG_LOADED=1
