#!/bin/bash
# Build Botti Voice with latest agent memory from NanoClaw groups
set -e
cd "$(dirname "$0")"

echo "Syncing agent memory..."
# Botti — main WhatsApp group
cp -f ../groups/whatsapp_main/CLAUDE.md memory/botti/CLAUDE.md 2>/dev/null || echo "  [skip] botti: no CLAUDE.md"
# Thais — from separate NanoClaw instance
cp -f ../../nanoclaw-thais/groups/gmail_main/CLAUDE.md memory/thais/CLAUDE.md 2>/dev/null || echo "  [skip] thais: no CLAUDE.md"
# Sam — global group (or whatsapp_main if Sam shares with Botti)
cp -f ../groups/global/CLAUDE.md memory/sam/CLAUDE.md 2>/dev/null || echo "  [skip] sam: no CLAUDE.md"

echo "Building Docker image..."
gcloud builds submit --tag europe-west1-docker.pkg.dev/adp-413110/botti-voice/botti-voice:latest .

echo "Deploying to Cloud Run..."
gcloud run deploy botti-voice \
  --image europe-west1-docker.pkg.dev/adp-413110/botti-voice/botti-voice:latest \
  --region europe-west1 \
  --allow-unauthenticated

echo "Done."
