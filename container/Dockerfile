# NanoClaw Agent Container
# Runs Claude Agent SDK in isolated Linux VM with browser automation

FROM node:22-slim

# Install system dependencies for Chromium
RUN apt-get update && apt-get install -y \
    chromium \
    fonts-liberation \
    fonts-noto-cjk \
    fonts-noto-color-emoji \
    libgbm1 \
    libnss3 \
    libatk-bridge2.0-0 \
    libgtk-3-0 \
    libx11-xcb1 \
    libxcomposite1 \
    libxdamage1 \
    libxrandr2 \
    libasound2 \
    libpangocairo-1.0-0 \
    libcups2 \
    libdrm2 \
    libxshmfence1 \
    curl \
    git \
    && rm -rf /var/lib/apt/lists/*

# Set Chromium path for agent-browser
ENV AGENT_BROWSER_EXECUTABLE_PATH=/usr/bin/chromium
ENV PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH=/usr/bin/chromium

# Install agent-browser and claude-code globally
RUN npm install -g agent-browser @anthropic-ai/claude-code @googleworkspace/cli

# Create app directory
WORKDIR /app

# Copy package files first for better caching
COPY agent-runner/package*.json ./

# Install dependencies
RUN npm install

# Copy source code
COPY agent-runner/ ./

# Build TypeScript
RUN npm run build

# Create GWS account wrapper scripts (gws-sam, gws-thais, gws-alan)
# These set GOOGLE_WORKSPACE_CLI_CONFIG_DIR so the correct OAuth token is used.
# Without these, calling bare `gws` from the shell uses the default account.
RUN for account in sam thais alan; do \
      printf '#!/bin/bash\n\
export GOOGLE_WORKSPACE_CLI_CONFIG_DIR=/home/node/.config/gws/accounts/%s\n\
# Pre-send log: identify active account before any gmail +send\n\
if echo "$@" | grep -q "gmail.*+send\\|gmail.*send"; then\n\
  echo "[gws-wrapper] account=%s args=$*" >&2\n\
fi\n\
exec gws "$@"\n' "$account" "$account" > /usr/local/bin/gws-${account} \
      && chmod +x /usr/local/bin/gws-${account}; \
    done

# Create workspace directories
RUN mkdir -p /workspace/group /workspace/global /workspace/extra /workspace/ipc/messages /workspace/ipc/tasks /workspace/ipc/input

# Copy entrypoint script
# Container input (prompt, group info) is passed via stdin JSON.
# Credentials are injected by the host's credential proxy — never passed here.
# Follow-up messages arrive via IPC files in /workspace/ipc/input/
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

# Set ownership to node user (non-root) for writable directories
RUN chown -R node:node /workspace && chmod 777 /home/node

# Switch to non-root user (required for --dangerously-skip-permissions)
USER node

# Set working directory to group workspace
WORKDIR /workspace/group

# Entry point reads JSON from stdin, outputs JSON to stdout
ENTRYPOINT ["/app/entrypoint.sh"]
