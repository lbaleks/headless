#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)"
API="$ROOT/apps/api"
LOG="$ROOT/.api.dev.log"
PIDF="$ROOT/.api.pid"
PORT="${PORT:-$(grep -E '^PORT=' "$ROOT/.env" | sed -n 's/^PORT=//p')}"
PORT="${PORT:-3044}"

# Restart korrekt – skriv alltid til ROOT-baserte stier
if lsof -ti tcp:"$PORT" >/dev/null 2>&1; then
  lsof -ti tcp:"$PORT" | xargs -r kill -9 || true
fi
: > "$LOG"
( cd "$API" && nohup npm run start > "$LOG" 2>&1 & echo $! > "$PIDF" )
sleep 1

echo "🩺 Health:";        curl -sS --max-time 6 "http://127.0.0.1:$PORT/v2/health" | jq -c . || true
echo "⚙️ Flags:";         curl -sS --max-time 6 "http://127.0.0.1:$PORT/v2/feature-flags" | jq -c . || true
echo "🧭 Routes:";        curl -sS --max-time 6 "http://127.0.0.1:$PORT/v2/debug/routes" | sed -n '1,120p' || true
