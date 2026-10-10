#!/bin/bash
set -e

cd "$(dirname "$0")"

LAMPAC_CONF="lampac-config/init.conf"

# Docker creates a missing bind-mount source as a directory, which breaks Lampac
if [ -d "$LAMPAC_CONF" ]; then
  echo "Error: $LAMPAC_CONF is a directory (likely created by Docker when the file was missing)."
  echo "Remove it and run this script again:"
  echo "  docker compose down && rm -rf $LAMPAC_CONF"
  exit 1
fi

if [ ! -f "$LAMPAC_CONF" ]; then
  cp "$LAMPAC_CONF.example" "$LAMPAC_CONF"
  echo "Created $LAMPAC_CONF from template."
fi

echo "Starting services..."
docker compose up -d

echo ""
echo "Services running:"
echo "  TorrServer:   http://localhost:8090"
echo "  Jackett:      http://localhost:9117"
echo "  Lampac:       http://localhost:9118"
echo "  FlareSolverr: internal only (no host port)"
