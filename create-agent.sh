#!/bin/bash
#
# create-agent.sh — Create a new NanoClaw agent instance
#
# Usage:
#   ./create-agent.sh <name> <email> [--port PORT] [--model MODEL]
#
# Example:
#   ./create-agent.sh alan ala@bestoftours.co.uk --port 3004
#   ./create-agent.sh marie marie@bestoftours.co.uk  # auto-detect port
#
set -euo pipefail

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
NANOCLAW_DIR="/Users/boty/nanoclaw"
HOME_DIR="/Users/boty"
LAUNCH_AGENTS_DIR="$HOME_DIR/Library/LaunchAgents"
FIREBASE_CREDS="$HOME_DIR/.firebase-mcp/adp-service-account.json"
NODE_BIN="/opt/homebrew/bin/node"
PATH_ENV="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$HOME_DIR/.local/bin:/opt/homebrew/share/google-cloud-sdk/bin"
OAUTH_SCOPES="https://mail.google.com/ https://www.googleapis.com/auth/calendar https://www.googleapis.com/auth/drive.readonly"
PORT_RANGE_START=3001
PORT_RANGE_END=3010

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
die()   { error "$*"; exit 1; }

step_num=0
step() {
  step_num=$((step_num + 1))
  echo ""
  echo -e "${BLUE}━━━ Step $step_num: $* ━━━${NC}"
}

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
NAME=""
EMAIL=""
PORT=""
MODEL="claude-opus-4-6"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --port)
      PORT="$2"
      shift 2
      ;;
    --model)
      MODEL="$2"
      shift 2
      ;;
    --help|-h)
      echo "Usage: $0 <name> <email> [--port PORT] [--model MODEL]"
      echo ""
      echo "Arguments:"
      echo "  name     Agent name (lowercase alpha only, e.g. 'alan')"
      echo "  email    Agent's email address (e.g. 'ala@bestoftours.co.uk')"
      echo ""
      echo "Options:"
      echo "  --port PORT    Credential proxy port (auto-detected if omitted)"
      echo "  --model MODEL  Claude model (default: claude-opus-4-6)"
      exit 0
      ;;
    -*)
      die "Unknown option: $1"
      ;;
    *)
      if [[ -z "$NAME" ]]; then
        NAME="$1"
      elif [[ -z "$EMAIL" ]]; then
        EMAIL="$1"
      else
        die "Unexpected argument: $1"
      fi
      shift
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Step 1: Validate inputs
# ---------------------------------------------------------------------------
step "Validate inputs"

[[ -z "$NAME" ]] && die "Name is required. Usage: $0 <name> <email> [--port PORT]"
[[ -z "$EMAIL" ]] && die "Email is required. Usage: $0 <name> <email> [--port PORT]"

# Name must be lowercase alpha only
if ! echo "$NAME" | grep -qE '^[a-z]+$'; then
  die "Name must be lowercase letters only (got: '$NAME')"
fi

# Email must contain @
if ! echo "$EMAIL" | grep -qE '@'; then
  die "Email must contain @ (got: '$EMAIL')"
fi

# Capitalize name for display
NAME_CAPITALIZED="$(echo "${NAME:0:1}" | tr '[:lower:]' '[:upper:]')${NAME:1}"

AGENT_DIR="$HOME_DIR/nanoclaw-$NAME"
GMAIL_MCP_DIR="$HOME_DIR/.gmail-mcp-$NAME"
PLIST_FILE="$LAUNCH_AGENTS_DIR/com.nanoclaw.$NAME.plist"
PLIST_LABEL="com.nanoclaw.$NAME"

ok "Name: $NAME ($NAME_CAPITALIZED)"
ok "Email: $EMAIL"

# Check if directory already exists
if [[ -d "$AGENT_DIR" ]]; then
  warn "Directory $AGENT_DIR already exists."
  read -rp "Overwrite? (y/N) " confirm
  if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    die "Aborted by user."
  fi
  info "Will overwrite existing installation."
fi

# Validate port if specified
if [[ -n "$PORT" ]]; then
  if ! echo "$PORT" | grep -qE '^[0-9]+$'; then
    die "Port must be a number (got: '$PORT')"
  fi
fi

