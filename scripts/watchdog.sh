#!/bin/bash
# watchdog.sh — Check agent health, alert on WhatsApp if any agent is down.
# Run via launchd every 5 minutes.
#
# Dependencies: curl, jq (optional for parsing)
# Alert channel: WhatsApp via the main NanoClaw instance (Botti)

set -euo pipefail

HEALTH_PORTS=(3001 3002 3003 3004)
AGENT_NAMES=("Botti" "Thais" "Sam" "Alan")
SERVICE_NAMES=("com.nanoclaw" "com.nanoclaw.thais" "com.nanoclaw.sam" "com.nanoclaw.alan")

# State file to track alerts (don't spam)
STATE_DIR="/Users/boty/.config/nanoclaw"
ALERT_STATE="$STATE_DIR/watchdog-state.json"
COOLDOWN_SECONDS=1800  # 30 min between alerts for same agent

mkdir -p "$STATE_DIR"

# Initialize state file if missing
if [ ! -f "$ALERT_STATE" ]; then
  echo '{}' > "$ALERT_STATE"
fi

now=$(date +%s)
alerts=""
recovered=""

for i in "${!HEALTH_PORTS[@]}"; do
  port="${HEALTH_PORTS[$i]}"
  name="${AGENT_NAMES[$i]}"
  service="${SERVICE_NAMES[$i]}"

  # Check health
  status=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 3 "http://localhost:$port/health" 2>/dev/null || echo "000")

  if [ "$status" != "200" ]; then
    # Agent is down — check cooldown
    last_alert=$(python3 -c "import json; d=json.load(open('$ALERT_STATE')); print(d.get('$name', 0))" 2>/dev/null || echo "0")
    elapsed=$((now - last_alert))

    if [ "$elapsed" -gt "$COOLDOWN_SECONDS" ]; then
      alerts="${alerts}⚠️ $name (port $port) is DOWN (HTTP $status)\n"
      # Update state
      python3 -c "
import json
d = json.load(open('$ALERT_STATE'))
d['$name'] = $now
json.dump(d, open('$ALERT_STATE', 'w'))
"
      # Try to restart the service
      launchctl kickstart -k "gui/$(id -u)/$service" 2>/dev/null && \
        alerts="${alerts}  → Restart attempted for $service\n" || \
        alerts="${alerts}  → Restart failed for $service\n"
    fi
  else
    # Agent is up — check if it was previously down (recovery notification)
    last_alert=$(python3 -c "import json; d=json.load(open('$ALERT_STATE')); print(d.get('$name', 0))" 2>/dev/null || echo "0")
    if [ "$last_alert" != "0" ]; then
      recovered="${recovered}✅ $name is back up\n"
      python3 -c "
import json
d = json.load(open('$ALERT_STATE'))
d['$name'] = 0
json.dump(d, open('$ALERT_STATE', 'w'))
"
    fi
  fi
done

# Check Docker
docker_status=$(docker info >/dev/null 2>&1 && echo "ok" || echo "down")
if [ "$docker_status" = "down" ]; then
  last_docker=$(python3 -c "import json; d=json.load(open('$ALERT_STATE')); print(d.get('docker', 0))" 2>/dev/null || echo "0")
  elapsed=$((now - last_docker))
  if [ "$elapsed" -gt "$COOLDOWN_SECONDS" ]; then
    alerts="${alerts}🐳 Docker is NOT running — agents cannot spawn containers\n"
    python3 -c "
import json
d = json.load(open('$ALERT_STATE'))
d['docker'] = $now
json.dump(d, open('$ALERT_STATE', 'w'))
"
    # Try to start Docker
    open -a Docker 2>/dev/null && alerts="${alerts}  → Docker start attempted\n"
  fi
else
  last_docker=$(python3 -c "import json; d=json.load(open('$ALERT_STATE')); print(d.get('docker', 0))" 2>/dev/null || echo "0")
  if [ "$last_docker" != "0" ]; then
    recovered="${recovered}🐳 Docker is back up\n"
    python3 -c "
import json
d = json.load(open('$ALERT_STATE'))
d['docker'] = 0
json.dump(d, open('$ALERT_STATE', 'w'))
"
  fi
fi

# Check dashboard
dash_status=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 3 "http://localhost:3100/" 2>/dev/null || echo "000")
if [ "$dash_status" != "200" ]; then
  launchctl kickstart -k "gui/$(id -u)/com.nanoclaw.dashboard" 2>/dev/null
fi

# Send alerts via IPC to Botti (WhatsApp)
if [ -n "$alerts" ] || [ -n "$recovered" ]; then
  message="[Watchdog Alert]\n${alerts}${recovered}"

  # Write IPC file for Botti to pick up and send via WhatsApp
  ipc_dir="/Users/boty/nanoclaw/data/ipc/whatsapp_main"
  mkdir -p "$ipc_dir"

  timestamp=$(date +%s%3N)
  cat > "$ipc_dir/watchdog-${timestamp}.json" << IPCEOF
{
  "type": "send_message",
  "data": {
    "text": "$(echo -e "$message" | sed 's/"/\\"/g' | tr '\n' ' ')"
  }
}
IPCEOF

  # Also log
  echo "[$(date)] ALERT: $(echo -e "$message")" >> /Users/boty/nanoclaw/logs/watchdog.log
fi
