# Ops notes

- The nightly archive of `/srv/files` is about 40 GB after compression. Measured over the last 30 nights.
- The office uplink is 20 Mbit/s. Measured with three uploads of a 1 GB file.
- The maintenance period is 02:00 to 04:00. Outside it, the uplink is shared with video calls.
- The backup runs from a cron entry on the file server. A failed run leaves no message anywhere.
- The last restore test was run from a local archive, not from the remote copy.
