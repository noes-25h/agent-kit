# judgment-index

日本語: [README.ja.md](README.ja.md)

A Claude Code plugin, and an empty frame that it unpacks into your repository. The frame is an index of judgment criteria: for each scene in which an agent would ask "may I do this", one row that says what to do, who decides, where that comes from, and what would prove it wrong.

It has five parts.

1. **The index and its categories.** `INDEX.md` and 15 category files. A category is a verb, what the agent is about to do: choose, set, publish, touch-live, unblock, reconcile, adopt, build, spend, respond, repair, assess, interpret, verify, allocate. Each category file ships with one or two sample rows.
2. **A tool** (`judgment.py`, Python standard library only) that checks the form of every row and generates the table of contents at the head of every category file.
3. **A skill, `consult`.** When Claude is about to ask whether it may do something, it reads `INDEX.md`, then the head of one category file, then one row. When no row matches, it adds one provisional row by a fixed procedure and continues.
4. **A skill, `capture`.** After a question was asked and answered, it turns the scene into a row, so that the answer stays in the repository.
5. **A frame for measuring.** A roster of scenarios (`_scenarios.md`, with samples) and a command that sends them to real Claude Code sessions and records whether the index was opened.

This is the structure that 25h uses in its own working environment. The rows of 25h are not included. What you fill in is yours.

## What it does not do

Read this before you install.

- **It does not stop Claude from asking.** Nothing enforces the lookup. A skill is an instruction that Claude loads when it judges it relevant.
- **It makes no claim about how much less Claude will ask.** The check against real Claude Code sessions (`tests/live-check.sh`) was run on 2026-10-19 (Claude Code 2.1.303) and on 2026-10-31 (Claude Code 2.1.314). It measures whether the index is opened, not how often Claude asks. In the three runs on 2026-10-31, with the skill alone the index was opened in 1 of 3 scenarios once and in 0 of 3 twice; with the `CLAUDE.md` line it was opened in 3 of 3 each time. See "What was checked".
- **It is not a permission system.** A row whose Decider is `never` does not block a command. To block a command, use the permission settings or a hook of Claude Code.
- **The sample rows are not your decisions.** All of them are marked strength C, which means provisional. Edit, promote, or delete them.
- **The check looks at form, not at truth.** It can tell that a row at strength A has no checked counter. It cannot tell whether the rule is right, or whether the branches of a Decider cover every case.
- **The index grows only when rows are written.** A question that was answered in chat and never captured leaves nothing behind.

## Where this sits next to CLAUDE.md and rules

Checked against the official documentation on 2026-10-09.

| Where | When it is in context | What belongs there |
|---|---|---|
| `CLAUDE.md` | Every session | Facts and "always do X" lines. The documentation asks for under 200 lines per file and says to move a multi-step procedure into a skill or a path-scoped rule. |
| `.claude/rules/` | Every session, or when a matching file is opened (`paths:`) | Constraints that always hold, or that hold for part of the code. |
| A skill | The description is listed in every session; the body loads when the skill is invoked | A procedure. Here: how to look a scene up, and how to add a row. |
| The index (`judgment/`) | Only the parts that Claude reads: `INDEX.md`, one head, one row | The criteria themselves, one row per scene. |

Three consequences for this plugin.

- A plugin cannot add an always-on instruction. A `CLAUDE.md` at the root of a plugin is not loaded. So the one line that points every session to the index has to be added to your own `CLAUDE.md` by you; `init` prints it.
- A plugin skill lives at `skills/<name>/SKILL.md` and is namespaced, so the two skills are `/judgment-index:consult` and `/judgment-index:capture`.
- When many skills are installed, Claude Code drops descriptions from the skill listing to fit its budget, starting with the skills invoked least. A dropped description means Claude no longer sees when to use the skill. The line in `CLAUDE.md` does not depend on that budget.

A rule that is already in `CLAUDE.md` or in an always-on rule file is not copied into the index. The index points to it with a row at strength P, and the check fails a pointer whose target is missing or is scoped with `paths:`.

Sources:

