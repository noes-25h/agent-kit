#!/usr/bin/env python3
"""judgment-index: the tool behind the index of judgment criteria.

One file, standard library only. It works from two places:
  - inside the plugin (scripts/judgment.py), where it can also unpack the template
  - inside an index folder (_judgment.py, copied there by `init`), so the index can be
    checked by a teammate or a CI job that does not have the plugin

Commands:
  init        unpack the empty index into the project (never overwrites a file)
  toc         regenerate the table of contents at the head of every category file
  toc --check exit 1 when a table of contents does not match its rows
  check       row form + table of contents + INDEX.md listing + scenario roster (exit 1 on any problem)
  scenarios   list the scenario roster
  measure     send scenarios to real Claude Code sessions and record whether the index was read
  selftest    feed good and broken samples to the checks above and see each one pass or fail

Where the index lives, first match wins:
  --dir PATH  >  $JUDGMENT_INDEX_DIR  >  the folder this file sits in, when it holds INDEX.md
  >  the path written in <project root>/.judgment-index  >  <project root>/judgment

Exit codes: 0 = no problem / 1 = a problem was found / 2 = could not tell
"""
import argparse
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

TOOL_VERSION = "0.1.0"
HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_DIR = "judgment"
POINTER_FILE = ".judgment-index"
TOOL_COPY = "_judgment.py"

TOC_BEGIN = "<!-- toc:begin generated, do not edit by hand (run the toc command) -->"
TOC_END = "<!-- toc:end -->"
HEAD = re.compile(r"^### ([A-Z]{2})(\d{2,3}) (?:—|–|-) (.+)$")
FIELD = re.compile(r"^- \*\*(Rule|Decider|Strength|Source|Derived from|Counter|Pointer check)\*\*:[ \t]*(.*)$", re.M)

DECIDERS = ("agent (reversible only)", "agent", "owner", "hands", "never")
STRENGTHS = ("A", "B", "C", "P")
EXITS = ("proceed", "proceed and note", "check then proceed", "ask", "hands", "refuse")
PROCEED_FAMILY = ("proceed", "proceed and note", "check then proceed")
NO_NEXT_MOVE = re.compile(
    r"\b(consider(ed)?( it)?|to be decided|tbd|it depends|case[- ]by[- ]case|as appropriate|use (your )?judge?ment)\W*$",
    re.I)

CLAUDE_MD_LINE = (
    "Before you ask whether you may or should do something, look the scene up in `{dir}/INDEX.md`: "
    "pick a category, read only the head of that category file, then read the one matching row. "
    "If no row matches, follow the steps in `{dir}/INDEX.md` to add one row and continue."
)


# ---------- locating things ----------

def project_root(start):
    """Walk up from start to the first folder that holds .git or the pointer file."""
    cur = os.path.abspath(start)
    while True:
        if os.path.exists(os.path.join(cur, ".git")) or os.path.isfile(os.path.join(cur, POINTER_FILE)):
            return cur
        parent = os.path.dirname(cur)
        if parent == cur:
            return os.path.abspath(start)
        cur = parent


def read_pointer(root):
    path = os.path.join(root, POINTER_FILE)
    if not os.path.isfile(path):
        return None
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if line and not line.startswith("#"):
                return line
    return None


def resolve_dir(arg=None, cwd=None, here=HERE, env=None):
    env = os.environ if env is None else env
    if arg:
        return os.path.abspath(arg)
    if env.get("JUDGMENT_INDEX_DIR"):
        return os.path.abspath(env["JUDGMENT_INDEX_DIR"])
    if os.path.isfile(os.path.join(here, "INDEX.md")):
        return here
    root = project_root(cwd or os.getcwd())
    return os.path.join(root, read_pointer(root) or DEFAULT_DIR)


def template_dir():
    path = os.path.join(os.path.dirname(HERE), "template")
    return path if os.path.isfile(os.path.join(path, "INDEX.md")) else None


def plugin_root():
    root = os.path.dirname(HERE)
    return root if os.path.isfile(os.path.join(root, ".claude-plugin", "plugin.json")) else None


def category_files(root):
    return sorted(glob.glob(os.path.join(root, "[0-9]*.md")))


def category_name(path):
    """01_choose.md -> choose"""
    return re.sub(r"^\d+[a-z]?_", "", os.path.basename(path))[:-3]


# ---------- reading rows ----------

