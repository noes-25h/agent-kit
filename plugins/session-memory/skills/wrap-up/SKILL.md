---
name: wrap-up
description: Close a working session. Writes the daily record (done, learned, next), rewrites the file that says where things stand, and adds the decisions of this session to the decision log. Use when the user says "wrap up", "end the session", "save where we are", or before a risky step as a checkpoint.
allowed-tools: Read, Bash(git status *), Bash(git log *), Bash(git diff --stat *)
---

# wrap-up

Record this session so that the next one can start from where this one stopped. The session-start hook of this plugin reads the files written here, so the formats below are fixed.

## Paths and time

```!
bash "${CLAUDE_PLUGIN_ROOT}/scripts/paths.sh" "${CLAUDE_PROJECT_DIR}"
```

If the block above shows no `key: value` lines, run that same command with the Bash tool before anything else. Use the paths, the date, and the time exactly as printed. Do not compute a date or a time yourself.

## What counts as a source

Write only what happened in this conversation, plus what `git status` and `git log` show for today. If something was planned but not done, it belongs under Next, not under Done. If you are not sure whether something was finished, check it or write that it was not checked. Do not write secrets, tokens, or passwords into any of these files; refer to them by name only.

Write in the language the user has been using. Keep the headings below in English, exactly as written, because the hook matches them.

## Step 1. The daily record

File: `journal_today`. Create the folder and the file when they do not exist. When the file exists, append a new session block at the end and leave earlier blocks untouched.

```markdown
# YYYY-MM-DD

## Session HH:MM

### Done
- One line per finished piece of work. Name the files or commands that prove it.

### Learned
- What turned out to be different from what was assumed. Include what failed and why.

### Next
- The first thing to do next time, written so that it can be started cold.
- At most five lines. The hook shows the last "Next" block of the latest day.
```

The `# YYYY-MM-DD` line appears once, at the top of the file. Leave a section with a single line `- (nothing)` when there is nothing to write. Do not pad.

## Step 2. Where things stand

File: `now_file`. Rewrite the whole file. It is a statement of the present, and history belongs in the daily record.

```markdown
# Now

Updated: YYYY-MM-DD HH:MM

- Goal: what this repository is working toward at the moment.
- State: what works, what is half done, what is broken.
- Blocked on: what is waiting, and on whom or what. Write "nothing" when nothing is.
- Entry point: the file or command to open first next time.
```

Keep it under 20 lines and keep every line under 200 bytes. The hook shows about 30 lines and cuts longer lines.

## Step 3. Decisions

File: `decisions_file`. Add only decisions that were actually made in this session by the user, or made by you and accepted by the user. A proposal that was not answered is not a decision. When there is none, skip this step and say so.

Insert new entries directly below the `# Decisions` title, above the older entries. The newest entry is always first.

```markdown
# Decisions

## YYYY-MM-DD Short title of the decision
- Decided: what was chosen.
- Why: the reason given at the time.
- Instead of: what was rejected, when something was.
```

The hook shows the title lines of the first five `## ` entries. Put the substance in the title.

When a new decision replaces an older one, do not delete the older entry. Add `- Replaced by: YYYY-MM-DD title` to it.

## Step 4. Tasks

File: `tasks_file`. Skip this step when the file does not exist and the user has not asked for a task list.

- Change `- [ ]` to `- [x]` for tasks finished in this session.
- Add new tasks as `- [ ] ...` lines. Put what matters most at the top. The hook shows the first eight open tasks.
- Do not reorder or reword tasks that the user wrote.

## Step 5. Report

Tell the user, in a few lines: which files were written, the "Next" lines, and anything you could not verify. Do not commit. If the user wants the records in version control, they will ask.

## When something is in the way

- A file has a shape that differs from the formats above: keep its content, append in the format above, and tell the user what you saw.
- `ignored_settings` appears in the paths block: tell the user which keys were ignored.
- The daily record of today already has a block for this same session: update that block and do not add a second one.
