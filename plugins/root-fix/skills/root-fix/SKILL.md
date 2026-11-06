---
name: root-fix
description: "Use when the same mistake has come back two or more times, or when a fix was applied to a symptom and the cause is still unknown. Traces the symptom to its source, narrows several symptoms to one point, sweeps the repository for siblings of the same defect, fixes the source, and adds a check that would catch the next occurrence. Diagnosis only by default; edits only with --apply. Not for a one-off bug with an obvious cause, and not for designing something new."
argument-hint: "[symptom, or file:line, or path to an incident log] [--apply] [--record <path>]"
model: inherit
effort: high
---

# root-fix

Arguments: $ARGUMENTS

A mistake that comes back was fixed at the wrong place. This skill finds the place that produces the mistake, fixes that one place, and leaves behind a check. It does not patch each symptom separately.

## When to use

- The same correction has been made two or more times.
- A bug was fixed and nobody asked what wrote the bad value in the first place.
- Several defects look related and each one is about to get its own patch.

## When not to use

- A one-off bug whose cause is already known. Fix it directly. Running every stage on it is wasted work.
- Designing a new feature.
- Finding defects without fixing anything. Use a linter or a review for that.

## Settings

The skill writes at most one thing outside the fix itself: a record of what the source was. Where the record goes is decided in this order.

1. `--record <path>` in the arguments.
2. The `record` key in `.claude/root-fix.json` at the project root, for example `{"record": "docs/root-causes.md"}`.
3. Neither is present: do not create a file. Put the record entry in the reply.

Without `--apply`, run Stage 0 through Stage 3 and stop. Do not edit, create, or delete any file. With `--apply`, continue through Stage 5.

## Stage 0. Verify each symptom against the actual text

Before tracing anything, open the file, log line, or output behind every reported symptom and confirm that it says what the report says.

- A hit from a search or a detector is a candidate, not a fact. Read the surrounding lines.
- A statement in an incident log ("fixed in the template") is a claim. Check the file it names.
- If a symptom turns out to be false, say so and drop it. Do not fix a symptom that is not there.

## Stage 1. Trace to the source

For each verified symptom, walk backwards: the bad value, then what wrote it, then what generated the writer, then the structure that allowed it.

- At each step, decide whether this is a single slip or a standing source. A standing source produces the defect again without anyone making a new mistake.
- Common standing sources: a generator or template that disagrees with the file it is meant to match; a copy of a value kept in two places; a document that was changed while the code that implements it was not; a step that depends on a person remembering to do it.
- Do not stop at the first cause that sounds plausible. Confirm each step in the actual files before moving to the next one.

## Stage 2. Narrow to one point

Put the symptoms side by side and ask: is there a single generator, script, template, or structure that, once corrected, makes all of them disappear?

- If yes, name it with a file path and, where possible, a line.
- If each symptom still needs its own fix, the trace in Stage 1 was too shallow. Go back.
- Before accepting the point, question the instrument: is the thing that reported the symptoms itself correct?

## Stage 3. Sweep for siblings

The source has probably produced the same defect in places that nobody has reported yet.

- Build the full set from the structure, not from memory: list every file the source writes to and every place the pattern can occur, using the file tree and search.
- Search with several phrasings of the defect, not one.
- For every member of the set, state one of: has the defect, does not have it, or excluded. Give the reason for each exclusion. "Looked at and excluded" and "never looked at" must be distinguishable in the report.

Without `--apply`, stop here and give the report.

## Stage 4. Fix the source and make recurrence visible

Only with `--apply`. Three layers, in this order.

1. Fix. Correct the source named in Stage 2. Correct the siblings from Stage 3 by running the corrected source again where that is possible, and by hand only where it is not.
2. Wire. If staying correct depends on a step that someone must remember, make that step happen as part of something that already runs, such as a build step or a script that is already called.
3. Check. Add one check that compares the expected state with the actual state and fails when they differ: a test, a script, or a CI step. Run the check against the state before the fix, or against a deliberately broken copy, and confirm that it fails there. A check that cannot fail is not a check.

Do not add a rule to a document as a substitute for layer 2 or layer 3.

## Stage 5. Check what the fix itself touches

List what reads or depends on each file changed in Stage 4. Run the existing tests of the project and the new check. Report anything that changed behaviour outside the defect.

## Record

One entry, in the place decided under Settings.

```
## <date> <short name of the defect>
- Symptoms: <the verified ones, with paths>
- Source: <path, and why it is a standing source>
- Fix: <what changed at the source>
- Check: <the command that fails if the defect comes back>
- Not done: <what was left, and why>
```

## Report format

End every run with these headings, in this order. Write "none" under a heading that has nothing.

```
### Symptoms verified
### Symptoms dropped
### Source
### Single point
### Siblings
### Excluded, with reasons
### Proposed fix
### Recurrence check
### Not done
```

With `--apply`, the seventh heading is "Fix applied". Under "Recurrence check", give the command and say whether it was seen to fail on the broken state.

## Do not

- Treat a search hit or a log entry as fact without opening the file.
- Correct the symptom data by hand and stop.
- Patch each symptom separately when no single point was found.
- Skip the sweep. The unreported siblings are the ones that come back.
- Stop after the fix with no check.
- Edit anything without `--apply`.
- Claim that the mistake will not happen again. Report what was changed and what the check covers.
