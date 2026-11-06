# install-gate

日本語: [README.ja.md](README.ja.md)

A Claude Code plugin. When Claude is about to install a tool machine-wide, it looks for an audit record for that tool in your project and does one of three things.

| State of the record | What happens |
|---|---|
| No record, the name does not match, or the risk line is not filled in | The install is blocked. Claude is told to write the record with the bundled skill. |
| The record says `Risk: LOW` | The install runs. Nothing is shown. |
| The record says `Risk: MID` or `Risk: HIGH` | You get a permission prompt that names the record and its risk. |
| The command installs something, but the gate cannot read what (see "How the command is read") | You get a permission prompt that says so. |

The bundled skill, `/install-gate:tool-audit`, walks through eight items (publisher, license, token storage, terms of service, reversibility, and others) and writes the record.

This is a rework of a hook and a skill that 25h runs in its own working environment.

How this differs from adding an "ask" permission rule for install commands: the record stays in your repository. The next time the same tool is installed, a LOW record lets it through without a prompt, and anyone can read why the tool was accepted.

## What it does not do

Read this before you install.

- It does not prove that an audit was done. Claude can write the record itself, and a record marked LOW passes without a prompt. The gate checks two things only: the file name matches the tool name exactly, and the file has exactly one risk line. If you want every install to reach you, set `ASK_ON_LOW = True` (see Adjust).
- It is a guard against accidents, not a wall against a determined bypass. These are not seen:
  - an install run through another language (`python3 -c "..."`, `node -e "..."`) or from a script file (`bash ./setup.sh`)
  - a manager whose name is not written out as a word: held in a variable (`$B install wget`), split by quotes (`br''ew`), or reached through an alias or a shell function
  - a quoted command handed to a program the gate does not know (`watch 'brew install wget'`)
- It only looks at installs that land machine-wide. These are not gated:
  - project dependencies (`npm install <name>` without `-g`, `pip install` without `--user`, anything from a requirements file, `uv pip install` without `--system`, `uv sync`)
  - one-off runs (`npx`, `uvx`)
  - a downloaded script piped into a shell
  - container images, `go install`, and OS package managers (apt, dnf, and so on)
  - local paths (`brew install ./formula.rb`, `cargo install --path .`)
- Records are per project. A tool audited in one repository is blocked again in another until that repository has its own record.

## What it gates

| Manager | When | Name that the record must match |
|---|---|---|
| brew | `install`, `reinstall` | the full name, including a tap (`user/tap/name`) |
| npm, pnpm, bun | `install` / `i` / `add` with `-g` or `--global` | the full name, including a scope; a trailing version is dropped |
| yarn | `global add` | same as npm |
| pipx | `install` | the name without a version specifier |
| uv | `tool install`; `pip install` with `--system` or `--break-system-packages`, or under `sudo` | same as pipx |
| pip | `install` with `--user` or `--break-system-packages`, or under `sudo` | same as pipx |
| cargo | `install` (not with `--path`) | the crate name without a version |
| gem | `install` | the gem name |
| claude | `mcp add`, `mcp add-json`, `plugin install` | the MCP server name; for a plugin, `name@marketplace` in full |

To turn a name into a file name: lowercase it, and replace `/`, `@`, and `:` with `-`. Then add `-audit.md`.

| Install command | Record |
|---|---|
| `brew install jq` | `docs/tool-audits/jq-audit.md` |
| `brew install user/tap/jq` | `docs/tool-audits/user-tap-jq-audit.md` |
| `npm install -g @scope/pkg` | `docs/tool-audits/scope-pkg-audit.md` |
| `claude plugin install name@market` | `docs/tool-audits/name-market-audit.md` |

A date in front (`2026-01-02_jq-audit.md`) is allowed. A different tap, scope, or marketplace is a different tool and needs its own record.

## How the command is read

The gate splits the command into words the way a shell does, and looks at each command in it. It does not search the text for install phrases, so text inside quotes that is only printed or stored is not an install.

An install is found in these places and is handled like one typed on its own (blocked, passed, or prompted, by its record):

- after `;`, `&&`, `||`, `|`, on a later line, or across a line continuation (a backslash at the end of a line)
- inside `( ... )`, `{ ...; }`, `if` / `then` / `else`, `for` / `while ... do`, and after `!`
- inside `$( ... )` and backquotes, also when they sit inside double quotes
- behind `sudo`, `doas`, `env`, `command`, `exec`, `time`, `nice`, `nohup`, `timeout`, `arch`, `caffeinate`, `stdbuf`, or a variable assignment
- in the text given to a shell (`sh -c "..."`, `bash <<< "..."`, a heredoc fed to a shell), to `eval`, or to `ssh host ...`. An install on another machine is looked up in this project's records too.

When the gate sees an install but cannot read it in full, you get a permission prompt. It does not pass silently, and it is not blocked.

- The names are not in the command: they come from a variable or a substitution (`brew install $PKG`, `brew install $(cat tools.txt)`) or from standard input (`... | xargs brew install`).
- The install sits behind a program the gate does not know (`watch -n 5 brew install wget`), or in text piped to a shell (`echo "brew install wget" | sh`). If every tool named there has a LOW record, it passes.
- The command cannot be split into words (for example an unbalanced quote) and mentions a package manager and an install word.

## Requirements

