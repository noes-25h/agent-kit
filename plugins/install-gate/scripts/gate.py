#!/usr/bin/env python3
"""install-gate / PreToolUse (Bash): decide what to do with a command that installs a tool machine-wide.

For every tool the command would install, look for an audit record in the project:

    no usable record            -> deny  (Claude is told to write one with /install-gate:tool-audit)
    record says  Risk: LOW      -> allow (nothing is printed)
    record says  Risk: MID/HIGH -> ask   (the user gets a prompt that points at the record)

An install the gate can see but cannot fully read also asks: the names come from a variable, a
substitution or standard input (xargs), or the install sits inside a command the gate does not know.

Reads the hook input (JSON) on stdin. Prints a PreToolUse decision (JSON) on stdout, or nothing to allow.
Any crash exits non-zero; the wrapper (gate.sh) turns that into "ask" so the gate never opens silently.
"""
import glob
import json
import os
import re
import shlex
import sys

# ---- settings you may change -------------------------------------------------------------------
ASK_ON_LOW = False    # True: prompt the user even when the record says LOW (every install reaches a human)
GATE_ALL_PIP = False  # True: gate every `pip install <name>`, not only --user / system-wide installs
# -------------------------------------------------------------------------------------------------

AUDIT_DIR = os.path.join("docs", "tool-audits")   # fixed; the bundled skill writes records here
SKILL = "/install-gate:tool-audit"

SHELLS = {"sh", "bash", "zsh", "dash", "ksh"}
PUNCT = "();<>|&\n"
# shell words that may stand in front of a command: `if brew ...`, `then brew ...`, `{ brew ...; }`, `! brew ...`
KEYWORDS = {"if", "then", "else", "elif", "do", "while", "until", "!", "{"}
# wrappers that run the rest of the line: name -> (flags that take a value, positional words to skip)
WRAPPERS = {"env": ({"-u", "--unset", "-C", "--chdir"}, 0), "command": (set(), 0), "builtin": (set(), 0),
            "exec": ({"-a"}, 0), "time": ({"-o", "--output", "-f", "--format"}, 0),
            "nice": ({"-n", "--adjustment"}, 0), "nohup": (set(), 0), "noglob": (set(), 0),
            "arch": ({"-arch", "-e"}, 0), "caffeinate": ({"-t", "-w"}, 0), "stdbuf": (set(), 0),
            "timeout": ({"-s", "--signal", "-k", "--kill-after"}, 1)}
SUDO_VALUE_FLAGS = {"-u", "-g", "-h", "-p", "-C", "-D", "-R", "-T", "-U"}
XARGS_VALUE_FLAGS = {"-I", "-n", "-P", "-L", "-d", "-E", "-s", "-J", "-R", "-S"}
SSH_VALUE_FLAGS = {"-b", "-c", "-D", "-E", "-e", "-F", "-I", "-i", "-J", "-L", "-l", "-m", "-O", "-o", "-p",
                   "-Q", "-R", "-S", "-W", "-w"}
# commands whose arguments are text or names, never a command to run
INERT = {"echo", "printf", "for", "select", "case", "grep", "egrep", "fgrep", "rg", "man", "which", "type",
         "whereis", "git"}
MANAGER = re.compile(r"^(brew|npm|pnpm|bun|yarn|pipx|uv|cargo|gem|claude|pip[\d.]*|python[\d.]*)$")
STDIN_SHELL = "\0shell-reading-stdin"
MAX_DEPTH = 6


# ---- 1. turn the command text into simple commands ---------------------------------------------

HEREDOC = re.compile(r"(?<!<)<<(?!<)-?\s*(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1")


def first_word(text):
    """Command word of the last pipeline segment in `text` (used to see who consumes a heredoc)."""
    seg = re.split(r"[;|&]", text)[-1].split()
    while seg and (re.match(r"^[A-Za-z_]\w*=", seg[0]) or seg[0] in ("sudo", "env", "command", "exec")):
        seg = seg[1:]
    return os.path.basename(seg[0]) if seg else ""


def strip_heredocs(text):
    """Drop heredoc bodies unless a shell consumes them (then the body is shell text and is kept)."""
    lines, out, i = text.split("\n"), [], 0
    while i < len(lines):
        line = lines[i]
        m = HEREDOC.search(line)
        if not m:
            out.append(line)
            i += 1
            continue
        delim, body, j = m.group(2), [], i + 1
        while j < len(lines) and lines[j].strip() != delim:
            body.append(lines[j])
            j += 1
        out.append(line[:m.start()] + " " + line[m.end():])
        if first_word(line[:m.start()]) in SHELLS:
            out.extend(body)
        i = j + 1
    return "\n".join(out)


