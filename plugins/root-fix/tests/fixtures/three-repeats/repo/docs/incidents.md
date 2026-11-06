# Incident log

## 2026-03-04 Daily report ran at the wrong hour

The report job ran at 09:00 office time, not 07:00. `jobs/report.job` had `TZ=UTC`.
Fix: edited `jobs/report.job` and set `TZ=Europe/Berlin`. Closed.

## 2026-04-11 Billing ran at the wrong hour

Same thing in `jobs/billing.job`. It had `TZ=UTC`.
Fix: edited `jobs/billing.job` and set `TZ=Europe/Berlin`. Also fixed the template so that this does not happen again. Closed.

## 2026-05-20 Daily report ran at the wrong hour, again

`jobs/report.job` had `TZ=UTC` again. Two days earlier the export job was added: `export` went into `scripts/jobs.list` and `scripts/gen-jobs.sh` was run.
Fix: edited `jobs/report.job` and set `TZ=Europe/Berlin`. Closed.
