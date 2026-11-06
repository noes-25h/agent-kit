# Plan: move the nightly backup from cron to the job scheduler

## Goal

The nightly backup of the file server runs from a cron entry on one machine. Nobody is told when it fails. Move it to the job scheduler, which records every run and sends a message on failure.

## Material

- `reference/backup.sh` is the script that cron runs today.
- `reference/ops-notes.md` holds the measured size of the archive and the measured speed of the uplink.

## Facts the plan relies on

- The archive is about 40 GB. The uplink is 20 Mbit/s. Both numbers are in the ops notes.
- The upload therefore completes inside the maintenance period from 02:00 to 04:00, the same as today.
- The script already confirms each archive against a checksum after upload, as `reference/backup.sh` shows. The new job leaves that part to the script.

## Steps

1. Register a job in the scheduler that calls `backup.sh` at 02:00 every night.
2. Point the failure message of the job at the on-call channel.
3. Delete the old cron entry and the local archives older than one day, to free the disk.
4. Run the new job for the first time and confirm that it completes.
5. Write the new procedure into the ops notes.

## Done when

The scheduler shows one completed run, and the on-call channel has received a test failure message.
