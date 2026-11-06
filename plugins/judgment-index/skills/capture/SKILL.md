---
name: capture
description: Use after the user has answered a "may I" or "should I" question, after the user corrected a judgment call you made, at the end of a session in which you asked for decisions, or when the user asks to review what was asked. Turns each scene that was asked into one row of the judgment index kept in the repository, so that the same question is not asked again, and promotes provisional rows that the user has confirmed.
---

# Capture asked scenes as rows

A question that was asked and answered leaves a decision in the conversation and nothing in the repository. This skill moves it into the judgment index as one row.

## 1. Find the index

The index folder is the path on the first line of `.judgment-index` at the project root when that file exists, and `judgment/` at the project root otherwise. When it has no `INDEX.md`, say so, give this command, and stop:

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/judgment.py" init
```

Read `INDEX.md` once: the lookup table, the row format, and the seven steps.

## 2. Collect the scenes

Gather from two places:

- **This conversation.** Every point where you asked the user for a decision, every point where the user asked you "why did you ask" or "why did you not ask", and every correction of a judgment call ("do not do that without asking", "you do not need to ask for that").
- **`_inbox.md`** in the index folder: the lines under "Waiting".

List them before writing anything: one line per scene, with the answer that was given, or "open" when there was none. A scene with no answer stays in `_inbox.md`.

Leave these out:

- A one-time choice that will not come back (which of two file names, this once).
- Anything that holds a secret, or a personal matter of a person.
- An answer about how to implement something. The index holds whether and who, not how.

## 3. For each scene

1. **Name it by its trigger**: when does it arrive. Not "about X".
2. **Pick the category** from the lookup table. When it fits two, the less reversible one wins.
3. **Read the head of that category file** and look for a row with the same scene.
   - A row exists and agrees: add the date to its `Source` and raise `n` by one. When it was strength C and the user has now confirmed it, replace `Derived from` with `Source: owner decision <date> (n=1)` and set the strength to B.
   - A row exists and disagrees: the most recent decision of the owner wins. Rewrite the rule, and put the new date in `Source`.
   - No row: write one at the end of the file with the next free ID.
4. **Set Decider and Strength from what actually happened**, not from what would be convenient:
   - The user said "do not ask for this again": `agent`, or `agent (reversible only)` when the step can be undone.
   - The user said "always ask": `owner`.
   - The user said "do not do this at all": `never`.
   - The user had to perform a manual step: `hands`.
   - One answer from the owner is one instance. That is strength **B**. Write **A** only when you have named a counter and actually checked it in this session; put what you checked and what came out after `->` in `Counter`.
5. **Write the rule so that it can be acted on** by a session that has never seen this conversation. Present tense. No story.

```markdown
### <ID> — <scene: when it arrives>

- **Rule**: <what to do next>
- **Decider**: <one of the five words, or closed branches>
- **Strength**: B
- **Source**: owner decision <YYYY-MM-DD> (n=1)
```

## 4. Close

1. Delete from `_inbox.md` the lines that are now rows. Leave the open ones.
2. Regenerate the tables of contents and check the form:

```bash
python3 <index folder>/_judgment.py toc
python3 <index folder>/_judgment.py check
```

3. Fix whatever `check` reports, and run it again until it exits 0.
4. Report in a short list: rows added (ID and scene), rows promoted, scenes left open in `_inbox.md`. Do not commit unless the user asked for it.

## Limits

- Do not turn your own guess about what the user would say into a row with an owner source. A guess is strength C with `Derived from`.
- Do not copy a rule that is already in `CLAUDE.md` or an always-on rule file. Write a pointer row (strength P) or nothing.
- When another session is writing in the same working tree, append to `_inbox.md` only and leave the category files alone.
