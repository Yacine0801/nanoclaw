#!/bin/bash
# Rotate NanoClaw logs (no root required):
#   1. Rotate pino logs when they exceed 50 MB (keep 5 archives)
#   2. Prune container logs older than 7 days
#
# Runs daily via launchd: load etc/launchd/com.nanoclaw.logrotate.plist

set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MAX_SIZE=$((50 * 1024 * 1024))  # 50 MB
KEEP=5

rotate_file() {
    local file="$1"
    [ -f "$file" ] || return 0
    local size
    size=$(stat -f%z "$file" 2>/dev/null || echo 0)
    [ "$size" -lt "$MAX_SIZE" ] && return 0

    # Shift archives: .5 -> delete, .4 -> .5, ... .1 -> .2, current -> .1
    local i=$KEEP
    while [ "$i" -gt 1 ]; do
        local prev=$((i - 1))
        [ -f "${file}.${prev}.gz" ] && mv "${file}.${prev}.gz" "${file}.${i}.gz"
        i=$prev
    done
    # Compress current into .1
    gzip -c "$file" > "${file}.1.gz"
    : > "$file"  # truncate in place (pino keeps the fd open)
    echo "  Rotated $file (was $((size / 1024 / 1024)) MB)"
}

echo "$(date -Iseconds) Starting log rotation"

# --- Pino logs ---
rotate_file "$PROJECT_DIR/logs/nanoclaw.log"
rotate_file "$PROJECT_DIR/logs/nanoclaw.error.log"
for f in "$PROJECT_DIR"/logs/gemini-*.log; do
    rotate_file "$f"
done

# --- Container logs: delete files older than 7 days ---
deleted=$(find "$PROJECT_DIR/groups" -path '*/logs/container-*.log' -mtime +7 -delete -print 2>/dev/null | wc -l | tr -d ' ')
remaining=$(find "$PROJECT_DIR/groups" -path '*/logs/container-*.log' 2>/dev/null | wc -l | tr -d ' ')
echo "  Container logs: deleted $deleted old files, $remaining remaining"

# --- SQLite backup ---
"$PROJECT_DIR/scripts/backup-db.sh"

echo "$(date -Iseconds) Log rotation + backup complete"
