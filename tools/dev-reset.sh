#!/usr/bin/env bash
set -euo pipefail
ports="3000 3001"

# drep prosesser på portene
pids=$(lsof -ti tcp:$ports 2>/dev/null || true)
[ -n "${pids:-}" ] && kill $pids || true
sleep 0.3
pids=$(lsof -ti tcp:$ports 2>/dev/null || true)
[ -n "${pids:-}" ] && kill -9 $pids || true

# drep evt. next dev
pkill -f "next dev" 2>/dev/null || true
pkill -f "node .*next" 2>/dev/null || true

# start på 3000
exec next dev -p 3000
