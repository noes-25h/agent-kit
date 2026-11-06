---
name: morning
description: Build one page for the start of a working day. Reads the previous daily record, the file that says where things stand, the open tasks, and the commits since the previous record, then writes a single page with today's focus and shows it. Use when the user says "good morning", "where were we", "what is today", or starts a day in this repository.
allowed-tools: Read, Bash(git status *), Bash(git log *)
---

# morning

Put the previous day and today's focus on one page. The page is built from files. It is not a plan you invent.

## Paths and time

```!
bash "${CLAUDE_PLUGIN_ROOT}/scripts/paths.sh" "${CLAUDE_PROJECT_DIR}"
```

If the block above shows no `key: value` lines, run that same command with the Bash tool before anything else. Use the paths and the date exactly as printed.

## Step 1. Read

Read these, and only these. Skip the ones that do not exist.

1. `journal_previous`: the whole file. When `journal_today` exists as well, read it too, because the day has already started.
2. `now_file`.
3. `tasks_file`: the open tasks (`- [ ]`).
4. `decisions_file`: the first five `## ` entries.
5. `git log --oneline --since="<date of journal_previous> 00:00"` and `git status --short`. These show work that was done without a wrap-up. When the folder is not a git repository, skip this.

When `memory_dir` does not exist, there is nothing to read. Tell the user that no records exist yet and that the wrap-up skill creates them, and stop. Do not write an empty page.

## Step 2. Write the page

File: `today_file`. Rewrite the whole file every time.

```markdown
# Today: YYYY-MM-DD (Weekday)

Built at HH:MM from: <the files that were read>

## Where things stand
Two to four lines, taken from the now file. Say so when the now file is older than the previous daily record.

## Since the last record (YYYY-MM-DD)
- What was finished, from "Done".
- Commits that no record mentions, when there are any. Mark them "(not in the record)".

## Focus for today
1. At most three items. The first one comes from the last "Next" block unless a task or a blocker clearly outranks it.
2. For each item, name the file or command to start from.

## Waiting or unclear
- What is blocked and on what. Questions the records leave open. Write "nothing" when there is nothing.
```

Rules for the page:

- Every line must trace back to something you read. When two sources disagree, show both and say which is newer.
- Do not carry a "Next" item forward silently when the commits show that it was already done. Say that it appears to be done.
- When the previous record is more than seven days old, say so on the first line of "Where things stand".
- Keep the page under 40 lines.

## Step 3. Show it

Print the page to the user as it was written. Do not ask what to do next. The user reads the page and decides.

## What this skill does not do

It does not read a calendar, mail, or an issue tracker. If the user has connected such tools and asks for them, read them and add a section. Without being asked, stay with the files above.
