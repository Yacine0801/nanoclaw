#!/bin/bash
# Rotate NanoClaw logs (no root required):
#   1. Rotate pino logs when they exceed 50 MB (keep 5 archives)
#   2. Prune container logs older than 14 days
#   3. Delete old rotated archives older than 7 days
#
# Covers the main instance and sibling instances (nanoclaw-sam, nanoclaw-alan, etc.)
# Runs daily at 3am via launchd: com.nanoclaw.logrotate.plist

set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOME_DIR="${HOME:-/Users/boty}"
MAX_SIZE=$((50 * 1024 * 1024))  # 50 MB
KEEP=5
CONTAINER_LOG_DAYS=14

# All NanoClaw instances to rotate
INSTANCES=("$PROJECT_DIR")
for sibling in "$HOME_DIR"/nanoclaw-*/; do
    [ -d "$sibling" ] && INSTANCES+=("${sibling%/}")
done

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

for inst in "${INSTANCES[@]}"; do
    echo "  Instance: $inst"

    # --- Pino logs ---
    rotate_file "$inst/logs/nanoclaw.log"
    rotate_file "$inst/logs/nanoclaw.error.log"
    for f in "$inst"/logs/gemini-*.log; do
        [ -f "$f" ] && rotate_file "$f"
    done

    # --- Delete old rotated archives (> 7 days) ---
    find "$inst/logs" -name '*.gz' -mtime +7 -delete 2>/dev/null || true

    # --- Container logs: delete files older than $CONTAINER_LOG_DAYS days ---
    if [ -d "$inst/groups" ]; then
        deleted=$(find "$inst/groups" -path '*/logs/container-*.log' -mtime +${CONTAINER_LOG_DAYS} -delete -print 2>/dev/null | wc -l | tr -d ' ')
        remaining=$(find "$inst/groups" -path '*/logs/container-*.log' 2>/dev/null | wc -l | tr -d ' ')
        echo "  Container logs: deleted $deleted old files, $remaining remaining"
    fi
done

# --- SQLite backup (main instance only) ---
"$PROJECT_DIR/scripts/backup-db.sh"

echo "$(date -Iseconds) Log rotation + backup complete"