# ---------------------------------------------------------------------------
# Step 2: Auto-detect port
# ---------------------------------------------------------------------------
step "Determine port"

if [[ -z "$PORT" ]]; then
  info "Scanning for used ports in existing plists..."
  USED_PORTS=()
  for plist in "$LAUNCH_AGENTS_DIR"/com.nanoclaw.*.plist; do
    [[ -f "$plist" ]] || continue
    p=$(grep -A1 'CREDENTIAL_PROXY_PORT' "$plist" 2>/dev/null | grep '<string>' | sed 's/.*<string>\(.*\)<\/string>.*/\1/' || true)
    if [[ -n "$p" ]]; then
      USED_PORTS+=("$p")
      info "  Port $p used by $(basename "$plist")"
    fi
  done
  # Also check the main nanoclaw .env
  main_port=$(grep '^CREDENTIAL_PROXY_PORT=' "$NANOCLAW_DIR/.env" 2>/dev/null | cut -d= -f2 || true)
  if [[ -n "$main_port" ]]; then
    USED_PORTS+=("$main_port")
    info "  Port $main_port used by main nanoclaw"
  fi

  for candidate in $(seq $PORT_RANGE_START $PORT_RANGE_END); do
    in_use=false
    for used in "${USED_PORTS[@]}"; do
      if [[ "$candidate" == "$used" ]]; then
        in_use=true
        break
      fi
    done
    if ! $in_use; then
      PORT="$candidate"
      break
    fi
  done

  [[ -z "$PORT" ]] && die "No free port found in range $PORT_RANGE_START-$PORT_RANGE_END"
fi

# Verify port is not already used by another agent
for plist in "$LAUNCH_AGENTS_DIR"/com.nanoclaw.*.plist; do
  [[ -f "$plist" ]] || continue
  existing_port=$(grep -A1 'CREDENTIAL_PROXY_PORT' "$plist" 2>/dev/null | grep '<string>' | sed 's/.*<string>\(.*\)<\/string>.*/\1/' || true)
  existing_name=$(basename "$plist" .plist | sed 's/com\.nanoclaw\.//')
  if [[ "$existing_port" == "$PORT" && "$existing_name" != "$NAME" ]]; then
    die "Port $PORT is already used by agent '$existing_name'"
  fi
done

ok "Port: $PORT"

# ---------------------------------------------------------------------------
# Step 3: Read ANTHROPIC_API_KEY from main nanoclaw
# ---------------------------------------------------------------------------
step "Read API key"

ANTHROPIC_API_KEY=$(grep '^ANTHROPIC_API_KEY=' "$NANOCLAW_DIR/.env" | cut -d= -f2)
[[ -z "$ANTHROPIC_API_KEY" ]] && die "Could not read ANTHROPIC_API_KEY from $NANOCLAW_DIR/.env"
ok "API key read from main nanoclaw (${ANTHROPIC_API_KEY:0:20}...)"

# ---------------------------------------------------------------------------
# Step 4: Create directory structure
# ---------------------------------------------------------------------------
step "Create directory structure"

mkdir -p "$AGENT_DIR"/{groups/gmail_main,data,logs,store}
ok "Created $AGENT_DIR with groups/gmail_main, data, logs, store"

# ---------------------------------------------------------------------------
# Step 5: Create symlinks
# ---------------------------------------------------------------------------
step "Create symlinks"

for target in container node_modules package.json src; do
  link="$AGENT_DIR/$target"
  rm -rf "$link"
  ln -s "$NANOCLAW_DIR/$target" "$link"
  ok "Symlinked $target -> $NANOCLAW_DIR/$target"
done

# ---------------------------------------------------------------------------
# Step 6: Copy dist/
# ---------------------------------------------------------------------------
step "Copy dist/"

rm -rf "$AGENT_DIR/dist"
cp -R "$NANOCLAW_DIR/dist" "$AGENT_DIR/dist"
ok "Copied dist/ (real copy, not symlink)"

# ---------------------------------------------------------------------------
# Step 7: Create .env
# ---------------------------------------------------------------------------
step "Create .env"

cat > "$AGENT_DIR/.env" << EOF
ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY

