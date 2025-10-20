#!/usr/bin/env bash
set -euo pipefail
PORT="${PORT:-$(grep -E '^PORT=' .env | sed -n 's/^PORT=//p')}"
PORT="${PORT:-3044}"
API="apps/api"
LOG=".api.dev.log"
PIDF=".api.pid"

echo "🧹 Killing port $PORT (if any)…"
lsof -ti tcp:"$PORT" | xargs -r kill -9 || true

: > "$LOG"
echo "🚀 Starting API…"
( cd "$API" && nohup npm run start > "../$LOG" 2>&1 & echo $! > "../$PIDF" )
sleep 2.5

echo "🩺 Health:"
curl -sS --max-time 6 "http://127.0.0.1:$PORT/v2/health" || true
echo
echo "🪵 Last 120 log lines:"
tail -n 120 "$LOG" || true
