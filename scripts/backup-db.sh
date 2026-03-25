#!/bin/bash
# Backup NanoClaw SQLite databases using the .backup command
# (safe even while the DB is open — uses SQLite's online backup API).
# Keeps 7 daily backups, rotates oldest.

set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BACKUP_DIR="$PROJECT_DIR/store/backups"
DB_PATH="$PROJECT_DIR/store/messages.db"
DATE=$(date +%Y-%m-%d)
KEEP=7

mkdir -p "$BACKUP_DIR"

if [ ! -f "$DB_PATH" ]; then
  echo "$(date -Iseconds) No database found at $DB_PATH, skipping"
  exit 0
fi

BACKUP_FILE="$BACKUP_DIR/messages-${DATE}.db"

# Use sqlite3 .backup for a consistent snapshot (safe with WAL mode)
sqlite3 "$DB_PATH" ".backup '$BACKUP_FILE'"

# Compress
gzip -f "$BACKUP_FILE"
echo "$(date -Iseconds) Backup: $BACKUP_FILE.gz ($(du -h "${BACKUP_FILE}.gz" | cut -f1))"

# Rotate: delete backups older than $KEEP days
find "$BACKUP_DIR" -name 'messages-*.db.gz' -mtime +$KEEP -delete 2>/dev/null || true
remaining=$(ls "$BACKUP_DIR"/messages-*.db.gz 2>/dev/null | wc -l | tr -d ' ')
echo "$(date -Iseconds) Backups retained: $remaining"
