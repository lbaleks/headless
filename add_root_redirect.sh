#!/usr/bin/env bash
set -euo pipefail
ROOT="$(pwd)"
API="$ROOT/apps/api"
SV="$API/src/server.js"
LOG="$ROOT/.api.dev.log"
PIDF="$ROOT/.api.pid"
PORT="${PORT:-$(grep -E '^PORT=' "$ROOT/.env" | sed -n 's/^PORT=//p')}"
PORT="${PORT:-3044}"

node <<'NODE'
import fs from 'fs'
const p='apps/api/src/server.js'
let s=fs.readFileSync(p,'utf8')

// Lag idempotent root route rett før app.listen()
if(!s.includes("app.get('/', async (_req, reply) => reply.redirect('/v2/admin'))")){
  const anchor='app.listen({'
  const i = s.indexOf(anchor)
  const inject = "app.get('/', async (_req, reply) => reply.redirect('/v2/admin'))\n"
  if(i !== -1){
    s = s.slice(0,i) + inject + s.slice(i)
  } else {
    s += "\n" + inject
  }
  fs.writeFileSync(p,s,'utf8')
  console.log('Root redirect added.')
} else {
  console.log('Root redirect already present.')
}
NODE

# Restart
lsof -ti tcp:"$PORT" | xargs -r kill -9 || true
: > "$LOG"
( cd "$API" && nohup npm run start > "$LOG" 2>&1 & echo $! > "$PIDF" )
sleep 2

echo "🩺 Health:"; curl -sS --max-time 6 "http://127.0.0.1:$PORT/v2/health" || true; echo
echo "🔁 Root (expect 302 -> /v2/admin):"
curl -sI --max-time 6 "http://127.0.0.1:$PORT/" || true; echo
echo "🧭 Routes:"; curl -sS --max-time 6 "http://127.0.0.1:$PORT/v2/debug/routes" || true; echo