CLAUDE_MODEL=$MODEL
ASSISTANT_NAME="$NAME_CAPITALIZED"
ASSISTANT_HAS_OWN_NUMBER=false
CREDENTIAL_PROXY_PORT=$PORT
CONTAINER_PREFIX=nanoclaw-$NAME
GMAIL_MCP_DIR=$GMAIL_MCP_DIR

GOOGLE_CHAT_ENABLED=true
GOOGLE_CHAT_AGENT_NAME=$NAME
GOOGLE_APPLICATION_CREDENTIALS=$FIREBASE_CREDS
EOF

ok "Created $AGENT_DIR/.env"

# ---------------------------------------------------------------------------
# Step 8: Create Gmail MCP directory and OAuth
# ---------------------------------------------------------------------------
step "Set up Gmail OAuth"

mkdir -p "$GMAIL_MCP_DIR"

# Find an existing gcp-oauth.keys.json to copy
OAUTH_KEYS_SRC=""
for dir in "$HOME_DIR"/.gmail-mcp-*/; do
  if [[ -f "${dir}gcp-oauth.keys.json" ]]; then
    OAUTH_KEYS_SRC="${dir}gcp-oauth.keys.json"
    break
  fi
done

if [[ -z "$OAUTH_KEYS_SRC" ]]; then
  die "No existing gcp-oauth.keys.json found in any ~/.gmail-mcp-* directory"
fi

cp "$OAUTH_KEYS_SRC" "$GMAIL_MCP_DIR/gcp-oauth.keys.json"
ok "Copied OAuth client config from $OAUTH_KEYS_SRC"

# Read client_id and client_secret
CLIENT_ID=$(python3 -c "import json; d=json.load(open('$GMAIL_MCP_DIR/gcp-oauth.keys.json')); print(d['installed']['client_id'])")
CLIENT_SECRET=$(python3 -c "import json; d=json.load(open('$GMAIL_MCP_DIR/gcp-oauth.keys.json')); print(d['installed']['client_secret'])")

if [[ -f "$GMAIL_MCP_DIR/credentials.json" ]]; then
  warn "credentials.json already exists in $GMAIL_MCP_DIR"
  read -rp "Re-run OAuth flow? (y/N) " reauth
  if [[ "$reauth" != "y" && "$reauth" != "Y" ]]; then
    ok "Keeping existing credentials.json"
    SKIP_OAUTH=true
  else
    SKIP_OAUTH=false
  fi
else
  SKIP_OAUTH=false
fi