def tokenize(text):
    lex = shlex.shlex(text, posix=True, punctuation_chars=PUNCT)
    lex.whitespace = " \t\r"
    lex.whitespace_split = True
    lex.commenters = ""
    return list(lex)   # raises ValueError on unbalanced quotes


def match_paren(text, i):
    """Index of the ")" that closes the "(" at text[i]; len(text) when it is never closed."""
    depth, quote, j, n = 0, "", i, len(text)
    while j < n:
        c = text[j]
        if quote:
            if c == "\\" and quote == '"':
                j += 2
                continue
            if c == quote:
                quote = ""
        elif c == "\\":
            j += 2
            continue
        elif c in "'\"":
            quote = c
        elif c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return j
        j += 1
    return n


def clean(text):
    """Prepare shell text for the word splitter. Returns (text, substitutions).

    - unquoted comments are removed (# at the start of a word, up to the end of the line)
    - a line continuation (backslash + newline) is removed, as the shell does
    - an unquoted backquote becomes a command separator, so what is inside is read as a command
    - $( ... ) and backquotes inside double quotes still run: their text is returned in `substitutions`
    """
    out, subs, quote, i, n = [], [], "", 0, len(text)
    while i < n:
        c = text[i]
        if quote == "'":
            if c == "'":
                quote = ""
        elif c == "\\" and i + 1 < n:
            if text[i + 1] != "\n":
                out.append(text[i:i + 2])
            i += 2
            continue
        elif quote == '"':
            if c == '"':
                quote = ""
            elif c == "`" or text.startswith("$(", i):
                j = text.find("`", i + 1) if c == "`" else match_paren(text, i + 1)
                j = n if j == -1 else j
                subs.append(text[i + (1 if c == "`" else 2):j])
                out.append(text[i:j + 1])
                i = j + 1
                continue
        elif c in "'\"":
            quote = c
        elif c == "`":
            out.append(" ; ")
            i += 1
            continue
        elif c == "#" and (i == 0 or text[i - 1] in " \t\n;|&("):
            while i < n and text[i] != "\n":
                i += 1
            continue
        out.append(c)
        i += 1
    return "".join(out), subs


def simple_commands(text, depth=0):
    """Yield (words, under_sudo, names_from_stdin) for each simple command in the text."""
    if depth > MAX_DEPTH:
        raise ValueError("nested too deep")
    body, subs = clean(strip_heredocs(text))
    for sub in subs:
        yield from simple_commands(sub, depth + 1)
    cur, skip_next, is_here, here = [], False, False, None
    for tok in tokenize(body) + ["\n"]:
        is_punct = tok != "" and all(c in PUNCT for c in tok)
        if skip_next:                       # the target of a redirection
            skip_next = False
            if not is_punct:
                if is_here:
                    here = tok              # here-string: `bash <<< "text"`
                continue
        if is_punct:
            if "<" in tok or ">" in tok:    # redirection: drop it, its target, and a leading fd number
                if cur and cur[-1].isdigit():
                    cur.pop()
                skip_next, is_here = True, tok == "<<<"
                continue
            if cur:
                yield from unwrap(cur, depth, here)
            cur, here = [], None
            continue
        cur.append(tok)


def unwrap(words, depth, here=None):
    """Strip assignments, keywords and wrappers; read again what a shell, eval or ssh is given as text.

    Yields (words, under_sudo, names_from_stdin).
    """
    sudo, piped = False, False
    w = list(words)
    while w:
        head = os.path.basename(w[0])
        if re.match(r"^[A-Za-z_]\w*=", w[0]) or w[0] in KEYWORDS:
            w = w[1:]
        elif head in ("sudo", "doas"):
            sudo = True
            w = w[1:]
            while w and w[0].startswith("-"):
                w = w[2:] if w[0] in SUDO_VALUE_FLAGS else w[1:]
        elif head in WRAPPERS:
            value_flags, skip = WRAPPERS[head]
            w = w[1:]
            while w and w[0].startswith("-"):
                w = w[2:] if w[0] in value_flags else w[1:]
            w = w[skip:]
        elif head == "xargs":               # the rest is a command; its last arguments come from stdin
            piped = True
            w = w[1:]
            while w and w[0].startswith("-"):
                w = w[2:] if w[0] in XARGS_VALUE_FLAGS else w[1:]
        else:
            break
    if not w:
        return
    head = os.path.basename(w[0])
    again = None
    if head == "eval":
        again = " ".join(w[1:])
    elif head == "ssh":                     # the command runs on another machine; read it the same way
        rest = w[1:]
        while rest and rest[0].startswith("-"):
            rest = rest[2:] if rest[0] in SSH_VALUE_FLAGS else rest[1:]
        again = " ".join(rest[1:])
    elif head in SHELLS:
        for i, a in enumerate(w[1:], start=1):
            if re.match(r"^-[A-Za-z]*c$", a) and i + 1 < len(w):
                again = w[i + 1]
                break
        else:
            if any(not a.startswith("-") for a in w[1:]):
                return                      # runs a script file; the gate does not read files
            if here is None:
                yield [STDIN_SHELL], sudo, piped
                return
            again = here
    if again is None:
        yield w, sudo, piped
        return
    for inner, inner_sudo, inner_piped in simple_commands(again, depth + 1):
        yield inner, (sudo or inner_sudo), (piped or inner_piped)