- Plugins: https://code.claude.com/docs/en/plugins
- Plugins reference (layout, `${CLAUDE_PLUGIN_ROOT}`, the note on `CLAUDE.md` at the plugin root): https://code.claude.com/docs/en/plugins-reference
- Skills (location and namespace of a plugin skill, frontmatter, listing budget): https://code.claude.com/docs/en/skills
- Memory (`CLAUDE.md`, `.claude/rules/`, when each is loaded): https://code.claude.com/docs/en/memory

## Requirements

- Claude Code. The version checked is 2.1.314.
- Python 3.8 or later for the tool. No package is installed. The version checked is 3.9.6.
- macOS or Linux for the two shell scripts in `tests/`. The tool itself has no shell dependency.

## Install

Run these two commands in order. Claude Code fetches the plugin from `noes-25h/agent-kit` on GitHub. If you already ran the first command for another plugin of this repository, run only the second.

```bash
claude plugin marketplace add noes-25h/agent-kit
```

```bash
claude plugin install judgment-index@25h-agent-kit
```

It is installed when the next command lists `judgment-index@25h-agent-kit` as `enabled`.

```bash
claude plugin list
```

A Claude Code session that is already open picks it up after you reopen it or type `/reload-plugins`.

## Unpack the index into a project

The index is a folder in your repository. From the root of the project, run `init` with the path to a clone of this repository (`git clone https://github.com/noes-25h/agent-kit`).

```bash
python3 /path/to/agent-kit/plugins/judgment-index/scripts/judgment.py init
```

This creates `judgment/` with `INDEX.md`, the 15 category files, `_scenarios.md`, `_inbox.md`, and a copy of the tool named `_judgment.py`. It does not overwrite a file that is already there. The copy of the tool is there so that the index can be checked by a teammate or a CI job that does not have the plugin.

To put the index somewhere else, pass `--dir`. The path is then recorded in a one-line file, `.judgment-index`, at the project root, and the skills and the tool read it from there.

```bash
python3 /path/to/agent-kit/plugins/judgment-index/scripts/judgment.py init --dir docs/judgment
```

`init` ends by printing one line for your `CLAUDE.md`. Add it by hand. `init` does not edit `CLAUDE.md`.

```
Before you ask whether you may or should do something, look the scene up in `judgment/INDEX.md`: pick a category, read only the head of that category file, then read the one matching row. If no row matches, follow the steps in `judgment/INDEX.md` to add one row and continue.
```

Then open `judgment/INDEX.md` and edit the list under "Where decisions live" so that it names the places where your decisions are recorded.

## Verify

Run the commands in this section from the root of a clone of this repository (`git clone https://github.com/noes-25h/agent-kit`).

There are two levels. The first one alone does not show that the index is used.

**The tool.** This feeds good and broken rows to the checks, and then drives the command line from an empty project: 68 checks of the checks, and 13 steps. It does not call Claude Code and finishes in a few seconds.

```bash
bash ./plugins/judgment-index/tests/selftest.sh
```

**Real Claude Code sessions.** Run by us; the result is under "What was checked". This unpacks the sample index into an empty folder and sends three scenarios to Claude Code in three arms: the index files alone, the index files with the plugin, and the same with the `CLAUDE.md` line. For each call it reads the tool calls of the session and records whether `INDEX.md` and a category file were opened. That is nine calls of your usage allowance.

```bash
bash ./plugins/judgment-index/tests/live-check.sh
```

Exit code 0 means that with the plugin and the `CLAUDE.md` line the index was opened in every scenario. 1 means it was not. 2 means it could not tell: a call did not finish, or the plugin is already installed for your user, in which case the arm without it is not a control. Uninstall the plugin for the duration of the check. The output also says so when the index was opened just as often without the plugin, and when the `CLAUDE.md` line was needed.

To measure your own index with your own scenarios:

```bash
python3 judgment/_judgment.py measure --plugin-dir /path/to/agent-kit/plugins/judgment-index --n 3
```

## Daily use

**One row.**

```markdown
### PB03 — a correction to a page that is already public

- **Rule**: Prepare the corrected text and the diff. Do not publish it.
- **Decider**: owner
- **Strength**: B
- **Source**: owner decision 2026-10-09 (n=1)
```

