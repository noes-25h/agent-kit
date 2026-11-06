#!/bin/sh
set -e

STAMP=$(date +%Y%m%d)
ARCHIVE="/var/backups/files-$STAMP.tar.gz"

tar -czf "$ARCHIVE" /srv/files
curl -sS -T "$ARCHIVE" "https://backup.example.com/files/files-$STAMP.tar.gz"
echo "uploaded $ARCHIVE"
