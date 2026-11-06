# Plan: move the nightly backup from cron to the job scheduler

Hand-written sample of a plan file after a review. It is not the output of Claude Code. selftest uses it, together with run.ndjson, to check the scoring in live-check.sh. run.ndjson is also written by hand: it is a made-up session in the line format of `claude -p --output-format stream-json`, not the record of a real run.

(body of the plan omitted)

## Adversarial review (2026-10-09, adversarial-reviewer, ran on not observed / effort not observed)

| # | Finding | Ruling |
|---|---|---|
| 1 fail | backup.sh has no checksum step | **adopt**. Checked against reference/backup.sh. The job gets its own comparison step. |
| 2 fail | The upload takes about 4.4 hours, not 2 | **adopt**. Recomputed from the ops notes. Switched to incremental archives. |
| 3 note | The failure message goes to one channel | **defer**. Recorded in the ops notes under open items. |

## Best-path review (2026-10-09, best-path-reviewer, ran on not observed / effort not observed)

| # | Proposal | Ruling |
|---|---|---|
| 1 large | Swap steps 3 and 4 | **adopt**. The cron entry stays until the new job has completed three runs. |
| 2 medium | Restore from the remote copy as a done condition | **escalate**. Question: is one restore test before the switch acceptable? Recommendation: yes. |

Both reviewers arrived at the order of the steps. The plan now proves the new job before it removes the old one.