- Claude Code. The version checked is 2.1.314.
- macOS or Linux, with bash and python3 (checked with 3.9). Windows is not supported.
- If python3 is missing or fails, the gate cannot decide. It then answers with a permission prompt on any command that mentions a package manager, instead of letting installs through silently.
- The self-check also needs jq.

## Install

Run these two commands in order. Claude Code fetches the plugin from `noes-25h/agent-kit` on GitHub. If you already ran the first command for another plugin of this repository, run only the second.

```bash
claude plugin marketplace add noes-25h/agent-kit
```

```bash
claude plugin install install-gate@25h-agent-kit
```

To see whether it is installed, run the next command. It is installed when `install-gate@25h-agent-kit` is listed as `enabled`.

```bash
claude plugin list
```

A Claude Code session that is already open picks it up after you reopen it or type `/reload-plugins`. The plugin applies to every project.

The gate applies to commands that Claude runs. Commands that you type in your own terminal are not gated.

## Verify

Run the commands in this section from the root of a clone of this repository (`git clone https://github.com/noes-25h/agent-kit`).

There are two levels of verification. The first one alone is not enough.

**The hook script.** This feeds commands to the hook as text and checks each decision, 271 checks in all. It installs nothing, does not call Claude Code, and finishes in a few seconds.

```bash
bash ./plugins/install-gate/tests/selftest.sh
```

**A real Claude Code session.** This asks Claude Code three times to run a fake `brew` (a script that only creates a marker file) and checks whether the marker appears. It installs nothing real. It takes a few minutes and uses three calls of your usage allowance.

```bash
bash ./plugins/install-gate/tests/live-check.sh
```

Run it from a plain terminal. The check ends with one of three results. Exit code 0: the hook ran and the install was stopped. Exit code 1: the hook ran and the result was wrong. Exit code 2: it cannot tell. That is the result when a call did not finish, when the side without the plugin is not a control, or when the hook did not run.

The check counts the hook lines that Claude Code records for each run. When no hook of this plugin ran to the end, it prints the reason on one line and gives no verdict. This is what happens when the check is started from inside a sandbox, for example from a Claude Code session: Claude Code cannot create the data folder of the plugin under `~/.claude/plugins/data/`, does not start the hook, and lets the tool call through. The failure line then says `EPERM` or `operation not permitted`. Open a plain terminal and run the check again.

The first check tells you that the script decides correctly. Only the second tells you that Claude Code actually calls it.

## What happens

**No record.** The install does not run. Claude receives a message like this.

```
install-gate: blocked this install. No usable audit record for: wget (brew; no record; expected docs/tool-audits/wget-audit.md). Run /install-gate:tool-audit <tool name> to research the tool and write the record. ...
```

**Record marked MID or HIGH.** You see a permission prompt labeled `[plugin:install-gate]`:

```
install-gate: ripgrep is marked MID in docs/tool-audits/ripgrep-audit.md. Read the audit record before you approve.
```

**An install the gate cannot read in full.** You see a permission prompt like one of these.

```
install-gate: this command installs something (brew), but the names are not in the command text (a variable, a substitution or standard input). Check the command before you approve.
```

```
install-gate: this looks like an install of wget (brew) inside a command the gate cannot fully read, and there is no usable audit record for it. Check the command before you approve.
```

In an unattended run (`claude -p`), nobody can answer the prompt, so the install is denied.

**Record marked LOW.** The install runs. Nothing is shown.

**A command that is not an install.** Nothing happens. Text that only mentions an install (an `echo`, a commit message, a document written with a heredoc) is not treated as one.

## The audit record

A record is a Markdown file in `docs/tool-audits/` with exactly one risk line:

```
Risk: LOW
```

`Risk: MID` and `Risk: HIGH` are the other two values. A file with no risk line, with more than one, or with the unfilled template line is treated as no record.

The skill writes the record for you:

```
/install-gate:tool-audit ripgrep
```

The skill uses the model of your session (`model: inherit`) at `effort: high`. To change that, edit the frontmatter of `plugins/install-gate/skills/tool-audit/SKILL.md`.

## Adjust

Two switches sit at the top of `plugins/install-gate/scripts/gate.py`.

- `ASK_ON_LOW = True` shows a permission prompt even for a LOW record. Every gated install then reaches you.
- `GATE_ALL_PIP = True` gates every `pip install <name>` and `uv pip install <name>`, including installs into a virtual environment. Requirements files and local paths still pass.

To change it, edit a clone of this repository and install from the clone instead of from GitHub (`claude plugin marketplace add ./agent-kit`, run from the folder one level above the clone). The plugin is then read directly from the clone. If you already installed from GitHub, this points the `25h-agent-kit` source at the clone, and plugins already installed from it update from the clone from then on. To go back, run `claude plugin marketplace add noes-25h/agent-kit`. Changes take effect after you reopen Claude Code or type `/reload-plugins`.

selftest assumes both switches are off. With a switch on, the cases that the switch changes are reported as failures (for example a LOW record now gives `ask`); the rest must still pass.

## Uninstall

```bash
claude plugin uninstall install-gate@25h-agent-kit
```

```bash
claude plugin marketplace remove 25h-agent-kit
```

The second command removes the registration of this repository as a source. Skip it if you still use another plugin from this repository. A copy of the plugin remains in the Claude Code config folder (`~/.claude/plugins/cache/25h-agent-kit/`). It is no longer read, and you can delete it by hand. Your audit records in `docs/tool-audits/` are yours and stay where they are.

## License

MIT. See [LICENSE](LICENSE).
