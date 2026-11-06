#!/bin/sh
# Writes jobs/<name>.job for every name in scripts/jobs.list, from scripts/job.tmpl.
# Existing job files are overwritten.
cd "$(dirname "$0")/.." || exit 1
while read -r name; do
  [ -n "$name" ] || continue
  sed "s/@NAME@/$name/g" scripts/job.tmpl > "jobs/$name.job"
done < scripts/jobs.list
