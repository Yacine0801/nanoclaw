#!/bin/bash
# NanoClaw Migration — Import (run on Mac mini)
# Expects ~/nanoclaw-migration.tar.gz from migrate-export.sh
set -e

echo "=== NanoClaw Migration Import ==="
echo ""

# Check prerequisites
TARBALL="$HOME/nanoclaw-migration.tar.gz"
if [ ! -f "$TARBALL" ]; then
  echo "Error: $TARBALL not found"
  echo "Transfer it from the MacBook first (AirDrop, USB, scp)"
  exit 1
fi

# Check for Homebrew
if ! command -v brew &>/dev/null; then
  echo "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# Install system dependencies
echo "[1/8] Installing system dependencies..."
brew install node git whisper-cpp ffmpeg 2>/dev/null || true

# Check Docker
if ! command -v docker &>/dev/null; then
  echo ""
  echo "WARNING: Docker not found."
  echo "Install Docker Desktop from https://docker.com/products/docker-desktop"
  echo "Then re-run this script."
  echo ""
  read -p "Press Enter if Docker is already installed elsewhere, or Ctrl+C to exit..."
fi

# Clone repo
echo "[2/8] Cloning NanoClaw..."
if [ -d "$HOME/nanoclaw" ]; then
  echo "  ~/nanoclaw already exists, pulling latest..."
  cd "$HOME/nanoclaw" && git pull
else
  git clone https://github.com/Yacine0801/nanoclaw.git "$HOME/nanoclaw"
fi
cd "$HOME/nanoclaw"

# Add remotes
echo "[3/8] Setting up git remotes..."
git remote add upstream https://github.com/qwibitai/nanoclaw.git 2>/dev/null || true
git remote add gmail https://github.com/qwibitai/nanoclaw-gmail.git 2>/dev/null || true
git remote add whatsapp https://github.com/qwibitai/nanoclaw-whatsapp.git 2>/dev/null || true

# Extract migration data
echo "[4/8] Extracting migration data..."
BACKUP_DIR="/tmp/nanoclaw-migration"
rm -rf "$BACKUP_DIR"
tar -xzf "$TARBALL" -C /tmp

# Restore project files
echo "[5/8] Restoring data..."
cp "$BACKUP_DIR/.env" "$HOME/nanoclaw/"
cp -r "$BACKUP_DIR/store" "$HOME/nanoclaw/"
cp -r "$BACKUP_DIR/data" "$HOME/nanoclaw/"
cp -r "$BACKUP_DIR/groups" "$HOME/nanoclaw/"

# Restore credential directories
mkdir -p "$HOME/.config/gws"
cp -r "$BACKUP_DIR/dot-config-gws/"* "$HOME/.config/gws/" 2>/dev/null || true
chmod 700 "$HOME/.config/gws"

mkdir -p "$HOME/.gmail-mcp"
cp -r "$BACKUP_DIR/dot-gmail-mcp/"* "$HOME/.gmail-mcp/" 2>/dev/null || true
chmod 700 "$HOME/.gmail-mcp"

mkdir -p "$HOME/.firebase-mcp"
cp -r "$BACKUP_DIR/dot-firebase-mcp/"* "$HOME/.firebase-mcp/" 2>/dev/null || true
chmod 700 "$HOME/.firebase-mcp"

mkdir -p "$HOME/.config/nanoclaw"

# Sync env to container
mkdir -p "$HOME/nanoclaw/data/env"
cp "$HOME/nanoclaw/.env" "$HOME/nanoclaw/data/env/env"

# Install & build
echo "[6/8] Installing dependencies & building..."
cd "$HOME/nanoclaw"
npm install
npm run build

# Build container
echo "[7/8] Building agent container..."
mkdir -p "$HOME/nanoclaw/logs"
cd "$HOME/nanoclaw/container" && ./build.sh

# Create launchd plist
echo "[8/8] Setting up auto-start service..."
PLIST="$HOME/Library/LaunchAgents/com.nanoclaw.plist"
NODE_PATH="$(which node)"
mkdir -p "$HOME/Library/LaunchAgents"

cat > "$PLIST" << PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.nanoclaw</string>
    <key>ProgramArguments</key>
    <array>
        <string>${NODE_PATH}</string>
        <string>${HOME}/nanoclaw/dist/index.js</string>
    </array>
    <key>WorkingDirectory</key>
    <string>${HOME}/nanoclaw</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:${HOME}/.local/bin</string>
        <key>HOME</key>
        <string>${HOME}</string>
    </dict>
    <key>StandardOutPath</key>
    <string>${HOME}/nanoclaw/logs/nanoclaw.log</string>
    <key>StandardErrorPath</key>
    <string>${HOME}/nanoclaw/logs/nanoclaw.error.log</string>
</dict>
</plist>
PLISTEOF

echo ""
echo "=== Migration complete ==="
echo ""
echo "Next steps:"
echo "  1. STOP NanoClaw on MacBook first:"
echo "     launchctl unload ~/Library/LaunchAgents/com.nanoclaw.plist"
echo ""
echo "  2. START NanoClaw on this Mac mini:"
echo "     launchctl load ~/Library/LaunchAgents/com.nanoclaw.plist"
echo ""
echo "  3. Check logs:"
echo "     tail -f ~/nanoclaw/logs/nanoclaw.log"
echo ""
echo "NOTE: Only ONE instance can be connected to WhatsApp at a time."
echo "Stop the MacBook BEFORE starting the Mac mini."

# Cleanup
rm -rf "$BACKUP_DIR"
