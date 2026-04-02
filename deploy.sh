#!/bin/bash
# Deploy NanoClaw — rebuild and distribute dist/ to all instances.
# Usage: ./deploy.sh [--restart]
set -e
cd "$(dirname "$0")"

echo "Building..."
npm run build

INSTANCES=(nanoclaw-sam nanoclaw-thais nanoclaw-alan)

for inst in "${INSTANCES[@]}"; do
  dir="/Users/boty/$inst"
  if [ -d "$dir" ]; then
    # Remove old dist (symlink or directory)
    rm -rf "$dir/dist"
    cp -R dist "$dir/dist"
    echo "  $inst: dist/ updated"
  fi
done

echo "Build distributed to ${#INSTANCES[@]} instances."

if [ "$1" = "--restart" ]; then
  echo "Restarting services..."
  launchctl kickstart -k "gui/$(id -u)/com.nanoclaw"
  for inst in "${INSTANCES[@]}"; do
    svc="com.${inst//-/.}"
    # nanoclaw-sam -> com.nanoclaw.sam
    svc="com.nanoclaw.${inst#nanoclaw-}"
    launchctl kickstart -k "gui/$(id -u)/$svc"
  done
  echo "All services restarted."
fi

echo "Done."
