# plan-review

日本語: [README.ja.md](README.ja.md)

A Claude Code plugin. When a plan is finished, it has the plan read by two reviewers that were not part of the conversation that produced it, and then makes the session that wrote the plan answer every finding in writing.

1. One skill, `/plan-review:plan-review`. It starts the two reviewers at the same time, rules on each finding (adopt, rebut, defer, or escalate), and appends the rulings to the plan file.
2. Two reviewer definitions. `plan-review:adversarial-reviewer` looks for the reasons the plan must not pass. `plan-review:best-path-reviewer` looks for a better conclusion that stands on top of the plan.

This is the review that 25h runs on its own plans, with the pointers to 25h files removed.

## What it does not do

Read this before you install.

- **The check against a real Claude Code session passed three times, not more.** 25h ran `tests/live-check.sh` on 2026-10-19 with Claude Code 2.1.303, on 2026-10-20 with 2.1.304, and on 2026-10-31 with 2.1.314. In each run, both reviewers were started by their plugin names in the same message, no start overrode the model or the effort, each reviewer named 3 of the 3 planted flaws, and both sections were appended to the plan. A run before the 2026-10-19 pass counted 0 of 3: the check was reading a 350-byte pointer instead of the report, and was fixed before the passing run. Whether a reviewer named a flaw is counted by keyword matching, so read the reports. Three runs are three samples. An earlier run on 2026-10-31 ended with exit code 1 and 0 of 3: the reviewers ran in the background, and the check read only the 1,122-byte launch notice. The check was fixed before the passing run.
- It is prompts. There is no mechanism that makes a review good. A reviewer can miss a flaw, and a reviewer can report a flaw that is not there. The skill tells the session to check a finding against the material before ruling on it, for that reason.
- It does not show that these two reviewers find more than a single plain request to "review this plan" would. The sample plan measures whether the wiring delivers reports that name three planted flaws. It is not a comparison.
- The reviewers can run Bash. The tool list removes Write, Edit, NotebookEdit, and Agent, but Claude Code has no way to make Bash read-only through the tool list. Only a line in the prompt asks the reviewers not to write. To remove Bash, see Adjust.
- The model and the effort written in the definitions are defaults, not locks. See "What was checked against the official documentation" for the cases in which something else wins.
- The reviewers receive the project instructions (CLAUDE.md) of the folder you run in, like any subagent. They do not receive your conversation.
- It costs usage. One review is two subagents at high effort, one on Sonnet and one on Opus, each reading the plan and the material you point to.

## Requirements

- Claude Code. The version checked is 2.1.314.
- An account that can use both Sonnet and Opus. Without one of them, Claude Code substitutes another model, and the two reviewers may end up on the same model.
- For the two checks only: bash, jq, grep, sed, awk. macOS or Linux. The plugin itself contains no scripts and runs wherever Claude Code runs.

## Install

Run these two commands in order. Claude Code fetches the plugin from `noes-25h/agent-kit` on GitHub. If you already ran the first command for another plugin of this repository, run only the second.

```bash
claude plugin marketplace add noes-25h/agent-kit
```

```bash
claude plugin install plan-review@25h-agent-kit
```

To see whether it is installed, run the next command. It is installed when `plan-review@25h-agent-kit` is listed as `enabled`.

```bash
claude plugin list
```

A Claude Code session that is already open picks it up after you reopen it or type `/reload-plugins`. The plugin applies to every project.

To try it once without installing, clone this repository (`git clone https://github.com/noes-25h/agent-kit`) and, from the root of the clone, point Claude Code at the folder when you start it.

```bash
claude --plugin-dir ./plugins/plan-review
```

## Verify

Run the commands in this section from the root of a clone of this repository (`git clone https://github.com/noes-25h/agent-kit`).

There are two levels of verification. The first one alone is not enough.

**The files.** This reads the manifests, the skill, the two definitions, and the sample plan, and runs 114 checks: the frontmatter has the shape Claude Code loads, the required sections are present, and the names the skill uses to start the reviewers resolve to the definitions. It also tries the scoring of the second level on a hand-written recorded session. It does not call Claude Code and finishes in a few seconds.

```bash
bash ./plugins/plan-review/tests/selftest.sh
```

**A real review.** This copies a sample plan with three planted flaws into an empty folder, runs Claude Code once with the plugin, and reads the recorded session: whether both reviewers were started by their plugin-scoped names, how many of the three flaws each report names, and whether the plan file received the two review sections. It takes several minutes and uses one session and two reviewer runs of your usage allowance.

```bash
bash ./plugins/plan-review/tests/live-check.sh
```

Why the second level is needed: every file in this plugin can be well formed while the review does nothing. The first check confirms that the names in the files agree with each other and with the documentation. It cannot see whether a session starts the reviewers under those names, or what the reviewers return.

How to read the second level:

- The flaw count is a keyword count. A flaw counts as named when one line of a report has a word for the subject and a word that says something is wrong. Read the reports in the work folder before you rely on the number.
- One run is one sample. A model can miss a flaw on one run and name it on the next.
- The three flaws are listed in `tests/fixtures/flaws.tsv`. The reviewers are not given that file.

## Use

Write the plan into one file. Then, in the session that wrote it:

```
/plan-review:plan-review path/to/plan.md
```

You can also ask in words, for example "review this plan with plan-review". Name the material the plan must agree with: project instructions, earlier decisions, the implementation, official documentation.

## What happens

