#!/usr/bin/env bash
set -euo pipefail
SV="apps/api/src/server.js"

# Sett inn ENV-logg like før app.listen(...), idempotent
if ! grep -q 'ENV loaded' "$SV"; then
  # macOS-kompatibel sed: legg inn linje før første forekomst av "app.listen("
  sed -i '' $'/app\\.listen/{i\\
app.log.info({ envFrom: process.env.__ENV_LOADED_FROM, warn: process.env.__ENV_WARN }, "ENV loaded");\\
}' "$SV"
fi

# Restart
PORT="${PORT:-3044}"
lsof -ti tcp:"$PORT" | xargs -r kill -9 || true
( cd apps/api && nohup npm run start > ../../.api.dev.log 2>&1 & echo $! > ../../.api.pid )
sleep 1
tail -n 5 .api.dev.log
