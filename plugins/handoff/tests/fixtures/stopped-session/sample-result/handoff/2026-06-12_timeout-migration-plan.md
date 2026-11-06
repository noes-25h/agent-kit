# Service configs: move orders and search to timeout_ms

This file was written by hand. It is not output from Claude Code.
selftest.sh uses it to confirm that the patterns in expected.tsv can be met at all.

Written: 2026-06-12. Review section 0 with extra care after 2026-06-19.
Where the decisions behind this sheet came from: the session of 2026-06-12 (session-notes.md).
This run holds only what is decided and can be confirmed by a machine.

## 0. Re-check at start

Run every row before doing anything else. If even one of them no longer holds, stop and report.

| # | Premise | How to confirm |
|---|---|---|
| 1 | Two configs are migrated and three are not | `sh test.sh` prints `2 of 5 migrated` |
| 2 | orders and search still use the old key | `grep -c '^timeout=' services/orders.conf services/search.conf` prints 1 for each |
| 3 | The work is on the branch migrate-timeouts | `git branch --show-current` prints `migrate-timeouts` |

If a premise fails: do not decide how to repair it. Write what changed and which parts of this sheet it makes invalid, then stop.

## Stop conditions

1. `sh test.sh` prints `4 of 5 migrated`.
2. `grep -c '^timeout=' services/orders.conf services/search.conf` prints 0 for each.

## Step 1: orders

Why: plain conversion, seconds times 1000.

- In services/orders.conf, replace `timeout=8` with `timeout_ms=8000`.

Negative test: before the change, `sh test.sh` prints `2 of 5 migrated`.

## Step 2: search

- In services/search.conf, replace `timeout=2` with `timeout_ms=2000`.

## Not in this run

| What | Why |
|---|---|
| services/export.conf | Its value 0 means "no limit" and the replacement is not decided. See TODO.md. |

## Allowed and forbidden paths

- Allowed: services/orders.conf, services/search.conf
- Forbidden: test.sh (shared with another repository), services/export.conf

## When to halt

- Three attempts at the same step without meeting its condition: stop and report what is blocking.
- A decision turns out to be needed: do not make it. Add a note to TODO.md and go on to the next step.
- Hard stop: Step 2 is done, or one hour has passed, whichever comes first.

## When finished

Commit the two config files on migrate-timeouts.
