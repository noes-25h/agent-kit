# time-guard

日本語: [README.ja.md](README.ja.md)

A Claude Code plugin. Claude Code gives Claude today's date but not the current time. In a long session, Claude can end up treating an old time from the conversation as now, or writing "this morning" without having looked at a clock. This plugin does three things about that.

1. On every prompt, and when a session starts, resumes, or is compacted, it reads the system clock and gives Claude the current local date and time.
2. When Claude writes text that has time wording with no clock time or date next to it ("this morning", "tomorrow", "for hours"), it adds a note for Claude that carries the current time. The write is not blocked.
3. It adds one skill, `/time-guard:now`, that reads the clock at the moment it is called.

These are the hooks that 25h runs in its own working environment, repackaged to work on their own.

**Status: the check against a real Claude Code session passed for this version (0.1.1) on 2026-10-31 with Claude Code 2.1.314.** The hook scripts and the install path were checked in an empty environment, and `tests/live-check.sh` showed that Claude Code hands the time and the note to Claude with this plugin installed (see Verify). That is one run of this version on this Claude Code on one machine. Run it again after you update Claude Code.

## What it does not cover

Read this before you install.

- The middle of a long turn. The clock is read when a prompt is submitted. If Claude then works for an hour without a new prompt, that value is an hour old. The note on a write and the skill carry a fresh time; nothing else does.
- Text that does not go through a file tool. The wording check looks at Write, Edit, MultiEdit, and NotebookEdit. A commit message, a file written with a shell command, and a reply in the chat are not checked.
- Files outside the list. By default only file names that end in `.md`, `.mdx`, `.txt`, `.rst`, `.org`, or `.adoc` are checked.
- Wording that is not in the table. The table has seven rows, English and Japanese. It is in `plugins/time-guard/scripts/config.sh`.
- A wrong clock time. The check looks for wording with no value next to it. It does not know whether `14:30` is the right time. A clock time or a date in a sentence turns the time-of-day rows off for that sentence.
- A time of day that does not mean now. "Evening decisions are slower" is noted like "this morning". The check cannot tell the two apart.
- A date written without a year and without 月 and 日, such as `5/9`. It is not taken as a date.
- What Claude does with it. The plugin gives Claude a value and a note. It does not force Claude to use them.
- A resumed session. Claude Code replays the time lines of earlier turns from the transcript as they were. The newest line is the current one, and each line says when it was read.

The plugin adds about 300 characters of context to every prompt. The description of the skill adds under 150 tokens to every session, as reported by `claude plugin details`.

## Requirements

- Claude Code. The version checked is 2.1.314.
- macOS or Linux. It uses bash, date, grep, sed, awk, tr, and jq. Windows is not supported.
- Without jq, the clock on every prompt still works. The wording check does not, and a notice is shown on every write.

## Install

Run these two commands in order. Claude Code fetches the plugin from `noes-25h/agent-kit` on GitHub. If you already ran the first command for another plugin of this repository, run only the second.

```bash
claude plugin marketplace add noes-25h/agent-kit
```

```bash
claude plugin install time-guard@25h-agent-kit
```

To see whether it is installed, run the next command. It is installed when `time-guard@25h-agent-kit` is listed as `enabled`.

```bash
claude plugin list
```

A Claude Code session that is already open picks it up after you reopen it or type `/reload-plugins`. The plugin applies to every project. It does not rewrite the hooks in your own `settings.json`.

To try it once without installing, clone this repository (`git clone https://github.com/noes-25h/agent-kit`) and, from the root of the clone, point Claude Code at the folder when you start it.

```bash
claude --plugin-dir ./plugins/time-guard
```

## Verify

Run the commands in this section from the root of a clone of this repository (`git clone https://github.com/noes-25h/agent-kit`).

There are two levels of verification. The first one alone is not enough.

**The hook scripts.** This feeds the hooks the same input that Claude Code sends and runs 117 checks: the time is the system clock, the time zone follows the environment and the setting, the returned value has the accepted shape, and the wording check never blocks. It does not call Claude Code and finishes in a few seconds.

```bash
bash ./plugins/time-guard/tests/selftest.sh
```

**A real Claude Code session.** This runs Claude Code twice with the plugin and twice without it. It asks Claude for the time to the minute in a time zone that differs from the one of your machine, and it asks Claude to repeat the note after a write. It takes a few minutes and uses four calls of your usage allowance.

```bash
bash ./plugins/time-guard/tests/live-check.sh
```

Run it from a plain terminal. The check ends with one of three results. Exit code 0: the hooks ran and the time and the note reached Claude. Exit code 1: the hooks ran and the time or the note did not reach Claude. Exit code 2: it cannot tell. That is the result when a call did not finish, when the side without the plugin is not a control, or when the hooks did not run.

The check counts the hook lines that Claude Code records for each run. When no hook of this plugin ran to the end, it prints the reason on one line and gives no verdict. This is what happens when the check is started from inside a sandbox, for example from a Claude Code session: Claude Code cannot create the data folder of the plugin under `~/.claude/plugins/data/`, does not start the hook, and Claude receives nothing. The failure line then says `EPERM` or `operation not permitted`. Open a plain terminal and run the check again.

