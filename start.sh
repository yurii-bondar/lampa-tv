#!/bin/bash
set -e

cd "$(dirname "$0")"

echo "Starting services..."
docker compose up -d

echo ""
echo "Services running:"
echo "  TorrServer:   http://localhost:8090"
echo "  Jackett:      http://localhost:9117"
echo "  Lampac:       http://localhost:9118"
echo "  FlareSolverr: internal only (no host port)"
