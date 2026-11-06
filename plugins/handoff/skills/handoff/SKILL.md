---
name: handoff
description: "Use when a session is ending with work left over and the next session will start with none of this context. Sorts each leftover item into one of three exits: an instruction sheet with stop conditions that a command can confirm, a standalone prompt for a small one-off, or a note that names what is still undecided. Every instruction sheet starts with a re-check of the facts it was written on. Writes the handoff; does not do the remaining work. Not for a session diary, and not for choosing what to work on next."
argument-hint: "[what to hand off] [--plans-dir <dir>] [--tasks-file <path>]"
model: inherit
effort: medium
---

# handoff

Arguments: $ARGUMENTS

A handoff goes stale. What was true when it was written may be false when it is run. So this skill does not produce a to-do list. It produces an agreement to execute, with a way to check its own premises first.

## When to use

- The session is about to end and something is unfinished.
- Work came up during the session that was not started.
- The next session, or another person, has to continue without this conversation.

## When not to use

- Recording what happened in the session. That is a diary, and it has a different reader.
- Choosing which task to start next.
- Items the next session can pick up from the project's own task list without this conversation. Leave those where they are.

## Settings

Two places are needed. Each is decided in this order.

Where instruction sheets go:

1. `--plans-dir <dir>` in the arguments.
2. The `plans_dir` key in `.claude/handoff.json` at the project root.
3. Neither is present: `docs/handoff/`.

Where notes about undecided items go:

1. `--tasks-file <path>` in the arguments.
2. The `tasks_file` key in `.claude/handoff.json`.
3. Neither is present: do not create a file. Put the notes in the reply.

Example `.claude/handoff.json`: `{"plans_dir": "docs/handoff", "tasks_file": "TODO.md"}`.

This skill writes instruction sheets and notes. It does not edit anything else and does not carry out the remaining work.

## Step 1. Collect what is left

- Work that was started in this session and is not finished. Go back through the conversation.
- Work that came up in this session and was not started.
- Entries in the project's task list that cannot be done without what was learned in this session.

Take only what would be lost with this conversation. If the next session could find an item and do it with no help, it does not belong in the handoff.

## Step 2. Sort each item into one of three exits

Test each item from the top. It goes to the first exit whose conditions it meets in full.

| Exit | Conditions (all of them) | Form |
|---|---|---|
| A. Instruction sheet | Completion can be confirmed by a machine: the output of a command, an HTTP response, the content of a file. The work can be cut into steps. No human decision is needed on the way. | A file in the plans directory |
| B. Standalone prompt | It can be read with no context. It is a single action that needs no steps. It involves nothing irreversible, no payment, and nothing published. | A prompt in the reply, ready to paste into a new session |
| C. Note only | Neither of the above: a decision is needed, the premises are not settled, or it depends on timing. | An entry in the tasks file, or in the reply |

When in doubt, choose C. A half-specified instruction sheet makes whoever runs it decide things that were never decided, and that costs the most.

If the stop condition for an A item cannot be written as a command and its expected output, the design is not finished. Do not force a sheet. Send the item to C and write in one line what is not decided.

## Step 3A. Write the instruction sheet

File name: `<plans dir>/<YYYY-MM-DD>_<slug>-plan.md`. Take the date from the system clock. Use this structure.

````markdown
# <subject>: <what this run does>

Written: <YYYY-MM-DD>. Review section 0 with extra care after <YYYY-MM-DD, about seven days later>.
Where the decisions behind this sheet came from: <commit, issue, document, or "the session of <date>">.
This run holds only what is decided and can be confirmed by a machine.

## 0. Re-check at start

Run every row before doing anything else. This sheet was written on these facts. If even one of them no longer holds, stop and report.

| # | Premise | How to confirm (a command, or a measurement) |
|---|---|---|
| 1 | <a fact the steps depend on> | `<command>` and the output that is expected |

If a premise fails: do not decide how to repair it. Write what changed and which parts of this sheet it makes invalid, then stop.

## Stop conditions

1. `<command>` gives `<expected output>`.

## Step 1: <name of a step that can be done in one go>

Why: <only what would change a decision during execution>

- <what to do>

Negative test: <run the check against the state before the change and see it fail>

## Not in this run

| What | Why |
|---|---|
| <what was left out> | <not decided / belongs to another run / needs a person> |

## Allowed and forbidden paths

- Allowed: <paths>
- Forbidden: <paths>

## When to halt

- Three attempts at the same step without meeting its condition: stop and report what is blocking.
- A decision turns out to be needed: do not make it. Add a note to the tasks file and go on to the next step.
- Hard stop: the last step is done, or <N> hours have passed, whichever comes first.

## When finished

<where to record the result, and what to commit>
````

Then give the user one line that starts the run, and leave the starting to them:

```
/goal Every stop condition in <path to the sheet> holds, confirmed by running the commands written there.
```

Writing the sheet is where this skill ends. Starting the run is the user's action.

## Step 3B. Write a standalone prompt

Put the prompt in the reply inside a code block. It must make sense to a session that has seen nothing else. Its first sentence is always a re-check:

> Before starting, confirm that <premise>. If it does not hold, do not carry out the task; report what you found instead.

## Step 3C. Leave a note

Write the entry in the tasks file, or in the reply when there is no tasks file. The first sentence names what is not decided. A single named open question helps the next session more than a list of things to do.

## Step 4. Present on one page

| Exit | Count | Content |
|---|---|---|
| Instruction sheet | N | the `/goal` line for each sheet |
| Standalone prompt | N | title of each prompt |
| Note | N | the undecided point of each note |

## Rules

- An instruction sheet has stop conditions, halting conditions, and a way to confirm its premises. If any of the three is missing, whoever runs it has to guess.
- Do not put an item in exit A when its completion cannot be confirmed by a machine. "Improve" and "tidy up" are not stop conditions.
- Do not leave out section 0. Counts, free slots, version numbers, and the results of other sessions drift between writing and running. The drift that nobody notices costs the most.
- When a premise has failed, whoever runs the sheet does not choose the repair. Stopping and reporting is correct. A repair is a new decision and is outside the handoff.
- Do not do the remaining work while writing the handoff.
