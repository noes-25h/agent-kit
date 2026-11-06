---
name: consult
description: Use before asking the user "may I", "should I", or "which one", and whenever you hesitate between acting and asking. Looks the scene up in the judgment index kept in the repository (INDEX.md, then the head of one category file, then one row) and acts on that row. When no row matches, adds one provisional row by a fixed procedure and continues. Do not use it to decide how to implement something once the decision is made.
---

# Consult the judgment index

You are about to ask a person whether you may or should do something, or you are unsure whether to act. Look the scene up first. Ask only when the index, or one of the three reasons to stop, says so.

## 1. Find the index

The index is a folder in the repository. Its place, first match wins:

1. the path on the first line of `.judgment-index` at the project root, when that file exists
2. `judgment/` at the project root

When the folder has no `INDEX.md`, the index is not set up. Say so in one line, give this command, and go on with the task using the three reasons to stop in section 4:

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/judgment.py" init
```

## 2. Read three things, and nothing else

1. `INDEX.md`. Pick one category from the lookup table. When the scene fits two, the less reversible category wins.
2. The head of that category file: read about the first 40 lines (the note and the table of contents). Do not read the whole file.
3. The one row whose scene matches. Find its ID in the table of contents and read from `### <ID>` to the next `###`.

Do not read other category files "to be safe". The index is built so that one judgment costs one head and one row.

## 3. A row matches

Do what `Rule` says. `Decider` tells you who decides:

| Decider | What you do |
|---|---|
| `agent` | Decide, act, report. |
| `agent (reversible only)` | Decide and act when the step can be undone. When it cannot, treat it as `owner`. |
| `owner` | Hand the decision over: one closed question, one recommendation, research finished first. |
| `hands` | Keep the decision. Ask a person for the one manual step, in one line. |
| `never` | Do not do it, and do not ask for approval to do it. Report what you did not do. |

`Strength` tells you how far the row carries:

- **A**: follow it.
- **B**: follow it for steps that can be undone.
- **C**: provisional. Follow it only when the step can be undone and its reach is small, and say in your report that you acted on a provisional row, with its ID.
- **P**: the rule lives in an instruction that is already in your context. Follow that instruction.

Name the row ID in your report, for example "followed PB01". That is how the owner sees which rows are in use.

## 4. No row matches

Do not ask just because the row is missing. First test the three reasons to stop:

1. It cannot be touched mechanically (a login, a one-time code, a hook or permission rule).
2. It cannot be undone (deletion, money, publishing, sending, anything that reaches many people).
3. A record says the owner decides it.

**One of them holds.** Ask: one closed question with one recommendation. Then append one line to `_inbox.md` in the index folder, in the form that file shows, so that the answer can become a row later.

**None holds.** Add a provisional row and continue:

1. Name the scene by its trigger: when does it arrive.
2. Look once in the places listed under "Where decisions live" in `INDEX.md`, to see that nothing on record contradicts what you are about to write. Open a hit before you rely on it.
3. Write the row at the end of the category file, with the next free ID of that file:

```markdown
### <ID> — <scene: when it arrives>

- **Rule**: <what to do next>
- **Decider**: agent (reversible only)
- **Strength**: C
- **Derived from**: <the principle or earlier decision it follows from>
```

4. Regenerate the tables of contents and check the form. Use the path of the index folder:

```bash
python3 <index folder>/_judgment.py toc
python3 <index folder>/_judgment.py check
```

5. Act on the row, and say in your report: "added provisional row <ID> and acted on it".

When you cannot write files in this context (a read-only agent, or another writer is active in the same working tree), append the row as one line to `_inbox.md` instead, or include it in your report, and continue.

## Limits

- Never write a row at strength A or B in this skill. A needs a checked counter, and both need a real source. Promotion happens when the owner has confirmed the row; the `capture` skill does that.
- Never use a provisional row for a step that cannot be undone.
- "Consider" is not a rule. When you cannot write the next move, do not write the row.
- A row is a criterion, not a log. Write it in the present tense, without the story of how it came up.
