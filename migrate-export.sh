#!/bin/bash
# NanoClaw Migration — Export (run on MacBook Pro)
# Creates a tarball with everything needed to migrate to Mac mini
set -e

BACKUP_DIR="/tmp/nanoclaw-migration"
rm -rf "$BACKUP_DIR"
mkdir -p "$BACKUP_DIR"

echo "=== NanoClaw Migration Export ==="
echo ""

# 1. Secrets
echo "[1/7] .env"
cp ~/nanoclaw/.env "$BACKUP_DIR/"

# 2. WhatsApp auth + message database
echo "[2/7] store/ (WhatsApp auth + DB)"
cp -r ~/nanoclaw/store "$BACKUP_DIR/"

# 3. Data (sessions, models, env)
echo "[3/7] data/ (sessions, models)"
cp -r ~/nanoclaw/data "$BACKUP_DIR/"

# 4. Group memories
echo "[4/7] groups/ (Botti memory)"
cp -r ~/nanoclaw/groups "$BACKUP_DIR/"

# 5. Google Workspace CLI credentials
echo "[5/7] ~/.config/gws/"
mkdir -p "$BACKUP_DIR/dot-config-gws"
cp -r ~/.config/gws/* "$BACKUP_DIR/dot-config-gws/" 2>/dev/null || echo "  (skipped — not found)"

# 6. Gmail MCP credentials
echo "[6/7] ~/.gmail-mcp/"
mkdir -p "$BACKUP_DIR/dot-gmail-mcp"
cp -r ~/.gmail-mcp/* "$BACKUP_DIR/dot-gmail-mcp/" 2>/dev/null || echo "  (skipped — not found)"

# 7. Firebase credentials
echo "[7/7] ~/.firebase-mcp/"
mkdir -p "$BACKUP_DIR/dot-firebase-mcp"
cp -r ~/.firebase-mcp/* "$BACKUP_DIR/dot-firebase-mcp/" 2>/dev/null || echo "  (skipped — not found)"

# Create tarball
TARBALL="$HOME/nanoclaw-migration.tar.gz"
echo ""
echo "Creating archive..."
tar -czf "$TARBALL" -C /tmp nanoclaw-migration

SIZE=$(du -sh "$TARBALL" | cut -f1)
echo ""
echo "=== Done ==="
echo "Archive: $TARBALL ($SIZE)"
echo ""
echo "Transfer to Mac mini via AirDrop, USB, or:"
echo "  scp $TARBALL user@mac-mini:~/"
echo ""
echo "Then on the Mac mini, run:"
echo "  ~/nanoclaw/migrate-import.sh"

rm -rf "$BACKUP_DIR"
