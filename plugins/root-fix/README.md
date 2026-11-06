# root-fix

日本語: [README.ja.md](README.ja.md)

A Claude Code plugin that holds one skill. The skill is for a mistake that keeps coming back. It tells Claude to work in this order.

1. Open the file behind each reported symptom and confirm that the report is true.
2. Trace each symptom back to what wrote the bad value, and to what generated that.
3. Narrow several symptoms to one point: a generator, a template, a script, a structure.
4. Sweep the repository for other places where the same source produced the same defect, and state a reason for every place it leaves out.
5. Only when you pass `--apply`: fix the source, and add one check that fails if the defect comes back.

This is the skill that 25h runs in its own working environment, repackaged to work on its own. The names of 25h's own ledgers, paths, and other skills were removed.

## What it does not do

Read this before you install.

- It is a prompt. It does not enforce anything. Claude can skip a stage, and nothing in the plugin stops that.
- It was checked against a real Claude Code session on 2026-10-19 (Claude Code 2.1.303), on 2026-10-31 (2.1.314), and on 2026-11-01 (2.1.316). In the latest run: 11 of 11 points with the plugin, 8 of 11 without. See "Verify" below. The count is keyword matching, not a judgment of the reasoning.
- It does not find mistakes by itself. You, a linter, or a review notices the repetition. The skill starts from there.
- It does not promise that a mistake stops. It asks Claude for a fix at the source and a check, and for a report of what the check covers.
- It is the wrong tool for a one-off bug with a known cause. The skill says so itself and tells Claude to fix such a bug directly.
- Without `--apply` it is told not to change any file. That is an instruction to Claude, not a permission setting. If you need that enforced, use the permission settings of Claude Code.

## Requirements

- Claude Code. The version checked is 2.1.316.
- macOS or Linux for the two test scripts. They use bash, grep, sed, awk, and jq. The skill itself is a Markdown file and has no such requirement.

## Install

Run these two commands in order. Claude Code fetches the plugin from `noes-25h/agent-kit` on GitHub. If you already ran the first command for another plugin of this repository, run only the second.

```bash
claude plugin marketplace add noes-25h/agent-kit
```

```bash
claude plugin install root-fix@25h-agent-kit
```

To see whether it is installed, run the next command. It is installed when `root-fix@25h-agent-kit` is listed as `enabled`.

```bash
claude plugin list
```

A Claude Code session that is already open picks it up after you reopen it or type `/reload-plugins`. The plugin applies to every project.

To try it once without installing, clone this repository (`git clone https://github.com/noes-25h/agent-kit`) and, from the root of the clone, point Claude Code at the folder when you start it.

```bash
claude --plugin-dir ./plugins/root-fix
```

## Use

Inside a Claude Code session:

```
/root-fix:root-fix the nightly report job ran in the wrong timezone again
```

A skill inside a plugin is called as `/<plugin name>:<skill name>`. Both names are `root-fix` here, so the command is `/root-fix:root-fix`. According to the skills page, the short form `/root-fix` also works unless another command already uses that name.

What you can pass:

- A description of the symptom, a `file:line`, or the path of an incident log.
- `--apply` to let the skill go past diagnosis and edit files.
- `--record <path>` to say where the one-entry record of the source goes.

Claude can also load the skill by itself when your message matches its description, for example when you say that the same mistake has happened again. To allow only the typed command, add `disable-model-invocation: true` to the frontmatter of `plugins/root-fix/skills/root-fix/SKILL.md`.

**Where the record goes.** The skill decides in this order: the `--record` argument; then the `record` key in `.claude/root-fix.json` at the root of your project, for example `{"record": "docs/root-causes.md"}`; and when neither is present it creates no file and puts the record in its reply.

**Model and effort.** The frontmatter sets `model: inherit` and `effort: high`. The skill runs on whatever model your session uses. Change either line if you want something else.

## Verify

Run the commands in this section from the root of a clone of this repository (`git clone https://github.com/noes-25h/agent-kit`).

There are two levels of verification. The first one alone tells you little.

**The files.** This checks the manifests, the frontmatter of the skill, the sections and sentences it must have, and the fixture that the second check scores against. It runs 42 checks, does not call Claude Code, and finishes in a few seconds.

```bash
bash ./plugins/root-fix/tests/selftest.sh
```

**A real Claude Code session.** This copies a small sample repository in which the same mistake is recorded three times, runs Claude Code on it once with the skill and once with a plain request, and counts how many of 11 expected points each reply meets. The points are listed in `plugins/root-fix/tests/fixtures/three-repeats/expected.tsv`. It uses two calls of your usage allowance.

```bash
bash ./plugins/root-fix/tests/live-check.sh
```

**What 25h got from this check.** The latest run was on 2026-11-01 with Claude Code 2.1.316. With the plugin, 11 of the 11 points were met; without it, 8. The threshold is 8, which does not separate the two sides on this run; the difference is the 3 points between 11 and 8. The run on 2026-10-19 met 10 with the plugin and 6 without. The number without the plugin is there for comparison: a capable model meets several points with no skill at all. That is one run on one machine. Your result can differ.

What the count is and is not. Each point is a keyword pattern. The count can include a point that was mentioned for the wrong reason, and can miss one that was phrased differently. The threshold of 8 in `expected.tsv` was chosen by reading, not tuned against runs. One run is one sample; Claude does not answer the same way twice. Read the reply that the script keeps in its work folder.

## Adjust

The skill is one file: `plugins/root-fix/skills/root-fix/SKILL.md`. Edit it freely.

- When you rename or remove a section, update `REQUIRED_SECTIONS` near the top of `tests/selftest.sh` to match. Otherwise selftest fails. The list exists so that a stage does not disappear without anyone noticing.
- The same holds for `REQUIRED_PHRASES`. Those are single sentences that carry a rule, such as the one that forbids edits without `--apply`.
- To score against a situation from your own project, add a folder next to `tests/fixtures/three-repeats/` with a `repo/` and an `expected.tsv`, and point `FIX` in `tests/live-check.sh` at it.

To change it, edit a clone of this repository and install from the clone instead of from GitHub (`claude plugin marketplace add ./agent-kit`, run from the folder one level above the clone). The plugin is then read directly from the clone. If you already installed from GitHub, this points the `25h-agent-kit` source at the clone, and plugins already installed from it update from the clone from then on. To go back, run `claude plugin marketplace add noes-25h/agent-kit`. Changes take effect after you reopen Claude Code or type `/reload-plugins`. Run selftest after every change.

## Uninstall

```bash
claude plugin uninstall root-fix@25h-agent-kit
```

```bash
claude plugin marketplace remove 25h-agent-kit
```

The second command removes the registration of this repository as a source. Skip it if you still use another plugin from this repository.

After uninstalling, a copy of the plugin remains in the Claude Code config folder (`~/.claude/plugins/cache/25h-agent-kit/`). It is no longer read, and you can delete it by hand. Nothing is left in `settings.json`. If you created `.claude/root-fix.json` or a record file in a project, those are yours and stay where they are.

## Sources

The plugin layout, the way a plugin skill is called, and the frontmatter fields were checked against these pages on 2026-10-09.

- Plugins: https://code.claude.com/docs/en/plugins
- Skills (frontmatter reference, "How a skill gets its command name", string substitutions): https://code.claude.com/docs/en/skills
- Plugin manifest reference: https://code.claude.com/docs/en/plugins-reference
- Running Claude Code non-interactively, used by live-check: https://code.claude.com/docs/en/headless

## License

MIT. See [LICENSE](LICENSE).
