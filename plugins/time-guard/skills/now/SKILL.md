---
name: now
description: Reads the current local date and time from the system clock. Use before writing a timestamp, a date, an elapsed time, or wording such as "this morning" or "tomorrow" into a file, a commit message, or a reply, and when time-guard reports time wording with no clock time next to it.
---

# now

The line below was produced by running the time-guard clock script at the moment this skill was loaded. It is not an estimate.

!`bash "${CLAUDE_PLUGIN_ROOT}/scripts/now.sh" plain`

If the line above is empty, or shows the command instead of a time, shell execution for skills is turned off in this session. In that case run `date '+%Y-%m-%d (%a) %H:%M:%S %z'` with the Bash tool and use its output.

## How to write time from this value

- A time of day is written as a clock time taken from the value above, for example `14:30`, together with the zone when the reader may be elsewhere.
- A day is written as a calendar date, for example `2026-10-09`. "Tomorrow" and "yesterday" are computed from the date above and written as dates.
- An elapsed time is the difference between two values that were both read from a clock or from a record such as a commit time. When only one value exists, the length is not known and is not written.
- An event that has no recorded time is named by what happened ("after the migration finished"), not by a part of the day.
- A time inside a quotation, or in a record written by someone else, is left as it is.

This value is correct for the moment the skill was loaded. In a long task, load the skill again before the next timestamp.