Why the second level is needed: when the value a hook returns has a slightly wrong shape, Claude Code discards it silently. No error is shown. The first check can pass in full while Claude receives nothing. Run the second check again after you update Claude Code.

25h ran the second check on 2026-10-31 with Claude Code 2.1.314 (version 0.1.1), with UTC given to the plugin as the time zone. It ended with exit code 0. With the plugin, the reply matched the system clock in UTC and repeated the phrase from the note; without it, neither. The file was written on both sides, since the note does not block anything. The hooks started 5 times and ran to the end 5 times.

## What happens

**On every prompt.** Claude receives one line like this. Nothing is shown on screen.

```
Current local time: 2026-10-09 (Fri) 07:04:31, UTC+09:00 (JST). This value was read from the system clock when this prompt was submitted (time zone of this machine). Dates and times that appear earlier in this conversation were read earlier and are older than this value.
```

**When Claude writes time wording with no value next to it.** The write runs. Claude receives this note next to the result of the write.

```
time-guard: the text being written to notes.md has time wording that is not backed by a value in the same text: 'this morning' (no clock time or date in the same sentence). Current local time: 2026-10-09 (Fri) 07:04:31, UTC+09:00 (JST) (time zone of this machine). The write was not blocked.
```

There are three kinds of wording.

| Kind | Example | Skipped when |
|---|---|---|
| A time of day | this morning, tonight, last night | the same sentence has a clock time, such as `14:30` or `6 pm`, or a calendar date |
| A relative day | yesterday, tomorrow | the text has a calendar date anywhere, such as `2026-10-09` (a date in a heading covers the whole text) |
| A length of time | for hours, half a day | never skipped |

A sentence ends at a line break, after `。`, and after `.` `!` `?` followed by a space. So in meeting notes that start with `14:00 start.`, a "this morning" in a later sentence is still noted. A length such as `3時間` (three hours) is not taken as a clock time.

An edit that removes such wording is not noted. The text being replaced is not scanned.

**When the clock cannot be read.** Claude receives nothing on the prompt. A missing time is better than a made-up one.

**A write with no time wording.** Nothing happens. Nothing is shown.

## Adjust

Edit only `plugins/time-guard/scripts/config.sh`.

- Time zone. By default the plugin uses the time zone of your machine, and the `TZ` environment variable if it is set. To fix another one, set `TG_TZ` to an IANA name such as `Europe/Berlin`. The environment variable `TIME_GUARD_TZ` wins over `TG_TZ`. A name that your machine does not know is not used: the system time zone is shown, and the text says so.
- Which files are checked. `TG_PATHS` is a list of file name patterns. Set it to `*` to check every file.
- A notice on screen. Set `TG_SHOW_USER` to 1 to see one line each time the wording check finds something. By default only Claude receives the note.
- The wording table. One row is one pattern with three columns (kind, name, regex). To stop looking for a pattern, delete its row. To add one, add a row and add a sample with the same name to `tg_sample` in `tests/selftest.sh`. selftest fails on a row that has no sample.

When you add or delete a row, update the record near the end of `tests/selftest.sh` (`TG_EXPECT_ROWS`) to match. Otherwise the last check of selftest fails. The record exists so that rows do not disappear without anyone noticing.

To change it, edit a clone of this repository and install from the clone instead of from GitHub (`claude plugin marketplace add ./agent-kit`, run from the folder one level above the clone). The plugin is then read directly from the clone. If you already installed from GitHub, this points the `25h-agent-kit` source at the clone, and plugins already installed from it update from the clone from then on. To go back, run `claude plugin marketplace add noes-25h/agent-kit`. Your changes take effect after you reopen Claude Code or type `/reload-plugins` in a session. Run selftest after every change. Its first section shows the settings that are in effect.

## Uninstall

```bash
claude plugin uninstall time-guard@25h-agent-kit
```

```bash
claude plugin marketplace remove 25h-agent-kit
```

The second command removes the registration of this repository as a source. Skip it if you still use another plugin from this repository.

After uninstalling, a copy of the plugin remains in the Claude Code config folder (`~/.claude/plugins/cache/25h-agent-kit/`). It is no longer read, and you can delete it by hand. Nothing is left in `settings.json`.

## How it is wired

The events and the shape of what the hooks return follow the official hooks reference: https://code.claude.com/docs/en/hooks (read on 2026-10-09).

| Event | Script | What it returns |
|---|---|---|
| `UserPromptSubmit` | `scripts/now.sh` | `hookSpecificOutput.additionalContext`, added next to the prompt |
| `SessionStart` | `scripts/now.sh` | `hookSpecificOutput.additionalContext`, added at the start of the conversation. This event runs again on resume and after compaction |
| `PreToolUse` (Write, Edit, MultiEdit, NotebookEdit) | `scripts/check-write.sh` | `hookSpecificOutput.additionalContext`, added next to the tool result. No `permissionDecision` is returned, so the permission flow is not touched |

The skill uses `${CLAUDE_PLUGIN_ROOT}` and the `` !`command` `` form described in the skills page: https://code.claude.com/docs/en/skills. When `disableSkillShellExecution` is on in your settings, the skill cannot read the clock by itself and tells Claude to run `date` instead.

## License

MIT. See [LICENSE](LICENSE).