# ---- 2. per-manager table: when is it a machine-wide install, and what is being installed -------

def positionals(args, value_flags, stop_at_dashdash=False):
    out, i = [], 0
    while i < len(args):
        a = args[i]
        if a == "--":
            if not stop_at_dashdash:
                out.extend(args[i + 1:])
            break
        if a.startswith("-") and len(a) > 1:
            i += 1 if ("=" in a or a not in value_flags) else 2
            continue
        out.append(a)
        i += 1
    return out


def subcommand(args):
    """(first non-flag word, the args after it)."""
    for i, a in enumerate(args):
        if not a.startswith("-"):
            return a, args[i + 1:]
    return "", []


def is_local_path(tok):
    return tok.startswith((".", "/", "~"))


def strip_version(tok, seps):
    for i, c in enumerate(tok):
        if c in seps and i > 0:
            return tok[:i]
    return tok


def npm_name(tok):
    if tok.startswith("@"):
        rest = tok[1:]
        return "@" + (rest.split("@")[0])
    return tok.split("@")[0]


def from_url(tok):
    if "://" in tok or tok.startswith("git+"):
        last = re.split(r"[#?]", tok)[0].rstrip("/").split("/")[-1]
        return re.sub(r"\.git$", "", last)
    return tok


PIP_VALUE = {"-r", "--requirement", "-c", "--constraint", "-e", "--editable", "-i", "--index-url",
             "--extra-index-url", "-t", "--target", "--prefix", "--python", "-f", "--find-links", "--root",
             "--src", "--platform", "--python-version", "--implementation", "--abi", "--progress-bar",
             "--cache-dir", "--trusted-host", "--proxy", "--config-settings", "-C", "--global-option",
             "--no-binary", "--only-binary", "--upgrade-strategy", "--report", "--log"}
NPM_VALUE = {"--registry", "--prefix", "--tag", "--userconfig", "--cache", "-w", "--workspace", "--otp"}
PIPX_VALUE = {"--python", "--pip-args", "--index-url", "-i", "--suffix"}
UV_VALUE = {"--python", "-p", "--with", "--from", "--index-url", "--index", "--extra-index-url",
            "--default-index"}
CARGO_VALUE = {"--version", "--vers", "--git", "--branch", "--tag", "--rev", "--path", "--root",
               "--registry", "--index", "--features", "-F", "--profile", "--target", "--target-dir", "-j",
               "--jobs", "--bin", "--example", "--config", "-Z", "--color"}
GEM_VALUE = {"-v", "--version", "-i", "--install-dir", "-n", "--bindir", "--source", "-s", "-P",
             "--trust-policy", "--platform", "-g", "--file", "-B", "--build-root", "--document"}
MCP_VALUE = {"-t", "--transport", "-s", "--scope", "-e", "--env", "-H", "--header", "--client-id",
             "--client-secret", "--callback-port"}
PLUGIN_VALUE = {"-s", "--scope", "--config", "--accept-command"}
PIP_SPEC = "=<>!~[; "