if [[ "$SKIP_OAUTH" == "false" ]]; then
  info ""
  info "Starting OAuth flow for $EMAIL..."
  info "A browser will open. Sign in with: $EMAIL"
  info ""

  # URL-encode scopes (spaces -> %20)
  ENCODED_SCOPES=$(echo "$OAUTH_SCOPES" | sed 's/ /%20/g')

  # Pick a local port for the OAuth redirect
  OAUTH_PORT=8749
  AUTH_URL="https://accounts.google.com/o/oauth2/auth?client_id=$CLIENT_ID&redirect_uri=http://localhost:$OAUTH_PORT&response_type=code&scope=$ENCODED_SCOPES&access_type=offline&prompt=consent"

  # Open browser
  open "$AUTH_URL" 2>/dev/null || echo "Open this URL in your browser: $AUTH_URL"

  info "Waiting for OAuth callback on localhost:$OAUTH_PORT..."

  # Minimal HTTP server to catch the redirect
  AUTH_CODE=""
  # Use a single nc call to catch the request and respond
  RESPONSE_BODY="<html><body><h1>Authorization successful!</h1><p>You can close this tab and return to the terminal.</p></body></html>"
  RESPONSE="HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: ${#RESPONSE_BODY}\r\nConnection: close\r\n\r\n$RESPONSE_BODY"

  # Listen for the OAuth redirect
  REQUEST=$(nc -l $OAUTH_PORT 2>/dev/null <<< "$RESPONSE" || true)

  # If nc didn't work well, try with a Python one-liner
  if [[ -z "$REQUEST" ]] || ! echo "$REQUEST" | grep -q "code="; then
    info "Retrying with Python HTTP server..."
    AUTH_CODE=$(python3 -c "
import http.server, urllib.parse, sys

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        query = urllib.parse.urlparse(self.path).query
        params = urllib.parse.parse_qs(query)
        code = params.get('code', [''])[0]
        self.send_response(200)
        self.send_header('Content-Type', 'text/html')
        self.end_headers()
        self.wfile.write(b'<h1>Authorization successful!</h1><p>You can close this tab.</p>')
        print(code, flush=True)
        # Shutdown after handling
        import threading
        threading.Thread(target=self.server.shutdown).start()
    def log_message(self, *args):
        pass

server = http.server.HTTPServer(('localhost', $OAUTH_PORT), Handler)
server.handle_request()
server.server_close()
" 2>/dev/null)
  else
    AUTH_CODE=$(echo "$REQUEST" | grep -oP 'code=\K[^& ]+' | head -1)
  fi

  if [[ -z "$AUTH_CODE" ]]; then
    die "Failed to capture OAuth authorization code. Please try again."
  fi

  ok "Got authorization code"

  # Exchange code for tokens
  info "Exchanging code for tokens..."
  TOKEN_RESPONSE=$(curl -s -X POST https://oauth2.googleapis.com/token \
    -d "code=$AUTH_CODE" \
    -d "client_id=$CLIENT_ID" \
    -d "client_secret=$CLIENT_SECRET" \
    -d "redirect_uri=http://localhost:$OAUTH_PORT" \
    -d "grant_type=authorization_code")

  # Check for error
  if echo "$TOKEN_RESPONSE" | python3 -c "import sys,json; d=json.load(sys.stdin); sys.exit(0 if 'refresh_token' in d else 1)" 2>/dev/null; then
    # Write credentials.json in the expected format
    python3 -c "
import json, sys
resp = json.loads('''$TOKEN_RESPONSE''')
creds = {
    'access_token': resp['access_token'],
    'refresh_token': resp['refresh_token'],
    'scope': resp.get('scope', '$OAUTH_SCOPES'),
    'token_type': resp.get('token_type', 'Bearer'),
    'expiry_date': int(resp.get('expires_in', 3600)) * 1000 + __import__('time').time_ns() // 1000000
}
with open('$GMAIL_MCP_DIR/credentials.json', 'w') as f:
    json.dump(creds, f, indent=2)
print('OK')
"
    ok "Saved credentials.json to $GMAIL_MCP_DIR"
  else
    error "Token exchange failed:"
    echo "$TOKEN_RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$TOKEN_RESPONSE"
    die "OAuth token exchange failed. Fix the issue and re-run."
  fi
fi

# ---------------------------------------------------------------------------
# Step 9: Create launchd plist
# ---------------------------------------------------------------------------
step "Create launchd plist"

cat > "$PLIST_FILE" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$PLIST_LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$NODE_BIN</string>
        <string>$NANOCLAW_DIR/dist/index.js</string>
    </array>
    <key>WorkingDirectory</key>
    <string>$AGENT_DIR</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>$PATH_ENV</string>
        <key>HOME</key>
        <string>$HOME_DIR</string>
        <key>CREDENTIAL_PROXY_PORT</key>
        <string>$PORT</string>
        <key>GMAIL_MCP_DIR</key>
        <string>$GMAIL_MCP_DIR</string>
        <key>GOOGLE_CHAT_ENABLED</key>
        <string>true</string>
        <key>GOOGLE_CHAT_AGENT_NAME</key>
        <string>$NAME</string>
        <key>GOOGLE_APPLICATION_CREDENTIALS</key>
        <string>$FIREBASE_CREDS</string>
    </dict>
    <key>StandardOutPath</key>
    <string>$AGENT_DIR/logs/nanoclaw.log</string>
    <key>StandardErrorPath</key>
    <string>$AGENT_DIR/logs/nanoclaw.error.log</string>
</dict>
</plist>
EOF

ok "Created $PLIST_FILE"

# ---------------------------------------------------------------------------
# Step 10: Create CLAUDE.md
# ---------------------------------------------------------------------------
step "Create CLAUDE.md for gmail_main group"

cat > "$AGENT_DIR/groups/gmail_main/CLAUDE.md" << 'TEMPLATE_EOF'
# AGENT_NAME_CAPITALIZED

Tu es AGENT_NAME_CAPITALIZED, assistant operationnel connecte via Gmail (AGENT_EMAIL).

## Identite et ton
- Francais par defaut. Anglais si le contexte l'exige.
- Factuel, direct, dense. Zero flatterie.
- Tutoie Yacine et l'equipe interne. Vouvoie les contacts externes.
- Si tu ne sais pas, dis-le et cherche.

## Qui est Yacine
PDG de Botler 360 (SaaS IA) et Best of Tours (tour operateur UK/FR/Australie). Base a Entraigues-sur-la-Sorgue, France. Fuseau Europe/Paris.
Emails : yacine@bestoftours.co.uk (pro), bakoucheyacine@gmail.com (perso).

## Equipe Direction
- Eline Engelbracht : Directrice/COO, eline@bestoftours.co.uk
- Ahmed Amdouni : CTO, ahmed@bestoftours.co.uk

## Regles critiques
- Signe les emails avec "AGENT_NAME_CAPITALIZED — Best of Tours" ou "AGENT_NAME_CAPITALIZED — Botler 360" selon le contexte.
- Emails internes (@bestoftours.co.uk) : envoie directement.
- Emails externes : reformule et attends la confirmation de Yacine avant d'envoyer.
- Ne partage jamais d'informations confidentielles (financieres, RH, contractuelles).
- Quand tu proposes une action, donne le "et ensuite ?" — l'etape d'apres.

## What You Can Do

- Answer questions and have conversations
- Search the web and fetch content from URLs
- **Browse the web** with `agent-browser` — open pages, click, fill forms, take screenshots, extract data (run `agent-browser open <url>` to start, then `agent-browser snapshot -i` to see interactive elements)
- Read and write files in your workspace
- Run bash commands in your sandbox
- Schedule tasks to run later or on a recurring basis
- Send messages back to the chat

## Communication

Your output is sent to the user or group.

You also have `mcp__nanoclaw__send_message` which sends a message immediately while you're still working. This is useful when you want to acknowledge a request before starting longer work.

### Internal thoughts

If part of your output is internal reasoning rather than something for the user, wrap it in `<internal>` tags:

```
<internal>Compiled all three reports, ready to summarize.</internal>

Here are the key findings from the research...
```

Text inside `<internal>` tags is logged but not sent to the user.

## Your Workspace

Files you create are saved in `/workspace/group/`. Use this for notes, research, or anything that should persist.

## Memory

The `conversations/` folder contains searchable history of past conversations. Use this to recall context from previous sessions.

When you learn something important:
- Create files for structured data (e.g., `customers.md`, `preferences.md`)
- Split files larger than 500 lines into folders
- Keep an index in your memory for the files you create

## Google Workspace

You have the `gws` CLI (Google Workspace CLI) available via Bash. Use it to access Gmail, Calendar, Drive, Sheets, and Docs for `AGENT_EMAIL`.

### Gmail
- `gws gmail +triage` — unread inbox summary (sender, subject, date)
- `gws gmail +read --message-id <ID>` — read a specific email
- `gws gmail +send --to <email> --subject "..." --body "..."` — send an email
- `gws gmail +reply --message-id <ID> --body "..."` — reply to an email
- `gws gmail +forward --message-id <ID> --to <email>` — forward an email
- `gws gmail users messages list --params '{"userId":"me","q":"search query","maxResults":5}'` — search emails

### Calendar
- `gws calendar events list --params '{"calendarId":"primary","timeMin":"2026-03-19T00:00:00Z","timeMax":"2026-03-20T00:00:00Z","singleEvents":true,"orderBy":"startTime"}'` — list events
- `gws calendar events insert --params '{"calendarId":"primary"}' --json '{"summary":"Meeting","start":{"dateTime":"2026-03-20T14:00:00+01:00"},"end":{"dateTime":"2026-03-20T15:00:00+01:00"}}'` — create event

### Drive
- `gws drive files list --params '{"q":"name contains '\''budget'\''","pageSize":10,"fields":"files(id,name,mimeType,webViewLink)"}'` — search files

### Sheets
- `gws sheets +read --spreadsheet-id <ID>` — read spreadsheet data
- `gws sheets +append --spreadsheet-id <ID> --range "Sheet1" --json '[["col1","col2"]]'` — append rows

### Docs
- `gws docs documents get --params '{"documentId":"<ID>"}'` — read a document
- `gws docs +write --document-id <ID> --text "content to append"` — write to a document
- `gws docs documents create --json '{"title":"My Document"}'` — create a new document

Always use Bash to run these commands. Parse JSON output to extract relevant information before presenting it to the user.

## Message Formatting

NEVER use markdown. Only use WhatsApp/Telegram formatting:
- *single asterisks* for bold (NEVER **double asterisks**)
- _underscores_ for italic
- • bullet points
- ```triple backticks``` for code

No ## headings. No [links](url). No **double stars**.
TEMPLATE_EOF

# Replace placeholders
sed -i '' "s/AGENT_NAME_CAPITALIZED/$NAME_CAPITALIZED/g" "$AGENT_DIR/groups/gmail_main/CLAUDE.md"
sed -i '' "s/AGENT_EMAIL/$EMAIL/g" "$AGENT_DIR/groups/gmail_main/CLAUDE.md"

ok "Created $AGENT_DIR/groups/gmail_main/CLAUDE.md"

# ---------------------------------------------------------------------------
# Step 11: Register in DB
# ---------------------------------------------------------------------------
step "Register in database"

DB_FILE="$AGENT_DIR/store/messages.db"

# Initialize the database with required tables if it doesn't exist
sqlite3 "$DB_FILE" << 'SQL'
CREATE TABLE IF NOT EXISTS chats (
  jid TEXT PRIMARY KEY,
  name TEXT,
  last_message_time TEXT,
  channel TEXT,
  is_group INTEGER DEFAULT 0
);
CREATE TABLE IF NOT EXISTS messages (
  id TEXT,
  chat_jid TEXT,
  sender TEXT,
  sender_name TEXT,
  content TEXT,
  timestamp TEXT,
  is_from_me INTEGER,
  is_bot_message INTEGER DEFAULT 0,
  PRIMARY KEY (id, chat_jid),
  FOREIGN KEY (chat_jid) REFERENCES chats(jid)
);
CREATE INDEX IF NOT EXISTS idx_timestamp ON messages(timestamp);
CREATE TABLE IF NOT EXISTS scheduled_tasks (
  id TEXT PRIMARY KEY,
  group_folder TEXT NOT NULL,
  chat_jid TEXT NOT NULL,
  prompt TEXT NOT NULL,
  schedule_type TEXT NOT NULL,
  schedule_value TEXT NOT NULL,
  next_run TEXT,
  last_run TEXT,
  last_result TEXT,
  status TEXT DEFAULT 'active',
  created_at TEXT NOT NULL,
  context_mode TEXT DEFAULT 'isolated'
);
CREATE INDEX IF NOT EXISTS idx_next_run ON scheduled_tasks(next_run);
CREATE INDEX IF NOT EXISTS idx_status ON scheduled_tasks(status);
CREATE TABLE IF NOT EXISTS task_run_logs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  task_id TEXT NOT NULL,
  run_at TEXT NOT NULL,
  duration_ms INTEGER NOT NULL,
  status TEXT NOT NULL,
  result TEXT,
  error TEXT,
  FOREIGN KEY (task_id) REFERENCES scheduled_tasks(id)
);
CREATE INDEX IF NOT EXISTS idx_task_run_logs ON task_run_logs(task_id, run_at);
CREATE TABLE IF NOT EXISTS router_state (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS sessions (
  group_folder TEXT PRIMARY KEY,
  session_id TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS registered_groups (
  jid TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  folder TEXT NOT NULL UNIQUE,
  trigger_pattern TEXT NOT NULL,
  added_at TEXT NOT NULL,
  container_config TEXT,
  requires_trigger INTEGER DEFAULT 1,
  is_main INTEGER DEFAULT 0
);
SQL

# Insert the gmail_main group and chat
NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
sqlite3 "$DB_FILE" << SQL
INSERT OR REPLACE INTO registered_groups (jid, name, folder, trigger_pattern, added_at, requires_trigger, is_main)
VALUES ('gmail:main', '$NAME_CAPITALIZED Inbox', 'gmail_main', '', '$NOW', 1, 1);

INSERT OR REPLACE INTO chats (jid, name, channel, is_group)
VALUES ('gmail:main', '$NAME_CAPITALIZED Inbox', 'gmail', 0);
SQL

ok "Registered gmail:main group and chat in $DB_FILE"

# ---------------------------------------------------------------------------
# Step 12: Update deploy.sh
# ---------------------------------------------------------------------------
step "Update deploy.sh"

DEPLOY_FILE="$NANOCLAW_DIR/deploy.sh"
INSTANCE_NAME="nanoclaw-$NAME"

if grep -q "$INSTANCE_NAME" "$DEPLOY_FILE"; then
  ok "$INSTANCE_NAME already in deploy.sh"
else
  # Add to the INSTANCES array
  sed -i '' "s/^INSTANCES=(\(.*\))/INSTANCES=(\1 $INSTANCE_NAME)/" "$DEPLOY_FILE"
  if grep -q "$INSTANCE_NAME" "$DEPLOY_FILE"; then
    ok "Added $INSTANCE_NAME to INSTANCES array in deploy.sh"
  else
    warn "Could not auto-update deploy.sh. Add '$INSTANCE_NAME' to the INSTANCES array manually."
  fi
fi

# ---------------------------------------------------------------------------
# Step 13: Chat gateway instructions
# ---------------------------------------------------------------------------
step "Chat gateway reminder"

echo ""
warn "ACTION REQUIRED: Add '$NAME' to VALID_AGENTS in the chat-gateway Cloud Run service."
info "This cannot be done from this script. Update the gateway config to include:"
info "  VALID_AGENTS: [..., \"$NAME\"]"
echo ""

# ---------------------------------------------------------------------------
# Step 14: Load and start launchd service
# ---------------------------------------------------------------------------
step "Load and start service"

# Unload first if already loaded (ignore errors)
launchctl bootout "gui/$(id -u)/$PLIST_LABEL" 2>/dev/null || true

launchctl load "$PLIST_FILE"
ok "Loaded $PLIST_LABEL"

# Give it a moment to start
sleep 2

# ---------------------------------------------------------------------------
# Step 15: Verify
# ---------------------------------------------------------------------------
step "Verify agent is running"

LOG_FILE="$AGENT_DIR/logs/nanoclaw.log"
ERROR_LOG="$AGENT_DIR/logs/nanoclaw.error.log"

if launchctl list "$PLIST_LABEL" >/dev/null 2>&1; then
  PID=$(launchctl list "$PLIST_LABEL" 2>/dev/null | grep PID | awk '{print $NF}' || true)
  if [[ -n "$PID" && "$PID" != "-" ]]; then
    ok "Service is running (PID: $PID)"
  else
    # Check if it's in the list at all
    STATUS=$(launchctl list | grep "$PLIST_LABEL" || true)
    if [[ -n "$STATUS" ]]; then
      ok "Service is loaded: $STATUS"
    else
      warn "Service loaded but may not be running yet"
    fi
  fi
else
  warn "Could not verify service status"
fi

if [[ -f "$LOG_FILE" ]]; then
  info "Last 5 lines of log:"
  tail -5 "$LOG_FILE" 2>/dev/null | while read -r line; do echo "  $line"; done
elif [[ -f "$ERROR_LOG" ]]; then
  info "Last 5 lines of error log:"
  tail -5 "$ERROR_LOG" 2>/dev/null | while read -r line; do echo "  $line"; done
else
  info "No log output yet (agent may still be starting)"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Agent '$NAME_CAPITALIZED' created successfully!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  Directory:   $AGENT_DIR"
echo "  Email:       $EMAIL"
echo "  Port:        $PORT"
echo "  Model:       $MODEL"
echo "  Gmail MCP:   $GMAIL_MCP_DIR"
echo "  Plist:       $PLIST_FILE"
echo "  Logs:        $AGENT_DIR/logs/"
echo ""
echo "  Manage:"
echo "    launchctl kickstart -k gui/$(id -u)/$PLIST_LABEL   # restart"
echo "    launchctl bootout gui/$(id -u)/$PLIST_LABEL        # stop"
echo "    tail -f $AGENT_DIR/logs/nanoclaw.log               # watch logs"
echo ""
echo -e "  ${YELLOW}Remember: Add '$NAME' to VALID_AGENTS in chat-gateway${NC}"
echo ""
