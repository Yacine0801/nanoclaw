#!/bin/bash
# backup.sh — Backup critical NanoClaw data to GCS daily.
# Run via launchd at 4:00 AM.
set -uo pipefail

BUCKET="gs://nanoclaw-backups-adp"
HOME_DIR="/Users/boty"
DATE=$(date +%Y-%m-%d)
LOG="/Users/boty/nanoclaw/logs/backup.log"
RETENTION_DAYS=30

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"; }
log "Backup started"

errors=0

# Backup function: local_path → GCS path
backup_file() {
  local src="$1"
  local dest="$2"
  if [ -f "$src" ]; then
    gcloud storage cp "$src" "${BUCKET}/${DATE}/${dest}" --quiet 2>>"$LOG" || {
      log "ERROR: failed to backup $src"
      errors=$((errors + 1))
    }
  fi
}

# Backup SQLite with .backup for consistency
backup_sqlite() {
  local db="$1"
  local dest="$2"
  if [ -f "$db" ]; then
    local tmp="/tmp/nanoclaw-backup-$(basename "$db")"
    sqlite3 "$db" ".backup '$tmp'" 2>>"$LOG" && \
    gzip -f "$tmp" 2>>"$LOG" && \
    gcloud storage cp "${tmp}.gz" "${BUCKET}/${DATE}/${dest}.gz" --quiet 2>>"$LOG" && \
    rm -f "${tmp}.gz" || {
      log "ERROR: failed to backup SQLite $db"
      errors=$((errors + 1))
    }
  fi
}

# === Backup all instances ===
for instance_dir in "$HOME_DIR"/nanoclaw "$HOME_DIR"/nanoclaw-*; do
  [ -d "$instance_dir" ] || continue
  name=$(basename "$instance_dir")

  # Skip non-instance dirs
  [[ "$name" == nanoclaw-private ]] && continue

  log "Backing up $name..."

  # SQLite databases
  backup_sqlite "$instance_dir/store/messages.db" "$name/messages.db"
  backup_sqlite "$instance_dir/data/nanoclaw.db" "$name/nanoclaw.db"

  # Agent memory (CLAUDE.md per group)
  for claude_md in "$instance_dir"/groups/*/CLAUDE.md; do
    [ -f "$claude_md" ] || continue
    group=$(basename "$(dirname "$claude_md")")
    backup_file "$claude_md" "$name/groups/${group}/CLAUDE.md"
  done

  # Config (redacted — .env contains API keys but we need it for disaster recovery)
  backup_file "$instance_dir/.env" "$name/.env"
done

# === Backup credentials ===
log "Backing up credentials..."

for mcp_dir in "$HOME_DIR"/.gmail-mcp "$HOME_DIR"/.gmail-mcp-*; do
  [ -d "$mcp_dir" ] || continue
  name=$(basename "$mcp_dir")
  backup_file "$mcp_dir/credentials.json" "credentials/$name/credentials.json"
  backup_file "$mcp_dir/gcp-oauth.keys.json" "credentials/$name/gcp-oauth.keys.json"
done

# Firebase service accounts
for sa in "$HOME_DIR"/.firebase-mcp/*.json; do
  [ -f "$sa" ] || continue
  backup_file "$sa" "credentials/firebase-mcp/$(basename "$sa")"
done

# NanoClaw config
for cfg in "$HOME_DIR"/.config/nanoclaw/*.json; do
  [ -f "$cfg" ] || continue
  backup_file "$cfg" "config/$(basename "$cfg")"
done

# === Retention: delete backups older than 30 days ===
log "Cleaning up old backups..."
cutoff_date=$(date -v-${RETENTION_DAYS}d +%Y-%m-%d 2>/dev/null || date -d "-${RETENTION_DAYS} days" +%Y-%m-%d)
gcloud storage ls "$BUCKET/" 2>/dev/null | while read -r dir; do
  dir_date=$(basename "$dir" | grep -oE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' || echo "")
  if [ -n "$dir_date" ] && [[ "$dir_date" < "$cutoff_date" ]]; then
    log "Deleting old backup: $dir"
    gcloud storage rm -r "$dir" --quiet 2>>"$LOG"
  fi
done

# === Report ===
if [ "$errors" -gt 0 ]; then
  log "Backup completed with $errors error(s)"
  # Alert via IPC
  ipc_dir="$HOME_DIR/nanoclaw/data/ipc/whatsapp_main"
  mkdir -p "$ipc_dir"
  ts=$(date +%s%3N)
  cat > "$ipc_dir/backup-alert-${ts}.json" << EOF
{
  "type": "send_message",
  "data": {
    "text": "⚠️ [Backup] Completed with $errors error(s). Check logs: $LOG"
  }
}
EOF
else
  log "Backup completed successfully"
fi