def installs(words, sudo):
    """(is a machine-wide install, [(label, name)], label when a name cannot be read from the text)."""
    cmd, args = os.path.basename(words[0]), words[1:]
    if re.match(r"^python[\d.]*$", cmd) and args[:2] == ["-m", "pip"]:
        cmd, args = "pip", args[2:]
    names, label, seen = [], cmd, False

    if cmd == "brew":
        sub, rest = subcommand(args)
        if sub in ("install", "reinstall"):
            seen = True
            names = positionals(rest, set())
    elif cmd in ("npm", "pnpm", "bun"):
        sub, rest = subcommand(args)
        is_global = any(a in ("-g", "--global", "--location=global") for a in args)
        if sub in ("install", "i", "add") and is_global:
            seen = True
            names = [npm_name(p) for p in positionals(rest, NPM_VALUE)]
            label = cmd + " -g"
    elif cmd == "yarn":
        sub, rest = subcommand(args)
        sub2, rest2 = subcommand(rest)
        if sub == "global" and sub2 == "add":
            seen = True
            names = [npm_name(p) for p in positionals(rest2, NPM_VALUE)]
            label = "yarn global"
    elif cmd == "pipx":
        sub, rest = subcommand(args)
        if sub == "install":
            seen = True
            names = [strip_version(from_url(p), PIP_SPEC) for p in positionals(rest, PIPX_VALUE)]
    elif cmd == "uv":
        sub, rest = subcommand(args)
        sub2, rest2 = subcommand(rest)
        if sub == "tool" and sub2 == "install":
            seen = True
            names = [strip_version(from_url(p), PIP_SPEC + "@") for p in positionals(rest2, UV_VALUE)]
            label = "uv tool"
        elif sub == "pip" and sub2 == "install":
            wide = sudo or any(a in ("--system", "--break-system-packages") for a in rest2)
            if GATE_ALL_PIP or wide:
                seen = True
                names = [strip_version(from_url(p), PIP_SPEC) for p in positionals(rest2, PIP_VALUE | UV_VALUE)]
                label = "uv pip"
    elif re.match(r"^pip[\d.]*$", cmd):
        sub, rest = subcommand(args)
        wide = sudo or any(a in ("--user", "--break-system-packages") for a in rest)
        if sub == "install" and (GATE_ALL_PIP or wide):
            seen = True
            names = [strip_version(from_url(p), PIP_SPEC) for p in positionals(rest, PIP_VALUE)]
            label = "pip"
    elif cmd == "cargo":
        sub, rest = subcommand(args)
        if sub == "install" and "--path" not in rest:
            seen = True
            names = [p.split("@")[0] for p in positionals(rest, CARGO_VALUE)]
            if not names and "--git" in rest and rest.index("--git") + 1 < len(rest):
                names = [from_url(rest[rest.index("--git") + 1])]
    elif cmd == "gem":
        sub, rest = subcommand(args)
        if sub in ("install", "i"):
            seen = True
            names = positionals(rest, GEM_VALUE, stop_at_dashdash=True)
    elif cmd == "claude":
        sub, rest = subcommand(args)
        sub2, rest2 = subcommand(rest)
        if sub == "mcp" and sub2 in ("add", "add-json"):
            seen = True
            names = positionals(rest2, MCP_VALUE, stop_at_dashdash=True)[:1]
            label = "claude mcp"
        elif sub in ("plugin", "plugins") and sub2 in ("install", "i"):
            seen = True
            names = positionals(rest2, PLUGIN_VALUE)[:1]
            label = "claude plugin"

    out, unreadable = [], ""
    for n in names:
        n = from_url(n) if cmd in ("brew", "gem") else n
        if "$" in n or "`" in n:            # a variable or a substitution: the name is not in the text
            unreadable = label
        elif n and not is_local_path(n):
            out.append((label, n))
    return seen, out, unreadable


# ---- 3. look up the audit record ----------------------------------------------------------------

def name_tokens(name):
    slug = re.sub(r"[/@:]", "-", name.lower().lstrip("@"))
    return tuple(t for t in re.split(r"[-_.]+", slug) if t)


def record_tokens(path):
    base = re.sub(r"\.md$", "", os.path.basename(path).lower())
    base = re.sub(r"^\d{4}-\d{2}-\d{2}[_-]", "", base)
    toks = [t for t in re.split(r"[-_.]+", base) if t]
    if not toks or toks[-1] != "audit":
        return None
    return tuple(toks[:-1])


RISK_LINE = re.compile(r"^\s*(?:[>*-]\s*)?\**risk\**\s*:\s*\**\s*(LOW|MID|HIGH)\b", re.I | re.M)
ORDER = {"LOW": 0, "MID": 1, "HIGH": 2}


def record_risk(path):
    """'LOW' / 'MID' / 'HIGH' when the record has exactly one risk line, else None."""
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            found = RISK_LINE.findall(f.read())
    except OSError:
        return None
    return found[0].upper() if len(found) == 1 else None


def lookup(name, records):
    """(risk or None, path or None) for a tool name."""
    want = name_tokens(name)
    hits = [p for toks, p in records if toks == want]
    best = (None, hits[0] if hits else None)
    for p in hits:
        r = record_risk(p)
        if r and (best[0] is None or ORDER[r] > ORDER[best[0]]):
            best = (r, p)
    return best


# ---- 4. decide ----------------------------------------------------------------------------------

