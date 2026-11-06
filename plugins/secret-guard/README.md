# secret-guard

日本語: [README.ja.md](README.ja.md)

A Claude Code plugin. It catches API keys at two points before they travel further through Claude.

1. It blocks a tool call that contains a key-shaped string, before the call runs. This covers Bash commands and file writes and edits.
2. When the output of a successful Bash command contains a key-shaped string, it replaces that part with a redaction mark before Claude receives the output.

These are the hooks that 25h runs in its own working environment, repackaged to work on their own.

## What it does not protect

Read this before you install. On the paths below, the key reaches Claude.

- Output of a failed command. When a Bash command exits with a non-zero code, Claude Code does not let a hook replace the output. A notice is shown if a key-shaped string is found, but Claude has already received it.
- File contents read with Read or Grep. To keep Claude from reading `.env`, deny the read in the standard Claude Code permission settings.
- A key that you paste into the prompt yourself.
- The raw transcript. Only what Claude receives is redacted. The transcript file on your machine keeps the original output.
- Keys in a shape that is not in the table. The plugin looks for 15 kinds, most with a fixed prefix, plus PEM private keys. The list is in `plugins/secret-guard/scripts/patterns.sh`.

If a real key was printed, rotating it is the safe choice even when it was redacted. This plugin reduces how often you have to rotate. It does not make rotation unnecessary.

## Requirements

- Claude Code. The version checked is 2.1.316.
- macOS or Linux. It uses bash, grep, sed, awk, and jq. Windows is not supported.
- Without jq, the blocking side still works, but output redaction does not. In that case a notice is shown on every Bash call.

## Install

Run these two commands in order. Claude Code fetches the plugin from `noes-25h/agent-kit` on GitHub. If you already ran the first command for another plugin of this repository, run only the second.

```bash
claude plugin marketplace add noes-25h/agent-kit
```

```bash
claude plugin install secret-guard@25h-agent-kit
```

To see whether it is installed, run the next command. It is installed when `secret-guard@25h-agent-kit` is listed as `enabled`.

```bash
claude plugin list
```

A Claude Code session that is already open picks it up after you reopen it or type `/reload-plugins`. The plugin applies to every project. It does not rewrite the hooks in your own `settings.json`.

To try it once without installing, clone this repository (`git clone https://github.com/noes-25h/agent-kit`) and, from the root of the clone, point Claude Code at the folder when you start it.

```bash
claude --plugin-dir ./plugins/secret-guard
```

## Verify

Run the commands in this section from the root of a clone of this repository (`git clone https://github.com/noes-25h/agent-kit`).

There are two levels of verification. The first one alone is not enough.

**The hook scripts.** This feeds fake keys to the hooks and runs 95 checks: blocked, passed, redacted. It does not call Claude Code and finishes in a few seconds.

```bash
bash ./plugins/secret-guard/tests/selftest.sh
```

**A real Claude Code session.** This runs Claude Code three times with the plugin and three times without it, and counts how many fake keys are left in the results that Claude received. It takes a few minutes and uses six calls of your usage allowance.

```bash
bash ./plugins/secret-guard/tests/live-check.sh
```

Run it from a plain terminal. The check ends with one of three results. Exit code 0: the hooks ran and the keys were stopped. Exit code 1: the hooks ran and a key got through. Exit code 2: it cannot tell. That is the result when a call did not finish, when the side without the plugin is not a control, or when the hooks did not run.

The check counts the hook lines that Claude Code records for each run. When no hook of this plugin ran to the end, it prints the reason on one line and gives no verdict. This is what happens when the check is started from inside a sandbox, for example from a Claude Code session: Claude Code cannot create the data folder of the plugin under `~/.claude/plugins/data/`, does not start the hook, and lets the tool call through. The failure line then says `EPERM` or `operation not permitted`. Open a plain terminal and run the check again.

Why the second level is needed: when the value a hook returns has a slightly wrong shape, Claude Code discards it silently. No error is shown. The first check can pass in full while nothing is actually redacted. Run the second check again after you update Claude Code.

## What happens

**When a call is blocked.** If Claude tries to run a command or write a file that contains a key, the call does not run. Claude receives this message.

```
secret-guard: blocked this call because it contains a string that matches the github-token key pattern. Do not write the value inline; read it from an environment variable or a secret store instead.
```

An edit that removes a key is not blocked. The text being replaced is not scanned. Without jq the whole call is scanned, so such an edit is blocked too.

**When output is redacted.** The command runs to the end. Only the output that Claude receives changes.

```
original output:       token: ghp_xxxxxxxx…
what Claude receives:  token: [REDACTED-BY-SECRET-GUARD]
```

One line on screen tells you that the output was redacted and that the raw transcript still holds the original.

**When a failed command prints a key.** It cannot be redacted. A notice is shown on screen, and Claude is told not to quote or reuse the value.

**A call with no key.** Nothing happens. Nothing is shown.

## Adjust

Edit only the table in `plugins/secret-guard/scripts/patterns.sh`. One row is one kind of key.

- To stop blocking a kind, change `B` to `R` on its row. It is then redacted only.
- To stop looking for a kind, delete its row.
- To add a kind, add one row with three columns (name, tier, regex), and add a sample with the same name to `sg_sample` in `tests/selftest.sh`. selftest fails on a row that has no sample.
- To also block literals such as `"password": "..."`, set `SG_BLOCK_LITERALS` to 1. This also fires on test data and sample configs.

When you change a tier or delete a row, update the record near the end of `tests/selftest.sh` (`SG_EXPECT_B` and `SG_EXPECT_R`) to match. Otherwise the last check of selftest fails. The record exists so that blocking rows do not shrink without anyone noticing.

To change it, edit a clone of this repository and install from the clone instead of from GitHub (`claude plugin marketplace add ./agent-kit`, run from the folder one level above the clone). The plugin is then read directly from the clone. If you already installed from GitHub, this points the `25h-agent-kit` source at the clone, and plugins already installed from it update from the clone from then on. To go back, run `claude plugin marketplace add noes-25h/agent-kit`. Your changes take effect after you reopen Claude Code or type `/reload-plugins` in a session. Run selftest after every change.

## Uninstall

```bash
claude plugin uninstall secret-guard@25h-agent-kit
```

```bash
claude plugin marketplace remove 25h-agent-kit
```

The second command removes the registration of this repository as a source. Skip it if you still use another plugin from this repository.

After uninstalling, a copy of the hooks remains in the Claude Code config folder (`~/.claude/plugins/cache/25h-agent-kit/`). It is no longer read, and you can delete it by hand. Nothing is left in `settings.json`.

## License

MIT. See [LICENSE](LICENSE).