- **Decider** is one of five words: `agent`, `agent (reversible only)`, `owner`, `hands` (the agent decides, a person performs one manual step), `never` (not done, even with approval). A scene that splits is written as branches: `agent (local copy) / owner (anything live)`.
- **Strength** is A, B, C, or P. A needs a `Counter` that names what was checked and what came out, after `->`. C is provisional, and `Derived from` may stand in place of `Source`. P is a pointer to an instruction that is already loaded in every session.

`judgment/INDEX.md` holds the full definitions and the seven steps for adding a row. The field names are fixed in English. The text of a row can be in any language; the one check that reads the text, a rule that ends in "consider", only knows English.

**After writing or editing a row**, regenerate the tables of contents and check.

```bash
python3 judgment/_judgment.py toc
```

```bash
python3 judgment/_judgment.py check
```

The table of contents is generated, never written by hand. A row that is missing from it is never taken out, which is worse than having no row. `check` exits 1 when a table of contents does not match its rows, when a row breaks the form, when `INDEX.md` and the category files disagree, or when the scenario roster names a category or an exit that does not exist. It is suited to a pre-commit hook or a CI step.

**The skills.** Claude invokes `consult` on its own when it is about to ask. You can also type `/judgment-index:consult`. Run `/judgment-index:capture` at the end of a session in which Claude asked you for decisions.

**Reading the counts.** `check` prints how many rows there are at each strength. Rows at C that keep growing while A and B do not are a sign that the agent is deciding alone and nobody is confirming.

## Adjust

- **Rename or drop a category.** Rename the file, change its line in the lookup table of `INDEX.md`, and change the category in `_scenarios.md`. `check` fails until the three agree.
- **Add a category.** Create `NN_verb.md` with the two toc marker lines copied from another category file, add its line to `INDEX.md`, and pick a two-letter ID prefix that no other file uses.
- **Refresh the copied tool** after updating the plugin: delete `judgment/_judgment.py` and run `init` again. `init` keeps every other file as it is.

## Uninstall

```bash
claude plugin uninstall judgment-index@25h-agent-kit
```

```bash
claude plugin marketplace remove 25h-agent-kit
```

The second command removes the registration of this repository as a source. Skip it if you still use another plugin from this repository. A copy of the plugin remains in the Claude Code config folder (`~/.claude/plugins/cache/25h-agent-kit/`); it is no longer read, and you can delete it by hand.

The index in your repository is not touched. It is yours, and `_judgment.py` inside it keeps working without the plugin. Remove the line from `CLAUDE.md` when you stop using it.

## What was checked

On 2026-10-09, in an empty folder outside any repository, with an empty Claude Code config folder, following this README from top to bottom:

- `claude plugin validate`, marketplace add, install, list. `claude plugin details` lists the two skills as components and estimates their always-on cost at under 300 tokens per session (the two descriptions).
- `init` into an empty project and at another place with `--dir`, then `check`
- writing a row, `toc`, `check`, and a row at strength A without a counter being rejected
- `tests/selftest.sh`: 68 checks and 13 steps, all as expected
- uninstall, marketplace remove; the index in the project still checks afterwards

The tool was also broken on purpose in 18 places, one at a time. The selftest failed on each of the 18.

On 2026-10-31, `tests/live-check.sh` was run with a logged-in Claude Code 2.1.314 and ended with exit code 0. The plugin's skills were listed at session start in both arms that load the plugin, and not in the arm without it.

- Index files alone: `INDEX.md` opened in 0 of 3 scenarios.
- With the plugin: opened in 1 of 3 in one run and 0 of 3 in the other two.
- With the plugin and the `CLAUDE.md` line: opened in 3 of 3, and a category file was read each time.

So the `CLAUDE.md` line was needed. The skill description alone is not enough to bring the session to the index. The session's own last line matched the expected exit (proceed, ask, refuse) in 3 of 3 scenarios with the line, and in 2 of 3 in the other two arms, which asked where a refusal was expected. That outcome is what the session said, not what it did.

Not checked: whether Claude asks less over real work. That is three runs of three scenarios on one machine. The run on 2026-10-19 (Claude Code 2.1.303) had the same 3 of 3 with the line, and 0 of 3 with the plugin alone.

## License

MIT. See [LICENSE](LICENSE).
