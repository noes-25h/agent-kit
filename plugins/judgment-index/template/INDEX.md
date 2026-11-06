# Judgment index — pick a category, read its head, take out one row

> **How to use it, in three lines.** (1) Pick a **category** from the lookup table below. (2) Read only the **head** of that category file: the note and the table of contents, about the first 40 lines. (3) Take out the **one row** whose scene matches, by its ID (from `### <ID>` to the next `###`).
> **A row exists: follow it. No row exists: add one by the steps below and continue.** Ask only when one of the three reasons to stop holds.
> One judgment costs this file, one head, and one row. A category that grows thick does not make a lookup more expensive.

The subject of every row is this project, not a person. A row says "here we do this", and names who decides.

## Lookup — from the words you heard, or from your own doubt

Come here at the moment you are about to ask "may I" or "should I". A category is a verb: what the agent is about to do.

| What was said, or what you are unsure about | Category | File |
|---|---|---|
| Which one / several routes, tools, or places would work | choose | `01_choose.md` |
| What price / what name / what to promise / where the line is | set | `02_set.md` |
| May this go out / may this be sent / schedule, correct, withdraw | publish | `03_publish.md` |
| Production, credentials, deletion, history, a delivery path / just before a destructive step | touch-live | `04_touch-live.md` |
| Denied / no permission, no login / a limit was hit | unblock | `05_unblock.md` |
| Record, decision, instruction, and actual state disagree | reconcile | `06_reconcile.md` |
| A first-time format, channel, or jurisdiction / installing a tool | adopt | `07_adopt.md` |
| Adding or changing a rule, hook, skill, or metric | build | `08_build.md` |
| May this be bought / a renewal / an expense | spend | `09_spend.md` |
| Another person is involved / asking, declining, replying | respond | `10_respond.md` |
| Broken, down, a false alarm / a supply is about to run out | repair | `11_repair.md` |
| How to go on / fear of rework / whether to escalate / now or later | assess | `12_assess.md` |
| "This" or "that" has two possible targets / a short instruction is unclear | interpret | `13_interpret.md` |
| Can this be called done / can a zero be trusted / is it really running | verify | `14_verify.md` |
| Which model / how many agents / context / parallel writers | allocate | `15_allocate.md` |

**When a scene fits two categories, the less reversible one wins.** `publish` and `touch-live` come before the others.

A category file that exists is not a category that is filled. When the scene you are looking for is not in the table of contents, add its first row by the steps below.

## The three reasons to stop

Ask a person only when one of these holds.

1. **It cannot be touched mechanically.** A login, a one-time code, a guard such as a hook or a permission rule.
2. **It cannot be undone.** Deletion, money, publishing, sending, anything that reaches many people.
3. **A record says the owner decides it.** Name the record when you ask.

Everything else: decide, act, report. When you do ask, finish the research first and ask one closed question with one recommendation.

## One row

```markdown
### <ID> — <scene: when it arrives>

- **Rule**: what to do next (reading this line alone has to be enough to act)
- **Decider**: agent / agent (reversible only) / owner / hands / never
- **Strength**: A / B / C / P
- **Source**: where the rule comes from, with a date (n = number of independent instances)
- **Counter**: what would kill this rule -> what was checked, and what came out
```

The ID is two capital letters for the category and a running number. It never changes; it is the name used in reports and the anchor used to take the row out.

**Decider** has five words. A scene that splits is written as branches, `agent (X) / owner (Y)`, closed so that no case is left outside.

| Word | Meaning |
|---|---|
| `agent` | The agent decides and acts. |
| `agent (reversible only)` | The agent decides and acts as long as the step can be undone. |
| `owner` | The decision is handed to the owner. It may pass. |
| `hands` | The agent decides; a person performs one manual step. This is not a question. |
| `never` | The agent does not do it, even with approval. |

**Strength** says how far the row can be trusted.

| Strength | Meaning | What it allows |
|---|---|---|
| **A** | The source is a specification, a statute, a measurement, or a decision of the owner; the object matches; the counter was actually checked. `Counter` is required and names the result after `->`. | `agent` |
| **B** | The source is real, but the counter is unchecked, the object is only adjacent, or there is one instance. | `agent (reversible only)` |
| **C** | Derived by the agent from the project's principles and earlier decisions. Provisional. `Derived from` may stand in place of `Source`. | Reversible and small only. Say in the report that a provisional row was used. |
| **P** | A pointer. The rule already lives in an instruction that is loaded in every session (`CLAUDE.md`, an always-on rule). The row only leads there. It has `Pointer check` and no `Counter`. | Whatever the target allows. |

A provisional row (C) has four limits: it is not used for anything that cannot be undone; it is written down in the same turn in which it was derived; its use is named in the report; and when the owner confirms it, the date goes into `Source` and the strength goes up.

## Adding a row — seven steps, in this order

| # | Step | Where it goes wrong |
|---|---|---|
| 1 | **Name the scene by its trigger**: when does it arrive. Not "about X". | An abstract name cannot be found later. |
| 2 | **Look up what the owner already decided.** The places are listed under "Where decisions live" below. | A search hit is a candidate. Open it before using it. |
| 3 | **Take the functional answer** when one exists: an official specification, the behavior of an API, the text of a law, your own measurement. | When one right answer exists, the row can reach A without waiting for the owner. Point to a value; do not copy it. |
| 4 | **When no single right answer exists, look at common practice.** | What enters here is C. Practice is a candidate, not a reason. |
| 5 | **Pass the gate**: can it be undone, how far does it reach, does one of the three reasons to stop hold. | When it fails the gate, the Decider is `owner`. |
| 6 | **Name one counter and actually check it.** | An easy counter does not count. With no checked counter the row is not A. |
| 7 | **Write the row** with its Decider and Strength, then run the `toc` command. | A row without a table-of-contents line is never taken out. |

**The short path for C**: steps 1, 2 (one lookup, to see that nothing on record contradicts it), and 5. Write `Derived from` and continue. The counter is checked when the row is promoted.

Two independent sources that reach the same conclusion raise the strength by one step. Two sources with the same upstream are one source.

## Where decisions live

Edit this list to match the project. Step 2 searches these places.

- `CLAUDE.md` and the files it imports
- The commit history (`git log`)
- (add the folder or file where decisions are recorded, if there is one)

## When two rows conflict

Apply in this order and stop at the first that decides: the most recent decision of the owner; the larger `n`; the higher strength; the stronger kind of source (specification, statute, measurement, or owner decision, then common practice). Do not score. Before any of this, check that the two rows talk about the same object.

## Writing rows

- Write the rule out. Do not replace it with a pointer. Two exceptions: values (numbers, prices, thresholds live where they are measured) and instructions that are already loaded in every session (strength P).
- No history in a row. Present tense only. The source carries the trail.
- "Consider" is not a rule. When the next move cannot be written, leave the row out.
- Do not create a category file that has no row. Mark its line in the lookup table `(not created)`.

## Checks

```bash
python3 judgment/_judgment.py toc      # regenerate the tables of contents after writing a row
python3 judgment/_judgment.py check    # row form, tables of contents, this file's listing, scenario roster
```

`_scenarios.md` is a roster of scenes in which an agent tends to ask. `_inbox.md` holds scenes that were asked and are not rows yet.
