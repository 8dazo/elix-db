#!/usr/bin/env bash
# Publish elix_db to Hex. Run from repo root or elix_db/. Set HEX_API_KEY in env.

set -e
cd "$(dirname "$0")/.."

echo "==> Building docs..."
mix docs

echo ""
echo "==> Publishing to Hex..."
if [ -z "$HEX_API_KEY" ]; then
  echo "Set HEX_API_KEY (from hex.pm/dashboard) then run again."
  exit 1
fi
mix hex.publish --yes

echo ""
echo "Published: https://hex.pm/packages/elix_db | https://hexdocs.pm/elix_db"
