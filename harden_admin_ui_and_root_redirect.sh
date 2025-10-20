#!/usr/bin/env bash
set -euo pipefail
ROOT="$(pwd)"
API="$ROOT/apps/api"
SV="$API/src/server.js"
UI="$API/src/plugins/admin.ui.js"
LOG="$ROOT/.api.dev.log"
PIDF="$ROOT/.api.pid"
PORT="${PORT:-$(grep -E '^PORT=' "$ROOT/.env" | sed -n 's/^PORT=//p')}"
PORT="${PORT:-3044}"

# 1) Sett no-store headers på /v2/admin
node <<'NODE'
import fs from 'fs'
const f='apps/api/src/plugins/admin.ui.js'
let s=fs.readFileSync(f,'utf8')
if(!/reply\.header\(['"]Cache-Control['"],\s*['"]no-store['"]\)/.test(s)){
  s = s.replace(/reply\.type\('text\/html'\)\.send\(html\);/,
    `reply.header('Cache-Control','no-store').type('text/html; charset=utf-8').send(html);`)
  fs.writeFileSync(f,s,'utf8')
  console.log('Admin UI set to no-store cache.')
} else {
  console.log('Admin UI already no-store.')
}
NODE

# 2) Legg inn root redirect '/' -> '/v2/admin' (idempotent)
node <<'NODE'
import fs from 'fs'
const p='apps/api/src/server.js'
let s=fs.readFileSync(p,'utf8')
if(!s.includes("app.get('/', async (_req, reply) => reply.redirect('/v2/admin'))")){
  s = s.replace(
    /app\.get\('\/v2\/debug\/routes'[\s\S]*?\}\)\n\}\)\n/,
`app.get('/v2/debug/routes', async () => {
  const lines = []
  lines.push('└── (root)')
  lines.push(app.printRoutes({ includeHooks: false }))
  return lines.join('\\n')
})
app.get('/', async (_req, reply) => reply.redirect('/v2/admin'))
`
  )
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
echo "🧭 Routes:"; curl -sS --max-time 6 "http://127.0.0.1:$PORT/v2/debug/routes" || true; echo
echo "🔗 Open Admin:"; echo "http://127.0.0.1:$PORT/  (redirects to /v2/admin)"
