# 25h Agent Kit

Eight small Claude Code plugins. Each one covers one failure that repeats: an API key leaking into a command or its output, a plan nobody else has read, a new session with no context, Claude guessing the date.

Most of them advise rather than enforce. Only secret-guard and install-gate stop a call. The README of each plugin says what it does not cover.

日本語: [README.ja.md](README.ja.md)

Made by 25h, a small business run by one person and an AI. We use these hooks and skills in our own work every day. This repository holds versions reworked to run on their own. MIT license.

## The plugins

| Plugin | When it helps | Type |
|---|---|---|
| [secret-guard](plugins/secret-guard/README.md) | A key is about to go into a tool call, or comes back in command output | Hooks |
| [install-gate](plugins/install-gate/README.md) | Claude is about to install a tool machine-wide with no audit record | Hook and skill |
| [time-guard](plugins/time-guard/README.md) | Claude does not know the time, or writes "this morning" with no date next to it | Hooks and a skill |
| [session-memory](plugins/session-memory/README.md) | A new session starts with no idea where the work stands | Hook and skills |
| [handoff](plugins/handoff/README.md) | Work is left at the end of a session and the next one has no context | Skill |
| [plan-review](plugins/plan-review/README.md) | A plan is finished and nobody without its context has read it | Skill and subagents |
| [root-fix](plugins/root-fix/README.md) | The same mistake keeps coming back | Skill |
| [judgment-index](plugins/judgment-index/README.md) | Claude keeps asking you questions you have already answered | Skills and a script |

Install only the ones you need. They work independently.

## Install

Inside Claude Code, the same two lines start with `/plugin` instead of `claude plugin`.

```bash
claude plugin marketplace add noes-25h/agent-kit
```

Then install what you need. Replace `secret-guard` with the plugin you want.

```bash
claude plugin install secret-guard@25h-agent-kit
```

## How they were checked

Each plugin has two levels of checks in its `tests/` folder.

- `selftest.sh` checks the files and the scripts. It does not call Claude Code.
- `live-check.sh` runs a real Claude Code session and reads what happened. It uses your usage allowance.

The second level exists because the original version of one of these hooks passed its own test for three and a half months while doing nothing at all. A hook whose return value has a slightly wrong shape is discarded by Claude Code with no error.

All eight ended `live-check.sh` with exit code 0: 2026-10-31 with Claude Code 2.1.314 (install-gate, time-guard, plan-review, session-memory, judgment-index); 2026-11-01 with Claude Code 2.1.316 (root-fix, handoff); 2026-11-02 with Claude Code 2.1.316 (secret-guard). For plan-review that was the second run of the day: the first ended with exit code 1 because the check read only a launch notice, and the check was fixed before the passing run. What that shows differs by plugin, and the "Verify" section of each README says what was measured. One example: judgment-index was consulted in every scenario only with its line in `CLAUDE.md`. That is one machine and a small number of runs. Run the check again on yours, and again after you update Claude Code.

## Support

Open an issue. This is shared as it is, with no promise of a reply or a fix date.

## License

MIT. See [LICENSE](LICENSE).
