# handoff

日本語: [README.ja.md](README.ja.md)

A Claude Code plugin that holds one skill. The skill is for the end of a session that leaves work unfinished. The next session starts with none of this conversation, so the skill tells Claude to turn what is left into something that can be run from nothing.

Each leftover item goes to one of three exits.

1. **An instruction sheet**, when completion can be confirmed by a command and no human decision is needed on the way. The sheet is a file with stop conditions, steps, paths that may and may not be touched, and conditions for giving up.
2. **A standalone prompt**, when the item is a small single action. It is printed in the reply, ready to paste into a new session.
3. **A note**, for everything else. Its first sentence names what is not decided.

Every instruction sheet opens with a section called "Re-check at start": the facts the sheet was written on, each with a command that confirms it. If one of them no longer holds, the instruction is to stop and report, not to improvise a repair.

This is the skill that 25h runs in its own working environment, repackaged to work on its own. The names of 25h's own ledgers, paths, and tools were removed.

## What it does not do

Read this before you install.

- It is a prompt. It does not enforce anything. Claude can leave out a section, and nothing in the plugin stops that.
- It was checked against a real Claude Code session on 2026-10-19 (Claude Code 2.1.303), on 2026-10-31 (2.1.314), and on 2026-11-01 (2.1.316). In the latest run: 14 of 14 points with the plugin, 8 of 14 without. See "Verify" below. The count is keyword matching, and whether a new session can run the sheet it wrote was not measured.
- It does not do the remaining work, and it does not start the next run. It writes the sheet and gives you the line that would start it.
- It does not record what happened in the session. It is not a diary.
- It does not promise that the next session succeeds. A sheet reduces what the next session has to guess. Whether the premises still hold is found out when the sheet is run.
- It reads the conversation it is called in. Called in a fresh session, it has nothing to hand off unless you point it at a record.

## Requirements

- Claude Code. The version checked is 2.1.316.
- macOS or Linux for the two test scripts. They use bash, grep, sed, awk, and jq. The skill itself is a Markdown file and has no such requirement.

## Install

Run these two commands in order. Claude Code fetches the plugin from `noes-25h/agent-kit` on GitHub. If you already ran the first command for another plugin of this repository, run only the second.

```bash
claude plugin marketplace add noes-25h/agent-kit
```

```bash
claude plugin install handoff@25h-agent-kit
```

To see whether it is installed, run the next command. It is installed when `handoff@25h-agent-kit` is listed as `enabled`.

```bash
claude plugin list
```

A Claude Code session that is already open picks it up after you reopen it or type `/reload-plugins`. The plugin applies to every project.

To try it once without installing, clone this repository (`git clone https://github.com/noes-25h/agent-kit`) and, from the root of the clone, point Claude Code at the folder when you start it.

```bash
claude --plugin-dir ./plugins/handoff
```

## Use

Inside the Claude Code session that is about to end:

```
/handoff:handoff
```

A skill inside a plugin is called as `/<plugin name>:<skill name>`. Both names are `handoff` here, so the command is `/handoff:handoff`. According to the skills page, the short form `/handoff` also works unless another command already uses that name.

What you can pass:

- A description of what to hand off, when you want less than everything that is left.
- `--plans-dir <dir>` to say where instruction sheets go.
- `--tasks-file <path>` to say where notes about undecided items go.

Claude can also load the skill by itself when your message matches its description, for example when you ask for a handoff to the next session. To allow only the typed command, add `disable-model-invocation: true` to the frontmatter of `plugins/handoff/skills/handoff/SKILL.md`.

**Where things go.** For each of the two places the skill decides in this order: the argument; then `.claude/handoff.json` at the root of your project, for example `{"plans_dir": "docs/handoff", "tasks_file": "TODO.md"}`. When neither is present, instruction sheets go to `docs/handoff/`, and notes are put in the reply with no file created.

