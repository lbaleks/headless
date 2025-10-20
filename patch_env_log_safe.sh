#!/usr/bin/env bash
set -euo pipefail

FILE="apps/api/src/server.js"
export TARGET_FILE="$(pwd)/$FILE"

node <<'NODE'
const fs = require('fs');
const file = process.env.TARGET_FILE;
let s = fs.readFileSync(file, 'utf8');

if (!s.includes('ENV loaded')) {
  const insert = 'app.log.info({ envFrom: process.env.__ENV_LOADED_FROM, warn: process.env.__ENV_WARN }, "ENV loaded");\n';
  const key = 'app.listen(';
  const idx = s.indexOf(key);
  if (idx !== -1) {
    s = s.slice(0, idx) + insert + s.slice(idx);
    fs.writeFileSync(file, s, 'utf8');
    console.log('✅ Injected ENV log before app.listen()');
  } else {
    console.log('ℹ️ Fant ikke app.listen( ) – ingen endring.');
  }
} else {
  console.log('ℹ️ ENV log allerede tilstede – ingen endring.');
}
NODE

# Restart
PORT="${PORT:-3044}"
lsof -ti tcp:"$PORT" | xargs -r kill -9 || true
( cd apps/api && nohup npm run start > ../../.api.dev.log 2>&1 & echo $! > ../../.api.pid )
sleep 1
tail -n 5 .api.dev.log