def emit(decision, reason):
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                             "permissionDecision": decision,
                                             "permissionDecisionReason": reason}}, ensure_ascii=False))


def read_command(cmd):
    """(direct, indirect, blind) for a command line.

    direct:   [(label, name)] installs the gate read as commands
    indirect: [(label, name)] installs found inside a command the gate does not know, or in text piped
              to a shell
    blind:    [label] installs whose names are not in the command text
    """
    direct, indirect, blind, others, stdin_shell = [], [], [], [], False
    for words, sudo, piped in simple_commands(cmd):
        if words[0] == STDIN_SHELL:
            stdin_shell = True
            continue
        seen, names, unreadable = installs(words, sudo)
        if seen:
            direct.extend(names)
            if piped or unreadable:
                blind.append(unreadable or (names[0][0] if names else os.path.basename(words[0])))
            continue
        others.append(words)
        head = os.path.basename(words[0])
        if head in INERT or MANAGER.match(head):
            continue
        for i in range(1, len(words)):      # `watch brew install x`: an install behind an unknown word
            if MANAGER.match(os.path.basename(words[i])):
                seen, names, unreadable = installs(words[i:], sudo)
                if seen:
                    indirect.extend(names)
                    if unreadable:
                        blind.append(unreadable)
                    break
    if stdin_shell:                         # `echo "brew install x" | sh`: the shell runs the text
        for words in others:
            texts = [a for a in words[1:] if re.search(r"\s", a)] + [" ".join(words[1:])]
            for text in dict.fromkeys(texts):
                try:
                    for inner, sudo, _ in simple_commands(text, 1):
                        if inner[0] != STDIN_SHELL:
                            indirect.extend(installs(inner, sudo)[1])
                except ValueError:
                    pass
    return direct, indirect, blind


def main():
    data = json.loads(sys.stdin.read())
    if data.get("tool_name") != "Bash":
        return
    cmd = (data.get("tool_input") or {}).get("command") or ""
    if not cmd.strip():
        return

    try:
        direct, indirect, blind = read_command(cmd)
    except ValueError:
        # Could not split the command into words (for example an unbalanced quote).
        if re.search(r"\b(brew|npm|pnpm|yarn|bun|pipx?|pip3|uv|cargo|gem|claude)\b", cmd) and \
           re.search(r"\b(install|reinstall|add|i)\b", cmd):
            emit("ask", "install-gate: could not parse this command, and it looks like it may install "
                        "something. Check the command before you approve.")
        return
    if not (direct or indirect or blind):
        return

    project = os.environ.get("CLAUDE_PROJECT_DIR") or data.get("cwd") or os.getcwd()
    records = []
    for p in sorted(glob.glob(os.path.join(project, AUDIT_DIR, "*.md"))):
        toks = record_tokens(p)
        if toks is not None:
            records.append((toks, p))

    missing, by_record, by_command = [], [], []
    direct = list(dict.fromkeys(direct))
    for label, name in direct:
        risk, path = lookup(name, records)
        slug = "-".join(name_tokens(name))
        if risk is None:
            why = "record has no single 'Risk:' line" if path else "no record"
            missing.append(f"{name} ({label}; {why}; expected {AUDIT_DIR}/{slug}-audit.md)")
        elif risk != "LOW" or ASK_ON_LOW:
            by_record.append(f"{name} is marked {risk} in {os.path.relpath(path, project)}")
    for label, name in dict.fromkeys(indirect):
        if (label, name) in direct:
            continue
        risk, path = lookup(name, records)
        if risk is None:
            by_command.append(f"this looks like an install of {name} ({label}) inside a command the gate "
                              "cannot fully read, and there is no usable audit record for it")
        elif risk != "LOW" or ASK_ON_LOW:
            by_record.append(f"{name} is marked {risk} in {os.path.relpath(path, project)}")
    if blind:
        by_command.append(f"this command installs something ({', '.join(dict.fromkeys(blind))}), but the "
                          "names are not in the command text (a variable, a substitution or standard input)")

    if missing:
        emit("deny",
             "install-gate: blocked this install. No usable audit record for: " + "; ".join(missing) + ". "
             f"Run {SKILL} <tool name> to research the tool and write the record. The record must contain "
             "exactly one line of the form 'Risk: LOW', 'Risk: MID' or 'Risk: HIGH'. Do not retry the "
             "install until the record exists, and do not rephrase the command to get around this.")
    elif by_command:
        emit("ask", "install-gate: " + "; ".join(by_command + by_record) + ". Check the command before you approve.")
    elif by_record:
        emit("ask", "install-gate: " + "; ".join(by_record) + ". Read the audit record before you approve.")


if __name__ == "__main__":
    main()