**Starting the run.** For each instruction sheet the skill prints one line that begins with `/goal`. `/goal` is a Claude Code command that keeps a session working until a condition holds (https://code.claude.com/docs/en/goal). Paste the line into a new session when you want the run to start. The skill does not start it.

**Model and effort.** The frontmatter sets `model: inherit` and `effort: medium`. The skill runs on whatever model your session uses. Change either line if you want something else.

## Verify

Run the commands in this section from the root of a clone of this repository (`git clone https://github.com/noes-25h/agent-kit`).

There are two levels of verification. The first one alone tells you little.

**The files.** This checks the manifests, the frontmatter of the skill, the sections and sentences it must have, and the fixture that the second check scores against. It runs 49 checks, does not call Claude Code, and finishes in a few seconds.

```bash
bash ./plugins/handoff/tests/selftest.sh
```

**A real Claude Code session.** This copies a small sample repository in which a migration stopped at 2 of 5, with one item that needs a decision and one small one-off. It runs Claude Code on it once with the skill and once with a plain request, and counts how many of 14 expected points the written files and the reply meet. The points are listed in `plugins/handoff/tests/fixtures/stopped-session/expected.tsv`. It uses two calls of your usage allowance.

```bash
bash ./plugins/handoff/tests/live-check.sh
```

**What 25h got from this check.** The latest run was on 2026-11-01 with Claude Code 2.1.316. With the plugin, 14 of the 14 points were met; without it, 8. The threshold is 10. The number without the plugin is there for comparison: a capable model meets several points with no skill at all. That is one run on one machine. Your result can differ.

What the count is and is not. Each point is a keyword pattern. The count can include a point that was mentioned for the wrong reason, and can miss one that was phrased differently. The threshold of 10 in `expected.tsv` was chosen by reading, not tuned against runs. One run is one sample; Claude does not answer the same way twice. The count also does not answer the real question, which is whether a new session can run the sheet. To see that, open a new session in the work folder that the script keeps and give it the sheet.

## Adjust

The skill is one file: `plugins/handoff/skills/handoff/SKILL.md`. Edit it freely. The instruction sheet template is inside it, under "Step 3A".

- When you rename or remove a section, including a section of the template, update `REQUIRED_SECTIONS` near the top of `tests/selftest.sh` to match. Otherwise selftest fails. The list exists so that a section does not disappear without anyone noticing.
- The same holds for `REQUIRED_PHRASES`. Those are single sentences that carry a rule, such as the one that says to stop when a premise fails.
- To score against a situation from your own project, add a folder next to `tests/fixtures/stopped-session/` with a `repo/` and an `expected.tsv`, and point `FIX` in `tests/live-check.sh` at it.

To change it, edit a clone of this repository and install from the clone instead of from GitHub (`claude plugin marketplace add ./agent-kit`, run from the folder one level above the clone). The plugin is then read directly from the clone. If you already installed from GitHub, this points the `25h-agent-kit` source at the clone, and plugins already installed from it update from the clone from then on. To go back, run `claude plugin marketplace add noes-25h/agent-kit`. Changes take effect after you reopen Claude Code or type `/reload-plugins`. Run selftest after every change.

## Uninstall

```bash
claude plugin uninstall handoff@25h-agent-kit
```

```bash
claude plugin marketplace remove 25h-agent-kit
```

The second command removes the registration of this repository as a source. Skip it if you still use another plugin from this repository.

After uninstalling, a copy of the plugin remains in the Claude Code config folder (`~/.claude/plugins/cache/25h-agent-kit/`). It is no longer read, and you can delete it by hand. Nothing is left in `settings.json`. Instruction sheets, notes, and `.claude/handoff.json` in your projects are yours and stay where they are.

## Sources

The plugin layout, the way a plugin skill is called, and the frontmatter fields were checked against these pages on 2026-10-09.

- Plugins: https://code.claude.com/docs/en/plugins
- Skills (frontmatter reference, "How a skill gets its command name", string substitutions): https://code.claude.com/docs/en/skills
- Plugin manifest reference: https://code.claude.com/docs/en/plugins-reference
- `/goal`: https://code.claude.com/docs/en/goal
- Running Claude Code non-interactively, used by live-check: https://code.claude.com/docs/en/headless

## License

MIT. See [LICENSE](LICENSE).