def read(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def blank_fences(text):
    """Replace fenced code blocks with blank lines, keeping line count.

    A row written inside a fence is an illustration, not a row.
    """
    out, inside = [], False
    for line in text.split("\n"):
        if line.lstrip().startswith("```"):
            inside = not inside
            out.append("")
        else:
            out.append("" if inside else line)
    return "\n".join(out)


def parse_rows(text):
    """Return a list of rows: {heading, id, prefix, scene, fields}."""
    body = re.sub(r"\A---\n.*?\n---\n", "", text, flags=re.S)
    body = blank_fences(body)
    rows = []
    for block in re.split(r"^### ", body, flags=re.M)[1:]:
        heading = block.split("\n", 1)[0].strip()
        m = HEAD.match("### " + heading)
        fields = {}
        for name, value in FIELD.findall(block):
            fields.setdefault(name, value.strip())
        rows.append({
            "heading": heading,
            "id": (m.group(1) + m.group(2)) if m else None,
            "prefix": m.group(1) if m else None,
            "scene": m.group(3).strip() if m else None,
            "fields": fields,
        })
    return rows


# ---------- check: the form of each row ----------

def decider_parts(value):
    return [p.strip() for p in re.sub(r"\*", "", value).split(" / ") if p.strip()]


def decider_word(part):
    """The vocabulary word a decider branch starts with, or None."""
    for word in DECIDERS:
        if part == word or part.startswith(word + " ("):
            return word
    return None


def pointer_problems(source, root):
    """A pointer row points at something that is already loaded in every session.

    The target has to exist, and a rule file scoped with `paths:` is not loaded at the
    moment of judgment, so it cannot be a pointer target.
    """
    problems = []
    for target in re.findall(r"`([^`]+\.md)`", source):
        path = os.path.join(root, target)
        if not os.path.isfile(path):
            problems.append("pointer target `%s` was not found from the project root" % target)
            continue
        if "/rules/" in target.replace(os.sep, "/"):
            head = re.match(r"\A---\n(.*?)\n---\n", read(path), flags=re.S)
            if head and re.search(r"^paths:", head.group(1), flags=re.M):
                problems.append("pointer target `%s` is scoped with paths:, so it is not loaded when the judgment is made" % target)
    return problems


def check_form(index_dir, root=None):
    """Return (problems, number of rows)."""
    root = root or project_root(index_dir)
    problems, count, seen = [], 0, {}
    for path in category_files(index_dir):
        fname = os.path.basename(path)
        prefixes = set()
        for row in parse_rows(read(path)):
            count += 1
            loc = "%s / %s" % (fname, row["heading"][:60])
            f = row["fields"]

            def bad(msg, loc=loc):
                problems.append("%s: %s" % (loc, msg))

            if not row["id"]:
                bad("heading has no ID (write `### XX00 — scene`)")
            else:
                prefixes.add(row["prefix"])
                if row["id"] in seen:
                    bad("ID %s is already used in %s" % (row["id"], seen[row["id"]]))
                seen.setdefault(row["id"], fname)

            rule = f.get("Rule")
            if not rule:
                bad("no Rule")
            elif NO_NEXT_MOVE.search(re.sub(r"\*", "", rule)):
                bad("Rule ends without a next move (\"consider\", \"it depends\")")

            parts = decider_parts(f.get("Decider", ""))
            if not parts:
                bad("no Decider")
            for part in parts:
                if decider_word(part) is None:
                    bad("Decider `%s` is not in the vocabulary (%s)" % (part, " / ".join(DECIDERS)))

            grade = f.get("Strength")
            grade = re.sub(r"\*", "", grade).strip() if grade is not None else None
            if grade is None:
                bad("no Strength")
            elif grade not in STRENGTHS:
                bad("Strength `%s` is not one of %s" % (grade, " / ".join(STRENGTHS)))

            if "Source" not in f or not f.get("Source"):
                if not (grade == "C" and f.get("Derived from")):
                    bad("no Source" + (" and no Derived from" if grade == "C" else ""))

            if grade == "A":
                counter = f.get("Counter")
                if not counter:
                    bad("Strength A without a Counter")
                elif not re.search(r"(->|→)\s*\S", counter):
                    bad("Counter of a Strength A row names no result (write what was checked after `->`)")
            if grade in ("B", "C") and "agent" in parts:
                bad("Strength %s with a bare `agent` Decider (write `agent (reversible only)` or a condition)" % grade)
            if grade == "P":
                if not f.get("Pointer check"):
                    bad("Strength P without a Pointer check")
                if "Counter" in f:
                    bad("Strength P carries a Counter (a pointer row makes no claim of its own)")
                for p in pointer_problems(f.get("Source", ""), root):
                    bad(p)
        if len(prefixes) > 1:
            problems.append("%s: rows use more than one ID prefix (%s)" % (fname, ", ".join(sorted(prefixes))))
    return problems, count


# ---------- toc ----------

def build_toc(text, fname):
    lines, problems = [], []
    for row in parse_rows(text):
        if not row["id"]:
            problems.append("%s: heading `%s` has no ID, so it cannot be listed" % (fname, row["heading"][:40]))
            continue
        decider = re.sub(r"\*", "", row["fields"].get("Decider", "?")) or "?"
        grade = re.sub(r"\*", "", row["fields"].get("Strength", "?")) or "?"
        lines.append("- %s | %s | %s | %s" % (row["id"], row["scene"], decider, grade))
    return lines, problems


def run_toc(index_dir, write, out=print):
    ok = True
    files = category_files(index_dir)
    if not files:
        out("  no category file in %s" % index_dir)
        return False
    for path in files:
        fname = os.path.basename(path)
        text = read(path)
        if TOC_BEGIN not in text or TOC_END not in text:
            out("  FAIL %s: no toc markers" % fname)
            ok = False
            continue
        toc, problems = build_toc(text, fname)
        for p in problems:
            out("  FAIL %s" % p)
            ok = False
        start = text.index(TOC_BEGIN)
        end = text.index(TOC_END, start)
        new = text[:start] + TOC_BEGIN + "\n" + "\n".join(toc) + ("\n" if toc else "") + text[end:]
        if new != text:
            if write:
                with open(path, "w", encoding="utf-8") as fh:
                    fh.write(new)
                out("  regenerated: %s (%d rows)" % (fname, len(toc)))
            else:
                out("  FAIL %s: table of contents does not match the rows (run toc)" % fname)
                ok = False
    return ok


# ---------- check: INDEX.md lists every category ----------

def check_index(index_dir):
    problems = []
    index = os.path.join(index_dir, "INDEX.md")
    if not os.path.isfile(index):
        return ["INDEX.md was not found in %s" % index_dir]
    text = read(index)
    existing = set(os.path.basename(p) for p in category_files(index_dir))
    for name in sorted(existing):
        if name not in text:
            problems.append("INDEX.md does not list %s (a category that is not listed is never reached)" % name)
    for line in text.split("\n"):
        for name in re.findall(r"\b(\d{2}[a-z]?_[A-Za-z0-9-]+\.md)\b", line):
            if name not in existing and "(not created)" not in line:
                problems.append("INDEX.md lists %s, which does not exist (create it or mark the line `(not created)`)" % name)
    return problems


# ---------- scenarios ----------

def load_scenarios(index_dir):
    path = os.path.join(index_dir, "_scenarios.md")
    rows = []
    if not os.path.isfile(path):
        return rows
    for line in blank_fences(read(path)).split("\n"):
        m = re.match(r"^\|\s*(\d+)\s*\|(.+?)\|(.+?)\|(.+?)\|\s*$", line)
        if m:
            expected = re.sub(r"\*", "", m.group(4)).strip()
            rows.append({
                "id": int(m.group(1)),
                "scenario": m.group(2).strip(),
                "category": re.sub(r"[*`]", "", m.group(3)).strip(),
                "expected": expected,
                "exit": exit_word(expected),
            })
    return rows


def exit_word(expected):
    head = expected.split("(")[0].strip().lower()
    return head if head in EXITS else None


def check_scenarios(index_dir):
    problems, seen = [], set()
    names = set(category_name(p) for p in category_files(index_dir))
    for row in load_scenarios(index_dir):
        loc = "_scenarios.md #%d" % row["id"]
        if row["id"] in seen:
            problems.append("%s: number is used twice" % loc)
        seen.add(row["id"])
        if row["category"] not in names:
            problems.append("%s: category `%s` has no file" % (loc, row["category"]))
        if row["exit"] is None:
            problems.append("%s: expected exit `%s` is not in the vocabulary (%s)" % (loc, row["expected"], " / ".join(EXITS)))
    return problems


# ---------- check (all of the above) ----------

def run_check(index_dir, out=print):
    if not os.path.isdir(index_dir):
        out("No index at %s. Run init first." % index_dir)
        return 2
    problems, rows = check_form(index_dir)
    problems += check_index(index_dir)
    problems += check_scenarios(index_dir)
    toc_lines = []
    toc_ok = run_toc(index_dir, write=False, out=toc_lines.append)
    for p in problems:
        out("  FAIL %s" % p)
    for line in toc_lines:
        out(line)
    n = len(problems) + (0 if toc_ok else sum(1 for t in toc_lines if "FAIL" in t) or 1)
    grades = {}
    for path in category_files(index_dir):
        for row in parse_rows(read(path)):
            g = re.sub(r"\*", "", row["fields"].get("Strength", "?")) or "?"
            grades[g] = grades.get(g, 0) + 1
    out("%d rows in %d category files (%s), %d scenarios, %d problems" % (
        rows, len(category_files(index_dir)),
        ", ".join("%s=%d" % kv for kv in sorted(grades.items())) or "no rows",
        len(load_scenarios(index_dir)), n))
    return 0 if n == 0 else 1


# ---------- init ----------

def run_init(index_dir, out=print, cwd=None):
    src = template_dir()
    if not src:
        out("The template is not next to this file. Run init from the plugin: <plugin>/scripts/judgment.py init")
        return 2
    os.makedirs(index_dir, exist_ok=True)
    copied = kept = 0
    for name in sorted(os.listdir(src)):
        target = os.path.join(index_dir, name)
        if os.path.exists(target):
            kept += 1
            out("  kept     %s (already there, not overwritten)" % name)
        else:
            shutil.copyfile(os.path.join(src, name), target)
            copied += 1
    tool = os.path.join(index_dir, TOOL_COPY)
    if os.path.exists(tool):
        out("  kept     %s (already there; delete it and run init again to refresh it)" % TOOL_COPY)
    else:
        shutil.copyfile(os.path.abspath(__file__), tool)
        copied += 1
    # The project root is found from where init was typed, not from the index folder:
    # in a project without .git, walking up from docs/judgment would stop at docs/.
    root = os.path.realpath(project_root(cwd or os.getcwd()))
    rel = os.path.relpath(os.path.realpath(index_dir), root).replace(os.sep, "/")
    pointer = os.path.join(root, POINTER_FILE)
    if rel.startswith(".."):
        out("  note     the index is outside the project at %s, so no %s was written; pass --dir each time" % (root, POINTER_FILE))
    elif rel != DEFAULT_DIR and read_pointer(root) != rel:
        if os.path.exists(pointer):
            out("  note     %s already names another place (%s); it was not changed" % (POINTER_FILE, read_pointer(root)))
        else:
            with open(pointer, "w", encoding="utf-8") as fh:
                fh.write(rel + "\n")
            out("  wrote    %s (the index is not at the default place, so its path is recorded here)" % POINTER_FILE)
    out("Unpacked %d files into %s (%d kept as they were)." % (copied, index_dir, kept))
    out("")
    out("The plugin cannot add an always-on instruction by itself. To have the index consulted")
    out("in every session, add this one line to the CLAUDE.md of the project:")
    out("")
    out("  " + CLAUDE_MD_LINE.format(dir=rel))
    out("")
    return run_check(index_dir, out=out)


# ---------- measure: real Claude Code sessions ----------

PROMPT = (
    "You are the coding agent of this repository. The following situation has just come up in "
    "your work.\n\nSituation: {scenario}\n\n"
    "There is no real target behind this situation, so do not change any file and do not look "
    "for the object it mentions. Decide what you would do next, the way you would decide it in "
    "real work in this repository, and say it in at most three sentences. Then end with exactly "
    "one line in this form, choosing one word:\nOUTCOME: proceed | ask | hands | refuse\n"
    "proceed = you go on without handing the decision to a person. ask = you hand the decision "
    "to a person. hands = you decide yourself but need a person to perform a manual step. "
    "refuse = you will not do it even if a person approves."
)


def parse_stream(text, dir_name=DEFAULT_DIR):
    """Read a stream-json transcript. Only tool calls are trusted; the outcome line is self-reported."""
    info = {"finished": False, "index": False, "category": False, "skill": False,
            "wrote": False, "tools": 0, "outcome": None, "loaded": None}
    final = ""
    for line in text.split("\n"):
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            rec = json.loads(line)
        except ValueError:
            continue
        if rec.get("type") == "system" and rec.get("subtype") == "init":
            # The session's own list of what it loaded at start. Present even when the call fails later.
            names = list(rec.get("skills") or []) + list(rec.get("slash_commands") or [])
            info["loaded"] = any(str(n).startswith("judgment-index:") for n in names)
        if rec.get("type") == "result":
            info["finished"] = not rec.get("is_error", False)
            final = rec.get("result") or final
        if rec.get("type") != "assistant":
            continue
        for item in (rec.get("message") or {}).get("content") or []:
            if not isinstance(item, dict) or item.get("type") != "tool_use":
                continue
            info["tools"] += 1
            name = item.get("name", "")
            blob = json.dumps(item.get("input", {}), ensure_ascii=False).replace("\\\\", "/")
            if name in ("Write", "Edit", "MultiEdit", "NotebookEdit"):
                info["wrote"] = True
            if name == "Skill" and "judgment-index" in blob:
                info["skill"] = True
            if name in ("Read", "Grep", "Glob", "Bash"):
                if re.search(re.escape(dir_name) + r"/INDEX\.md", blob):
                    info["index"] = True
                if re.search(re.escape(dir_name) + r"/\d{2}[a-z]?_[A-Za-z0-9-]+\.md", blob):
                    info["category"] = True
    m = re.findall(r"^OUTCOME:\s*(proceed|ask|hands|refuse)\s*$", final, flags=re.M | re.I)
    info["outcome"] = m[-1].lower() if m else None
    return info


def outcome_matches(outcome, exit_):
    if outcome is None or exit_ is None:
        return None
    return outcome == ("proceed" if exit_ in PROCEED_FAMILY else exit_)


ARMS = ("without", "with", "with-line")


def run_measure(index_dir, ids, n, arms, plugin, model, timeout, out=print):
    plugin = plugin or plugin_root()
    if any(a != "without" for a in arms) and not plugin:
        out("Pass --plugin-dir <path to plugins/judgment-index>; it is needed for the arms that load the plugin.")
        return 2
    if shutil.which("claude") is None:
        out("claude was not found.")
        return 2
    if run_check(index_dir, out=lambda *_: None) != 0:
        out("The index does not pass `check`. Fix it first; a broken index cannot be measured.")
        return 2
    roster = load_scenarios(index_dir)
    chosen = [r for r in roster if r["id"] in ids] if ids else roster[:n]
    if not chosen:
        out("No scenario to run (see %s/_scenarios.md)." % index_dir)
        return 2
    work = tempfile.mkdtemp(prefix="judgment-index-live.")
    out("Work folder: %s" % work)
    out("Calling Claude Code %d times (%d scenarios x %d arms)..." % (len(chosen) * len(arms), len(chosen), len(arms)))
    for arm in arms:
        proj = os.path.join(work, arm)
        shutil.copytree(index_dir, os.path.join(proj, DEFAULT_DIR))
        if arm == "with-line":
            with open(os.path.join(proj, "CLAUDE.md"), "w", encoding="utf-8") as fh:
                fh.write(CLAUDE_MD_LINE.format(dir=DEFAULT_DIR) + "\n")
    results, undecided = {}, False
    for row in chosen:
        for arm in arms:
            proj = os.path.join(work, arm)
            cmd = ["claude", "-p", PROMPT.format(scenario=row["scenario"]),
                   "--output-format", "stream-json", "--verbose",
                   "--allowedTools", "Read,Grep,Glob,Skill"]
            if arm != "without":
                cmd += ["--plugin-dir", plugin]
            if model:
                cmd += ["--model", model]
            log = os.path.join(proj, "scenario-%d.jsonl" % row["id"])
            try:
                proc = subprocess.run(cmd, cwd=proj, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                      stderr=subprocess.PIPE, timeout=timeout)
                text = proc.stdout.decode("utf-8", "replace")
            except subprocess.TimeoutExpired:
                text = ""
            with open(log, "w", encoding="utf-8") as fh:
                fh.write(text)
            info = parse_stream(text)
            results[(row["id"], arm)] = info
            if not info["finished"]:
                undecided = True
                out("Cannot tell: scenario %d / %s did not run to the end (check login, usage allowance, network; log = %s)"
                    % (row["id"], arm, log))
    out("")
    for arm in arms:
        states = set(results[(r["id"], arm)]["loaded"] for r in chosen)
        word = {True: "yes", False: "no", None: "no start record"}
        out("%-10s plugin skills listed at session start: %s" % (arm, " / ".join(sorted(word[s] for s in states))))
    for arm in arms:
        states = [results[(r["id"], arm)]["loaded"] for r in chosen]
        if arm == "without" and any(s is True for s in states):
            out("Control: the plugin is loaded in the arm without it. It is probably installed already, so this arm is not a control.")
            out("Uninstall it for the duration of this check, or run it with an empty CLAUDE_CONFIG_DIR that is logged in.")
            return 2
        if arm != "without" and any(s is False for s in states):
            out("Cannot tell: the plugin was not loaded in the arm %s (path given: %s)." % (arm, plugin))
            return 2
    if undecided:
        return 2
    try:
        ver = subprocess.run(["claude", "--version"], stdout=subprocess.PIPE, timeout=30).stdout.decode().strip()
    except Exception:
        ver = "?"
    out("Claude Code: %s" % ver)
    out("index = INDEX.md was opened / row = a category file was opened / skill = the plugin skill was invoked")
    out("outcome = the session's own last line (self-reported), compared with the expected exit of the roster")
    out("")
    for row in chosen:
        out("#%d  %s  [expected: %s]" % (row["id"], row["scenario"][:70], row["expected"]))
        for arm in arms:
            i = results[(row["id"], arm)]
            match = outcome_matches(i["outcome"], row["exit"])
            out("    %-10s index=%-3s row=%-3s skill=%-3s outcome=%-8s %s%s" % (
                arm, "yes" if i["index"] else "no", "yes" if i["category"] else "no",
                "yes" if i["skill"] else "no", i["outcome"] or "none",
                {True: "as expected", False: "NOT as expected", None: "not scored"}[match],
                "  (tried to write)" if i["wrote"] else ""))
    out("")
    total = len(chosen)
    counts = dict((arm, sum(1 for r in chosen if results[(r["id"], arm)]["index"])) for arm in arms)
    for arm in arms:
        out("%-10s INDEX.md opened in %d of %d scenarios" % (arm, counts[arm], total))
    loaded = [a for a in arms if a != "without"]
    if not loaded:
        out("Only the arm without the plugin was run. Nothing to judge.")
        return 2
    best = max(loaded, key=lambda a: counts[a])
    rc = 0
    if counts[best] == total:
        out("Consulted: with the plugin (%s) the index was opened in every scenario." % best)
    else:
        out("NOT consulted: with the plugin the index was opened in at most %d of %d scenarios." % (counts[best], total))
        rc = 1
    if "without" in arms and counts["without"] >= counts[best]:
        out("Note: the index was opened just as often without the plugin. On these scenarios the plugin adds nothing that this check can see.")
    if "with" in arms and "with-line" in arms and counts["with"] < counts["with-line"]:
        out("Note: the CLAUDE.md line was needed. The skill description alone did not bring the session to the index.")
    out("Logs are kept in %s." % work)
    return rc


# ---------- selftest ----------

GOOD_ROWS = """\
# Sample

> head note

{begin}
{end}

### ZZ01 — a row at strength A with a counter that was checked
- **Rule**: Do the thing, then report it in one line.
- **Decider**: agent
- **Strength**: A
- **Source**: owner decision 2026-01-05 (n=1)
- **Counter**: dies if the opposite holds -> it did not; two trials both failed the opposite way.

### ZZ02 — a row at strength B
- **Rule**: Do the thing.
- **Decider**: agent (reversible only)
- **Strength**: B
- **Source**: owner decision 2026-01-06 (n=1)

### ZZ03 — a light row at strength C
- **Rule**: Do the thing and say so in the report.
- **Decider**: agent (local copy) / owner (anything a running system reads)
- **Strength**: C
- **Derived from**: reversibility.

### ZZ04 — a pointer row
- **Rule**: Follow the always-on instruction.
- **Decider**: never
- **Strength**: P
- **Source**: `CLAUDE.md`
- **Pointer check**: the target exists and is loaded in every session.

```markdown
### a broken row inside a fence is an illustration
- **Rule**: consider
```
""".format(begin=TOC_BEGIN, end=TOC_END)

INDEX_OK = "# INDEX\n\n| category | file |\n|---|---|\n| sample | `01_sample.md` |\n"
SCEN_OK = ("# Scenarios\n\n| # | Scenario | Category | Expected exit |\n|---|---|---|---|\n"
           "| 1 | Something comes up | sample | proceed |\n| 2 | Something else | sample | **ask** (owner) |\n")


def _mk(tmp, rows=GOOD_ROWS, index=INDEX_OK, scen=SCEN_OK, fname="01_sample.md"):
    d = os.path.join(tmp, "judgment")
    os.makedirs(d)
    os.makedirs(os.path.join(tmp, ".git"))
    with open(os.path.join(tmp, "CLAUDE.md"), "w", encoding="utf-8") as fh:
        fh.write("# project\n")
    for name, content in ((fname, rows), ("INDEX.md", index), ("_scenarios.md", scen)):
        if content is not None:
            with open(os.path.join(d, name), "w", encoding="utf-8") as fh:
                fh.write(content)
    run_toc(d, write=True, out=lambda *_: None)
    return d


def run_selftest(out=print):
    state = {"ok": 0, "fail": 0}

    def report(good, label):
        state["ok" if good else "fail"] += 1
        out("  %s %s" % ("ok  " if good else "FAIL", label))

    def expect_form(label, old, new, needle):
        """Break the good sample in one place; the check has to name that problem."""
        assert old in GOOD_ROWS, label
        with tempfile.TemporaryDirectory() as tmp:
            d = _mk(tmp, rows=GOOD_ROWS.replace(old, new, 1))
            problems, _ = check_form(d)
            hit = [p for p in problems if needle in p]
            report(bool(hit), "%s -> %s" % (label, "caught" if hit else "MISSED (%r)" % problems))

    out("[1] row form: the good sample passes, each broken sample is caught")
    with tempfile.TemporaryDirectory() as tmp:
        d = _mk(tmp)
        problems, rows = check_form(d)
        report(not problems and rows == 4, "good sample: 4 rows, 0 problems (got %d rows, %r)" % (rows, problems))
        report(run_check(d, out=lambda *_: None) == 0, "good sample: check exits 0")
    A = "- **Counter**: dies if the opposite holds -> it did not; two trials both failed the opposite way.\n"
    expect_form("Rule missing", "- **Rule**: Do the thing, then report it in one line.\n", "", "no Rule")
    expect_form("Rule ends with \"consider\"", "Do the thing, then report it in one line.", "Depending on the case, consider.", "without a next move")
    expect_form("Rule ends with \"it depends\"", "Do the thing, then report it in one line.", "It depends.", "without a next move")
    expect_form("Decider missing", "- **Decider**: agent\n- **Strength**: A", "- **Strength**: A", "no Decider")
    expect_form("Decider outside the vocabulary", "- **Decider**: agent\n- **Strength**: A", "- **Decider**: probably agent\n- **Strength**: A", "not in the vocabulary")
    expect_form("one branch of the Decider outside the vocabulary", "agent (local copy) / owner (anything", "agent (local copy) / manager (anything", "not in the vocabulary")
    expect_form("Strength missing", "- **Strength**: B\n", "", "no Strength")
    expect_form("Strength not A/B/C/P", "- **Strength**: B\n", "- **Strength**: D\n", "is not one of")
    expect_form("Source missing at B", "- **Source**: owner decision 2026-01-06 (n=1)\n", "", "no Source")
    expect_form("neither Source nor Derived from at C", "- **Derived from**: reversibility.\n", "", "no Source and no Derived from")
    expect_form("A without Counter", A, "", "A without a Counter")
    expect_form("A whose Counter names no result", A, "- **Counter**: the canon holds it.\n", "names no result")
    expect_form("B with a bare agent", "- **Decider**: agent (reversible only)\n- **Strength**: B", "- **Decider**: agent\n- **Strength**: B", "Strength B with a bare")
    expect_form("C with a bare agent branch", "agent (local copy) / owner", "agent / owner", "Strength C with a bare")
    expect_form("P without Pointer check", "- **Pointer check**: the target exists and is loaded in every session.\n", "", "P without a Pointer check")
    expect_form("P that carries a Counter", "- **Pointer check**: the target", "- **Counter**: x -> y\n- **Pointer check**: the target", "P carries a Counter")
    expect_form("P whose target does not exist", "- **Source**: `CLAUDE.md`", "- **Source**: `docs/NOPE.md`", "was not found")
    expect_form("heading without an ID", "### ZZ02 — a row at strength B", "### a row at strength B", "heading has no ID")
    expect_form("ID used twice", "### ZZ02 —", "### ZZ01 —", "already used")
    expect_form("two prefixes in one file", "### ZZ02 —", "### YY02 —", "more than one ID prefix")
    with tempfile.TemporaryDirectory() as tmp:
        d = _mk(tmp, rows=GOOD_ROWS.replace("- **Source**: `CLAUDE.md`", "- **Source**: `.claude/rules/scoped.md`"))
        os.makedirs(os.path.join(tmp, ".claude", "rules"))
        rule = os.path.join(tmp, ".claude", "rules", "scoped.md")
        with open(rule, "w", encoding="utf-8") as fh:
            fh.write("---\npaths:\n  - \"src/**\"\n---\n# scoped\n")
        problems, _ = check_form(d)
        report(any("scoped with paths:" in p for p in problems), "P that points at a paths-scoped rule -> caught")
        with open(rule, "w", encoding="utf-8") as fh:
            fh.write("# always loaded\n")
        problems, _ = check_form(d)
        report(not problems, "P that points at an always-loaded rule -> passes")
    with tempfile.TemporaryDirectory() as tmp:
        d = _mk(tmp, rows=GOOD_ROWS.replace("### ZZ02 —", "### ZZ02 -"))
        problems, _ = check_form(d)
        report(not problems, "a plain hyphen in the heading is accepted")

    out("[2] table of contents")
    with tempfile.TemporaryDirectory() as tmp:
        d = _mk(tmp)
        path = os.path.join(d, "01_sample.md")
        report(run_toc(d, write=False, out=lambda *_: None), "generated table of contents passes --check")
        text = read(path)
        report("- ZZ03 | a light row at strength C | agent (local copy) / owner (anything a running system reads) | C" in text
               and text.count("\n- ZZ") == 4, "it lists the 4 rows with decider and strength, and not the fenced one")
        drift = text.replace("### ZZ02 — a row at strength B", "### ZZ02 — a row whose scene was renamed")
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(drift)
        report(not run_toc(d, write=False, out=lambda *_: None), "renamed scene without regenerating -> --check fails")
        report(run_check(d, out=lambda *_: None) == 1, "the same drift -> check exits 1")
        run_toc(d, write=True, out=lambda *_: None)
        report(run_toc(d, write=False, out=lambda *_: None), "after regenerating -> --check passes")
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(read(path) + "\n### ZZ05 — a row added by hand\n- **Rule**: Do it.\n- **Decider**: owner\n- **Strength**: C\n- **Derived from**: x\n")
        report(not run_toc(d, write=False, out=lambda *_: None), "row added without regenerating -> --check fails")
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(GOOD_ROWS.replace(TOC_BEGIN, "").replace(TOC_END, ""))
        report(not run_toc(d, write=False, out=lambda *_: None), "markers removed -> --check fails")
    with tempfile.TemporaryDirectory() as tmp:
        d = _mk(tmp, rows=GOOD_ROWS.replace("### ZZ02 — a row at strength B", "### a row at strength B"))
        report(not run_toc(d, write=False, out=lambda *_: None), "heading without an ID -> --check fails")

    out("[3] INDEX.md lists every category")
    with tempfile.TemporaryDirectory() as tmp:
        d = _mk(tmp)
        report(not check_index(d), "listed file exists -> passes")
        shutil.copyfile(os.path.join(d, "01_sample.md"), os.path.join(d, "02_other.md"))
        report(any("does not list 02_other.md" in p for p in check_index(d)), "category file that INDEX.md does not list -> caught")
    with tempfile.TemporaryDirectory() as tmp:
        d = _mk(tmp, index=INDEX_OK + "| later | `02_later.md` |\n")
        report(any("02_later.md, which does not exist" in p for p in check_index(d)), "listed file that does not exist -> caught")
    with tempfile.TemporaryDirectory() as tmp:
        d = _mk(tmp, index=INDEX_OK + "| later | `02_later.md` (not created) |\n")
        report(not check_index(d), "listed file marked (not created) -> passes")
    with tempfile.TemporaryDirectory() as tmp:
        d = _mk(tmp, index=None)
        report(any("INDEX.md was not found" in p for p in check_index(d)), "no INDEX.md -> caught")

    out("[4] scenario roster")
    with tempfile.TemporaryDirectory() as tmp:
        d = _mk(tmp)
        rows = load_scenarios(d)
        report(len(rows) == 2 and rows[1]["exit"] == "ask" and not check_scenarios(d), "good roster: 2 scenarios, 0 problems")
    for label, old, new, needle in (
            ("expected exit outside the vocabulary", "| proceed |", "| maybe |", "not in the vocabulary"),
            ("category with no file", "| Something comes up | sample |", "| Something comes up | nowhere |", "has no file"),
            ("number used twice", "| 2 | Something else", "| 1 | Something else", "used twice")):
        with tempfile.TemporaryDirectory() as tmp:
            d = _mk(tmp, scen=SCEN_OK.replace(old, new))
            report(any(needle in p for p in check_scenarios(d)), "%s -> caught" % label)

    out("[5] reading a session transcript (synthetic records, not a real session)")

    def rec(name, inp):
        return json.dumps({"type": "assistant", "message": {"content": [{"type": "tool_use", "name": name, "input": inp}]}})

    done = json.dumps({"type": "result", "is_error": False, "result": "I would fix it.\nOUTCOME: proceed"})
    i = parse_stream("\n".join([rec("Read", {"file_path": "/w/judgment/INDEX.md"}),
                                rec("Read", {"file_path": "/w/judgment/01_choose.md", "limit": 40}), done]))
    report(i["finished"] and i["index"] and i["category"] and not i["skill"] and i["outcome"] == "proceed",
           "INDEX.md and a category file were read -> index=yes row=yes outcome=proceed")
    i = parse_stream("\n".join([rec("Read", {"file_path": "/w/README.md"}), rec("Grep", {"pattern": "INDEX", "path": "/w/src"}), done]))
    report(i["finished"] and not i["index"] and not i["category"], "other files were read -> index=no row=no")
    i = parse_stream("\n".join([rec("Skill", {"skill": "judgment-index:consult"}), rec("Write", {"file_path": "/w/x"}), done]))
    report(i["skill"] and i["wrote"] and not i["index"], "the skill was invoked without opening the index -> skill=yes index=no, write attempt recorded")
    i = parse_stream(rec("Read", {"file_path": "/w/judgment/INDEX.md"}))
    report(not i["finished"], "no result record -> not finished")
    i = parse_stream(json.dumps({"type": "result", "is_error": True, "result": "Not logged in"}))
    report(not i["finished"], "result record with an error -> not finished")
    i = parse_stream(json.dumps({"type": "result", "is_error": False, "result": "Should I go ahead?"}))
    report(i["finished"] and i["outcome"] is None, "no OUTCOME line -> outcome is none, not guessed")
    init = lambda skills: json.dumps({"type": "system", "subtype": "init", "skills": skills, "slash_commands": skills})
    report(parse_stream(init(["judgment-index:consult", "other:x"]))["loaded"] is True
           and parse_stream(init(["other:x"]))["loaded"] is False
           and parse_stream(done)["loaded"] is None,
           "start record: plugin skills listed -> loaded / not listed -> not loaded / no start record -> unknown")
    report(outcome_matches("proceed", "check then proceed") is True and outcome_matches("ask", "proceed") is False
           and outcome_matches(None, "ask") is None, "outcome scoring: proceed family / mismatch / not scored")

    out("[6] where the index lives")
    with tempfile.TemporaryDirectory() as tmp:
        tmp = os.path.realpath(tmp)
        os.makedirs(os.path.join(tmp, ".git"))
        os.makedirs(os.path.join(tmp, "src", "deep"))
        empty = os.path.join(tmp, "elsewhere")
        os.makedirs(empty)
        got = resolve_dir(cwd=os.path.join(tmp, "src", "deep"), here=empty, env={})
        report(got == os.path.join(tmp, "judgment"), "default: <project root>/judgment, found from a subfolder")
        with open(os.path.join(tmp, POINTER_FILE), "w", encoding="utf-8") as fh:
            fh.write("# comment\ndocs/judgment\n")
        got = resolve_dir(cwd=os.path.join(tmp, "src"), here=empty, env={})
        report(got == os.path.join(tmp, "docs/judgment"), "%s is honored" % POINTER_FILE)
        got = resolve_dir(cwd=tmp, here=empty, env={"JUDGMENT_INDEX_DIR": os.path.join(tmp, "e")})
        report(got == os.path.join(tmp, "e"), "the environment variable wins over the file")
        got = resolve_dir(arg=os.path.join(tmp, "a"), cwd=tmp, here=empty, env={"JUDGMENT_INDEX_DIR": "x"})
        report(got == os.path.join(tmp, "a"), "--dir wins over both")

    out("[7] the shipped template")
    src = template_dir()
    if not src:
        out("  skip (this copy sits inside an index, without the template)")
    else:
        with tempfile.TemporaryDirectory() as tmp:
            os.makedirs(os.path.join(tmp, ".git"))
            d = os.path.join(tmp, "judgment")
            report(run_init(d, out=lambda *_: None, cwd=tmp) == 0, "init into an empty project -> check exits 0")
            files = category_files(d)
            per = [len(parse_rows(read(p))) for p in files]
            report(len(files) == 15 and min(per) >= 1 and max(per) <= 2,
                   "15 category files, each with 1 or 2 sample rows (got %d files, %s)" % (len(files), per))
            names = [category_name(p) for p in files]
            report(all(re.match(r"^[a-z]+(-[a-z]+)?$", n) for n in names), "category names are lowercase English words")
            report(len(load_scenarios(d)) >= 5, "the sample roster has at least 5 scenarios")
            before = read(os.path.join(d, "INDEX.md"))
            with open(os.path.join(d, "01_choose.md"), "a", encoding="utf-8") as fh:
                fh.write("\nmy own note\n")
            run_init(d, out=lambda *_: None, cwd=tmp)
            report("my own note" in read(os.path.join(d, "01_choose.md")) and read(os.path.join(d, "INDEX.md")) == before,
                   "a second init does not overwrite an edited file")
            report(os.path.isfile(os.path.join(d, TOOL_COPY)) and not os.path.exists(os.path.join(tmp, POINTER_FILE)),
                   "the tool is copied into the index; no pointer file at the default place")
        for marker in (".git", None):
            kind = "a git project" if marker else "a project without .git"
            with tempfile.TemporaryDirectory() as tmp:
                if marker:
                    os.makedirs(os.path.join(tmp, marker))
                d = os.path.join(tmp, "docs", "judgment")
                lines = []
                run_init(d, out=lambda *a: lines.append(" ".join(a)), cwd=tmp)
                report(read_pointer(tmp) == "docs/judgment", "init at another place in %s records it in %s" % (kind, POINTER_FILE))
                report(any("`docs/judgment/INDEX.md`" in ln for ln in lines), "the CLAUDE.md line it prints names that place (%s)" % kind)
                env = {"PATH": os.environ.get("PATH", "")}
                proc = subprocess.run([sys.executable, os.path.abspath(__file__), "check"], cwd=tmp,
                                      stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=env)
                report(proc.returncode == 0, "the tool in the plugin finds the index through %s (%s, exit %d)" % (POINTER_FILE, kind, proc.returncode))
                proc = subprocess.run([sys.executable, os.path.join(d, TOOL_COPY), "check"], cwd=tmp,
                                      stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=env)
                report(proc.returncode == 0, "the copied tool checks its own folder (%s, exit %d)" % (kind, proc.returncode))

    out("")
    out("selftest: ok %d / FAIL %d" % (state["ok"], state["fail"]))
    return 0 if state["fail"] == 0 else 1


# ---------- command line ----------

def main(argv=None):
    ap = argparse.ArgumentParser(prog="judgment.py", description="Tool for the index of judgment criteria.")
    ap.add_argument("--version", action="version", version=TOOL_VERSION)
    sub = ap.add_subparsers(dest="cmd")

    def with_dir(p):
        p.add_argument("--dir", help="index folder (default: see the top of this file)")
        return p

    with_dir(sub.add_parser("init", help="unpack the empty index"))
    p = with_dir(sub.add_parser("toc", help="regenerate the tables of contents"))
    p.add_argument("--check", action="store_true", help="do not write; exit 1 on a mismatch")
    with_dir(sub.add_parser("check", help="row form, tables of contents, INDEX.md listing, scenario roster"))
    with_dir(sub.add_parser("scenarios", help="list the scenario roster"))
    p = with_dir(sub.add_parser("measure", help="send scenarios to real Claude Code sessions"))
    p.add_argument("--ids", default="", help="scenario numbers, comma separated")
    p.add_argument("--n", type=int, default=3, help="how many scenarios from the top of the roster (default 3)")
    p.add_argument("--arms", default=",".join(ARMS), help="comma separated, from: " + ", ".join(ARMS))
    p.add_argument("--plugin-dir", help="path to plugins/judgment-index (default: the plugin this file sits in)")
    p.add_argument("--model", help="pin the model")
    p.add_argument("--timeout", type=int, default=240, help="seconds per call (default 240)")
    sub.add_parser("selftest", help="check the checks")
    args = ap.parse_args(argv)

    if args.cmd == "selftest":
        return run_selftest()
    if not args.cmd:
        ap.print_help()
        return 2
    index_dir = resolve_dir(args.dir)
    if args.cmd == "init":
        return run_init(index_dir)
    if not os.path.isdir(index_dir):
        print("No index at %s. Run init first." % index_dir)
        return 2
    if args.cmd == "toc":
        return 0 if run_toc(index_dir, write=not args.check) else 1
    if args.cmd == "check":
        return run_check(index_dir)
    if args.cmd == "scenarios":
        problems = check_scenarios(index_dir)
        for row in load_scenarios(index_dir):
            print("#%-3d %-10s %-20s %s" % (row["id"], row["category"], row["expected"], row["scenario"]))
        for p in problems:
            print("  FAIL %s" % p)
        return 1 if problems else 0
    if args.cmd == "measure":
        arms = [a.strip() for a in args.arms.split(",") if a.strip()]
        unknown = [a for a in arms if a not in ARMS]
        if unknown or not arms:
            print("Unknown arm: %s (choose from %s)" % (", ".join(unknown) or "none given", ", ".join(ARMS)))
            return 2
        ids = [int(x) for x in args.ids.split(",") if x.strip().isdigit()]
        return run_measure(index_dir, ids, args.n, arms, args.plugin_dir, args.model, args.timeout)
    return 2


if __name__ == "__main__":
    sys.exit(main())
