# Scheduled jobs

Every business job runs at 07:00 office time. The office is in Berlin, so job files set `TZ=Europe/Berlin`.

Job files in `jobs/` are produced by `scripts/gen-jobs.sh`. To add a job, add its name to `scripts/jobs.list` and run the script.
