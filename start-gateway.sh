#!/usr/bin/env bash
cd "$(dirname "$0")/m2-gateway" || exit 1
pkill -f "node server.js" 2>/dev/null || true
node server.js