1. Two reviewers start in the same message. Each receives the path of the plan file and the paths of the material, and nothing about how the plan came to be.
2. Each returns a summary of at most 600 words. The adversarial reviewer gives each finding a severity (fail, fix, or note), an alternative, and a falsifier: the condition under which the finding is wrong. The best-path reviewer gives each proposal an expected effect and a falsifier, and ends with how it would build the plan.
3. The session rules on every finding: adopt, rebut with a reason, defer to a recorded follow-up, or escalate to you as one closed question.
4. Two sections are appended to the plan file, one table row per finding:

```
## Adversarial review (2026-10-09, adversarial-reviewer, ran on <model> / effort <effort>)
## Best-path review (2026-10-09, best-path-reviewer, ran on <model> / effort <effort>)
```

A plan file without these two sections has not been through the review. That is the point of writing them into the file: you can check for them later with a search.

## Adjust

- **Models and effort.** Edit `model` and `effort` in the frontmatter of `plugins/plan-review/agents/*.md`. The two reviewers are on different models on purpose. The reason is the expectation that different models miss different things. This kit contains no measurement of that.
- **Lenses.** Edit the numbered list under "What to look for" in each definition. Add the lens that matches the failure you keep having.
- **Report length.** Edit "at most 600 words" in each definition.
- **Read-only reviewers.** Remove `Bash` from `tools` in each definition. The reviewers can then no longer count lines or confirm that a command exists.
- **No network.** The reviewers can reach the network through `WebFetch` and `Bash`, so a plan's text can leave your machine. Remove both to close that path.
- **Reviewers that do not read CLAUDE.md.** Add `omitClaudeMd: true` to the frontmatter of each definition (Claude Code 2.1.271 or later).

When you change a model or an effort, update the record near the top of `tests/selftest.sh` (`PR_EXPECT_MODEL_...` and `PR_EXPECT_EFFORT`) to match. Otherwise selftest fails. The record exists so that a definition does not change without anyone noticing.

To change it, edit a clone of this repository and install from the clone instead of from GitHub (`claude plugin marketplace add ./agent-kit`, run from the folder one level above the clone). The plugin is then read directly from the clone. If you already installed from GitHub, this points the `25h-agent-kit` source at the clone, and plugins already installed from it update from the clone from then on. To go back, run `claude plugin marketplace add noes-25h/agent-kit`. Your changes take effect after you reopen Claude Code or type `/reload-plugins` in a session. Run selftest after every change.

## Uninstall

```bash
claude plugin uninstall plan-review@25h-agent-kit
```

```bash
claude plugin marketplace remove 25h-agent-kit
```

The second command removes the registration of this repository as a source. Skip it if you still use another plugin from this repository.

After uninstalling, a copy of the plugin remains in the Claude Code config folder (`~/.claude/plugins/cache/25h-agent-kit/`). It is no longer read, and you can delete it by hand. Review sections that were appended to your plan files stay where they are.

## What was checked against the official documentation

Read on 2026-10-09. Each statement below was matched against the text of the page, not against a summary of it.

- **How a plugin agent is called.** Claude Code namespaces every component under the plugin name. An agent `adversarial-reviewer` in the plugin `plan-review` is `plan-review:adversarial-reviewer`. An agent name cannot contain `:`. A plugin skill is `/plugin-name:skill-name`. Sources: https://code.claude.com/docs/en/plugins-reference (the `name` field) and https://code.claude.com/docs/en/sub-agents ("Supported frontmatter fields", "Invoke subagents explicitly") and https://code.claude.com/docs/en/skills ("How a skill gets its command name").
- **Whether the definition can fix the model and the effort.** A subagent definition accepts `model` and `effort`. Plugin subagents ignore `hooks`, `mcpServers`, `permissionMode`, and `initialPrompt`; `model`, `effort`, `tools`, and `disallowedTools` are not on that list. Source: https://code.claude.com/docs/en/sub-agents ("Choose the subagent scope", "Supported frontmatter fields").
- **When the definition does not win.** For the model, a `model` passed in the call comes first, then the definition. With `CLAUDE_CODE_SUBAGENT_MODEL_FORCE` set, the definition is ignored. An alias such as `opus` resolves to the exact model of the main conversation when that model belongs to the same family. An organization allowlist can substitute another model. For the effort, an `effort` passed in the call overrides the definition (Claude Code 2.1.292 or later), and the `CLAUDE_CODE_EFFORT_LEVEL` environment variable overrides both. This is why the skill tells the session to pass neither, and to write down what actually ran. Source: https://code.claude.com/docs/en/sub-agents ("Choose a model", "Choose an effort level").
- **How to stop a reviewer from starting its own subagents.** By default a subagent can start subagents, up to three layers below the main conversation. To keep one subagent from doing so, omit `Agent` from its `tools` or add it to `disallowedTools`. Both definitions do both. Source: https://code.claude.com/docs/en/sub-agents ("Let subagents spawn their own subagents").
- **Where to see what actually ran.** `/tasks` names the model on the row of each subagent, and the effort if one is set (Claude Code 2.1.242 or later). Transcripts are stored under `~/.claude/projects/{project}/{sessionId}/subagents/`. Source: https://code.claude.com/docs/en/sub-agents.
- **The layout of a plugin.** `agents/` and `skills/<name>/SKILL.md` at the plugin root are found without being listed in `plugin.json`. Source: https://code.claude.com/docs/en/plugins and https://code.claude.com/docs/en/plugins-reference.

What the documentation says and what a session does are two things. The second is what `tests/live-check.sh` is for. The runs that passed were one each on 2026-10-19 (2.1.303), 2026-10-20 (2.1.304), and 2026-10-31 (2.1.314); before those, two runs on 10-19 did not reach the end, and the runs on 10-19 and 10-31 that found 0 of 3 are described under "What it does not do".

## License

MIT. See [LICENSE](LICENSE).
